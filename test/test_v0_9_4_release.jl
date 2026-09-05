using Test
using Dates
using Base: ismutabletype

function _v094_test_config()
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

@testset "v0.9.4 release metadata" begin
    @test VersionNumber(LongBridge.VERSION) >= v"0.9.4"

    # Both the public handle and the worker state are mutable. The handle is
    # mutable because Julia requires a mutable object to attach a finalizer; the
    # worker state is mutable because the background tasks update it. Users never
    # mutate the handle's `inner` field (it is private).
    @test ismutabletype(LongBridge.QuoteContext)
    @test ismutabletype(LongBridge.TradeContext)
    @test ismutabletype(LongBridge.Quote.InnerQuoteContext)
    @test ismutabletype(LongBridge.Trade.InnerTradeContext)

    # The handle exposes exactly one field: the inner worker reference.
    @test fieldnames(LongBridge.QuoteContext) == (:inner,)
    @test fieldnames(LongBridge.TradeContext) == (:inner,)
end

@testset "v0.9.4 outer/inner handle split keeps finalizer cleanup" begin
    cfg = _v094_test_config()

    quote_ctx = LongBridge.Quote._build_quote_context(cfg; start_tasks = false)
    @test quote_ctx isa LongBridge.QuoteContext
    @test quote_ctx.inner isa LongBridge.Quote.InnerQuoteContext
    finalize(quote_ctx)
    @test quote_ctx.inner.shutdown[]
    @test !isopen(quote_ctx.inner.command_ch)
    close(quote_ctx)

    trade_ctx = LongBridge.Trade._build_trade_context(cfg; start_tasks = false)
    @test trade_ctx isa LongBridge.TradeContext
    @test trade_ctx.inner isa LongBridge.Trade.InnerTradeContext
    finalize(trade_ctx)
    @test trade_ctx.inner.shutdown[]
    @test !isopen(trade_ctx.inner.command_ch)
    close(trade_ctx)
end
