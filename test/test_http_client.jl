using Test
using Dates
using HTTP, JSON, SHA
using HTTP: WebSockets
using LongBridge

# HTTP 层回归：进程级共享 client 的配置、单一 HTTP.request 入口的线路格式、
# 签名与 header 归一化，以及对齐上游 Rust SDK 的 429 重试策略。

const _HTTPClient = LongBridge.HttpClient
const _LBClient = LongBridge.Client

function _http_test_config(url::String; papertrading::Bool = false)
    return LongBridge.Config.Settings(
        "app_key_x",
        "app_secret_y",
        "tok_z",
        DateTime(2099, 1, 1);
        http_url = url,
        quote_ws_url = "wss://quote.test",
        trade_ws_url = "wss://trade.test",
        enable_papertrading = papertrading,
    )
end

@testset "Shared HTTP client configuration" begin
    client = _HTTPClient.HTTP_CLIENT
    @test client.cookiejar === nothing
    @test client.default_connect_timeout == _HTTPClient.DEFAULT_TIMEOUT.connect
    @test client.default_read_idle_timeout == _HTTPClient.DEFAULT_TIMEOUT.read
    @test client.default_write_idle_timeout == _HTTPClient.DEFAULT_TIMEOUT.write
    # 整体截止时间：HTTP.jl 只在 kwarg 为 0 时回落到 Client 默认值
    @test client.default_request_timeout == _HTTPClient.DEFAULT_TIMEOUT.request
    @test client.default_request_timeout > 0

    # User-Agent 覆盖 HTTP.jl 的默认 "HTTP.jl/<版本>"
    @test startswith(_HTTPClient.USER_AGENT, "openapi-sdk ")
    @test occursin(LongBridge.VERSION, _HTTPClient.USER_AGENT)
    @test HTTP.header(client.default_headers, "User-Agent") == _HTTPClient.USER_AGENT

    # Token 类接口共用一套放宽的超时
    kw = _HTTPClient.TOKEN_REQUEST_KW
    @test kw.client === client
    @test kw.connect_timeout == _HTTPClient.OAUTH_TIMEOUT.connect
    @test kw.request_timeout == _HTTPClient.OAUTH_TIMEOUT.request
    @test kw.response_header_timeout == _HTTPClient.OAUTH_TIMEOUT.response_header
    @test kw.read_idle_timeout == _HTTPClient.OAUTH_TIMEOUT.read
end

@testset "Retry policy defers to HTTP.jl except for 429" begin
    # 429 无论方法都重试（网关限流时请求未被执行）
    @test _LBClient._retry_rate_limited(1, nothing, nothing, HTTP.Response(429)) === true
    # 其余交回内置策略：非幂等方法不会被自动重发
    @test _LBClient._retry_rate_limited(1, nothing, nothing, HTTP.Response(500)) === nothing
    @test _LBClient._retry_rate_limited(1, nothing, nothing, HTTP.Response(200)) === nothing
    @test _LBClient._retry_rate_limited(1, EOFError(), nothing, nothing) === nothing
end

@testset "Request signature covers method/path/query/body" begin
    cfg = _http_test_config("https://example.test")
    sig = _LBClient.sign("GET", "/v1/quote", "1700000000000", "symbol=700.HK", "", cfg)
    @test startswith(sig, "HMAC-SHA256 SignedHeaders=authorization;x-api-key;x-timestamp, Signature=")
    # 相同输入必须稳定（线路格式回归）
    @test sig == _LBClient.sign("GET", "/v1/quote", "1700000000000", "symbol=700.HK", "", cfg)
    # 任一签名输入变化都必须改变签名
    @test sig != _LBClient.sign("POST", "/v1/quote", "1700000000000", "symbol=700.HK", "", cfg)
    @test sig != _LBClient.sign("GET", "/v1/other", "1700000000000", "symbol=700.HK", "", cfg)
    @test sig != _LBClient.sign("GET", "/v1/quote", "1700000000001", "symbol=700.HK", "", cfg)
    @test sig != _LBClient.sign("GET", "/v1/quote", "1700000000000", "symbol=AAPL.US", "", cfg)
    @test sig != _LBClient.sign("GET", "/v1/quote", "1700000000000", "symbol=700.HK", "{}", cfg)
    # OAuth 模式（无 app_secret）不签名
    oauth_cfg = LongBridge.Config.Settings(
        "app_key_x", "", "tok_z", DateTime(2099, 1, 1); http_url = "https://example.test")
    @test _LBClient.sign("GET", "/v1/quote", "1700000000000", "", "", oauth_cfg) === nothing
end

@testset "Response header lookup is case-insensitive" begin
    resp = HTTP.Response(
        200,
        ["Content-Type" => "application/json", "X-Trace-Id" => "tid-1", "x-request-id" => "rid-1"];
        body = """{"code":0,"message":"success","data":{"ok":true}}""",
    )
    api = LongBridge.Errors.ApiResponse(resp)
    @test api.code == 0
    @test api.headers["x-trace-id"] == "tid-1"
    @test api.headers["x-request-id"] == "rid-1"
    @test LongBridge.Errors._header_value(api.headers, "X-Trace-Id") == "tid-1"
    @test LongBridge.Errors._header_value(api.headers, "x-trace-id") == "tid-1"
    @test LongBridge.Errors._header_value(api.headers, "missing") == ""
end

@testset "REST wire format over loopback" begin
    seen = Vector{NamedTuple}()
    ratelimit_pending = Ref(true)

    server = HTTP.serve!("127.0.0.1", 0; listenany = true) do req
        uri = HTTP.URI(req.target)
        push!(seen, (
            method = req.method,
            path = String(uri.path),
            query = String(uri.query),
            headers = Dict(lowercase(k) => v for (k, v) in req.headers),
            body = String(req.body),
        ))
        if uri.path == "/v1/ratelimit" && ratelimit_pending[]
            ratelimit_pending[] = false
            return HTTP.Response(
                429,
                ["Content-Type" => "application/json", "Retry-After" => "0"];
                body = """{"code":429,"message":"too many requests"}""",
            )
        end
        return HTTP.Response(
            200,
            ["Content-Type" => "application/json", "x-request-id" => "rid-1"];
            body = """{"code":0,"message":"success","data":{"ok":true}}""",
        )
    end

    try
        url = "http://127.0.0.1:$(HTTP.port(server))"
        cfg = _http_test_config(url)

        # GET：query 参与签名，必须原样上线；重复 key 展开为多个参数
        resp = LongBridge.Client.http_get(
            cfg, "/v1/quote"; params = Dict{String,Any}("symbol" => ["700.HK", "AAPL.US"]))
        got = seen[end]
        @test resp.status == 200
        @test got.method == "GET"
        @test got.path == "/v1/quote"
        @test got.query == "symbol=700.HK&symbol=AAPL.US"
        @test isempty(got.body)
        @test got.headers["user-agent"] == _HTTPClient.USER_AGENT
        @test got.headers["x-api-key"] == "app_key_x"
        @test got.headers["authorization"] == "tok_z"
        @test got.headers["content-type"] == "application/json; charset=utf-8"
        @test got.headers["x-dc-region"] == "ap"
        @test !haskey(got.headers, "x-papertrading")
        @test haskey(got.headers, "x-timestamp")
        @test got.headers["x-api-signature"] == _LBClient.sign(
            "GET", "/v1/quote", got.headers["x-timestamp"], got.query, "", cfg)

        # POST：JSON body 参与签名
        LongBridge.Client.http_post(cfg, "/v1/trade/order"; body = Dict("symbol" => "700.HK"))
        got = seen[end]
        @test got.method == "POST"
        @test got.body == """{"symbol":"700.HK"}"""
        @test got.headers["x-api-signature"] == _LBClient.sign(
            "POST", "/v1/trade/order", got.headers["x-timestamp"], "", got.body, cfg)

        # PUT
        LongBridge.Client.http_put(cfg, "/v1/trade/order"; body = Dict("order_id" => "1"))
        got = seen[end]
        @test got.method == "PUT"
        @test got.body == """{"order_id":"1"}"""

        # DELETE：不带 body
        LongBridge.Client.http_delete(
            cfg, "/v1/trade/order"; params = Dict{String,Any}("order_id" => "1"))
        got = seen[end]
        @test got.method == "DELETE"
        @test got.query == "order_id=1"
        @test isempty(got.body)

        # DELETE：带 body（Alert / Sharelist 等接口）
        LongBridge.Client.http_delete(cfg, "/v1/watchlist/groups"; body = Dict("id" => "7"))
        got = seen[end]
        @test got.method == "DELETE"
        @test got.body == """{"id":"7"}"""
        @test got.headers["x-api-signature"] == _LBClient.sign(
            "DELETE", "/v1/watchlist/groups", got.headers["x-timestamp"], "", got.body, cfg)

        # 429：POST 也会重试一次并最终成功
        before = length(seen)
        resp = LongBridge.Client.http_post(cfg, "/v1/ratelimit"; body = Dict("a" => 1))
        @test resp.status == 200
        @test length(seen) - before == 2
        @test all(entry -> entry.method == "POST", seen[(before + 1):end])

        # 模拟盘路由头
        LongBridge.Client.http_get(_http_test_config(url; papertrading = true), "/v1/quote")
        @test seen[end].headers["x-papertrading"] == "true"
    finally
        HTTP.forceclose(server)
    end
end

@testset "WebSocket handshake reuses the shared HTTP client" begin
    seen = Ref{Any}(nothing)
    server = WebSockets.listen!("127.0.0.1", 0; listenany = true) do ws
        seen[] = (
            target = String(ws.handshake_request.target),
            headers = Dict(lowercase(k) => v for (k, v) in ws.handshake_request.headers),
        )
        for msg in ws
            WebSockets.send(ws, msg)
        end
    end

    try
        addr = WebSockets.server_addr(server)
        WebSockets.open(
            "ws://$addr/quote?version=1";
            client = _HTTPClient.HTTP_CLIENT,
            headers = ["x-dc-region" => "ap"],
            connect_timeout = _LBClient.WS_CONNECT_TIMEOUT,
            read_idle_timeout = _LBClient.WS_HEARTBEAT_TIMEOUT,
            write_idle_timeout = _LBClient.WS_WRITE_TIMEOUT,
        ) do ws
            WebSockets.send(ws, UInt8[0x01, 0x02, 0x03])
            @test WebSockets.receive(ws) == UInt8[0x01, 0x02, 0x03]
            # 长连接的空转窗口只能来自 open 的参数；Client 上的 REST 超时
            # （尤其是整体 request_timeout）不得泄漏成 WS 的生命周期上限
            @test ws.read_idle_timeout_ns ==
                  Int64(_LBClient.WS_HEARTBEAT_TIMEOUT) * 1_000_000_000
            @test !WebSockets.isclosed(ws)
        end

        @test seen[].target == "/quote?version=1"
        @test seen[].headers["x-dc-region"] == "ap"
        # 共享 client 没有 cookie jar
        @test !haskey(seen[].headers, "cookie")
        # 显式传 client 时 HTTP.jl 不接管其生命周期：WS 关闭不能关掉共享 client
        @test isopen(_HTTPClient.HTTP_CLIENT)
    finally
        close(server)
    end
end
