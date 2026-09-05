module ScreenerProtocol

using JSON
using ..Utils: JSONObject
import ..Utils: construct

export ScreenerCondition,
    ScreenerRecommendStrategiesResponse,
    ScreenerUserStrategiesResponse,
    ScreenerStrategyResponse,
    ScreenerSearchResponse,
    ScreenerIndicatorsResponse

# 上游 5 个端点均返回结构多变的 JSON——这里统一保留原始 JSON 对象，
# 由调用方按需取字段。后续若 API 稳定可再细化类型。
const RawJSON = Union{JSON.Object{String,Any},Dict{String,Any},Vector{Any},Nothing}

function _string_any_dict(x)
    if x isa AbstractDict
        return Dict{String,Any}(String(k) => v for (k, v) in pairs(x))
    end
    return Dict{String,Any}()
end

# ── screener_condition (v4.2.1 新增) ───────────────────────────

"""
    ScreenerCondition(key; min="", max="", tech_values=Dict())

`screener_search` Mode B 用的筛选条件。

- `key`：指标 key（不要带 `filter_` 前缀），如 `"pettm"`、`"roe"`、`"macd_day"`。
- `min` / `max`：区间边界，空字符串表示该边无限制。
- `tech_values`：技术指标参数（基本面指标传空 Dict 即可），如 `Dict("category"=>"goldenfork","period"=>"day")`。
"""
struct ScreenerCondition
    key::String
    min::String
    max::String
    tech_values::Dict{String,Any}
end

ScreenerCondition(
    key::AbstractString;
    min::AbstractString = "",
    max::AbstractString = "",
    tech_values = Dict{String,Any}(),
) = ScreenerCondition(String(key), String(min), String(max), _string_any_dict(tech_values))
ScreenerCondition(;
    key::AbstractString,
    min::AbstractString = "",
    max::AbstractString = "",
    tech_values = Dict{String,Any}(),
) = ScreenerCondition(key; min, max, tech_values)

"""
`screener_recommend_strategies` 的原始 JSON 响应包装。
"""
struct ScreenerRecommendStrategiesResponse
    data::RawJSON
end
construct(::Type{ScreenerRecommendStrategiesResponse}, obj) =
    ScreenerRecommendStrategiesResponse(obj)

"""
`screener_user_strategies` 的原始 JSON 响应包装。
"""
struct ScreenerUserStrategiesResponse
    data::RawJSON
end
construct(::Type{ScreenerUserStrategiesResponse}, obj) =
    ScreenerUserStrategiesResponse(obj)

"""
`screener_strategy` 的原始 JSON 响应包装。
"""
struct ScreenerStrategyResponse
    data::RawJSON
end
construct(::Type{ScreenerStrategyResponse}, obj) = ScreenerStrategyResponse(obj)

"""
`screener_search` 的原始 JSON 响应包装（含分页结果）。
"""
struct ScreenerSearchResponse
    data::RawJSON
end
construct(::Type{ScreenerSearchResponse}, obj) = ScreenerSearchResponse(obj)

"""
`screener_indicators` 的原始 JSON 响应包装。
"""
struct ScreenerIndicatorsResponse
    data::RawJSON
end
construct(::Type{ScreenerIndicatorsResponse}, obj) =
    ScreenerIndicatorsResponse(obj)

end # module ScreenerProtocol
