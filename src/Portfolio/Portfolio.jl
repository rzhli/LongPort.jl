module Portfolio

using Dates

using ..Config
using ..Client
using ..Errors
using ..Utils: construct, symbol_to_counter_id
using ..PortfolioProtocol

export PortfolioContext,
    exchange_rate,
    profit_analysis,
    profit_analysis_by_market,
    profit_analysis_detail,
    profit_analysis_flows

"""
    PortfolioContext(config::Config.Settings)

投资组合分析上下文。HTTP-only，无 WebSocket。
"""
struct PortfolioContext
    config::Config.Settings
end

# ── Helpers ────────────────────────────────────────────────────────

"""
把 `YYYY-MM-DD` 日期字符串或 `Date` 转成当日 00:00 UTC 的 unix 时间戳。
"""
_date_to_unix_opt(::Nothing) = nothing
_date_to_unix_opt(d::Date) = Int64(datetime2unix(DateTime(d)))
function _date_to_unix_opt(s::AbstractString)
    isempty(s) && return nothing
    date = tryparse(Date, s)
    return isnothing(date) ? nothing : _date_to_unix_opt(date)
end

_date_to_unix_end_opt(::Nothing) = nothing
_date_to_unix_end_opt(d) = (ts = _date_to_unix_opt(d); isnothing(ts) ? nothing : ts + 86399)

function _check_or_raise(resp)
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
end

# ── exchange_rate ──────────────────────────────────────────────────

"""
    exchange_rate(ctx::PortfolioContext) -> ExchangeRates

查询全部支持币种的汇率（基准币 → 其他币）。

端点：`GET /v1/asset/exchange_rates`
"""
function exchange_rate(ctx::PortfolioContext)
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/asset/exchange_rates"))
    _check_or_raise(resp)
    construct(ExchangeRates, resp.data)
end

# ── profit_analysis (fan-out) ──────────────────────────────────────

"""
    profit_analysis(ctx::PortfolioContext; start=nothing, end_=nothing) -> ProfitAnalysis

投资组合盈亏分析（账户总览 + 逐只股票明细）。两个端点并行调用。

端点：`GET /v1/portfolio/profit-analysis-summary` + `GET /v1/portfolio/profit-analysis-sublist`
"""
function profit_analysis(
    ctx::PortfolioContext;
    start::Union{Date,AbstractString,Nothing} = nothing,
    end_::Union{Date,AbstractString,Nothing} = nothing,
)
    start_ts = _date_to_unix_opt(start)
    end_ts = _date_to_unix_end_opt(end_)

    summary_params = Dict{String,Any}()
    isnothing(start_ts) || (summary_params["start"] = start_ts)
    isnothing(end_ts) || (summary_params["end"] = end_ts)

    sublist_params = Dict{String,Any}("profit_or_loss" => "all")
    isnothing(start_ts) || (sublist_params["start"] = start_ts)
    isnothing(end_ts) || (sublist_params["end"] = end_ts)

    summary_t = errormonitor(@async ApiResponse(
        Client.http_get(
            ctx.config,
            "/v1/portfolio/profit-analysis-summary";
            params = summary_params,
        ),
    ))
    sublist_t = errormonitor(@async ApiResponse(
        Client.http_get(
            ctx.config,
            "/v1/portfolio/profit-analysis-sublist";
            params = sublist_params,
        ),
    ))
    summary, sublist = fetch(summary_t), fetch(sublist_t)
    _check_or_raise(summary)
    _check_or_raise(sublist)

    ProfitAnalysis(
        construct(ProfitAnalysisSummary, summary.data),
        construct(ProfitAnalysisSublist, sublist.data),
    )
end

# ── profit_analysis_by_market ──────────────────────────────────────

"""
    profit_analysis_by_market(ctx::PortfolioContext; page, size, market=nothing, start=nothing, end_=nothing, currency=nothing) -> ProfitAnalysisByMarket

按市场维度分页查询盈亏（每只证券一条）。

端点：`GET /v1/portfolio/profit-analysis/by-market`
"""
function profit_analysis_by_market(
    ctx::PortfolioContext;
    page::Integer,
    size::Integer,
    market::Union{AbstractString,Nothing} = nothing,
    start::Union{Date,AbstractString,Nothing} = nothing,
    end_::Union{Date,AbstractString,Nothing} = nothing,
    currency::Union{AbstractString,Nothing} = nothing,
)
    params = Dict{String,Any}("page" => Int(page), "size" => Int(size))
    isnothing(market) || (params["market"] = String(market))
    isnothing(currency) || (params["currency"] = String(currency))
    s = _date_to_unix_opt(start)
    isnothing(s) || (params["start"] = s)
    e = _date_to_unix_end_opt(end_)
    isnothing(e) || (params["end"] = e)

    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/portfolio/profit-analysis/by-market"; params),
    )
    _check_or_raise(resp)
    construct(ProfitAnalysisByMarket, resp.data)
end

# ── profit_analysis_detail ─────────────────────────────────────────

"""
    profit_analysis_detail(ctx::PortfolioContext, symbol; start=nothing, end_=nothing) -> ProfitAnalysisDetail

查询单只证券的盈亏明细（含正股 / 衍生品分解）。

端点：`GET /v1/portfolio/profit-analysis/detail`
"""
function profit_analysis_detail(
    ctx::PortfolioContext,
    symbol::AbstractString;
    start::Union{Date,AbstractString,Nothing} = nothing,
    end_::Union{Date,AbstractString,Nothing} = nothing,
)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    s = _date_to_unix_opt(start)
    isnothing(s) || (params["start"] = s)
    e = _date_to_unix_end_opt(end_)
    isnothing(e) || (params["end"] = e)
    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/portfolio/profit-analysis/detail"; params),
    )
    _check_or_raise(resp)
    construct(ProfitAnalysisDetail, resp.data)
end

# ── profit_analysis_flows ──────────────────────────────────────────

"""
    profit_analysis_flows(ctx::PortfolioContext, symbol; page, size, derivative=false, start=nothing, end_=nothing) -> ProfitAnalysisFlows

查询单只证券的盈亏流水。

注意：上游 Rust 在此方法中**不把日期转 unix 时间戳**，直接传日期字符串。这里保持一致。

端点：`GET /v1/portfolio/profit-analysis/flows`
"""
function profit_analysis_flows(
    ctx::PortfolioContext,
    symbol::AbstractString;
    page::Integer,
    size::Integer,
    derivative::Bool = false,
    start::Union{Date,AbstractString,Nothing} = nothing,
    end_::Union{Date,AbstractString,Nothing} = nothing,
)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "page" => Int(page),
        "size" => Int(size),
        "derivative" => derivative,
    )
    st = _to_date_str(start)
    isnothing(st) || (params["start"] = st)
    en = _to_date_str(end_)
    isnothing(en) || (params["end"] = en)

    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/portfolio/profit-analysis/flows"; params),
    )
    _check_or_raise(resp)
    construct(ProfitAnalysisFlows, resp.data)
end

_to_date_str(::Nothing) = nothing
_to_date_str(d::Date) = Dates.format(d, dateformat"yyyy-mm-dd")
_to_date_str(s::AbstractString) = isempty(s) ? nothing : String(s)

end # module Portfolio
