module Fundamental

using JSON, Dates

using ..Config
using ..Client
using ..Errors
using ..Utils: construct, symbol_to_counter_id
using ..FundamentalProtocol
using ..USProtocol

export FundamentalContext,
    financial_report,
    institution_rating,
    institution_rating_detail,
    dividend,
    dividend_detail,
    forecast_eps,
    consensus,
    valuation,
    valuation_history,
    industry_valuation,
    industry_valuation_dist,
    company,
    executive,
    shareholder,
    fund_holder,
    corp_action,
    invest_relation,
    operating,
    buyback,
    ratings,
    business_segments,
    business_segments_history,
    institution_rating_views,
    industry_rank,
    industry_peers,
    financial_report_snapshot,
    shareholder_top,
    shareholder_detail,
    valuation_comparison,
    etf_asset_allocation,
    macroeconomic_indicators,
    macroeconomic,
    us_company_overview,
    us_valuation_overview,
    us_financial_overview,
    us_financial_statement,
    us_key_financial_metrics,
    us_analyst_consensus,
    us_etf_dividend_info,
    us_company_dividends,
    us_etf_files

"""
    FundamentalContext(config::Config.Settings)

基本面数据上下文。HTTP-only。
"""
struct FundamentalContext
    config::Config.Settings
end

_check(resp) =
    resp.code == 0 ||
    @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))

function _us_get(ctx::FundamentalContext, path::String, ::Type{T}; params) where {T}
    resp = ApiResponse(Client.http_get(ctx.config, path; params, dc_region = :us))
    _check(resp)
    return USProtocol.construct_us(T, resp.data)
end

_us_symbol_params(symbol::AbstractString) =
    Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))

"""Get the US company overview. Requires US-region credentials."""
us_company_overview(ctx::FundamentalContext, symbol::AbstractString) =
    _us_get(
        ctx,
        "/v1/us/stock-info/company-overview",
        USCompanyOverview;
        params = _us_symbol_params(symbol),
    )

"""Get the US valuation overview. Requires US-region credentials."""
us_valuation_overview(ctx::FundamentalContext, symbol::AbstractString) =
    _us_get(
        ctx,
        "/v1/us/stock-info/valuation-overview",
        USValuationOverview;
        params = _us_symbol_params(symbol),
    )

function us_financial_overview(
    ctx::FundamentalContext,
    symbol::AbstractString,
    report::AbstractString,
)
    params = _us_symbol_params(symbol)
    params["report"] = String(report)
    return _us_get(
        ctx,
        "/v1/us/stock-info/finn-overview",
        USFinancialOverview;
        params,
    )
end

function us_financial_statement(
    ctx::FundamentalContext,
    symbol::AbstractString,
    kind::AbstractString,
    report::AbstractString,
)
    params = _us_symbol_params(symbol)
    params["kind"] = String(kind)
    params["report"] = String(report)
    return _us_get(
        ctx,
        "/v1/us/quote/financials/statements",
        USFinancialStatement;
        params,
    )
end

function us_key_financial_metrics(
    ctx::FundamentalContext,
    symbol::AbstractString,
    report::AbstractString,
)
    params = _us_symbol_params(symbol)
    params["report"] = String(report)
    return _us_get(
        ctx,
        "/v1/us/stock-info/fin-keyfactor",
        USKeyFinancialMetrics;
        params,
    )
end

function us_analyst_consensus(
    ctx::FundamentalContext,
    symbol::AbstractString,
    report::AbstractString,
)
    params = _us_symbol_params(symbol)
    params["report"] = String(report)
    return _us_get(
        ctx,
        "/v1/us/stock-info/fin-consensus",
        USAnalystConsensus;
        params,
    )
end

us_etf_dividend_info(ctx::FundamentalContext, symbol::AbstractString) =
    _us_get(
        ctx,
        "/v1/us/stock-info/etf-dividend-info",
        USETFDividendInfo;
        params = _us_symbol_params(symbol),
    )

us_company_dividends(ctx::FundamentalContext, symbol::AbstractString) =
    _us_get(
        ctx,
        "/v1/us/stock-info/company-dividends",
        USCompanyDividends;
        params = _us_symbol_params(symbol),
    )

function us_etf_files(
    ctx::FundamentalContext,
    symbol::AbstractString;
    size::Union{Integer,Nothing} = nothing,
)
    params = _us_symbol_params(symbol)
    isnothing(size) || (params["size"] = Int(size))
    return _us_get(
        ctx,
        "/v1/us/stock-info/etf-files",
        USETFFilesResponse;
        params,
    )
end

# ── 1. financial_report ────────────────────────────────────────────

"""
    financial_report(ctx, symbol; kind, period=nothing) -> FinancialReports

财务报表（嵌套结构因 kind 而异，list 字段保留原 JSON）。

端点：`GET /v1/quote/financial-reports`
"""
function financial_report(
    ctx::FundamentalContext,
    symbol::AbstractString;
    kind::FinancialReportKind.T,
    period::Union{FinancialReportPeriod.T,Nothing} = nothing,
)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "kind" => FundamentalProtocol._financial_report_kind_str(kind),
    )
    isnothing(period) ||
        (params["report"] = FundamentalProtocol._financial_report_period_str(period))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/financial-reports"; params))
    _check(resp)
    construct(FinancialReports, resp.data)
end

# ── 2. institution_rating (fan-out) ────────────────────────────────

"""
    institution_rating(ctx, symbol) -> InstitutionRating

机构评级（最新快照 + 共识汇总），两个端点并行调用。

端点：`GET /v1/quote/institution-rating-latest` + `GET /v1/quote/institution-ratings`
"""
function institution_rating(ctx::FundamentalContext, symbol::AbstractString)
    counter_id = symbol_to_counter_id(symbol)
    latest_t = errormonitor(@async ApiResponse(
        Client.http_get(
            ctx.config,
            "/v1/quote/institution-rating-latest";
            params = Dict{String,Any}("counter_id" => counter_id),
        ),
    ))
    summary_t = errormonitor(@async ApiResponse(
        Client.http_get(
            ctx.config,
            "/v1/quote/institution-ratings";
            params = Dict{String,Any}("counter_id" => counter_id),
        ),
    ))
    latest, summary = fetch(latest_t), fetch(summary_t)
    _check(latest)
    _check(summary)
    InstitutionRating(
        construct(InstitutionRatingLatest, latest.data),
        construct(InstitutionRatingSummary, summary.data),
    )
end

# ── 3. institution_rating_detail ───────────────────────────────────

"""
    institution_rating_detail(ctx, symbol) -> InstitutionRatingDetail

机构评级历史明细（按周快照）。

端点：`GET /v1/quote/institution-ratings/detail`
"""
function institution_rating_detail(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/quote/institution-ratings/detail"; params),
    )
    _check(resp)
    construct(InstitutionRatingDetail, resp.data)
end

# ── 4. dividend ────────────────────────────────────────────────────

"""
    dividend(ctx, symbol) -> DividendList

分红历史。

端点：`GET /v1/quote/dividends`
"""
function dividend(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/dividends"; params))
    _check(resp)
    construct(DividendList, resp.data)
end

# ── 5. dividend_detail ─────────────────────────────────────────────

"""
    dividend_detail(ctx, symbol) -> DividendList

详细分红信息（含分配方案）。

端点：`GET /v1/quote/dividends/details`
"""
function dividend_detail(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/dividends/details"; params))
    _check(resp)
    construct(DividendList, resp.data)
end

# ── 6. forecast_eps ────────────────────────────────────────────────

"""
    forecast_eps(ctx, symbol) -> ForecastEps

分析师 EPS 预测。

端点：`GET /v1/quote/forecast-eps`
"""
function forecast_eps(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/forecast-eps"; params))
    _check(resp)
    construct(ForecastEps, resp.data)
end

# ── 7. consensus ───────────────────────────────────────────────────

"""
    consensus(ctx, symbol) -> FinancialConsensus

营收/利润/EPS 一致预期（含实际值对比）。

端点：`GET /v1/quote/financial-consensus-detail`
"""
function consensus(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/quote/financial-consensus-detail"; params),
    )
    _check(resp)
    construct(FinancialConsensus, resp.data)
end

# ── 8. valuation ───────────────────────────────────────────────────

"""
    valuation(ctx, symbol) -> ValuationData

P/E、P/B、P/S、股息率快照（含历史 high/low/median）。

端点：`GET /v1/quote/valuation`（固定 `indicator=pe`、`range=1`）
"""
function valuation(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "indicator" => "pe",
        "range" => "1",
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/valuation"; params))
    _check(resp)
    construct(ValuationData, resp.data)
end

# ── 9. valuation_history ───────────────────────────────────────────

"""
    valuation_history(ctx, symbol) -> ValuationHistoryResponse

历史估值时间序列。

端点：`GET /v1/quote/valuation/detail`
"""
function valuation_history(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/valuation/detail"; params))
    _check(resp)
    construct(ValuationHistoryResponse, resp.data)
end

# ── 10. industry_valuation ─────────────────────────────────────────

"""
    industry_valuation(ctx, symbol) -> IndustryValuationList

与同行业可比公司估值对比。

端点：`GET /v1/quote/industry-valuation-comparison`
"""
function industry_valuation(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/quote/industry-valuation-comparison"; params),
    )
    _check(resp)
    construct(IndustryValuationList, resp.data)
end

# ── 11. industry_valuation_dist ────────────────────────────────────

"""
    industry_valuation_dist(ctx, symbol) -> IndustryValuationDist

本行业 PE/PB/PS 分位分布。

端点：`GET /v1/quote/industry-valuation-distribution`
"""
function industry_valuation_dist(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/quote/industry-valuation-distribution"; params),
    )
    _check(resp)
    construct(IndustryValuationDist, resp.data)
end

# ── 12. company ────────────────────────────────────────────────────

"""
    company(ctx, symbol) -> CompanyOverview

公司概况（含地址、网站、董事长、高管等）。

端点：`GET /v1/quote/comp-overview`
"""
function company(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/comp-overview"; params))
    _check(resp)
    construct(CompanyOverview, resp.data)
end

# ── 13. executive ──────────────────────────────────────────────────

"""
    executive(ctx, symbol) -> ExecutiveList

管理层与董事会成员。

端点：`GET /v1/quote/company-professionals`（注意 query 参数是 `counter_ids` 而非 `counter_id`）
"""
function executive(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_ids" => symbol_to_counter_id(symbol))
    resp =
        ApiResponse(Client.http_get(ctx.config, "/v1/quote/company-professionals"; params))
    _check(resp)
    construct(ExecutiveList, resp.data)
end

# ── 14. shareholder ────────────────────────────────────────────────

"""
    shareholder(ctx, symbol) -> ShareholderList

主要股东列表（含变动追踪与交叉持仓）。

端点：`GET /v1/quote/shareholders`
"""
function shareholder(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/shareholders"; params))
    _check(resp)
    construct(ShareholderList, resp.data)
end

# ── 15. fund_holder ────────────────────────────────────────────────

"""
    fund_holder(ctx, symbol) -> FundHolders

持有该证券的基金和 ETF 列表。

端点：`GET /v1/quote/fund-holders`
"""
function fund_holder(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/fund-holders"; params))
    _check(resp)
    construct(FundHolders, resp.data)
end

# ── 16. corp_action ────────────────────────────────────────────────

"""
    corp_action(ctx, symbol) -> CorpActions

公司行动（分红、拆股、回购等事件）。

端点：`GET /v1/quote/company-act`（固定 `req_type=1`、`version=3`）
"""
function corp_action(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "req_type" => "1",
        "version" => "3",
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/company-act"; params))
    _check(resp)
    construct(CorpActions, resp.data)
end

# ── 17. invest_relation ────────────────────────────────────────────

"""
    invest_relation(ctx, symbol) -> InvestRelations

本公司持有的其他公司股权（投资者关系/对外投资）。

端点：`GET /v1/quote/invest-relations`（固定 `count=0`）
"""
function invest_relation(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol), "count" => "0")
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/invest-relations"; params))
    _check(resp)
    construct(InvestRelations, resp.data)
end

# ── 18. operating ──────────────────────────────────────────────────

"""
    operating(ctx, symbol) -> OperatingList

经营报告（含管理层讨论与关键财务指标）。

端点：`GET /v1/quote/operatings`
"""
function operating(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/operatings"; params))
    _check(resp)
    construct(OperatingList, resp.data)
end

# ── 19. buyback ────────────────────────────────────────────────────

"""
    buyback(ctx, symbol) -> BuybackData

股票回购数据（含 TTM 摘要、历史与比率）。

端点：`GET /v1/quote/buy-backs`
"""
function buyback(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/buy-backs"; params))
    _check(resp)
    construct(BuybackData, resp.data)
end

# ── 20. ratings ────────────────────────────────────────────────────

"""
    ratings(ctx, symbol) -> StockRatings

多维度股票评级（成长、盈利、估值等子指标 + 行业排名）。

端点：`GET /v1/quote/ratings`
"""
function ratings(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/ratings"; params))
    _check(resp)
    construct(StockRatings, resp.data)
end

# ════════════════════════════════════════════════════════════════════
# v4.2.0 新增（9 个方法）
# ════════════════════════════════════════════════════════════════════

# ── 21. business_segments ──────────────────────────────────────────

"""
    business_segments(ctx, symbol) -> BusinessSegments

最新一期业务分部收入构成。

端点：`GET /v1/quote/fundamentals/business-segments`
"""
function business_segments(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/quote/fundamentals/business-segments"; params),
    )
    _check(resp)
    construct(BusinessSegments, resp.data)
end

# ── 22. business_segments_history ──────────────────────────────────

"""
    business_segments_history(ctx, symbol; report=nothing, cate=nothing) -> BusinessSegmentsHistory

历史业务分部+地区构成。`report`/`cate` 为可选过滤参数（透传至 API）。

端点：`GET /v1/quote/fundamentals/business-segments/history`
"""
function business_segments_history(
    ctx::FundamentalContext,
    symbol::AbstractString;
    report::Union{AbstractString,Nothing} = nothing,
    cate::Union{AbstractString,Nothing} = nothing,
)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    isnothing(report) || (params["report"] = String(report))
    isnothing(cate) || (params["cate"] = String(cate))
    resp = ApiResponse(
        Client.http_get(
            ctx.config,
            "/v1/quote/fundamentals/business-segments/history";
            params,
        ),
    )
    _check(resp)
    construct(BusinessSegmentsHistory, resp.data)
end

# ── 23. institution_rating_views ───────────────────────────────────

"""
    institution_rating_views(ctx, symbol) -> InstitutionRatingViews

机构评级分布的历史时间序列（每个时点的 buy/hold/sell 等分布）。

端点：`GET /v1/quote/ratings/institutional`
"""
function institution_rating_views(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp =
        ApiResponse(Client.http_get(ctx.config, "/v1/quote/ratings/institutional"; params))
    _check(resp)
    construct(InstitutionRatingViews, resp.data)
end

# ── 24. industry_rank ──────────────────────────────────────────────

"""
    industry_rank(ctx, market, indicator, sort_type, limit) -> IndustryRankResponse

某市场下按指定指标排序的行业排名。

端点：`GET /v1/quote/industry/rank`
"""
function industry_rank(
    ctx::FundamentalContext,
    market::AbstractString,
    indicator::AbstractString,
    sort_type::AbstractString,
    limit::Integer,
)
    params = Dict{String,Any}(
        "market" => String(market),
        "indicator" => String(indicator),
        "sort_type" => String(sort_type),
        "limit" => Int(limit),
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/industry/rank"; params))
    _check(resp)
    construct(IndustryRankResponse, resp.data)
end

# ── 25. industry_peers ─────────────────────────────────────────────

"""
    industry_peers(ctx, counter_or_symbol, market; industry_id=nothing) -> IndustryPeersResponse

行业同业链——可传 symbol（如 `"AAPL.US"`，内部转 `counter_id`）或已是 `counter_id`（含 `/`）。

端点：`GET /v1/quote/industries/peers`（固定 `type=1`）
"""
function industry_peers(
    ctx::FundamentalContext,
    counter_or_symbol::AbstractString,
    market::AbstractString;
    industry_id::Union{AbstractString,Nothing} = nothing,
)
    raw = String(counter_or_symbol)
    cid = occursin('/', raw) ? raw : symbol_to_counter_id(raw)
    params = Dict{String,Any}(
        "type" => "1",
        "market" => String(market),
        "industry_id" => something(industry_id, ""),
        "counter_id" => cid,
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/industries/peers"; params))
    _check(resp)
    construct(IndustryPeersResponse, resp.data)
end

# ── 26. financial_report_snapshot ──────────────────────────────────

"""
    financial_report_snapshot(ctx, symbol; report=nothing, fiscal_year=nothing, fiscal_period=nothing) -> FinancialReportSnapshot

财报快照（业绩 vs 预期、关键指标比率）。

端点：`GET /v1/quote/financials/earnings-snapshot`
"""
function financial_report_snapshot(
    ctx::FundamentalContext,
    symbol::AbstractString;
    report::Union{AbstractString,Nothing} = nothing,
    fiscal_year::Union{Integer,Nothing} = nothing,
    fiscal_period::Union{AbstractString,Nothing} = nothing,
)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    isnothing(report) || (params["report"] = String(report))
    isnothing(fiscal_year) || (params["fiscal_year"] = Int(fiscal_year))
    isnothing(fiscal_period) || (params["fiscal_period"] = String(fiscal_period))
    resp = ApiResponse(
        Client.http_get(ctx.config, "/v1/quote/financials/earnings-snapshot"; params),
    )
    _check(resp)
    construct(FinancialReportSnapshot, resp.data)
end

# ── 27. shareholder_top ────────────────────────────────────────────

"""
    shareholder_top(ctx, symbol) -> ShareholderTopResponse

主要股东排行（原始 JSON 保留——结构因品种而异）。

端点：`GET /v1/quote/shareholders/top`
"""
function shareholder_top(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/shareholders/top"; params))
    _check(resp)
    construct(ShareholderTopResponse, resp.data)
end

# ── 28. shareholder_detail ─────────────────────────────────────────

"""
    shareholder_detail(ctx, symbol, object_id) -> ShareholderDetailResponse

指定股东对象的持仓历史明细（`object_id` 来自 `shareholder` / `shareholder_top` 返回中的对象 ID）。

端点：`GET /v1/quote/shareholders/holding`
"""
function shareholder_detail(
    ctx::FundamentalContext,
    symbol::AbstractString,
    object_id::Integer,
)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "object_id" => string(Int64(object_id)),
    )
    resp =
        ApiResponse(Client.http_get(ctx.config, "/v1/quote/shareholders/holding"; params))
    _check(resp)
    construct(ShareholderDetailResponse, resp.data)
end

# ── 29. valuation_comparison ───────────────────────────────────────

"""
    valuation_comparison(ctx, symbol, currency; comparison_symbols=nothing) -> ValuationComparisonResponse

某证券与可选同业的估值对比（含 PE/PB/PS 历史曲线）。

`comparison_symbols`：可选对比 symbol 列表，内部会逐个转 `counter_id` 后序列化。

端点：`GET /v1/quote/compare/valuation`
"""
function valuation_comparison(
    ctx::FundamentalContext,
    symbol::AbstractString,
    currency::AbstractString;
    comparison_symbols::Union{AbstractVector{<:AbstractString},Nothing} = nothing,
)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "currency" => String(currency),
    )
    if !isnothing(comparison_symbols)
        ids = String[symbol_to_counter_id(s) for s in comparison_symbols]
        params["comparison_counter_ids"] = JSON.json(ids)
    end
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/compare/valuation"; params))
    _check(resp)
    construct(ValuationComparisonResponse, resp.data)
end

# ── 30. etf_asset_allocation ──────────────────────────────────────

"""
    etf_asset_allocation(ctx, symbol) -> AssetAllocationResponse

ETF 资产配置，按 holdings / regional / asset class / industry 分组。

端点：`GET /v1/quote/etf-asset-allocation`
"""
function etf_asset_allocation(ctx::FundamentalContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp =
        ApiResponse(Client.http_get(ctx.config, "/v1/quote/etf-asset-allocation"; params))
    _check(resp)
    construct(AssetAllocationResponse, resp.data)
end

# ════════════════════════════════════════════════════════════════════
# macrodata Fundamental API（2 个方法）
# ════════════════════════════════════════════════════════════════════

# ── 31. macroeconomic_indicators ──────────────────────────────────

"""
    macroeconomic_indicators(ctx; country=nothing, keyword=nothing, offset=nothing, limit=nothing) -> MacroeconomicIndicatorListResponse

宏观经济指标列表。`country` 为可选的国家/地区过滤（`MacroeconomicCountry.T` 枚举，
内部转为 v2 API 要求的市场代码，如 `UnitedStates` → `"US"`），`keyword` 为可选的
关键字模糊过滤。
`offset` 默认 0，`limit` 默认 100（最大 1000）。响应 `count` 为符合条件的指标总数。

端点：`GET /v2/quote/macrodata`
"""
function macroeconomic_indicators(
    ctx::FundamentalContext;
    country::Union{MacroeconomicCountry.T,Nothing} = nothing,
    keyword::Union{AbstractString,Nothing} = nothing,
    name::Union{AbstractString,Nothing} = nothing,
    offset::Union{Integer,Nothing} = nothing,
    limit::Union{Integer,Nothing} = nothing,
)
    params = Dict{String,Any}(
        "market" => isnothing(country) ? "ALL" : _macro_country_market(country),
    )
    filter_keyword = isnothing(keyword) ? name : keyword
    isnothing(filter_keyword) || (params["keyword"] = String(filter_keyword))
    isnothing(offset) || (params["offset"] = Int(offset))
    isnothing(limit) || (params["limit"] = Int(limit))
    resp = ApiResponse(Client.http_get(ctx.config, "/v2/quote/macrodata"; params))
    _check(resp)
    construct(MacroeconomicIndicatorListResponse, resp.data)
end

# ── 32. macroeconomic ─────────────────────────────────────────────

"""
    macroeconomic(ctx, id; start_date=nothing, end_date=nothing, offset=nothing, limit=nothing, sort="desc") -> MacroeconomicResponse

指定宏观经济指标的历史数据。`id` 通常来自 `macroeconomic_indicators` 返回的
`indicator_code` 字段。`start_date`/`end_date` 接受 `"YYYY-MM-DD"` 字符串或 `Date`，
内部按 v2 API 要求发送为 `start_date` / `end_date`。
`sort` 默认为 `"desc"`，即按最新数据在前返回。响应 `count` 为历史数据点总数。

端点：`GET /v2/quote/macrodata/{id}`
"""
function macroeconomic(
    ctx::FundamentalContext,
    id::AbstractString;
    start_date::Union{AbstractString,Dates.Date,Nothing} = nothing,
    end_date::Union{AbstractString,Dates.Date,Nothing} = nothing,
    offset::Union{Integer,Nothing} = nothing,
    limit::Union{Integer,Nothing} = nothing,
    sort::Union{AbstractString,Nothing} = "desc",
)
    params = Dict{String,Any}()
    isnothing(start_date) || (params["start_date"] = _date_str(start_date))
    isnothing(end_date) || (params["end_date"] = _date_str(end_date))
    isnothing(offset) || (params["offset"] = Int(offset))
    isnothing(limit) || (params["limit"] = Int(limit))
    isnothing(sort) || (params["sort"] = String(sort))
    resp = ApiResponse(Client.http_get(ctx.config, "/v2/quote/macrodata/$(id)"; params))
    _check(resp)
    construct(MacroeconomicResponse, resp.data)
end

_date_str(d::Dates.Date) = Dates.format(d, Dates.dateformat"yyyy-mm-dd")
_date_str(s::AbstractString) = String(s)

function _macro_country_market(c::MacroeconomicCountry.T)
    c === MacroeconomicCountry.HongKong ? "HK" :
    c === MacroeconomicCountry.China ? "CN" :
    c === MacroeconomicCountry.UnitedStates ? "US" :
    c === MacroeconomicCountry.EuroZone ? "EU" :
    c === MacroeconomicCountry.Japan ? "JP" :
    c === MacroeconomicCountry.Singapore ? "SG" :
    error("unknown MacroeconomicCountry: $c")
end

end # module Fundamental
