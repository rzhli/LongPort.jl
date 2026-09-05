using Test
using LongBridge
using LongBridge.MarketProtocol:
    _market_trade_status_allow_trading,
    _market_trade_status_code,
    _market_trade_status_from_int,
    _market_trade_status_is_special,
    _market_trade_status_is_trading,
    _market_trade_status_label,
    _market_trade_status_name,
    _market_trade_status_normalize
using LongBridge.Utils: construct
using JSON

# =========================================================================
# v0.8.6 同步上游 LongBridge OpenAPI v4.3.3（market TradeStatus）
# =========================================================================

@testset "market TradeStatus 状态表" begin
    codes = [
        101, 102, 103, 105, 106, 107, 108, 110, 111, 112, 120, 121, 122, 123,
        201, 202, 203, 204, 206, 207, 1000, 1001, 1002, 1003, 1004, 1005,
        1006, 1007, 1008, 1009, 1010, 1011, 2001,
    ]

    for code in codes
        @test _market_trade_status_code(_market_trade_status_from_int(code)) == code
    end

    @test _market_trade_status_from_int(456) === MarketTradeStatus.UNKNOWN
    @test _market_trade_status_from_int(2001) === MarketTradeStatus.FUSE
    @test _market_trade_status_name(_market_trade_status_from_int(123)) == "Temporary Break"
    @test _market_trade_status_name(_market_trade_status_from_int(1009)) == "Not Listed"
    @test _market_trade_status_name(_market_trade_status_from_int(1010)) == "Terminated"
    @test _market_trade_status_name(_market_trade_status_from_int(2001)) == "Fuse"
end

@testset "market TradeStatus display helpers" begin
    @test _market_trade_status_normalize(MarketTradeStatus.CLEAN) === MarketTradeStatus.CLOSING
    @test _market_trade_status_normalize(MarketTradeStatus.US_CLEAN) === MarketTradeStatus.US_PREV
    @test _market_trade_status_normalize(MarketTradeStatus.US_PREV_MARKET_CLEAN) === MarketTradeStatus.US_CLOSING
    @test _market_trade_status_normalize(MarketTradeStatus.US_AFTER_MARKET_CLEAN) === MarketTradeStatus.US_TRADING

    @test _market_trade_status_label(MarketTradeStatus.US_PREV) == "Pre-Market"
    @test _market_trade_status_label(MarketTradeStatus.US_CLEAN) == "Pre-Market"
    @test _market_trade_status_label(MarketTradeStatus.US_AFTER) == "Post-Market"
    @test _market_trade_status_label(MarketTradeStatus.US_CLOSING) == "Closed"
    @test _market_trade_status_label(MarketTradeStatus.US_AFTER_MARKET_CLEAN) == "Trading"
    @test _market_trade_status_label(MarketTradeStatus.TRADING) == "Trading"
    @test _market_trade_status_label(MarketTradeStatus.OPEN_BID) == ""

    @test _market_trade_status_is_trading(MarketTradeStatus.US_AFTER_MARKET_CLEAN)
    @test _market_trade_status_allow_trading(MarketTradeStatus.NOON_CLOSING)
    @test _market_trade_status_is_special(MarketTradeStatus.FUSE)
end

@testset "MarketTimeItem 使用 market TradeStatus" begin
    item = construct(MarketTimeItem, JSON.parse("""
        {"market":"US","trade_status":202,"timestamp":"1717200000",
         "delay_trade_status":204,"delay_timestamp":"1717200000",
         "sub_status":0,"delay_sub_status":0}"""))

    @test item.trade_status === MarketTradeStatus.US_TRADING
    @test item.delay_trade_status === MarketTradeStatus.US_CLOSING
    @test LongBridge.MarketProtocol.TradeStatus.US_TRADING === MarketTradeStatus.US_TRADING
    @test LongBridge.TradeStatus.Normal === LongBridge.QuoteProtocol.TradeStatus.Normal
end
