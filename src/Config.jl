module Config

    using TOML
    using HTTP, JSON3, SHA, Base64, Dates
    using ..Constant
    using ..Errors: LongBridgeError
    using ..OAuth: OAuthHandle, access_token as oauth_access_token

    export config, from_toml, from_oauth

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
    
    mutable struct config
        app_key::String
        app_secret::String
        access_token::String
        token_expire_time::DateTime
        http_url::Union{String, Nothing}
        quote_ws_url::Union{String, Nothing}
        trade_ws_url::Union{String, Nothing}
        language::Language.T
        enable_overnight::Bool
        auth_mode::Symbol          # :apikey or :oauth
        oauth::Union{Nothing, OAuthHandle}

        function config(
            app_key::String,
            app_secret::String,
            access_token::String,
            token_expire_time::DateTime;
            http_url::Union{String, Nothing} = nothing,
            quote_ws_url::Union{String, Nothing} = nothing,
            trade_ws_url::Union{String, Nothing} = nothing,
            language::Language.T = Language.ZH_CN,
            enable_overnight::Bool = true   # 美股夜盘交易行情，需订阅US LV1实时行情并开启enable_overnight参数，否则会返回null
        )
            new(
                app_key,
                app_secret,
                access_token,
                token_expire_time,
                http_url,
                quote_ws_url,
                trade_ws_url,
                language,
                enable_overnight,
                :apikey,
                nothing
            )
        end
    end

    """
    Create a new `config` from TOML configuration file

    Args:
        path: Path to the TOML configuration file

    Returns:
        config instance
    """
    function from_toml(path::String)
        if !isfile(path)
            throw(LongBridgeException("Config file not found: $path"))
        end
        
        # URLs - use Constant defaults
        http_url = DEFAULT_HTTP_URL_CN
        quote_ws_url = DEFAULT_QUOTE_WS_CN
        trade_ws_url = DEFAULT_TRADE_WS_CN
        
        config_dict = TOML.parsefile(path)
        
        # Required fields
        required_keys = ["app_key", "app_secret", "access_token"]
        for key in required_keys
            if !haskey(config_dict, key)
                throw(LongBridgeException("Missing required config key: $key"))
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
            headers = Dict(
                "Authorization" => "Bearer " * access_token,
                "X-API-KEY" => app_key
            )
            query_param = Dict(
                "expired_at" => raw_dt
            )
            try
                resp = HTTP.get(url; headers = headers, query = query_param)
                data = JSON3.read(String(resp.body))
                if data.code == 0
                    access_token = data.data.token
                    raw_expired_at = data.data.expired_at
                    if endswith(raw_expired_at, "Z")
                        raw_expired_at = chop(raw_expired_at)
                    end
                    token_expire_time = DateTime(raw_expired_at)
                    config_dict["access_token"] = access_token
                    config_dict["token_expire_time"] = string(token_expire_time)
                    open(path, "w") do f
                        TOML.print(f, config_dict)
                    end
                else
                    @warn "refresh token failed: $(data.message)"
                end
            catch e
                @warn "refresh token exception: $e"
            end
        end
        
        config(
            app_key,
            app_secret,
            access_token,
            token_expire_time;
            http_url = http_url,
            quote_ws_url = quote_ws_url,
            trade_ws_url = trade_ws_url
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
            joinpath(dirname(@__DIR__), "config.toml")
        ]
        
        for path in config_paths
            if isfile(path)
                return from_toml(path)
            end
        end
        
        throw(LongBridgeException("Config file not found. Please create config.toml in one of these locations: $(join(config_paths, ", "))"))
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
        http_url::Union{String, Nothing} = DEFAULT_HTTP_URL_CN,
        quote_ws_url::Union{String, Nothing} = DEFAULT_QUOTE_WS_CN,
        trade_ws_url::Union{String, Nothing} = DEFAULT_TRADE_WS_CN,
        language::Language.T = Language.ZH_CN,
        enable_overnight::Bool = true
    )
        cfg = config(
            oauth_handle.client_id,   # app_key = client_id
            "",                        # app_secret not needed for OAuth
            "",                        # access_token resolved dynamically
            DateTime(9999, 12, 31);    # placeholder, not used in OAuth mode
            http_url = http_url,
            quote_ws_url = quote_ws_url,
            trade_ws_url = trade_ws_url,
            language = language,
            enable_overnight = enable_overnight
        )
        cfg.auth_mode = :oauth
        cfg.oauth = oauth_handle
        return cfg
    end

end # module Config
