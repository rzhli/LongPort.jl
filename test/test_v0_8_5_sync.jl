using Test
using LongBridge
using LongBridge.FundamentalProtocol:
    _macroeconomic_country_str, _macroeconomic_importance_from_int, _rfc3339_opt
using LongBridge.Utils: construct
using JSON, Dates

# =========================================================================
# v0.8.5 同步上游 LongBridge OpenAPI（macroeconomic 两个 API + macrodata v2 变更）
# =========================================================================

@testset "MacroeconomicCountry → API 全名" begin
    @test _macroeconomic_country_str(MacroeconomicCountry.HongKong)     == "Hong Kong SAR China"
    @test _macroeconomic_country_str(MacroeconomicCountry.China)        == "China (Mainland)"
    @test _macroeconomic_country_str(MacroeconomicCountry.UnitedStates) == "United States"
    @test _macroeconomic_country_str(MacroeconomicCountry.EuroZone)     == "Euro Zone"
    @test _macroeconomic_country_str(MacroeconomicCountry.Japan)        == "Japan"
    @test _macroeconomic_country_str(MacroeconomicCountry.Singapore)    == "Singapore"

    @test LongBridge.Fundamental._macro_country_market(MacroeconomicCountry.HongKong) == "HK"
    @test LongBridge.Fundamental._macro_country_market(MacroeconomicCountry.China) == "CN"
    @test LongBridge.Fundamental._macro_country_market(MacroeconomicCountry.UnitedStates) == "US"
    @test LongBridge.Fundamental._macro_country_market(MacroeconomicCountry.EuroZone) == "EU"
    @test LongBridge.Fundamental._macro_country_market(MacroeconomicCountry.Japan) == "JP"
    @test LongBridge.Fundamental._macro_country_market(MacroeconomicCountry.Singapore) == "SG"
end

@testset "MacroeconomicImportance from int" begin
    @test _macroeconomic_importance_from_int(1) == MacroeconomicImportance.Low
    @test _macroeconomic_importance_from_int(2) == MacroeconomicImportance.Medium
    @test _macroeconomic_importance_from_int(3) == MacroeconomicImportance.High
    @test isnothing(_macroeconomic_importance_from_int(0))
    @test isnothing(_macroeconomic_importance_from_int(99))
end

@testset "_rfc3339_opt 解析" begin
    @test _rfc3339_opt("2024-03-01T08:30:00Z") == DateTime(2024, 3, 1, 8, 30, 0)
    @test _rfc3339_opt("2024-03-01T08:30:00.123Z") == DateTime(2024, 3, 1, 8, 30, 0)
    # +08:00 偏移转 UTC
    @test _rfc3339_opt("2024-03-01T08:30:00+08:00") == DateTime(2024, 3, 1, 0, 30, 0)
    @test _rfc3339_opt("2024-03-01T00:30:00-05:00") == DateTime(2024, 3, 1, 5, 30, 0)
    @test isnothing(_rfc3339_opt(""))
    @test isnothing(_rfc3339_opt(nothing))
    @test isnothing(_rfc3339_opt("not-a-date"))
end

@testset "MacroeconomicIndicatorListResponse 构造" begin
    resp = construct(MacroeconomicIndicatorListResponse, JSON.parse("""
        {"list":[
            {"indicator_code":"US_CPI_YOY","source_org":"BLS","country":"United States",
             "name":"CPI YoY",
             "adjustment_factor":"sa","periodicity":"monthly","category":"inflation",
             "describe":"Consumer Price Index",
             "importance":3,"start_date":"1960-01-01T00:00:00Z"},
            {"indicator_code":"X_NULL_FIELDS","name":null,"describe":null}
        ],"count":248}"""))
    @test resp.count == 248
    @test length(resp.data) == 2

    ind = resp.data[1]
    @test ind.indicator_code == "US_CPI_YOY"
    @test ind.source_org == "BLS"
    @test ind.country == "United States"
    @test ind.name == "CPI YoY"
    @test ind.describe == "Consumer Price Index"
    @test ind.periodicity == "monthly"
    @test ind.category == "inflation"
    @test ind.importance == 3
    @test _macroeconomic_importance_from_int(ind.importance) == MacroeconomicImportance.High
    @test ind.start_date == DateTime(1960, 1, 1)

    # 上游允许 name/describe 为 null，客户端兜底为空字符串。
    nullish = resp.data[2]
    @test nullish.name == ""
    @test nullish.describe == ""
    @test isnothing(nullish.start_date)
    @test nullish.importance == 0

    v2 = construct(MacroeconomicIndicatorListResponse, JSON.parse("""
        {"data":[{"id":"US_CPI_YOY","name":"CPI YoY","importance":3}],"total_count":1}"""))
    @test v2.count == 1
    @test length(v2.data) == 1
    @test v2.data[1].indicator_code == "US_CPI_YOY"
    @test v2.data[1].name == "CPI YoY"

    nested = construct(MacroeconomicIndicatorListResponse, JSON.parse("""
        {"count":1,"result":{"rows":[{"id":"CN_CPI","name":"China CPI","importance":2}]}}"""))
    @test nested.count == 1
    @test length(nested.data) == 1
    @test nested.data[1].indicator_code == "CN_CPI"
    @test nested.data[1].name == "China CPI"

    actual_v2 = construct(MacroeconomicIndicatorListResponse, JSON.parse("""
        {"indicator_list":[{"indicator_id":42,"indicator_name":"China CPI YoY",
                            "market":"CN","frequence":"month",
                            "description":"Consumer prices","importance":2}],"total":27}"""))
    @test actual_v2.count == 27
    @test length(actual_v2.data) == 1
    @test actual_v2.data[1].indicator_code == "42"
    @test actual_v2.data[1].name == "China CPI YoY"
    @test actual_v2.data[1].country == "CN"
    @test actual_v2.data[1].periodicity == "month"
    @test actual_v2.data[1].describe == "Consumer prices"

    aliased = construct(MacroeconomicIndicatorListResponse, JSON.parse("""
        {"indicator_list":[{"indicator_id":"CN_CPI","indicator_name":"China CPI",
                            "source":"NBS","country_name":"China (Mainland)",
                            "frequence":"monthly","description":"Consumer prices",
                            "start_at":"1990-01-01T00:00:00Z","importance":2}],"total":1}"""))
    @test aliased.count == 1
    @test aliased.data[1].indicator_code == "CN_CPI"
    @test aliased.data[1].name == "China CPI"
    @test aliased.data[1].source_org == "NBS"
    @test aliased.data[1].country == "China (Mainland)"
    @test aliased.data[1].periodicity == "monthly"
    @test aliased.data[1].describe == "Consumer prices"
    @test aliased.data[1].start_date == DateTime(1990, 1, 1)
end

@testset "MacroeconomicResponse 构造" begin
    resp = construct(MacroeconomicResponse, JSON.parse("""
        {"info":{"indicator_code":"US_CPI_YOY","country":"United States",
                 "name":"CPI YoY",
                 "importance":3},
         "data":[
            {"period":"2024-03","release_at":"2024-04-10T12:30:00Z",
             "actual_value":"3.5","previous_value":"3.2","forecast_value":"3.4","revised_value":"",
             "next_release_at":"2024-05-15T12:30:00Z",
             "unit":"%",
             "unit_prefix":null}
         ],"count":770}"""))
    @test resp.count == 770
    @test resp.info.indicator_code == "US_CPI_YOY"
    @test resp.info.name == "CPI YoY"
    @test length(resp.data) == 1

    pt = resp.data[1]
    @test pt.period == "2024-03"
    @test pt.release_at == DateTime(2024, 4, 10, 12, 30, 0)
    @test pt.next_release_at == DateTime(2024, 5, 15, 12, 30, 0)
    @test pt.actual_value == "3.5"
    @test pt.previous_value == "3.2"
    @test pt.forecast_value == "3.4"
    @test pt.revised_value == ""
    @test pt.unit == "%"
    @test pt.unit_prefix == ""

    v2 = construct(MacroeconomicResponse, JSON.parse("""
        {"indicator":{"indicator_id":8401,"indicator_name":"Nonfarm Payrolls",
                      "unit":"Thousand","description":"US employment report",
                      "market":"US","frequence":"monthly","importance":3,
                      "indicator_data":[
                        {"actual_data":"175","previous_data":"315","estimated_data":"243",
                         "published_time":"2024-05-03T12:30:00",
                         "observation_date":"2024-04"}
                      ]},
         "total":290}"""))
    @test v2.count == 290
    @test v2.info.indicator_code == "8401"
    @test v2.info.name == "Nonfarm Payrolls"
    @test v2.info.country == "US"
    @test v2.info.periodicity == "monthly"
    @test v2.info.importance == 3
    @test v2.info.describe == "US employment report"
    @test v2.data[1].period == "2024-04"
    @test v2.data[1].release_at == DateTime(2024, 5, 3, 12, 30, 0)
    @test v2.data[1].actual_value == "175"
    @test v2.data[1].previous_value == "315"
    @test v2.data[1].forecast_value == "243"
    @test v2.data[1].unit == "Thousand"
end

@testset "MacroeconomicResponse info 为 null 兜底" begin
    resp = construct(MacroeconomicResponse,
        JSON.parse("""{"info":null,"data":[],"count":0}"""))
    @test resp.info isa MacroeconomicIndicator
    @test resp.info.indicator_code == ""
    @test isempty(resp.data)
    @test resp.count == 0
end

@testset "macroeconomic 方法签名" begin
    @test hasmethod(macroeconomic_indicators, (FundamentalContext,))
    @test hasmethod(macroeconomic,            (FundamentalContext, String))
    kw_indicators = Base.kwarg_decl.(methods(macroeconomic_indicators))
    @test any(k -> :country in k && :keyword in k && :name in k && :offset in k && :limit in k, kw_indicators)
    # 日期参数 String 和 Date 都可接受
    kw = Base.kwarg_decl.(methods(macroeconomic))
    @test any(k -> :start_date in k && :end_date in k && :offset in k && :limit in k && :sort in k, kw)
end

@testset "Fundamental._date_str" begin
    @test LongBridge.Fundamental._date_str(Date(2024, 3, 1)) == "2024-03-01"
    @test LongBridge.Fundamental._date_str("2024-03-01") == "2024-03-01"
end

# ── 典型用法流程（离线演示，响应用 mock JSON）──────────────────────────────
#
# 线上用法（见 examples/p0_analytics.jl）：
#   indicators = macroeconomic_indicators(fc; country=MacroeconomicCountry.UnitedStates, keyword="CPI")
#   code = indicators.data[1].indicator_code
#   hist = macroeconomic(fc, code; start_date="2023-01-01", end_date="2024-12-31")

@testset "macroeconomic 典型用法流程" begin
    # 第一步：macroeconomic_indicators 返回指标列表，按重要性筛选
    indicators = construct(MacroeconomicIndicatorListResponse, JSON.parse("""
        {"list":[
            {"indicator_code":"US_NFP","country":"United States","importance":3,
             "name":"Nonfarm Payrolls",
             "periodicity":"monthly","category":"employment"},
            {"indicator_code":"US_PMI_SVC","country":"United States","importance":2,
             "name":"Services PMI",
             "periodicity":"monthly","category":"business"}
        ],"count":2}"""))

    high = filter(indicators.data) do ind
        _macroeconomic_importance_from_int(ind.importance) == MacroeconomicImportance.High
    end
    @test length(high) == 1
    @test high[1].indicator_code == "US_NFP"
    @test high[1].name == "Nonfarm Payrolls"

    # 第二步：用拿到的 indicator_code 查历史数据，读实际值 vs 预期值
    hist = construct(MacroeconomicResponse, JSON.parse("""
        {"info":{"indicator_code":"US_NFP","country":"United States","importance":3,
                 "name":"Nonfarm Payrolls"},
         "data":[
            {"period":"2024-04","release_at":"2024-05-03T12:30:00Z",
             "actual_value":"175","previous_value":"315","forecast_value":"243","revised_value":"",
             "next_release_at":"2024-06-07T12:30:00Z",
             "unit":"Thousand",
             "unit_prefix":null},
            {"period":"2024-03","release_at":"2024-04-05T12:30:00Z",
             "actual_value":"315","previous_value":"270","forecast_value":"214","revised_value":"310",
             "next_release_at":"2024-05-03T12:30:00Z",
             "unit":"Thousand",
             "unit_prefix":null}
         ],"count":290}"""))

    @test hist.info.indicator_code == high[1].indicator_code
    @test hist.count == 290
    @test hist.data[1].release_at > hist.data[2].release_at

    # 找"实际值低于预期"的数据点
    misses = filter(hist.data) do pt
        a = tryparse(Float64, pt.actual_value)
        f = tryparse(Float64, pt.forecast_value)
        !isnothing(a) && !isnothing(f) && a < f
    end
    @test length(misses) == 1
    @test misses[1].period == "2024-04"
    @test misses[1].release_at == DateTime(2024, 5, 3, 12, 30, 0)
    @test misses[1].unit == "Thousand"

    # 日期参数会以 v2 API 的 start_date/end_date 形式发送。
    @test LongBridge.Fundamental._date_str(Date(2023, 1, 1)) == "2023-01-01"
    @test LongBridge.Fundamental._date_str("2024-12-31") == "2024-12-31"
end
