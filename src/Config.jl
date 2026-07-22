module Config

using TOML
using HTTP, JSON3, Dates
using ..Constant
using ..Errors: LongBridgeError
using ..OAuth: OAuthHandle

export Settings,
    config,
    from_toml,
    from_oauth,
    enable_papertrading!,
    dc_region

"""
Configuration options for Longport SDK
Args:
    app_key: App Key
    app_secret: App Secret
    access_token: Access Token
    http_url: HTTP API url
    quote_ws_url: Websocket url for quote API
    trade_ws_url: Websocket url for trade API
    language: Language identifier
    enable_overnight: Enable overnight quote
    push_candlestick_mode: Push candlestick mode
    enable_print_quote_packages: Enable printing the opened quote packages when connected to the server
    log_path: Set the path of the log files
"""

mutable struct Settings
    app_key::String
    app_secret::String
    access_token::String
    token_expire_time::DateTime
    http_url::String
    quote_ws_url::String
    trade_ws_url::String
    language::Language.T
    enable_overnight::Bool
    enable_papertrading::Bool
    auth_mode::Symbol          # :apikey or :oauth
    oauth::Union{Nothing,OAuthHandle}

    function Settings(
        app_key::String,
        app_secret::String,
        access_token::String,
        token_expire_time::DateTime;
        http_url::Union{String,Nothing} = DEFAULT_HTTP_URL_CN,
        quote_ws_url::Union{String,Nothing} = DEFAULT_QUOTE_WS_CN,
        trade_ws_url::Union{String,Nothing} = DEFAULT_TRADE_WS_CN,
        language::Language.T = Language.ZH_CN,
        enable_overnight::Bool = true,   # 美股夜盘交易行情，需订阅US LV1实时行情并开启enable_overnight参数，否则会返回null
        enable_papertrading::Bool = false,
    )
        new(
            app_key,
            app_secret,
            access_token,
            token_expire_time,
            something(http_url, DEFAULT_HTTP_URL_CN),
            something(quote_ws_url, DEFAULT_QUOTE_WS_CN),
            something(trade_ws_url, DEFAULT_TRADE_WS_CN),
            language,
            enable_overnight,
            enable_papertrading,
            :apikey,
            nothing,
        )
    end
end

# Backwards-compat alias for the old lowercase name.
const config = Settings

"""Enable paper-trading routing for all subsequent API requests."""
function enable_papertrading!(cfg::Settings)
    cfg.enable_papertrading = true
    return cfg
end

_credential_is_us(value::AbstractString) =
    startswith(chopprefix(value, "Bearer "), "us_")

"""Return `:us` or `:ap` from the configured credential prefixes."""
function dc_region(cfg::Settings)
    if cfg.auth_mode === :oauth
        token = oauth_access_token(cfg.oauth)
        return _credential_is_us(token) ? :us : :ap
    end
    return any(_credential_is_us, (cfg.app_key, cfg.app_secret, cfg.access_token)) ? :us : :ap
end

"""
Create a new `config` from TOML configuration file

Args:
    path: Path to the TOML configuration file

Returns:
    config instance
"""
function from_toml(path::AbstractString)
    if !isfile(path)
        throw(LongBridgeError(404, "Config file not found: $path"))
    end

    config_path = String(path)
    config_dict = TOML.parsefile(config_path)

    # URLs - use Constant defaults unless the TOML explicitly overrides them
    http_url = String(get(config_dict, "http_url", DEFAULT_HTTP_URL_CN))
    quote_ws_url = String(get(config_dict, "quote_ws_url", DEFAULT_QUOTE_WS_CN))
    trade_ws_url = String(get(config_dict, "trade_ws_url", DEFAULT_TRADE_WS_CN))
    enable_papertrading = Bool(get(
        config_dict,
        "enable_papertrading",
        lowercase(get(ENV, "LONGBRIDGE_PAPERTRADING", "false")) == "true",
    ))

    # Required fields
    required_keys = ["app_key", "app_secret", "access_token", "token_expire_time"]
    for key in required_keys
        if !haskey(config_dict, key)
            throw(LongBridgeError(400, "Missing required config key: $key"))
        end
    end

    app_key = config_dict["app_key"]
    app_secret = config_dict["app_secret"]
    access_token = config_dict["access_token"]

    raw_dt = config_dict["token_expire_time"]
    if endswith(raw_dt, "Z")
        raw_dt = chop(raw_dt)
    end
    token_expire_time = DateTime(raw_dt)

    # Token过期三天前更新
    if now(Dates.UTC) > token_expire_time - Day(3)
        url = http_url * "/v1/token/refresh"
        headers = Dict("Authorization" => "Bearer " * access_token, "X-API-KEY" => app_key)
        query_param = Dict("expired_at" => raw_dt)
        try
            resp = HTTP.get(
                url;
                headers = headers,
                query = query_param,
                connect_timeout = 10,
                request_timeout = 60,
                response_header_timeout = 10,
                read_idle_timeout = 30,
            )
            data = JSON3.read(resp.body)
            if data.code == 0
                access_token = data.data.token
                raw_expired_at = data.data.expired_at
                if endswith(raw_expired_at, "Z")
                    raw_expired_at = chop(raw_expired_at)
                end
                token_expire_time = DateTime(raw_expired_at)
                config_dict["access_token"] = access_token
                config_dict["token_expire_time"] = string(token_expire_time)
                open(config_path, "w") do f
                    TOML.print(f, config_dict)
                end
            else
                @warn "refresh token failed: $(data.message)"
            end
        catch e
            @warn "refresh token exception" exception=(e, catch_backtrace())
        end
    end

    Settings(
        app_key,
        app_secret,
        access_token,
        token_expire_time;
        http_url = http_url,
        quote_ws_url = quote_ws_url,
        trade_ws_url = trade_ws_url,
        enable_papertrading = enable_papertrading,
    )
end

"""
from_toml()

Load configuration from default TOML file (config.toml).

Returns:
    config instance
"""
function from_toml()
    # Try different possible locations for config.toml
    config_paths = [
        "config.toml",
        "src/config.toml",
        joinpath(@__DIR__, "config.toml"),
        joinpath(dirname(@__DIR__), "config.toml"),
    ]

    for path in config_paths
        if isfile(path)
            return from_toml(path)
        end
    end

    throw(
        LongBridgeError(
            404,
            "Config file not found. Please create config.toml in one of these locations: $(join(config_paths, ", "))",
        ),
    )
end

"""
from_oauth(oauth_handle::OAuthHandle; kwargs...) -> config

Create a config from an OAuthHandle. In OAuth mode, HMAC signatures are
skipped and a Bearer token is used instead.

# Keyword Arguments
- `http_url`: HTTP API url (default: CN endpoint)
- `quote_ws_url`: WebSocket url for quote API (default: CN endpoint)
- `trade_ws_url`: WebSocket url for trade API (default: CN endpoint)
- `language`: Language identifier (default: ZH_CN)
- `enable_overnight`: Enable overnight quote (default: true)
"""
function from_oauth(
    oauth_handle::OAuthHandle;
    http_url::Union{String,Nothing} = DEFAULT_HTTP_URL_CN,
    quote_ws_url::Union{String,Nothing} = DEFAULT_QUOTE_WS_CN,
    trade_ws_url::Union{String,Nothing} = DEFAULT_TRADE_WS_CN,
    language::Language.T = Language.ZH_CN,
    enable_overnight::Bool = true,
    enable_papertrading::Bool = false,
)
    cfg = Settings(
        oauth_handle.client_id,   # app_key = client_id
        "",                        # app_secret not needed for OAuth
        "",                        # access_token resolved dynamically
        DateTime(9999, 12, 31);    # placeholder, not used in OAuth mode
        http_url = http_url,
        quote_ws_url = quote_ws_url,
        trade_ws_url = trade_ws_url,
        language = language,
        enable_overnight = enable_overnight,
        enable_papertrading = enable_papertrading,
    )
    cfg.auth_mode = :oauth
    cfg.oauth = oauth_handle
    return cfg
end

end # module Config
