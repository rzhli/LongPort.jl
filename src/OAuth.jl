module OAuth

using HTTP, JSON3, Random, Dates, StructTypes
using Base.Threads: ReentrantLock

using ..Constant
using ..Errors: LongBridgeError

export OAuthToken, OAuthHandle, OAuthBuilder, build,
       is_expired, expires_soon, access_token,
       load_from_path, save_to_path

# ==================== Constants ====================

const OAUTH_BASE_URL = "https://openapi.longbridgeapp.com"
const OAUTH_AUTHORIZE_PATH = "/oauth2/authorize"
const OAUTH_TOKEN_PATH = "/oauth2/token"
const DEFAULT_CALLBACK_PORT = UInt16(60355)
const DEFAULT_REDIRECT_URI = "http://localhost:60355/callback"
const TOKEN_DIR = joinpath(pkgdir(parentmodule(@__MODULE__)), ".tokens")
const AUTH_TIMEOUT = 300.0  # 5 minutes

# ==================== OAuthToken ====================

"""
    OAuthToken

Represents an OAuth 2.0 token with access and refresh tokens.
Persisted as JSON at `<project>/.tokens/<client_id>`.
"""
struct OAuthToken
    client_id::String
    access_token::String
    refresh_token::Union{String, Nothing}
    expires_at::UInt64  # unix timestamp
end

# JSON3 serialization support
StructTypes.StructType(::Type{OAuthToken}) = StructTypes.Struct()

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
token_path(client_id::String) = joinpath(TOKEN_DIR, client_id)

"""
    save_to_path(token::OAuthToken)

Persist the token to `<project>/.tokens/<client_id>`.
"""
function save_to_path(token::OAuthToken)
    path = token_path(token.client_id)
    mkpath(dirname(path))
    open(path, "w") do f
        JSON3.write(f, token)
    end
    return path
end

"""
    load_from_path(client_id::String) -> Union{OAuthToken, Nothing}

Load a cached token from disk. Returns `nothing` if no cached token exists.
"""
function load_from_path(client_id::String)::Union{OAuthToken, Nothing}
    path = token_path(client_id)
    isfile(path) || return nothing
    try
        data = read(path, String)
        return JSON3.read(data, OAuthToken)
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
    token::Union{OAuthToken, Nothing}
    lock::ReentrantLock

    function OAuthHandle(client_id::String, callback_port::UInt16, token::Union{OAuthToken, Nothing})
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
                        throw(LongBridgeError(401, "OAuth token expired and refresh failed: $e", nothing))
                    end
                end
            elseif is_expired(token)
                throw(LongBridgeError(401, "OAuth token expired and no refresh token available", nothing))
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

    resp = HTTP.post(
        OAUTH_BASE_URL * OAUTH_TOKEN_PATH;
        headers = ["Content-Type" => "application/x-www-form-urlencoded"],
        body = HTTP.URIs.escapeuri(Dict(
            "grant_type" => "refresh_token",
            "refresh_token" => token.refresh_token,
            "client_id" => handle.client_id,
            "redirect_uri" => redirect_uri
        ))
    )

    data = JSON3.read(String(resp.body))

    new_refresh = get(data, :refresh_token, token.refresh_token)
    new_token = OAuthToken(
        handle.client_id,
        data.access_token,
        new_refresh,
        UInt64(data.expires_in) + UInt64(floor(time()))
    )

    handle.token = new_token
    save_to_path(new_token)
    @info "OAuth token refreshed" client_id=handle.client_id
end

# ==================== Authorization Flow ====================

"""
    authorize!(handle::OAuthHandle, open_url_fn::Function)

Run the full browser-based OAuth authorization flow:
1. Start local HTTP callback server
2. Open authorization URL in browser
3. Wait for callback with authorization code
4. Exchange code for tokens
"""
function authorize!(handle::OAuthHandle, open_url_fn::Function)
    redirect_uri = "http://localhost:$(handle.callback_port)/callback"
    csrf_state = randstring(32)

    auth_url = string(
        OAUTH_BASE_URL, OAUTH_AUTHORIZE_PATH,
        "?client_id=", HTTP.URIs.escapeuri(handle.client_id),
        "&redirect_uri=", HTTP.URIs.escapeuri(redirect_uri),
        "&response_type=code",
        "&state=", HTTP.URIs.escapeuri(csrf_state),
        "&scope=openapi"
    )

    # 单一结果通道，避免轮询多个 channel
    # value: (:ok, code) on success, (:err, msg) on failure/timeout
    result_ch = Channel{Tuple{Symbol, String}}(1)

    # Start callback server
    server = HTTP.serve!(
        "0.0.0.0", Int(handle.callback_port)
    ) do request::HTTP.Request
        uri = HTTP.URI(request.target)
        if startswith(uri.path, "/callback")
            params = HTTP.queryparams(uri)
            state = get(params, "state", "")
            code = get(params, "code", "")
            err = get(params, "error", "")

            if !isempty(err)
                isopen(result_ch) && put!(result_ch, (:err, err))
                return HTTP.Response(200, "Authorization failed: $err. You can close this window.")
            end

            if state != csrf_state
                isopen(result_ch) && put!(result_ch, (:err, "CSRF state mismatch"))
                return HTTP.Response(400, "CSRF state mismatch. Please try again.")
            end

            if isempty(code)
                isopen(result_ch) && put!(result_ch, (:err, "No authorization code received"))
                return HTTP.Response(400, "No authorization code received.")
            end

            isopen(result_ch) && put!(result_ch, (:ok, code))
            return HTTP.Response(200, "Authorization successful! You can close this window.")
        end
        return HTTP.Response(404, "Not Found")
    end

    try
        # Open the URL for the user
        open_url_fn(auth_url)

        # Race a timeout against the callback by putting an :err onto the same channel.
        timer = Timer(AUTH_TIMEOUT) do _
            isopen(result_ch) && put!(result_ch, (:err, "Authorization timed out after $(Int(AUTH_TIMEOUT)) seconds"))
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
        resp = HTTP.post(
            OAUTH_BASE_URL * OAUTH_TOKEN_PATH;
            headers = ["Content-Type" => "application/x-www-form-urlencoded"],
            body = HTTP.URIs.escapeuri(Dict(
                "grant_type" => "authorization_code",
                "code" => auth_code,
                "client_id" => handle.client_id,
                "redirect_uri" => redirect_uri
            ))
        )

        data = JSON3.read(String(resp.body))

        new_token = OAuthToken(
            handle.client_id,
            data.access_token,
            get(data, :refresh_token, nothing),
            UInt64(data.expires_in) + UInt64(floor(time()))
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
    callback_port(builder::OAuthBuilder, port::Integer) -> OAuthBuilder

Set the local callback port for the OAuth authorization flow.
"""
function callback_port(builder::OAuthBuilder, port::Integer)
    builder.callback_port = UInt16(port)
    return builder
end

"""
    build(open_url_fn::Function) -> Function

Returns a function that takes an OAuthBuilder and completes the OAuth flow:
1. Check for cached token on disk
2. If valid → use it
3. If expired → try refresh; if refresh fails → full auth flow
4. If no token → full auth flow
5. Persist token and return OAuthHandle
"""
function build(open_url_fn::Function)
    return function(builder::OAuthBuilder)
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
