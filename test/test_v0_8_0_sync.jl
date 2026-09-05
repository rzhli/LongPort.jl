using Test
using LongBridge
using LongBridge.Utils: construct
using JSON, Dates

# =========================================================================
# v0.8.0 同步上游 LongPort SDK v4.2.0 的新增 / 调整
# =========================================================================

@testset "ScreenerContext constructor" begin
    cfg = LongBridge.Config.Settings(
        "k", "s", "t", DateTime(2099, 1, 1);
        http_url     = "https://example.test",
        quote_ws_url = "wss://example.test",
        trade_ws_url = "wss://example.test",
    )
    @test ScreenerContext(cfg) isa ScreenerContext
end

# ── Quote: ShortPositionsItem / ShortTradesItem ──────────────────────────

@testset "ShortPositionsItem (US)" begin
    item = construct(ShortPositionsItem, JSON.parse("""
        {"timestamp":"1747257600","rate":"0.03","close":"350.5",
         "current_shares_short":"50000000","avg_daily_share_volume":"100000000",
         "days_to_cover":"0.5"}"""))
    @test item.timestamp == unix2datetime(1747257600)
    @test item.rate == "0.03"
    @test item.close == "350.5"
    @test item.current_shares_short == "50000000"
    @test item.avg_daily_share_volume == "100000000"
    @test item.days_to_cover == "0.5"
    # HK-only fields default to "" when not present
    @test item.amount == ""
    @test item.balance == ""
    @test item.cost == ""
end

@testset "ShortPositionsItem (HK)" begin
    item = construct(ShortPositionsItem, JSON.parse("""
        {"timestamp":"1747257600","rate":"0.012","close":"480.0",
         "amount":"123456789","balance":"7000000","cost":"480.0"}"""))
    @test item.timestamp == unix2datetime(1747257600)
    @test item.amount == "123456789"
    @test item.balance == "7000000"
    @test item.cost == "480.0"
    @test item.current_shares_short == ""    # US-only defaults
end

@testset "ShortPositionsResponse" begin
    resp = construct(ShortPositionsResponse, JSON.parse("""
        {"counter_id":"ST/HK/700","data":[
          {"timestamp":"1747257600","rate":"0.012","close":"480.0",
           "amount":"100","balance":"50","cost":"480"},
          {"timestamp":"1747171200","rate":"0.013","close":"479.0",
           "amount":"110","balance":"55","cost":"479"}]}"""))
    @test length(resp.data) == 2
    @test resp.data[1] isa ShortPositionsItem
    @test resp.data[2].rate == "0.013"
    # 空响应兜底
    empty = construct(ShortPositionsResponse, JSON.parse("""{}"""))
    @test isempty(empty.data)
end

@testset "ShortTradesItem (US)" begin
    item = construct(ShortTradesItem, JSON.parse("""
        {"timestamp":"1747257600","rate":"0.045","close":"180.0",
         "nus_amount":"1000","ny_amount":"2000","total_amount":"3000"}"""))
    @test item.timestamp == unix2datetime(1747257600)
    @test item.total_amount == "3000"
    @test item.amount == ""    # HK-only default
end

@testset "ShortTradesResponse" begin
    resp = construct(ShortTradesResponse, JSON.parse("""
        {"counter_id":"ST/HK/700","data":[
          {"timestamp":"1747257600","rate":"0.04","close":"480",
           "amount":"100","balance":"50"}]}"""))
    @test length(resp.data) == 1
    @test resp.data[1].amount == "100"
end

# ── Market: top_movers / rank_list / rank_categories ──────────────────────

@testset "TopMoversEvent + Response" begin
    raw = """
    {"events":[
      {"timestamp":1747257600,"alert_reason":"急涨","alert_type":1,
       "stock":{"counter_id":"ST/US/NVDA","code":"NVDA","name":"NVIDIA",
                "full_name":"NVIDIA Corp","change":"0.05","last_done":"950.0",
                "market":"US","labels":["AI","semi"],"logo":"https://logo/x"},
       "post":{"id":"p1"}},
      {"timestamp":"1747171200","alert_reason":"放量","alert_type":2,
       "stock":{"counter_id":"ST/HK/700","code":"700","name":"腾讯",
                "change":"-0.02","last_done":"480","market":"HK"},
       "post":null}],
     "next_params":{"cursor":"abc"}}
    """
    resp = construct(TopMoversResponse, JSON.parse(raw))
    @test length(resp.events) == 2
    @test resp.events[1].timestamp == unix2datetime(1747257600)
    @test resp.events[2].timestamp == unix2datetime(1747171200)  # 字符串也能解析
    @test resp.events[1].stock.symbol == "NVDA.US"
    @test resp.events[1].stock.labels == ["AI", "semi"]
    @test resp.events[2].stock.symbol == "700.HK"
    @test resp.events[2].stock.labels == String[]                # 缺失字段兜底
end

@testset "RankCategoriesResponse (raw)" begin
    raw = """{"categories":[{"key":"top_gain","name":"涨幅榜"}]}"""
    r = construct(RankCategoriesResponse, JSON.parse(raw))
    @test !isnothing(r.data)
    @test r.data.categories[1].key == "top_gain"
end

@testset "RankListResponse" begin
    raw = """
    {"bmp":true,"lists":[
      {"counter_id":"ST/US/MU","code":"MU","name":"Micron","last_done":"120.0",
       "chg":"0.03","change":"3.5","inflow":"500000","market_cap":"130000000000",
       "industry":"semi","pre_post_price":"121","pre_post_chg":"0.008",
       "amplitude":"0.05","five_day_chg":"0.12","turnover_rate":"0.02",
       "volume_rate":"1.8","pb_ttm":"2.3"}]}
    """
    r = construct(RankListResponse, JSON.parse(raw))
    @test r.bmp == true
    @test length(r.lists) == 1
    @test r.lists[1].symbol == "MU.US"
    @test r.lists[1].pb_ttm == "2.3"
end

# ── Fundamental: 9 个新类型 ───────────────────────────────────────────────

@testset "BusinessSegments + History" begin
    cur = construct(BusinessSegments, JSON.parse("""
        {"date":"2024.12.31","total":"100","currency":"USD",
         "business":[{"name":"云","percent":"40"},{"name":"广告","percent":"35"}]}"""))
    @test cur.date == "2024.12.31"
    @test length(cur.business) == 2
    @test cur.business[1].name == "云"

    hist = construct(BusinessSegmentsHistory, JSON.parse("""
        {"historical":[
          {"date":"2024.12.31","total":"100","currency":"USD",
           "business":[{"name":"云","percent":"40","value":"40"}],
           "regionals":[{"name":"北美","percent":"60","value":"60"}]}]}"""))
    @test length(hist.historical) == 1
    @test hist.historical[1].business[1].value == "40"
    @test hist.historical[1].regionals[1].name == "北美"
end

@testset "InstitutionRatingViews" begin
    v = construct(InstitutionRatingViews, JSON.parse("""
        {"elist":[
          {"date":"1747257600","buy":"10","over":"5","hold":"3","under":"1","sell":"0","total":"19"},
          {"date":1747171200,"buy":"9","over":"4","hold":"3","under":"1","sell":"0","total":"17"}]}"""))
    @test length(v.elist) == 2
    @test v.elist[1].buy == "10"
    @test v.elist[2].date == "1747171200"     # 裸整数也保留为字符串
end

@testset "IndustryPeerNode (recursive)" begin
    raw = """
    {"top":{"name":"半导体","market":"US"},
     "chain":{"name":"半导体","counter_id":"IND/US/SEMI","stock_num":50,
              "chg":"0.02","ytd_chg":"0.15",
              "next":[
                {"name":"晶圆代工","counter_id":"IND/US/FAB","stock_num":5,
                 "chg":"0.03","ytd_chg":"0.2","next":[]}]}}
    """
    r = construct(IndustryPeersResponse, JSON.parse(raw))
    @test r.top.name == "半导体"
    @test !isnothing(r.chain)
    @test r.chain.stock_num == 50
    @test length(r.chain.next) == 1
    @test r.chain.next[1].name == "晶圆代工"
    @test isempty(r.chain.next[1].next)
end

@testset "FinancialReportSnapshot" begin
    raw = """
    {"name":"Apple","ticker":"AAPL","fp_start":"2024-10-01","fp_end":"2024-12-31",
     "currency":"USD","report_desc":"Q1 FY25",
     "fo_revenue":{"value":"124","yoy":"0.05","cmp_desc":"beat","est_value":"123"},
     "fr_revenue":{"value":"124.3","yoy":"0.04"},
     "fr_roe_ttm":"1.5","fr_profit_margin":"0.25","fr_profit_margin_ttm":"0.26",
     "fr_asset_turn_ttm":"1.1","fr_leverage_ttm":"5.0","fr_debt_assets_ratio":"0.8"}
    """
    s = construct(FinancialReportSnapshot, JSON.parse(raw))
    @test s.name == "Apple"
    @test s.fo_revenue.value == "124"
    @test s.fr_revenue.yoy == "0.04"
    @test s.fo_ebit === nothing                # 缺失字段 → nothing
    @test s.fr_roe_ttm == "1.5"
end

@testset "ValuationComparison (history.date → DateTime)" begin
    raw = """
    {"list":[
      {"counter_id":"ST/US/AAPL","name":"Apple","currency":"USD",
       "market_value":"3e12","price_close":"190","pe":"30","pb":"45","ps":"7",
       "roe":"1.5","eps":"6.3","bps":"4.2","dps":"0.96","div_yld":"0.005","assets":"3.5e11",
       "history":[
         {"date":"1747257600","pe":"30","pb":"45","ps":"7"},
         {"date":"1747171200","pe":"29","pb":"44","ps":"6.9"}]}]}
    """
    r = construct(ValuationComparisonResponse, JSON.parse(raw))
    @test length(r.list) == 1
    it = r.list[1]
    @test it.symbol == "AAPL.US"
    @test length(it.history) == 2
    @test it.history[1].date == unix2datetime(1747257600)
end

@testset "StockRatings numeric scores" begin
    raw = """
    {"style_txt_name":"Growth","scale_txt_name":"Large","report_period_txt":"Q1",
     "multi_score":88.5,"multi_letter":"A","multi_score_change":2,
     "industry_name":"semi","industry_rank":"3","industry_total":120,
     "industry_mean_score":"66.2","industry_median_score":null,
     "ratings":[
       {"type":1,"sub_indicators":[
         {"indicator":{"name":"Quality","score":"90","letter":"A"},
          "sub_indicators":[{"name":"ROE","value":"20","value_type":"pct","score":1.5,"letter":"A"}]}]}]}
    """
    r = construct(StockRatings, JSON.parse(raw))
    @test r.multi_score == 88.5
    @test r.industry_rank == 3
    @test r.industry_total == 120
    @test r.industry_mean_score == 66.2
    @test r.industry_median_score === nothing
    @test r.ratings[1].sub_indicators[1].indicator.score == 90
    @test r.ratings[1].sub_indicators[1].sub_indicators[1].score == 1.5
end

@testset "ETF AssetAllocationResponse" begin
    raw = """
    {"info":[
      {"report_date":"20260601","asset_type":1,
       "lists":[
         {"name":"NVIDIA","code":"NVDA","position_ratio":"0.0861114",
          "counter_id":"ST/US/NVDA",
          "name_locales_map":{"zh-CN":"英伟达","en":"NVIDIA"},
          "holding_detail":{"industry_id":"571010","industry_name":"Semiconductors",
                            "index":"BK/US/CP99000","index_name":"Technology",
                            "holding_type":"E","holding_type_name":"Stock"}}]},
      {"report_date":"20260601","asset_type":2,
       "lists":[{"name":"United States","position_ratio":"0.95",
                 "name_locales_map":{"zh-CN":"美国"}}]}]}
    """
    r = construct(AssetAllocationResponse, JSON.parse(raw))
    @test length(r.info) == 2
    @test r.info[1].asset_type === ElementType.Holdings
    @test r.info[2].asset_type === ElementType.Regional
    item = r.info[1].lists[1]
    @test item.symbol == "NVDA.US"
    @test item.name_locales["zh-CN"] == "英伟达"
    @test !isnothing(item.holding_detail)
    @test item.holding_detail.holding_type == "E"
end

# ── method signatures ─────────────────────────────────────────────────────

@testset "Method signatures present" begin
    @test hasmethod(short_positions, (QuoteContext, String))
    @test hasmethod(short_trades,    (QuoteContext, String))
    @test hasmethod(top_movers,      (MarketContext, Vector{String}, Int, Int))
    @test hasmethod(rank_list,       (MarketContext, String))
    @test hasmethod(symbol_to_counter_ids, (QuoteContext, Vector{String}))
    @test hasmethod(resolve_counter_ids,   (QuoteContext, Vector{String}))
    @test hasmethod(business_segments,           (FundamentalContext, String))
    @test hasmethod(business_segments_history,   (FundamentalContext, String))
    @test hasmethod(institution_rating_views,    (FundamentalContext, String))
    @test hasmethod(industry_rank,               (FundamentalContext, String, String, String, Int))
    @test hasmethod(industry_peers,              (FundamentalContext, String, String))
    @test hasmethod(financial_report_snapshot,   (FundamentalContext, String))
    @test hasmethod(shareholder_top,             (FundamentalContext, String))
    @test hasmethod(shareholder_detail,          (FundamentalContext, String, Int))
    @test hasmethod(valuation_comparison,        (FundamentalContext, String, String))
    @test hasmethod(etf_asset_allocation,        (FundamentalContext, String))
    @test hasmethod(screener_recommend_strategies, (ScreenerContext, String))
    @test hasmethod(screener_user_strategies,      (ScreenerContext, String))
    @test hasmethod(screener_strategy,             (ScreenerContext, Int))
    @test hasmethod(screener_search,               (ScreenerContext, String))
    @test hasmethod(screener_indicators,           (ScreenerContext,))
end
