module Screener

using ..Config
using ..Client
using ..Errors
using ..Utils: construct, json_to_mutable
using ..ScreenerProtocol

export ScreenerContext,
    screener_recommend_strategies,
    screener_user_strategies,
    screener_strategy,
    screener_search,
    screener_indicators

"""
    ScreenerContext(config::Config.Settings)

选股器（stock screener）上下文。HTTP-only。

v0.8.1 起对齐上游 LongPort SDK v4.2.1：端点迁移到 `/v1/quote/ai/screener/*`；
`screener_recommend_strategies` / `screener_user_strategies` 接受 `market` 参数；
`screener_search` 支持 Mode A（按 strategy_id）与 Mode B（用 `ScreenerCondition` 列表）；
`screener_strategy` / `screener_search` / `screener_indicators` 的响应会自动剥离
`filter_` 前缀；`screener_indicators` 还会按 `tech_indicators` 重组出 `tech_values`。
"""
struct ScreenerContext
    config::Config.Settings
end

_check(resp) =
    resp.code == 0 ||
    @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))

# `screener_search` 始终带上的默认返回列
const DEFAULT_RETURNS = String[
    "filter_prevclose",
    "filter_prevchg",
    "filter_marketcap",
    "filter_salesgrowthyoy",
    "filter_pettm",
    "filter_pbmrq",
    "filter_industry",
]

# 内部小工具：剥离 / 补齐 filter_ 前缀
_strip_filter(k::AbstractString) = String(chopprefix(k, "filter_"))
_with_filter(k::AbstractString) =
    startswith(k, "filter_") ? String(k) : string("filter_", k)

# ── screener_recommend_strategies ──────────────────────────────────

"""
    screener_recommend_strategies(ctx, market) -> ScreenerRecommendStrategiesResponse

指定市场（如 `"US"` / `"HK"`）的推荐内置策略。

端点：`GET /v1/quote/ai/screener/strategies/recommend?market=<market>`
"""
function screener_recommend_strategies(ctx::ScreenerContext, market::AbstractString)
    params = Dict{String,Any}("market" => String(market))
    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/quote/ai/screener/strategies/recommend"; params),
    )
    _check(resp)
    construct(ScreenerRecommendStrategiesResponse, resp.data)
end

# ── screener_user_strategies ───────────────────────────────────────

"""
    screener_user_strategies(ctx, market) -> ScreenerUserStrategiesResponse

指定市场的当前账户已保存策略。

端点：`GET /v1/quote/ai/screener/strategies/mine?market=<market>`
"""
function screener_user_strategies(ctx::ScreenerContext, market::AbstractString)
    params = Dict{String,Any}("market" => String(market))
    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/quote/ai/screener/strategies/mine"; params),
    )
    _check(resp)
    construct(ScreenerUserStrategiesResponse, resp.data)
end

# ── screener_strategy ──────────────────────────────────────────────

"""
    screener_strategy(ctx, id) -> ScreenerStrategyResponse

按 ID 取单个策略详情。响应中 `filter.filters[].key` 的 `filter_` 前缀会被剥离。

端点：`GET /v1/quote/ai/screener/strategy/{id}`
"""
function screener_strategy(ctx::ScreenerContext, id::Integer)
    path = string("/v1/quote/ai/screener/strategy/", Int64(id))
    resp = ApiResponse(Client.http_get(ctx.config, path))
    _check(resp)
    data = json_to_mutable(resp.data)
    if data isa Dict
        filter_obj = get(data, "filter", nothing)
        if filter_obj isa Dict
            filters = get(filter_obj, "filters", nothing)
            if filters isa Vector
                for f in filters
                    if f isa Dict && haskey(f, "key") && f["key"] isa AbstractString
                        f["key"] = _strip_filter(f["key"])
                    end
                end
            end
        end
    end
    ScreenerStrategyResponse(data)
end

# ── screener_search ────────────────────────────────────────────────

# Mode A 内部用：拉策略并构建 filters + 有效 market
function _fetch_strategy_filters(ctx::ScreenerContext, sid::Int64)
    path = string("/v1/quote/ai/screener/strategy/", sid)
    resp = ApiResponse(Client.http_get(ctx.config, path))
    _check(resp)
    strategy = json_to_mutable(resp.data)
    mkt_raw = strategy isa Dict ? get(strategy, "market", "US") : "US"
    mkt = mkt_raw isa AbstractString ? uppercase(String(mkt_raw)) : "US"
    if isempty(mkt) || mkt == "-"
        mkt = "US"
    end
    filters = Any[]
    if strategy isa Dict
        filter_obj = get(strategy, "filter", nothing)
        if filter_obj isa Dict
            fs = get(filter_obj, "filters", nothing)
            if fs isa Vector
                for ind in fs
                    ind isa Dict || continue
                    key = String(get(ind, "key", ""))
                    isempty(key) && continue
                    tv = get(ind, "tech_values", nothing)
                    tv = (tv isa Dict) ? tv : Dict{String,Any}()
                    push!(
                        filters,
                        Dict{String,Any}(
                            "key" => key,
                            "min" => String(get(ind, "min", "")),
                            "max" => String(get(ind, "max", "")),
                            "tech_values" => tv,
                        ),
                    )
                end
            end
        end
    end
    (mkt, filters)
end

# 把 search 结果里 items[].indicators[].key 的 filter_ 前缀剥掉
function _strip_search_keys!(data)
    data isa Dict || return data
    items = get(data, "items", nothing)
    if items isa Vector
        for item in items
            item isa Dict || continue
            inds = get(item, "indicators", nothing)
            if inds isa Vector
                for ind in inds
                    if ind isa Dict && haskey(ind, "key") && ind["key"] isa AbstractString
                        ind["key"] = _strip_filter(ind["key"])
                    end
                end
            end
        end
    end
    data
end

"""
    screener_search(ctx, market; strategy_id=nothing, conditions=ScreenerCondition[],
                    show=String[], page=0, size=20) -> ScreenerSearchResponse

使用策略或自定义条件筛选证券。

## Mode A —— 给 `strategy_id`

先拉策略 (`GET /v1/quote/ai/screener/strategy/{id}`) 获取 filters，再 POST 到 search。
`market` 取策略响应中的 `market`（缺失或为 `"-"` 时回落到 `"US"`），传入的 `market` 仅在
`strategy_id=nothing` 时使用。

## Mode B —— 自定义条件

传 `conditions::Vector{ScreenerCondition}`，使用传入的 `market`。

`show` 是希望额外返回的列名（不带 `filter_` 前缀）；`DEFAULT_RETURNS` 始终包含。
`page` 从 0 开始。

返回响应中 `items[].indicators[].key` 的 `filter_` 前缀会被剥离。

端点：`POST /v1/quote/ai/screener/search`
"""
function screener_search(
    ctx::ScreenerContext,
    market::AbstractString;
    strategy_id::Union{Integer,Nothing} = nothing,
    conditions::AbstractVector{ScreenerCondition} = ScreenerCondition[],
    show::AbstractVector{<:AbstractString} = String[],
    page::Integer = 0,
    size::Integer = 20,
)
    mkt = String(market)

    # 1) 构建 filters 与 effective_market
    effective_market, filters = if !isnothing(strategy_id)
        _fetch_strategy_filters(ctx, Int64(strategy_id))
    else
        fs = Any[]
        for c in conditions
            isempty(c.key) && continue
            api_key = _with_filter(c.key)
            tv = (c.tech_values isa Dict) ? c.tech_values : Dict{String,Any}()
            push!(
                fs,
                Dict{String,Any}(
                    "key" => api_key,
                    "min" => c.min,
                    "max" => c.max,
                    "tech_values" => tv,
                ),
            )
        end
        (mkt, fs)
    end

    # 2) 构建 returns（默认 + filter keys + show 列）
    returns = copy(DEFAULT_RETURNS)
    for f in filters
        k = (f isa Dict) ? get(f, "key", "") : ""
        k isa AbstractString || continue
        api_key = _with_filter(k)
        api_key in returns || push!(returns, api_key)
    end
    for s in show
        api_key = _with_filter(String(s))
        api_key in returns || push!(returns, api_key)
    end

    # 3) POST
    body = Dict{String,Any}(
        "market" => effective_market,
        "filters" => filters,
        "returns" => returns,
        "page" => Int(page),
        "size" => Int(size),
    )
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/quote/ai/screener/search"; body))
    _check(resp)
    data = json_to_mutable(resp.data)
    _strip_search_keys!(data)
    ScreenerSearchResponse(data)
end

# ── screener_indicators ────────────────────────────────────────────

"""
    screener_indicators(ctx) -> ScreenerIndicatorsResponse

所有可用的筛选指标元数据。响应做两个后处理：

- `groups[].indicators[].key` 的 `filter_` 前缀剥离
- 由 `tech_indicators` 构建 `tech_values = {tech_key => [{value, label}]}`

端点：`GET /v1/quote/ai/screener/indicators`
"""
function screener_indicators(ctx::ScreenerContext)
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/ai/screener/indicators"))
    _check(resp)
    data = json_to_mutable(resp.data)
    if data isa Dict
        groups = get(data, "groups", nothing)
        if groups isa Vector
            for group in groups
                group isa Dict || continue
                inds = get(group, "indicators", nothing)
                inds isa Vector || continue
                for ind in inds
                    ind isa Dict || continue
                    # 剥 filter_ 前缀
                    if haskey(ind, "key") && ind["key"] isa AbstractString
                        ind["key"] = _strip_filter(ind["key"])
                    end
                    # 从 tech_indicators 构建 tech_values
                    tech_inds = get(ind, "tech_indicators", nothing)
                    if tech_inds isa Vector
                        tv = Dict{String,Any}()
                        for ti in tech_inds
                            ti isa Dict || continue
                            key = get(ti, "tech_key", nothing)
                            key isa AbstractString || continue
                            items = get(ti, "tech_items", Any[])
                            opts = Any[]
                            if items isa Vector
                                for it in items
                                    it isa Dict || continue
                                    push!(
                                        opts,
                                        Dict{String,Any}(
                                            "value" => String(get(it, "item_value", "")),
                                            "label" => String(get(it, "item_name", "")),
                                        ),
                                    )
                                end
                            end
                            tv[String(key)] = opts
                        end
                        if !isempty(tv)
                            ind["tech_values"] = tv
                        end
                    end
                end
            end
        end
    end
    ScreenerIndicatorsResponse(data)
end

end # module Screener
