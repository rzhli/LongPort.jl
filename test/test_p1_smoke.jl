using Test
using LongBridge
using LongBridge.Utils: Dec64, construct
using JSON, Dates

# =========================================================================
# P1: 新增 Context 全部加载并可构造
# =========================================================================

@testset "P1 Context constructors" begin
    cfg = LongBridge.Config.Settings(
        "k", "s", "t", DateTime(2099, 1, 1);
        http_url     = "https://example.test",
        quote_ws_url = "wss://example.test",
        trade_ws_url = "wss://example.test",
    )
    @test AlertContext(cfg) isa AlertContext
    @test SharelistContext(cfg) isa SharelistContext
    @test DCAContext(cfg) isa DCAContext
    @test ContentContext(cfg) isa ContentContext
end

# =========================================================================
# Alert
# =========================================================================

@testset "Alert enums & parsing" begin
    @test Int(AlertCondition.PriceRise)   == 1
    @test Int(AlertCondition.PercentFall) == 4
    @test Int(AlertFrequency.Daily)       == 1
    @test Int(AlertFrequency.Once)        == 3

    ai = construct(AlertItem, JSON.parse("""
        {"id":"100","indicator_id":"1","enabled":true,"frequency":1,"scope":0,
         "text":"涨到 600","state":[1],"value_map":{"price":"600"}}"""))
    @test ai.id == "100"
    @test ai.enabled
    @test ai.value_map isa Dict{String,String}
    @test ai.value_map["price"] == "600"

    al = construct(AlertList, JSON.parse("""
        {"lists":[{"counter_id":"ST/HK/700","code":"700","market":"HK","name":"腾讯",
         "price":"380.5","chg":"-1.5","p_chg":"-0.39","product":"stock","indicators":[]}]}"""))
    @test length(al.lists) == 1
    @test al.lists[1].symbol == "700.HK"
    @test al.lists[1].price == Dec64("380.5")
end

# =========================================================================
# Sharelist
# =========================================================================

@testset "Sharelist parsing" begin
    import LongBridge.SharelistProtocol: _parse_id
    @test _parse_id(123) === Int64(123)
    @test _parse_id("456") === Int64(456)

    ss = construct(SharelistStock, JSON.parse("""
        {"counter_id":"ST/HK/700","name":"腾讯","market":"HK","code":"700",
         "intro":"互联网","change":"-1.17","last_done":"380.5","trade_status":102,"latency":false}"""))
    @test ss.symbol == "700.HK"
    @test ss.last_done == Dec64("380.5")
    @test ss.trade_status == 102

    si = construct(SharelistInfo, JSON.parse("""
        {"id":"42","name":"科技股","description":"","cover":"","subscribers_count":100,
         "created_at":"1747257600","edited_at":"1747257600","this_year_chg":"12.5",
         "creator":{"name":"alice"},"stocks":[],"subscribed":false,"chg":"0.5",
         "sharelist_type":0,"industry_code":""}"""))
    @test si.id === Int64(42)
    @test si.this_year_chg == Dec64("12.5")
    @test si.creator.name == "alice"

    sc = construct(SharelistScopes, JSON.parse("""{"subscription":true,"self":false}"""))
    @test sc.subscription
    @test !sc.is_self
end

# =========================================================================
# DCA
# =========================================================================

@testset "DCA enums & parsing" begin
    import LongBridge.DCAProtocol: _dca_frequency_str, _dca_status_str, _dca_status_from_str
    @test _dca_frequency_str(DCAFrequency.Daily)       == "Daily"
    @test _dca_frequency_str(DCAFrequency.Weekly)      == "Weekly"
    @test _dca_frequency_str(DCAFrequency.Fortnightly) == "Fortnightly"
    @test _dca_frequency_str(DCAFrequency.Monthly)     == "Monthly"
    @test _dca_status_str(DCAStatus.Active)            == "Active"
    @test _dca_status_str(DCAStatus.Suspended)         == "Suspended"
    @test _dca_status_str(DCAStatus.Finished)          == "Finished"
    @test _dca_status_from_str("Active")    === DCAStatus.Active
    @test _dca_status_from_str("Suspended") === DCAStatus.Suspended

    # DcaPlan 解析（含 alter_hours 整数转字符串）
    plan_raw = """
    {"plan_id":"p-100","status":"Active","counter_id":"ST/HK/700","member_id":"m1","aaid":"a1",
     "account_channel":"hk","display_account":"H123","market":"HK",
     "per_invest_amount":"1000","invest_frequency":"Monthly",
     "invest_day_of_week":"","invest_day_of_month":"15","allow_margin_finance":false,
     "alter_hours":6,"created_at":"2026-01-01","updated_at":"2026-05-15","next_trd_date":"2026-06-15",
     "stock_name":"腾讯","cum_amount":"5000","issue_number":5,
     "average_cost":"380.5","cum_profit":"125.5"}
    """
    plan = construct(DcaPlan, JSON.parse(plan_raw))
    @test plan.symbol == "700.HK"
    @test plan.status === DCAStatus.Active
    @test plan.invest_frequency === DCAFrequency.Monthly
    @test plan.per_invest_amount == Dec64("1000")
    @test plan.alter_hours == "6"
    @test plan.market === Market.HK

    # 空 per_invest_amount 转 0
    plan2 = construct(DcaPlan, JSON.parse("""
        {"plan_id":"p-2","counter_id":"ST/US/AAPL","per_invest_amount":""}"""))
    @test plan2.per_invest_amount == Dec64(0)

    # 其他类型
    sl = construct(DcaSupportList, JSON.parse("""
        {"infos":[{"counter_id":"ST/HK/700","support_regular_saving":true}]}"""))
    @test length(sl.infos) == 1
    @test sl.infos[1].symbol == "700.HK"
    @test sl.infos[1].support_regular_saving

    @test construct(DcaCreateResult, JSON.parse("""{"plan_id":"x"}""")).plan_id == "x"
    @test construct(DcaCalcDateResult, JSON.parse("""{"trade_date":"1747257600"}""")).trade_date == "1747257600"
end

# =========================================================================
# Content
# =========================================================================

@testset "Content options & parsing" begin
    # Options kwdef
    @test MyTopicsOptions(page=1).page == 1
    @test isnothing(MyTopicsOptions().page)
    @test CreateTopicOptions(title="T", body="B").tickers === nothing
    @test CreateReplyOptions(body="hi").reply_to_id === nothing

    # OwnedTopic 反序列化
    ot = construct(OwnedTopic, JSON.parse("""
        {"id":"t100","title":"我的话题","description":"摘要","body":"# 标题",
         "author":{"member_id":"m1","name":"alice","avatar":"http://x"},
         "tickers":["AAPL.US"],"hashtags":[],"images":[],
         "likes_count":10,"comments_count":5,"views_count":100,"shares_count":2,
         "topic_type":"article","detail_url":"http://t",
         "created_at":"1747257600","updated_at":"1747261200"}"""))
    @test ot.id == "t100"
    @test ot.author.name == "alice"
    @test ot.tickers == ["AAPL.US"]

    # TopicReply
    tr = construct(TopicReply, JSON.parse("""
        {"id":"r1","topic_id":"t100","body":"评论","reply_to_id":"0",
         "author":{"member_id":"m2","name":"bob"},"images":[],
         "likes_count":2,"comments_count":0,"created_at":"1747257600"}"""))
    @test tr.id == "r1"
    @test tr.author.name == "bob"

    # NewsItem
    ni = construct(NewsItem, JSON.parse("""
        {"id":"n1","title":"新闻","description":"","url":"http://news",
         "published_at":"1747257600","comments_count":0,"likes_count":0,"shares_count":0}"""))
    @test ni.id == "n1"
end

# =========================================================================
# 公开 API 导出完整性
# =========================================================================

@testset "P1 API exports" begin
    for s in (
        # Alert
        :AlertContext, :list_alerts, :add_alert, :update_alert, :delete_alerts,
        :AlertCondition, :AlertFrequency,
        # Sharelist
        :SharelistContext, :list_sharelists, :sharelist_detail, :popular_sharelists,
        :create_sharelist, :delete_sharelist,
        :add_sharelist_securities, :remove_sharelist_securities, :sort_sharelist_securities,
        # DCA
        :DCAContext, :list_dca, :create_dca, :update_dca,
        :pause_dca, :resume_dca, :stop_dca,
        :dca_history, :dca_stats, :dca_check_support,
        :dca_calc_date, :dca_set_reminder,
        :DCAFrequency, :DCAStatus,
        # Content
        :ContentContext, :my_topics, :create_topic, :topics_by_symbol,
        :topic_detail, :topic_replies, :create_topic_reply, :news,
    )
        @test isdefined(LongBridge, s)
    end
end
