using Test
using Dates

function _v093_test_config()
    return LongBridge.Config.Settings(
        "test_app_key",
        "test_app_secret",
        "test_access_token",
        DateTime(2099, 1, 1);
        http_url = "https://openapi.longportapp.com",
        quote_ws_url = "wss://openapi-quote.longportapp.com",
        trade_ws_url = "wss://openapi-trade.longportapp.com",
    )
end

@testset "v0.9.3 release metadata" begin
    @test LongBridge.VERSION == "0.9.3"
    @test hasmethod(close, Tuple{LongBridge.QuoteContext})
    @test hasmethod(close, Tuple{LongBridge.TradeContext})
end

@testset "Process-wide HTTP client" begin
    shared = LongBridge.HttpClient.HTTP_CLIENT
    @test LongBridge.Client.HTTP_CLIENT === shared
    @test LongBridge.Config.HTTP_CLIENT === shared
    @test LongBridge.OAuth.HTTP_CLIENT === shared
    @test shared.cookiejar === nothing
    @test shared.default_connect_timeout == 10
    @test shared.default_read_idle_timeout == 20

    oauth_timeout = LongBridge.HttpClient.OAUTH_TIMEOUT
    @test oauth_timeout.connect == 10
    @test oauth_timeout.request == 60
    @test oauth_timeout.response_header == 10
    @test oauth_timeout.read == 30
end

@testset "WSClient shutdown cancels disconnected reconnect work" begin
    cfg = _v093_test_config()
    client = LongBridge.Client.WSClient(cfg.quote_ws_url, cfg)
    reconnect_task = @async begin
        try
            while !client.shutdown[]
                sleep(0.01)
            end
        catch e
            e isa InterruptException || rethrow(e)
        end
    end
    client.reconnect_task = reconnect_task

    pending = Channel{Tuple{UInt8,Vector{UInt8}}}(1)
    client.pending[UInt32(1)] = pending

    LongBridge.Client.shutdown!(client)
    LongBridge.Client.shutdown!(client) # idempotent

    @test client.shutdown[]
    @test client.reconnect_task === nothing
    @test isempty(client.pending)
    @test !isopen(pending)
    @test timedwait(() -> istaskdone(reconnect_task), 1.0; pollint = 0.01) === :ok
end

@testset "Context shutdown and finalizers are idempotent" begin
    cfg = _v093_test_config()

    quote_ctx = LongBridge.Quote._build_quote_context(cfg; start_tasks = false)
    quote_inner = quote_ctx.inner
    finalize(quote_ctx)
    @test quote_inner.shutdown[]
    @test !isopen(quote_inner.command_ch)
    @test !isopen(quote_inner.push_ch)
    close(quote_ctx)

    trade_ctx = LongBridge.Trade._build_trade_context(cfg; start_tasks = false)
    trade_inner = trade_ctx.inner
    finalize(trade_ctx)
    @test trade_inner.shutdown[]
    @test !isopen(trade_inner.command_ch)
    close(trade_ctx)
end
