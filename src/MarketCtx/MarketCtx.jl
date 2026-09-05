module MarketCtx

using ..Config
using ..Client
using ..Errors
using ..Utils: construct, symbol_to_counter_id, index_symbol_to_counter_id, json_to_mutable
using ..MarketProtocol

export MarketContext,
    market_status,
    broker_holding,
    broker_holding_detail,
    broker_holding_daily,
    ah_premium,
    ah_premium_intraday,
    trade_stats,
    anomaly,
    constituent,
    top_movers,
    rank_categories,
    rank_list

"""
    MarketContext(config::Config.Settings)

市场数据上下文。HTTP-only。
"""
struct MarketContext
    config::Config.Settings
end

_check(resp) =
    resp.code == 0 ||
    @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))

# ── market_status ──────────────────────────────────────────────────

"""
    market_status(ctx::MarketContext) -> MarketStatusResponse

各市场的开市/收市状态。

端点：`GET /v1/quote/market-status`
"""
function market_status(ctx::MarketContext)
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/market-status"))
    _check(resp)
    construct(MarketStatusResponse, resp.data)
end

# ── broker_holding ─────────────────────────────────────────────────

"""
    broker_holding(ctx::MarketContext, symbol, period::BrokerHoldingPeriod.T) -> BrokerHoldingTop

某证券在指定周期内净买/净卖前十名券商。

端点：`GET /v1/quote/broker-holding`
"""
function broker_holding(
    ctx::MarketContext,
    symbol::AbstractString,
    period::BrokerHoldingPeriod.T,
)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "type" => MarketProtocol._broker_holding_period_str(period),
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/broker-holding"; params))
    _check(resp)
    construct(BrokerHoldingTop, resp.data)
end

"""
    broker_holding_detail(ctx::MarketContext, symbol) -> BrokerHoldingDetail

完整券商持仓明细（每个券商 1/5/20/60 日变化）。

端点：`GET /v1/quote/broker-holding/detail`
"""
function broker_holding_detail(ctx::MarketContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp =
        ApiResponse(Client.http_get(ctx.config, "/v1/quote/broker-holding/detail"; params))
    _check(resp)
    construct(BrokerHoldingDetail, resp.data)
end

"""
    broker_holding_daily(ctx::MarketContext, symbol, broker_id) -> BrokerHoldingDailyHistory

指定券商对某证券的每日持仓历史。`broker_id` 是参与者编号（`parti_number`）。

端点：`GET /v1/quote/broker-holding/daily`
"""
function broker_holding_daily(
    ctx::MarketContext,
    symbol::AbstractString,
    broker_id::AbstractString,
)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "parti_number" => String(broker_id),
    )
    resp =
        ApiResponse(Client.http_get(ctx.config, "/v1/quote/broker-holding/daily"; params))
    _check(resp)
    construct(BrokerHoldingDailyHistory, resp.data)
end

# ── ah_premium ─────────────────────────────────────────────────────

"""
    ah_premium(ctx::MarketContext, symbol, period::AhPremiumPeriod.T, count::Integer) -> AhPremiumKlines

A/H 溢价 K 线数据。`symbol` 用任一边即可（如 `"700.HK"`）。

端点：`GET /v1/quote/ahpremium/klines`
"""
function ah_premium(
    ctx::MarketContext,
    symbol::AbstractString,
    period::AhPremiumPeriod.T,
    count::Integer,
)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "line_type" => MarketProtocol._ah_premium_period_line_type(period),
        "line_num" => Int(count),
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/ahpremium/klines"; params))
    _check(resp)
    construct(AhPremiumKlines, resp.data)
end

"""
    ah_premium_intraday(ctx::MarketContext, symbol) -> AhPremiumIntraday

A/H 溢价分时数据（当日）。

端点：`GET /v1/quote/ahpremium/timeshares`
"""
function ah_premium_intraday(ctx::MarketContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol), "days" => "1")
    resp =
        ApiResponse(Client.http_get(ctx.config, "/v1/quote/ahpremium/timeshares"; params))
    _check(resp)
    construct(AhPremiumIntraday, resp.data)
end

# ── trade_stats ────────────────────────────────────────────────────

"""
    trade_stats(ctx::MarketContext, symbol) -> TradeStatsResponse

买/卖/中性方向成交统计（含各价位明细）。

端点：`GET /v1/quote/trades-statistics`
"""
function trade_stats(ctx::MarketContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/trades-statistics"; params))
    _check(resp)
    construct(TradeStatsResponse, resp.data)
end

# ── anomaly ────────────────────────────────────────────────────────

"""
    anomaly(ctx::MarketContext, market) -> AnomalyResponse

市场异动列表（如大宗交易、融资买入激增等）。`market` 为 "HK"/"US"/"CN"/"SG"。

端点：`GET /v1/quote/changes`
"""
function anomaly(ctx::MarketContext, market::AbstractString)
    params = Dict{String,Any}("market" => uppercase(String(market)), "category" => "0")
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/changes"; params))
    _check(resp)
    construct(AnomalyResponse, resp.data)
end

# ── constituent ────────────────────────────────────────────────────

"""
    constituent(ctx::MarketContext, symbol) -> IndexConstituents

指数成份股列表。`symbol` 是指数 symbol（如 `"HSI.HK"`），内部会用 `index_symbol_to_counter_id`。

端点：`GET /v1/quote/index-constituents`
"""
function constituent(ctx::MarketContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => index_symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/index-constituents"; params))
    _check(resp)
    construct(IndexConstituents, resp.data)
end

# ── top_movers ─────────────────────────────────────────────────────

"""
    top_movers(ctx::MarketContext, markets::Vector{<:AbstractString}, sort::Integer, limit::Integer;
               date::Union{AbstractString,Nothing}=nothing) -> TopMoversResponse

异动榜（原 `stock_events`）。

- `markets`：`["HK"]`、`["US","HK"]` 等。
- `sort`：排序代码（0 升序，1 降序）。
- `limit`：返回条数。
- `date`：可选日期过滤，格式 `"YYYY-MM-DD"`。

端点：`POST /v1/quote/market/stock-events`
"""
function top_movers(
    ctx::MarketContext,
    markets::AbstractVector{<:AbstractString},
    sort::Integer,
    limit::Integer;
    date::Union{AbstractString,Nothing} = nothing,
)
    body = Dict{String,Any}(
        "limit" => Int(limit),
        "sort" => Int(sort),
        "markets" => String[String(m) for m in markets],
    )
    isnothing(date) || (body["date"] = String(date))
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/quote/market/stock-events"; body))
    _check(resp)
    construct(TopMoversResponse, resp.data)
end

# ── rank_categories ────────────────────────────────────────────────

"""
    rank_categories(ctx::MarketContext) -> RankCategoriesResponse

可用的排行榜分类。v0.8.1 起：`first_tags[].key` 与 `second_tags[].key`
的 `ib_` 前缀会被剥离，让用户拿到干净的 key 直接喂给 `rank_list`。

端点：`GET /v1/quote/market/rank/categories`
"""
function rank_categories(ctx::MarketContext)
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/market/rank/categories"))
    _check(resp)
    data = json_to_mutable(resp.data)
    if data isa Dict && haskey(data, "first_tags") && data["first_tags"] isa Vector
        for tag in data["first_tags"]
            tag isa Dict || continue
            if haskey(tag, "key") && tag["key"] isa AbstractString
                tag["key"] = String(chopprefix(tag["key"], "ib_"))
            end
            if haskey(tag, "second_tags") && tag["second_tags"] isa Vector
                for sub in tag["second_tags"]
                    if sub isa Dict && haskey(sub, "key") && sub["key"] isa AbstractString
                        sub["key"] = String(chopprefix(sub["key"], "ib_"))
                    end
                end
            end
        end
    end
    RankCategoriesResponse(data)
end

# ── rank_list ──────────────────────────────────────────────────────

"""
    rank_list(ctx::MarketContext, key::AbstractString; need_article::Bool=false) -> RankListResponse

指定分类的排行榜列表。`key` 来自 `rank_categories`。
v0.8.1 起：若 `key` 缺少 `ib_` 前缀，自动补上（与上游一致，配合 `rank_categories` 的剥离后行为）。

端点：`GET /v1/quote/market/rank/list`（固定 `delay_bmp=false`）
"""
function rank_list(ctx::MarketContext, key::AbstractString; need_article::Bool = false)
    k = String(key)
    api_key = startswith(k, "ib_") ? k : string("ib_", k)
    params = Dict{String,Any}(
        "key" => api_key,
        "delay_bmp" => "false",
        "need_article" => need_article ? "true" : "false",
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/market/rank/list"; params))
    _check(resp)
    construct(RankListResponse, resp.data)
end

end # module MarketCtx
