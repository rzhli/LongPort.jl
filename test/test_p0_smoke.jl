using Test
using LongBridge
using LongBridge.TradeProtocol: AccountBalance, BalanceType, CashFlow, CashFlowDirection,
                               CashInfo, FrozenTransactionFee, FundPositionChannel,
                               FundPositionsResponse, RiskLevel, StockPositionChannel,
                               StockPositionsResponse
using LongBridge.Utils: Dec64, symbol_to_counter_id, index_symbol_to_counter_id,
                       counter_id_to_symbol, lookup_counter_id, is_etf,
                       _parse_optional_decimal, safeparse, construct
using JSON, Dates

# =========================================================================
# P0: 新增 Context 全部加载并可构造
# =========================================================================

@testset "P0 Context constructors" begin
    cfg = LongBridge.Config.Settings(
        "k", "s", "t", DateTime(2099, 1, 1);
        http_url     = "https://example.test",
        quote_ws_url = "wss://example.test",
        trade_ws_url = "wss://example.test",
    )
    @test FundamentalContext(cfg) isa FundamentalContext
    @test MarketContext(cfg) isa MarketContext
    @test CalendarContext(cfg) isa CalendarContext
    @test PortfolioContext(cfg) isa PortfolioContext
end

# =========================================================================
# Utils 扩展
# =========================================================================

@testset "symbol ↔ counter_id" begin
    @test symbol_to_counter_id("TSLA.US") == "ST/US/TSLA"
    @test symbol_to_counter_id("700.HK")  == "ST/HK/700"
    @test symbol_to_counter_id("00700.HK") == "ST/HK/700"
    @test symbol_to_counter_id("09988.HK") == "ST/HK/9988"
    @test symbol_to_counter_id("000001.SZ") == "ST/SZ/000001"
    @test symbol_to_counter_id("SPY.US")  == "ETF/US/SPY"
    @test symbol_to_counter_id("DRAM.US") == "ETF/US/DRAM"
    @test symbol_to_counter_id("HSI.HK") == "IX/HK/HSI"
    @test symbol_to_counter_id(".DJI.US") == "IX/US/.DJI"
    @test symbol_to_counter_id("10005.HK") == "WT/HK/10005"
    @test symbol_to_counter_id("NOSYMBOL") == "NOSYMBOL"
    @test index_symbol_to_counter_id("HSI.HK") == "IX/HK/HSI"
    @test counter_id_to_symbol("ST/US/TSLA") == "TSLA.US"
    @test counter_id_to_symbol("ETF/US/SPY") == "SPY.US"
    @test counter_id_to_symbol("IX/HK/HSI")  == "HSI.HK"
    @test counter_id_to_symbol("IX/US/.DJI") == ".DJI.US"
    @test counter_id_to_symbol("WT/HK/10005") == "10005.HK"
    @test counter_id_to_symbol("noslash")    == "noslash"
    @test lookup_counter_id("QQQ.US") == "ETF/US/QQQ"
    @test lookup_counter_id("HSI.HK") == "IX/HK/HSI"
    @test lookup_counter_id("TSLA.US") === nothing
    @test is_etf("SPY.US")
    @test is_etf("DRAM.US")
    @test !is_etf("TSLA.US")
    @test !is_etf("HSI.HK")
end

@testset "Decimal parsing" begin
    @test safeparse(Dec64, "")     == Dec64(0)
    @test safeparse(Dec64, "1.23") == Dec64("1.23")
    @test safeparse(Float64, 1) == 1.0
    @test safeparse(BalanceType.T, 1) === BalanceType.Cash
    @test isnothing(_parse_optional_decimal(nothing))
    @test isnothing(_parse_optional_decimal(""))
    @test _parse_optional_decimal("3.14")  == Dec64("3.14")
    @test _parse_optional_decimal(42)      == Dec64(42)
    # API 偶尔返回 "--" 等占位符表示无数据
    @test isnothing(_parse_optional_decimal("--"))
    @test isnothing(_parse_optional_decimal("N/A"))
end

# =========================================================================
# Trade
# =========================================================================

@testset "Trade account balance parsing" begin
    raw = """
    {"total_cash":"1000.5","max_finance_amount":"5000","remaining_finance_amount":"4500",
     "risk_level":"Moderate","margin_call":"0","currency":"USD",
     "cash_infos":[{"withdraw_cash":"800","available_cash":"900.25","frozen_cash":"50",
                    "settling_cash":"150","currency":"USD"}],
     "net_assets":"1200.75","init_margin":"100","maintenance_margin":"80","buy_power":"3000",
     "frozen_transaction_fees":[{"currency":"HKD","frozen_transaction_fee":"12.34"}],
     "market":"US"}"""
    balance = construct(AccountBalance, JSON.parse(raw))

    @test balance.currency === Currency.USD
    @test balance.risk_level === RiskLevel.Moderate
    @test balance.market === Market.US
    @test balance.total_cash == 1000.5
    @test length(balance.cash_infos) == 1
    @test balance.cash_infos[1] isa CashInfo
    @test balance.cash_infos[1].available_cash == 900.25
    @test length(balance.frozen_transaction_fees) == 1
    @test balance.frozen_transaction_fees[1] isa FrozenTransactionFee
    @test balance.frozen_transaction_fees[1].frozen_transaction_fee == 12.34
end

@testset "Trade cash flow parsing" begin
    raw = """
    {"transaction_flow_name":"存入资金","direction":1,"business_type":0,
     "balance":1000.5,"currency":"USD","business_time":"1746748800",
     "symbol":null,"description":"deposit"}"""
    flow = construct(CashFlow, JSON.parse(raw))

    @test flow.transaction_flow_name == "存入资金"
    @test flow.direction === CashFlowDirection.Out
    @test flow.business_type === BalanceType.UnknownBalance
    @test flow.balance == 1000.5
    @test flow.business_time == unix2datetime(1746748800)
    @test isnothing(flow.symbol)
    @test flow.description == "deposit"

    business_time = string(unix2datetime(1746748800))
    @test sprint(show, flow) == "CashFlow($(business_time), Out, 1000.5 USD, 存入资金)"
    vector_display = sprint(show, MIME"text/plain"(), [flow])
    @test occursin("Cash Flows: 1", vector_display)
    @test occursin("$(business_time) | Out | 1000.5 USD | 存入资金", vector_display)
end

@testset "Trade position display" begin
    funds = FundPositionsResponse(FundPositionChannel[])
    stocks = StockPositionsResponse([StockPositionChannel("lb", [])])

    @test sprint(show, funds) == "Fund Positions: 0 funds in 0 channels"
    @test sprint(show, stocks) == "Stock Positions: 0 stocks in 1 channel\n  - lb: 0 stocks"
end

# =========================================================================
# Calendar
# =========================================================================

@testset "Calendar enum & parsing" begin
    @test CalendarCategory.Report    isa CalendarCategory.T
    @test CalendarCategory.MacroData isa CalendarCategory.T

    import LongBridge.CalendarProtocol: _calendar_category_str
    @test _calendar_category_str(CalendarCategory.Report)    == "report"
    @test _calendar_category_str(CalendarCategory.Dividend)  == "dividend"
    @test _calendar_category_str(CalendarCategory.MacroData) == "macrodata"
    @test _calendar_category_str(CalendarCategory.Merge)     == "merge"

    raw = """
    {"date":"2026-05-15","next_date":"2026-05-16","list":[{"date":"2026-05-15","count":1,"infos":[
      {"counter_id":"ST/HK/700","market":"HK","content":"Q1 财报","counter_name":"腾讯",
       "date":"2026.05.15","data_kv":[{"key":"EPS","value":"3.21","type":"estimate_eps","value_raw":"3.21"}],
       "type":"financial","datetime":"1747257600","star":3,"id":"evt-1","live":null,"ext":null}
    ]}]}
    """
    resp = construct(CalendarEventsResponse, JSON.parse(raw))
    @test resp.date == "2026-05-15"
    @test resp.next_date == "2026-05-16"
    @test length(resp.list[1].infos) == 1
    info = resp.list[1].infos[1]
    @test info.symbol == "700.HK"
    @test info.event_type == "financial"
    @test info.data_kv[1].value_raw == Dec64("3.21")

    # 空响应
    empty_resp = construct(CalendarEventsResponse, JSON.parse("""{"date":"x","list":[]}"""))
    @test empty_resp.next_date == ""
    @test isempty(empty_resp.list)
end

# =========================================================================
# Portfolio
# =========================================================================

@testset "Portfolio enums & parsing" begin
    import LongBridge.PortfolioProtocol: _flow_direction_from_str, _asset_type_from_str
    @test _flow_direction_from_str("buy")  === FlowDirection.Buy
    @test _flow_direction_from_str("sell") === FlowDirection.Sell
    @test _flow_direction_from_str("xx")   === FlowDirection.Unknown
    @test _asset_type_from_str("stock")    === AssetType.Stock
    @test _asset_type_from_str("crypto")   === AssetType.Crypto

    # ExchangeRates
    exr = construct(ExchangeRates, JSON.parse("""
        {"exchanges":[{"average_rate":7.79,"base_currency":"USD","bid_rate":7.78,"offer_rate":7.80,"other_currency":"HKD"}]}"""))
    @test length(exr.exchanges) == 1
    @test exr.exchanges[1].base_currency == "USD"

    # FlowItem
    fi = construct(FlowItem, JSON.parse("""
        {"executed_date":"2026-05-15","code":"AAPL","direction":"buy",
         "executed_quantity":"100","executed_price":"172.50","executed_cost":"17250"}"""))
    @test fi.direction === FlowDirection.Buy
    @test fi.executed_quantity == Dec64("100")
    @test fi.executed_timestamp === nothing

    fi2 = construct(FlowItem, JSON.parse("""
        {"executed_date":"2026-05-15","executed_timestamp":"1747257600",
         "code":"AAPL","direction":"sell"}"""))
    @test fi2.direction === FlowDirection.Sell
    @test fi2.executed_timestamp == "1747257600"

    # 空字段兜底
    bm = construct(ProfitAnalysisByMarket, JSON.parse("""{}"""))
    @test !bm.has_more
    @test isnothing(bm.profit)
end

# =========================================================================
# Market
# =========================================================================

@testset "Market enums & parsing" begin
    import LongBridge.MarketProtocol: _broker_holding_period_str, _ah_premium_period_line_type, _market_from_str
    @test _broker_holding_period_str(BrokerHoldingPeriod.Rct1)  == "rct_1"
    @test _broker_holding_period_str(BrokerHoldingPeriod.Rct60) == "rct_60"
    @test _ah_premium_period_line_type(AhPremiumPeriod.Min5)    == "5"
    @test _ah_premium_period_line_type(AhPremiumPeriod.Day)     == "1000"
    @test _ah_premium_period_line_type(AhPremiumPeriod.Year)    == "4000"
    @test _market_from_str("US") === Market.US
    @test _market_from_str("HK") === Market.HK
    @test _market_from_str("xx") === Market.Unknown

    # MarketStatusResponse
    ms = construct(MarketStatusResponse, JSON.parse("""
        {"market_time":[{"market":"HK","trade_status":102,"timestamp":"1747257600",
         "delay_trade_status":108,"delay_timestamp":"1747257600","sub_status":0,"delay_sub_status":0}]}"""))
    @test length(ms.market_time) == 1
    @test ms.market_time[1].market === Market.HK
    @test ms.market_time[1].trade_status === MarketTradeStatus.OPEN_BID
    @test ms.market_time[1].delay_trade_status === MarketTradeStatus.CLOSING
    @test LongBridge.MarketProtocol._market_trade_status_code(ms.market_time[1].trade_status) == 102

    # BrokerHoldingTop（含 chg 为空）
    top = construct(BrokerHoldingTop, JSON.parse("""
        {"buy":[{"name":"瑞银","parti_number":"6727","chg":"1000","strong":true},
                {"name":"中金","parti_number":"6996","chg":"","strong":false}],
         "sell":[],"updated_at":"2026-05-15"}"""))
    @test length(top.buy) == 2
    @test top.buy[1].chg == Dec64("1000")
    @test isnothing(top.buy[2].chg)

    # AhPremiumKline (empty_is_zero 语义)
    ahk = construct(AhPremiumKline, JSON.parse("""
        {"aprice":"42.5","apreclose":"","hprice":"380","hpreclose":"385",
         "currency_rate":"0.91","ahpremium_rate":"-15.2","price_spread":"-12.5","timestamp":"1747257600"}"""))
    @test ahk.aprice == Dec64("42.5")
    @test ahk.apreclose == Dec64(0)

    # ConstituentStock (counter_id 转换 + JSON null 兜底)
    cs = construct(ConstituentStock, JSON.parse("""
        {"counter_id":"ST/HK/700","name":"腾讯","last_done":"380.5","prev_close":"385",
         "inflow":"-1500000","balance":null,"amount":"15000000","total_shares":"9000000000",
         "tags":["龙头"],"intro":"互联网","market":"HK","circulating_shares":"3000000000",
         "delay":false,"chg":"-1.17","trade_status":102}"""))
    @test cs.symbol == "700.HK"
    @test cs.last_done == Dec64("380.5")
    @test isnothing(cs.balance)
    @test cs.tags == ["龙头"]
end

# =========================================================================
# Fundamental
# =========================================================================

@testset "Fundamental enums & parsing" begin
    import LongBridge.FundamentalProtocol: _financial_report_kind_str, _financial_report_period_str, _institution_recommend_from_str
    @test _financial_report_kind_str(FinancialReportKind.IncomeStatement) == "IS"
    @test _financial_report_kind_str(FinancialReportKind.BalanceSheet)    == "BS"
    @test _financial_report_kind_str(FinancialReportKind.CashFlow)        == "CF"
    @test _financial_report_kind_str(FinancialReportKind.All)             == "ALL"
    @test _financial_report_period_str(FinancialReportPeriod.Annual)      == "af"
    @test _financial_report_period_str(FinancialReportPeriod.ThreeQ)      == "3q"
    @test _institution_recommend_from_str("buy")         === InstitutionRecommend.Buy
    @test _institution_recommend_from_str("strong_sell") === InstitutionRecommend.StrongSell
    @test _institution_recommend_from_str("xx")          === InstitutionRecommend.Unknown

    # DividendList
    dl = construct(DividendList, JSON.parse("""
        {"list":[{"counter_id":"ST/HK/700","id":"1","desc":"每股派息 5.3 HKD",
                  "record_date":"2026.05.18","ex_date":"2026.05.15","payment_date":"2026.06.01"}]}"""))
    @test length(dl.list) == 1
    @test dl.list[1].symbol == "700.HK"

    # InstitutionRatingSummary (recommend 字符串映射 + 可选 Decimal)
    rs = construct(InstitutionRatingSummary, JSON.parse("""
        {"ccy_symbol":"HK\$","change":"5.2","recommend":"buy","target":"420","updated_at":"x",
         "evaluate":{"buy":5,"date":"2026-05-15","hold":3,"sell":0,"strong_buy":2,"under":0}}"""))
    @test rs.recommend === InstitutionRecommend.Buy
    @test rs.target == Dec64("420")

    # CompanyOverview (注意 "Phone" 大写字段)
    co_raw = """
    {"name":"腾讯","company_name":"腾讯控股","founded":"1998","listing_date":"2004-06-16",
     "market":"港交所","region":"HK","address":"开曼","office_address":"深圳","website":"tencent.com",
     "issue_price":"3.7","shares_offered":"100000000","chairman":"马化腾","secretary":"郭凯天",
     "audit_inst":"PwC","category":"互联网","year_end":"12 月 31 日","employees":"110000",
     "Phone":"+86-755","fax":"+86-755","email":"ir@tencent.com","legal_repr":"马化腾","manager":"马化腾",
     "bus_license":"123","accounting_firm":"PwC","securities_rep":"郭凯天","legal_counsel":"金杜",
     "zip_code":"518057","ticker":"00700","icon":"http://x/icon","profile":"互联网","sector":1001}
    """
    co = construct(CompanyOverview, JSON.parse(co_raw))
    @test co.phone == "+86-755"
    @test co.issue_price == Dec64("3.7")
    @test co.sector == 1001

    # FundHolder (position_ratio 用 empty_is_zero)
    fh = construct(FundHolder, JSON.parse("""
        {"code":"513050","counter_id":"ETF/SH/513050","currency":"CNY","name":"中概 ETF",
         "position_ratio":"0.05","report_date":"2025.12.31"}"""))
    @test fh.symbol == "513050.SH"
    @test fh.position_ratio == Dec64("0.05")

    # FundHolder（position_ratio 缺失）
    fh2 = construct(FundHolder, JSON.parse("""
        {"code":"X","counter_id":"ETF/SH/X","currency":"CNY","name":"X","position_ratio":"","report_date":""}"""))
    @test fh2.position_ratio == Dec64(0)
end

# =========================================================================
# QuoteContext v4.1.0 新增
# =========================================================================

@testset "QuoteContext v4.1.0 additions" begin
    import LongBridge.Quote: _pinned_mode_str
    @test PinnedMode.Add isa PinnedMode.T
    @test _pinned_mode_str(PinnedMode.Add)    == "add"
    @test _pinned_mode_str(PinnedMode.Remove) == "remove"

    # ShortPositionsResponse —— v0.8.0 改为不再含 symbol/sources 外层字段，
    # 且 item 是 ShortPositionsItem，timestamp 现在是 DateTime (UTC)。
    sp = construct(ShortPositionsResponse, JSON.parse("""
        {"counter_id":"ST/US/TSLA","data":[
          {"timestamp":"1747257600","rate":"0.03","avg_daily_share_volume":"100000000",
           "current_shares_short":"50000000","days_to_cover":"0.5","close":"350.5"}]}"""))
    @test length(sp.data) == 1
    @test sp.data[1] isa ShortPositionsItem
    @test sp.data[1].timestamp == unix2datetime(1747257600)
    @test sp.data[1].rate == "0.03"
    @test sp.data[1].current_shares_short == "50000000"

    # OptionVolumeStats
    ov = construct(OptionVolumeStats, JSON.parse("""{"c":"100000","p":"50000"}"""))
    @test ov.c == "100000"
    @test ov.p == "50000"

    # OptionVolumeDaily
    ovd = construct(OptionVolumeDaily, JSON.parse("""
        {"stats":[{"underlying_counter_id":"ST/US/AAPL","timestamp":"1747257600",
                   "total_volume":"1000","total_put_volume":"400","total_call_volume":"600",
                   "put_call_volume_ratio":"0.67","total_open_interest":"10000",
                   "total_put_open_interest":"4000","total_call_open_interest":"6000",
                   "put_call_open_interest_ratio":"0.67"}]}"""))
    @test length(ovd.stats) == 1
    @test ovd.stats[1].symbol == "AAPL.US"
end

# =========================================================================
# 完整 export 检查
# =========================================================================

@testset "Public API exports" begin
    for s in (:FundamentalContext, :MarketContext, :CalendarContext, :PortfolioContext,
              :financial_report, :institution_rating, :dividend, :forecast_eps, :valuation,
              :company, :executive, :shareholder, :corp_action,
              :market_status, :broker_holding, :ah_premium, :trade_stats, :anomaly, :constituent,
              :finance_calendar,
              :exchange_rate, :profit_analysis,
              :short_positions, :option_volume, :option_volume_daily, :update_pinned,
              :FinancialReportKind, :CalendarCategory, :BrokerHoldingPeriod, :PinnedMode,
              :FlowDirection, :AssetType, :InstitutionRecommend,
              # v0.8.0 additions (LongPort SDK v4.2.0)
              :ScreenerContext, :screener_indicators, :screener_recommend_strategies,
              :screener_user_strategies, :screener_strategy, :screener_search,
              :short_trades, :ShortPositionsItem, :ShortTradesItem,
              :top_movers, :rank_categories, :rank_list,
              :TopMoversEvent, :TopMoversResponse, :RankListItem,
              :symbol_to_counter_ids, :resolve_counter_ids,
              :business_segments, :business_segments_history,
              :institution_rating_views, :industry_rank, :industry_peers,
              :financial_report_snapshot, :shareholder_top, :shareholder_detail,
              :valuation_comparison, :etf_asset_allocation,
              :FinancialReportSnapshot, :ValuationComparisonItem, :IndustryPeerNode,
              :ElementType, :AssetAllocationResponse, :AssetAllocationGroup,
              :AssetAllocationItem, :HoldingDetail)
        @test isdefined(LongBridge, s)
    end
end
