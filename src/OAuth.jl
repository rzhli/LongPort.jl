module OAuth

using HTTP, JSON, Random
using Base.Threads: ReentrantLock

using ..Errors: LongBridgeError
# HTTP_CLIENT 仅作为进程级共享 client 的引用入口（实际请求经 TOKEN_REQUEST_KW 下发）。
using ..HttpClient: HTTP_CLIENT, TOKEN_REQUEST_KW

export OAuthToken,
    OAuthHandle,
    OAuthBuilder,
    build,
    is_expired,
    expires_soon,
    access_token,
    load_from_path,
    save_to_path,
    callback_port!

# ==================== Constants ====================

const OAUTH_BASE_URL = "https://openapi.longbridgeapp.com"
const OAUTH_AUTHORIZE_PATH = "/oauth2/authorize"
const OAUTH_TOKEN_PATH = "/oauth2/token"
const DEFAULT_CALLBACK_PORT = UInt16(60355)
const DEFAULT_REDIRECT_URI = "http://localhost:60355/callback"
const AUTH_TIMEOUT = 300.0  # 5 minutes

# ==================== Token Endpoint ====================

"""
    _post_token(fields::NamedTuple) -> JSON 解析后的响应

POST 到 OAuth token 端点。`fields` 直接作为请求体传给 HTTP.jl：NamedTuple
会被自动做 application/x-www-form-urlencoded 编码，并在未显式指定时补上
对应的 Content-Type。授权码/刷新令牌交换不幂等，HTTP.jl 默认不重试
非幂等方法，正是此处需要的行为。
"""
function _post_token(fields::NamedTuple)
    resp = HTTP.post(OAUTH_BASE_URL * OAUTH_TOKEN_PATH; body = fields, TOKEN_REQUEST_KW...)
    return JSON.parse(resp.body)
end

function _token_dir()
    dir = get(ENV, "LONGBRIDGE_TOKEN_DIR", "")
    !isempty(dir) && return dir

    home = get(ENV, Sys.iswindows() ? "USERPROFILE" : "HOME", "")
    !isempty(home) && return joinpath(home, ".longbridge", "tokens")

    return joinpath(first(Base.DEPOT_PATH), "longbridge", "tokens")
end

# ==================== OAuthToken ====================

"""
    OAuthToken

Represents an OAuth 2.0 token with access and refresh tokens.
Persisted as JSON under `\$LONGBRIDGE_TOKEN_DIR` when set, otherwise under
the user-level LongBridge token directory.
"""
struct OAuthToken
    client_id::String
    access_token::String
    refresh_token::Union{String,Nothing}
    expires_at::UInt64  # unix timestamp
end

"""
    is_expired(token::OAuthToken) -> Bool

Returns true if the token has expired.
"""
is_expired(token::OAuthToken) = UInt64(floor(time())) >= token.expires_at

"""
    expires_soon(token::OAuthToken) -> Bool

Returns true if the token expires within 1 hour (or is already expired).
"""
function expires_soon(token::OAuthToken)
    now_ts = UInt64(floor(time()))
    token.expires_at <= 3600 || now_ts >= token.expires_at - 3600
end

"""
    token_path(client_id::String) -> String

Returns the filesystem path for persisting this client's token.
"""
token_path(client_id::AbstractString) = joinpath(_token_dir(), client_id)

"""
    save_to_path(token::OAuthToken)

Persist the token to `\$LONGBRIDGE_TOKEN_DIR/<client_id>` when set, otherwise
to the user-level LongBridge token directory.
"""
function save_to_path(token::OAuthToken)
    path = token_path(token.client_id)
    mkpath(dirname(path))
    open(path, "w") do f
        JSON.json(f, token)
    end
    return path
end

"""
    load_from_path(client_id::String) -> Union{OAuthToken, Nothing}

Load a cached token from disk. Returns `nothing` if no cached token exists.
"""
function load_from_path(client_id::AbstractString)::Union{OAuthToken,Nothing}
    path = token_path(client_id)
    isfile(path) || return nothing
    try
        return open(path) do io
            JSON.parse(io, OAuthToken)
        end
    catch e
        @warn "Failed to load cached OAuth token" path exception=e
        return nothing
    end
end

# ==================== OAuthHandle ====================

"""
    OAuthHandle

Manages an active OAuth session with automatic token refresh.
Thread-safe via ReentrantLock on the token field.
"""
mutable struct OAuthHandle
    client_id::String
    callback_port::UInt16
    token::Union{OAuthToken,Nothing}
    lock::ReentrantLock

    function OAuthHandle(
        client_id::String,
        callback_port::UInt16,
        token::Union{OAuthToken,Nothing},
    )
        new(client_id, callback_port, token, ReentrantLock())
    end
end

"""
    access_token(handle::OAuthHandle) -> String

Returns a valid access token, refreshing automatically if expired or expiring soon.
"""
function access_token(handle::OAuthHandle)::String
    lock(handle.lock) do
        token = handle.token
        if isnothing(token)
            throw(LongBridgeError(401, "No OAuth token available", nothing))
        end

        if is_expired(token) || expires_soon(token)
            if !isnothing(token.refresh_token)
                try
                    refresh_token!(handle)
                    return handle.token.access_token
                catch e
                    @warn "Token refresh failed" exception=e
                    if is_expired(token)
                        throw(
                            LongBridgeError(
                                401,
                                "OAuth token expired and refresh failed: $e",
                                nothing,
                            ),
                        )
                    end
                end
            elseif is_expired(token)
                throw(
                    LongBridgeError(
                        401,
                        "OAuth token expired and no refresh token available",
                        nothing,
                    ),
                )
            end
        end

        return token.access_token
    end
end

"""
    refresh_token!(handle::OAuthHandle)

Exchange the refresh token for a new access token via the OAuth token endpoint.
Must be called while holding handle.lock.
"""
function refresh_token!(handle::OAuthHandle)
    token = handle.token
    if isnothing(token) || isnothing(token.refresh_token)
        throw(LongBridgeError(401, "No refresh token available", nothing))
    end

    redirect_uri = "http://localhost:$(handle.callback_port)/callback"

    data = _post_token((
        grant_type = "refresh_token",
        refresh_token = token.refresh_token,
        client_id = handle.client_id,
        redirect_uri = redirect_uri,
    ))

    new_refresh = get(data, :refresh_token, token.refresh_token)
    new_token = OAuthToken(
        handle.client_id,
        data.access_token,
        new_refresh,
        UInt64(data.expires_in) + UInt64(floor(time())),
    )

    handle.token = new_token
    save_to_path(new_token)
    @info "OAuth token refreshed" client_id=handle.client_id
end

# ==================== Authorization Flow ====================

"""
    authorize!(handle::OAuthHandle, open_url_fn)

Run the full browser-based OAuth authorization flow:
1. Start local HTTP callback server
2. Open authorization URL in browser
3. Wait for callback with authorization code
4. Exchange code for tokens
"""
function authorize!(handle::OAuthHandle, open_url_fn)
    redirect_uri = "http://localhost:$(handle.callback_port)/callback"
    csrf_state = randstring(32)

    auth_url = string(
        OAUTH_BASE_URL,
        OAUTH_AUTHORIZE_PATH,
        "?",
        HTTP.URIs.escapeuri((
            client_id = handle.client_id,
            redirect_uri = redirect_uri,
            response_type = "code",
            state = csrf_state,
            scope = "openapi",
        )),
    )

    # 单一结果通道，避免轮询多个 channel
    # value: (:ok, code) on success, (:err, msg) on failure/timeout
    result_ch = Channel{Tuple{Symbol,String}}(1)

    # Start callback server
    # 回调里带的是授权码与 CSRF state，而 redirect_uri 固定为 localhost，
    # 因此只监听回环地址，不向局域网暴露这个端点。
    server = HTTP.serve!("127.0.0.1", Int(handle.callback_port)) do request::HTTP.Request
        uri = HTTP.URI(request.target)
        if startswith(uri.path, "/callback")
            params = HTTP.queryparams(uri)
            state = get(params, "state", "")
            code = get(params, "code", "")
            err = get(params, "error", "")

            if !isempty(err)
                isopen(result_ch) && put!(result_ch, (:err, err))
                return HTTP.Response(
                    200;
                    body = "Authorization failed: $err. You can close this window.",
                )
            end

            if state != csrf_state
                isopen(result_ch) && put!(result_ch, (:err, "CSRF state mismatch"))
                return HTTP.Response(400; body = "CSRF state mismatch. Please try again.")
            end

            if isempty(code)
                isopen(result_ch) &&
                    put!(result_ch, (:err, "No authorization code received"))
                return HTTP.Response(400; body = "No authorization code received.")
            end

            isopen(result_ch) && put!(result_ch, (:ok, code))
            return HTTP.Response(
                200;
                body = "Authorization successful! You can close this window.",
            )
        end
        return HTTP.Response(404; body = "Not Found")
    end

    try
        # Open the URL for the user
        open_url_fn(auth_url)

        # Race a timeout against the callback by putting an :err onto the same channel.
        timer = Timer(AUTH_TIMEOUT) do _
            isopen(result_ch) && put!(
                result_ch,
                (:err, "Authorization timed out after $(Int(AUTH_TIMEOUT)) seconds"),
            )
        end

        kind, payload = try
            take!(result_ch)
        finally
            close(timer)
        end

        if kind === :err
            throw(LongBridgeError(401, "OAuth authorization failed: $payload", nothing))
        end

        auth_code = payload

        # Exchange code for token
        data = _post_token((
            grant_type = "authorization_code",
            code = auth_code,
            client_id = handle.client_id,
            redirect_uri = redirect_uri,
        ))

        new_token = OAuthToken(
            handle.client_id,
            data.access_token,
            get(data, :refresh_token, nothing),
            UInt64(data.expires_in) + UInt64(floor(time())),
        )

        handle.token = new_token
        save_to_path(new_token)
        @info "OAuth authorization successful" client_id=handle.client_id
    finally
        close(server)
    end
end

# ==================== OAuthBuilder ====================

"""
    OAuthBuilder

Builder pattern for constructing an OAuthHandle with token lifecycle management.

# Usage
```julia
oauth = OAuthBuilder("your-client-id") |> build(url -> run(`xdg-open \$url`))
cfg = from_oauth(oauth)
```
"""
mutable struct OAuthBuilder
    client_id::String
    callback_port::UInt16

    OAuthBuilder(client_id::String) = new(client_id, DEFAULT_CALLBACK_PORT)
end

"""
    callback_port!(builder::OAuthBuilder, port::Integer) -> OAuthBuilder

Set the local callback port for the OAuth authorization flow.
"""
function callback_port!(builder::OAuthBuilder, port::Integer)
    builder.callback_port = UInt16(port)
    return builder
end

# Backwards-compatible alias for older code; prefer callback_port! for new code.
callback_port(builder::OAuthBuilder, port::Integer) = callback_port!(builder, port)

"""
    build(open_url_fn) -> Function

Returns a function that takes an OAuthBuilder and completes the OAuth flow:
1. Check for cached token on disk
2. If valid → use it
3. If expired → try refresh; if refresh fails → full auth flow
4. If no token → full auth flow
5. Persist token and return OAuthHandle
"""
function build(open_url_fn)
    return function (builder::OAuthBuilder)
        handle = OAuthHandle(builder.client_id, builder.callback_port, nothing)

        # Try loading cached token
        cached = load_from_path(builder.client_id)

        if !isnothing(cached)
            handle.token = cached

            if !is_expired(cached) && !expires_soon(cached)
                @info "Using cached OAuth token" client_id=builder.client_id
                return handle
            end

            # Token expired or expiring soon — try refresh
            if !isnothing(cached.refresh_token)
                try
                    @info "Cached token expiring, attempting refresh..." client_id=builder.client_id
                    refresh_token!(handle)
                    return handle
                catch e
                    @warn "Token refresh failed, falling back to full authorization" exception=e
                end
            end
        end

        # No valid token — run full authorization flow
        @info "Starting OAuth authorization flow..." client_id=builder.client_id
        authorize!(handle, open_url_fn)
        return handle
    end
end

end # module OAuth
