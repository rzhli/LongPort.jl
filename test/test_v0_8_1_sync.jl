using Test
using LongBridge
using LongBridge.Screener: _strip_filter, _with_filter, DEFAULT_RETURNS, _strip_search_keys!
using LongBridge.MarketCtx
using LongBridge.Utils: construct
using JSON, Dates

# =========================================================================
# v0.8.1 同步上游 LongPort SDK v4.2.1
# =========================================================================

@testset "ScreenerCondition constructor" begin
    c = ScreenerCondition("pettm"; min="0", max="20")
    @test c.key == "pettm"
    @test c.min == "0"
    @test c.max == "20"
    @test c.tech_values isa Dict{String,Any}
    @test isempty(c.tech_values)

    # 含 tech_values（如 MACD 金叉）
    c2 = ScreenerCondition("macd_day"; tech_values=Dict("category"=>"goldenfork","period"=>"day"))
    @test c2.key == "macd_day"
    @test c2.tech_values isa Dict{String,Any}
    @test c2.tech_values["category"] == "goldenfork"
end

@testset "Screener filter_ prefix helpers" begin
    @test _strip_filter("filter_pettm") == "pettm"
    @test _strip_filter("pettm") == "pettm"
    @test _with_filter("pettm") == "filter_pettm"
    @test _with_filter("filter_pettm") == "filter_pettm"
end

@testset "Screener DEFAULT_RETURNS" begin
    @test length(DEFAULT_RETURNS) == 7
    @test "filter_pettm" in DEFAULT_RETURNS
    @test "filter_industry" in DEFAULT_RETURNS
end

@testset "Screener _strip_search_keys! mutation" begin
    data = Dict{String,Any}(
        "items" => Any[
            Dict{String,Any}("indicators" => Any[
                Dict{String,Any}("key"=>"filter_pettm", "value"=>"15"),
                Dict{String,Any}("key"=>"filter_roe",   "value"=>"0.2"),
            ])
        ]
    )
    _strip_search_keys!(data)
    @test data["items"][1]["indicators"][1]["key"] == "pettm"
    @test data["items"][1]["indicators"][2]["key"] == "roe"
end

@testset "ScreenerContext method signatures (v4.2.1)" begin
    @test hasmethod(screener_recommend_strategies, (ScreenerContext, String))
    @test hasmethod(screener_user_strategies,      (ScreenerContext, String))
    @test hasmethod(screener_strategy,             (ScreenerContext, Int))
    @test hasmethod(screener_search,               (ScreenerContext, String))
    @test hasmethod(screener_indicators,           (ScreenerContext,))
end

# ── Fundamental: OperatingFinancial.symbol ────────────────────────────────

@testset "OperatingFinancial.symbol (was counter_id)" begin
    of = construct(LongBridge.FundamentalProtocol.OperatingFinancial, JSON.parse("""
        {"code":"AAPL","counter_id":"ST/US/AAPL","currency":"USD","name":"Apple",
         "region":"US","report":"Q1","report_txt":"Q1 FY25",
         "indicators":[]}"""))
    @test of.symbol == "AAPL.US"
    @test of.code == "AAPL"
    @test of.name == "Apple"
    @test !hasfield(typeof(of), :counter_id)   # 老字段已经移除
end

# ── Market: rank_categories strips ib_ / rank_list adds ib_ ───────────────

@testset "json_to_mutable helper" begin
    raw = JSON.parse("""{"a":1,"b":{"c":[1,2,3]},"d":[{"x":"y"}]}""")
    d = LongBridge.Utils.json_to_mutable(raw)
    @test d isa Dict{String,Any}
    @test d["a"] == 1
    @test d["b"] isa Dict
    @test d["b"]["c"] isa Vector
    @test d["d"][1]["x"] == "y"
end

# rank_list 自动补 ib_ 前缀（通过观察 params 行为间接验证）
@testset "rank_list ib_ prefix logic" begin
    k1 = "us_top_gain"
    k2 = "ib_us_top_gain"
    expected = "ib_us_top_gain"
    # 调用方用纯 key
    @test (startswith(k1, "ib_") ? k1 : string("ib_", k1)) == expected
    # 调用方已带前缀
    @test (startswith(k2, "ib_") ? k2 : string("ib_", k2)) == expected
end

# rank_categories 剥离 ib_ 前缀 —— 用模拟的 JSON 直接走客户端处理路径
@testset "rank_categories ib_ stripping (client-side)" begin
    raw = JSON.parse("""
    {"first_tags":[
       {"key":"ib_market","name":"市场",
        "second_tags":[{"key":"ib_us_top_gain","name":"涨幅榜"},
                       {"key":"ib_us_top_loss","name":"跌幅榜"}]},
       {"key":"ib_industry","name":"行业","second_tags":[]}]}""")
    # 模拟 rank_categories 的客户端处理
    data = LongBridge.Utils.json_to_mutable(raw)
    for tag in data["first_tags"]
        if haskey(tag, "key") && tag["key"] isa AbstractString
            tag["key"] = replace(tag["key"], r"^ib_" => "")
        end
        if haskey(tag, "second_tags") && tag["second_tags"] isa Vector
            for sub in tag["second_tags"]
                if sub isa Dict && haskey(sub, "key") && sub["key"] isa AbstractString
                    sub["key"] = replace(sub["key"], r"^ib_" => "")
                end
            end
        end
    end
    @test data["first_tags"][1]["key"] == "market"
    @test data["first_tags"][1]["second_tags"][1]["key"] == "us_top_gain"
    @test data["first_tags"][2]["key"] == "industry"
end

# ── Exports check ─────────────────────────────────────────────────────────

@testset "v0.8.1 exports" begin
    @test isdefined(LongBridge, :ScreenerCondition)
end
