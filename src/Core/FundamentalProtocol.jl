module FundamentalProtocol

using EnumX, JSON, Dates
using ..Utils: Dec64, JSONObject, counter_id_to_symbol, to_china_time
import ..Utils: _parse_optional_decimal, construct

export FinancialReportKind,
    FinancialReportPeriod,
    InstitutionRecommend,
    ElementType,
    FinancialReports,
    RatingEvaluate,
    RatingTarget,
    RatingSummaryEvaluate,
    InstitutionRatingLatest,
    InstitutionRatingSummary,
    InstitutionRating,
    InstitutionRatingDetailEvaluateItem,
    InstitutionRatingDetailEvaluate,
    InstitutionRatingDetailTargetItem,
    InstitutionRatingDetailTarget,
    InstitutionRatingDetail,
    DividendItem,
    DividendList,
    ForecastEpsItem,
    ForecastEps,
    ConsensusDetail,
    ConsensusReport,
    FinancialConsensus,
    ValuationPoint,
    ValuationMetricData,
    ValuationMetricsData,
    ValuationData,
    ValuationHistoryMetric,
    ValuationHistoryMetrics,
    ValuationHistoryData,
    ValuationHistoryResponse,
    IndustryValuationHistory,
    IndustryValuationItem,
    IndustryValuationList,
    ValuationDist,
    IndustryValuationDist,
    CompanyOverview,
    Professional,
    ExecutiveGroup,
    ExecutiveList,
    ShareholderStock,
    Shareholder,
    ShareholderList,
    FundHolder,
    FundHolders,
    CorpActionLive,
    CorpActionItem,
    CorpActions,
    InvestSecurity,
    InvestRelations,
    OperatingIndicator,
    OperatingFinancial,
    OperatingItem,
    OperatingList,
    RecentBuybacks,
    BuybackHistoryItem,
    BuybackRatios,
    BuybackData,
    RatingLeafIndicator,
    RatingIndicator,
    RatingSubIndicatorGroup,
    RatingCategory,
    StockRatings,
    BusinessSegmentItem,
    BusinessSegments,
    BusinessSegmentHistoryItem,
    BusinessSegmentsHistoricalItem,
    BusinessSegmentsHistory,
    InstitutionRatingViewItem,
    InstitutionRatingViews,
    IndustryRankItem,
    IndustryRankGroup,
    IndustryRankResponse,
    IndustryPeersTop,
    IndustryPeerNode,
    IndustryPeersResponse,
    SnapshotForecastMetric,
    SnapshotReportedMetric,
    FinancialReportSnapshot,
    ShareholderTopResponse,
    ShareholderDetailResponse,
    ValuationHistoryPoint,
    ValuationComparisonItem,
    ValuationComparisonResponse,
    HoldingDetail,
    AssetAllocationItem,
    AssetAllocationGroup,
    AssetAllocationResponse,
    MacroeconomicCountry,
    MacroeconomicImportance,
    MacroeconomicIndicator,
    MacroeconomicIndicatorListResponse,
    Macroeconomic,
    MacroeconomicResponse,
    _financial_report_kind_str,
    _financial_report_period_str,
    _institution_recommend_from_str,
    _macroeconomic_country_str,
    _macroeconomic_importance_from_int

@enumx FinancialReportKind begin
    IncomeStatement = 1   # 利润表 (IS)
    BalanceSheet = 2   # 资产负债表 (BS)
    CashFlow = 3   # 现金流量表 (CF)
    All = 4   # 全部 (ALL)
end

@enumx FinancialReportPeriod begin
    Annual = 1   # af
    SemiAnnual = 2   # saf
    Q1 = 3
    Q2 = 4
    Q3 = 5
    QuarterlyFull = 6   # qf
    ThreeQ = 7   # 3q (前三季)
end

@enumx InstitutionRecommend begin
    Unknown = 0
    StrongBuy = 1
    Buy = 2
    Hold = 3
    Sell = 4
    StrongSell = 5
    Underperform = 6
    NoOpinion = 7
end

@enumx ElementType begin
    Unknown = 0
    Holdings = 1
    Regional = 2
    AssetClass = 3
    Industry = 4
end

const RawJSON = Union{JSON.Object{String,Any},Dict{String,Any},Vector{Any},Nothing}
const MaybeNumber = Union{Int64,Float64,Nothing}

_maybe_number(::Nothing)::MaybeNumber = nothing
_maybe_number(v::Integer)::MaybeNumber = Int64(v)
_maybe_number(v::AbstractFloat)::MaybeNumber = Float64(v)
_maybe_number(v::Real)::MaybeNumber = Float64(v)
function _maybe_number(v::AbstractString)::MaybeNumber
    isempty(v) && return nothing
    i = tryparse(Int64, String(v))
    isnothing(i) || return i
    f = tryparse(Float64, String(v))
    isnothing(f) ? nothing : f
end
_maybe_number(v)::MaybeNumber = nothing

function _financial_report_kind_str(k::FinancialReportKind.T)
    k === FinancialReportKind.IncomeStatement ? "IS" :
    k === FinancialReportKind.BalanceSheet ? "BS" :
    k === FinancialReportKind.CashFlow ? "CF" :
    k === FinancialReportKind.All ? "ALL" : error("unknown FinancialReportKind: $k")
end

function _financial_report_period_str(p::FinancialReportPeriod.T)
    p === FinancialReportPeriod.Annual ? "af" :
    p === FinancialReportPeriod.SemiAnnual ? "saf" :
    p === FinancialReportPeriod.Q1 ? "q1" :
    p === FinancialReportPeriod.Q2 ? "q2" :
    p === FinancialReportPeriod.Q3 ? "q3" :
    p === FinancialReportPeriod.QuarterlyFull ? "qf" :
    p === FinancialReportPeriod.ThreeQ ? "3q" : error("unknown FinancialReportPeriod: $p")
end

function _institution_recommend_from_str(s::AbstractString)
    s == "strong_buy" ? InstitutionRecommend.StrongBuy :
    s == "buy" ? InstitutionRecommend.Buy :
    s == "hold" ? InstitutionRecommend.Hold :
    s == "sell" ? InstitutionRecommend.Sell :
    s == "strong_sell" ? InstitutionRecommend.StrongSell :
    s == "underperform" ? InstitutionRecommend.Underperform :
    s == "no_opinion" ? InstitutionRecommend.NoOpinion : InstitutionRecommend.Unknown
end

function _element_type_from_int(n::Integer)
    n == 1 ? ElementType.Holdings :
    n == 2 ? ElementType.Regional :
    n == 3 ? ElementType.AssetClass : n == 4 ? ElementType.Industry : ElementType.Unknown
end

function _element_type_from_value(v)
    try
        return _element_type_from_int(v isa AbstractString ? parse(Int, v) : Int(v))
    catch
        return ElementType.Unknown
    end
end

# ── financial_report ───────────────────────────────────────────────

struct FinancialReports
    list::RawJSON                        # 嵌套数据结构因 kind 而异，保留原 JSON
end
construct(::Type{FinancialReports}, obj::JSONObject) =
    FinancialReports(get(obj, :list, nothing))

# ── institution_rating ─────────────────────────────────────────────

struct RatingEvaluate
    buy::Int
    over::Int
    hold::Int
    under::Int
    sell::Int
    no_opinion::Int
    total::Int
    start_date::String
    end_date::String
end
function construct(::Type{RatingEvaluate}, obj::JSONObject)
    RatingEvaluate(
        Int(get(obj, :buy, 0)),
        Int(get(obj, :over, 0)),
        Int(get(obj, :hold, 0)),
        Int(get(obj, :under, 0)),
        Int(get(obj, :sell, 0)),
        Int(get(obj, :no_opinion, 0)),
        Int(get(obj, :total, 0)),
        String(get(obj, :start_date, "")),
        String(get(obj, :end_date, "")),
    )
end

struct RatingTarget
    highest_price::Union{Dec64,Nothing}
    lowest_price::Union{Dec64,Nothing}
    prev_close::Union{Dec64,Nothing}
    start_date::String
    end_date::String
end
function construct(::Type{RatingTarget}, obj::JSONObject)
    RatingTarget(
        _parse_optional_decimal(get(obj, :highest_price, nothing)),
        _parse_optional_decimal(get(obj, :lowest_price, nothing)),
        _parse_optional_decimal(get(obj, :prev_close, nothing)),
        String(get(obj, :start_date, "")),
        String(get(obj, :end_date, "")),
    )
end

struct RatingSummaryEvaluate
    buy::Int
    date::String
    hold::Int
    sell::Int
    strong_buy::Int
    under::Int
end
function construct(::Type{RatingSummaryEvaluate}, obj::JSONObject)
    RatingSummaryEvaluate(
        Int(get(obj, :buy, 0)),
        String(get(obj, :date, "")),
        Int(get(obj, :hold, 0)),
        Int(get(obj, :sell, 0)),
        Int(get(obj, :strong_buy, 0)),
        Int(get(obj, :under, 0)),
    )
end

struct InstitutionRatingLatest
    evaluate::RatingEvaluate
    target::RatingTarget
    industry_id::Int64
    industry_name::String
    industry_rank::Int
    industry_total::Int
    industry_mean::Int
    industry_median::Int
end
function construct(::Type{InstitutionRatingLatest}, obj::JSONObject)
    InstitutionRatingLatest(
        construct(RatingEvaluate, obj.evaluate),
        construct(RatingTarget, obj.target),
        Int64(get(obj, :industry_id, 0)),
        String(get(obj, :industry_name, "")),
        Int(get(obj, :industry_rank, 0)),
        Int(get(obj, :industry_total, 0)),
        Int(get(obj, :industry_mean, 0)),
        Int(get(obj, :industry_median, 0)),
    )
end

struct InstitutionRatingSummary
    ccy_symbol::String
    change::Union{Dec64,Nothing}
    evaluate::RatingSummaryEvaluate
    recommend::InstitutionRecommend.T
    target::Union{Dec64,Nothing}
    updated_at::String
end
function construct(::Type{InstitutionRatingSummary}, obj::JSONObject)
    InstitutionRatingSummary(
        String(get(obj, :ccy_symbol, "")),
        _parse_optional_decimal(get(obj, :change, nothing)),
        construct(RatingSummaryEvaluate, obj.evaluate),
        _institution_recommend_from_str(String(get(obj, :recommend, ""))),
        _parse_optional_decimal(get(obj, :target, nothing)),
        String(get(obj, :updated_at, "")),
    )
end

struct InstitutionRating
    latest::InstitutionRatingLatest
    summary::InstitutionRatingSummary
end

# ── institution_rating_detail ──────────────────────────────────────

struct InstitutionRatingDetailEvaluateItem
    buy::Int
    date::String
    hold::Int
    sell::Int
    strong_buy::Int
    no_opinion::Int
    under::Int
end
function construct(
    ::Type{InstitutionRatingDetailEvaluateItem},
    obj::JSONObject,
)
    InstitutionRatingDetailEvaluateItem(
        Int(get(obj, :buy, 0)),
        String(get(obj, :date, "")),
        Int(get(obj, :hold, 0)),
        Int(get(obj, :sell, 0)),
        Int(get(obj, :strong_buy, 0)),
        Int(get(obj, :no_opinion, 0)),
        Int(get(obj, :under, 0)),
    )
end

struct InstitutionRatingDetailEvaluate
    list::Vector{InstitutionRatingDetailEvaluateItem}
end
function construct(::Type{InstitutionRatingDetailEvaluate}, obj::JSONObject)
    items = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(InstitutionRatingDetailEvaluateItem, x) for x in obj.list]
    else
        InstitutionRatingDetailEvaluateItem[]
    end
    InstitutionRatingDetailEvaluate(items)
end

struct InstitutionRatingDetailTargetItem
    avg_target::Union{Dec64,Nothing}
    date::String
    max_target::Union{Dec64,Nothing}
    min_target::Union{Dec64,Nothing}
    meet::Bool
    price::Union{Dec64,Nothing}
    timestamp::String
end
function construct(::Type{InstitutionRatingDetailTargetItem}, obj::JSONObject)
    InstitutionRatingDetailTargetItem(
        _parse_optional_decimal(get(obj, :avg_target, nothing)),
        String(get(obj, :date, "")),
        _parse_optional_decimal(get(obj, :max_target, nothing)),
        _parse_optional_decimal(get(obj, :min_target, nothing)),
        Bool(get(obj, :meet, false)),
        _parse_optional_decimal(get(obj, :price, nothing)),
        String(get(obj, :timestamp, "")),
    )
end

struct InstitutionRatingDetailTarget
    data_percent::Union{Dec64,Nothing}
    prediction_accuracy::Union{Dec64,Nothing}
    updated_at::String
    list::Vector{InstitutionRatingDetailTargetItem}
end
function construct(::Type{InstitutionRatingDetailTarget}, obj::JSONObject)
    items = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(InstitutionRatingDetailTargetItem, x) for x in obj.list]
    else
        InstitutionRatingDetailTargetItem[]
    end
    # data_percent 也可能是数字或 null
    dp_raw = get(obj, :data_percent, nothing)
    data_percent = _parse_optional_decimal(dp_raw)
    InstitutionRatingDetailTarget(
        data_percent,
        _parse_optional_decimal(get(obj, :prediction_accuracy, nothing)),
        String(get(obj, :updated_at, "")),
        items,
    )
end

struct InstitutionRatingDetail
    ccy_symbol::String
    evaluate::InstitutionRatingDetailEvaluate
    target::InstitutionRatingDetailTarget
end
function construct(::Type{InstitutionRatingDetail}, obj::JSONObject)
    InstitutionRatingDetail(
        String(get(obj, :ccy_symbol, "")),
        construct(InstitutionRatingDetailEvaluate, obj.evaluate),
        construct(InstitutionRatingDetailTarget, obj.target),
    )
end

# ── dividend ───────────────────────────────────────────────────────

struct DividendItem
    symbol::String
    id::String
    desc::String
    record_date::String
    ex_date::String
    payment_date::String
end
function construct(::Type{DividendItem}, obj::JSONObject)
    DividendItem(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :id, "")),
        String(get(obj, :desc, "")),
        String(get(obj, :record_date, "")),
        String(get(obj, :ex_date, "")),
        String(get(obj, :payment_date, "")),
    )
end

struct DividendList
    list::Vector{DividendItem}
end
function construct(::Type{DividendList}, obj::JSONObject)
    items = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(DividendItem, x) for x in obj.list]
    else
        DividendItem[]
    end
    DividendList(items)
end

# ── forecast_eps ───────────────────────────────────────────────────

struct ForecastEpsItem
    forecast_eps_median::Union{Dec64,Nothing}
    forecast_eps_mean::Union{Dec64,Nothing}
    forecast_eps_lowest::Union{Dec64,Nothing}
    forecast_eps_highest::Union{Dec64,Nothing}
    institution_total::Int
    institution_up::Int
    institution_down::Int
    forecast_start_date::DateTime    # API 返回 unix 时间戳
    forecast_end_date::DateTime
end
function construct(::Type{ForecastEpsItem}, obj::JSONObject)
    ForecastEpsItem(
        _parse_optional_decimal(get(obj, :forecast_eps_median, nothing)),
        _parse_optional_decimal(get(obj, :forecast_eps_mean, nothing)),
        _parse_optional_decimal(get(obj, :forecast_eps_lowest, nothing)),
        _parse_optional_decimal(get(obj, :forecast_eps_highest, nothing)),
        Int(get(obj, :institution_total, 0)),
        Int(get(obj, :institution_up, 0)),
        Int(get(obj, :institution_down, 0)),
        to_china_time(
            obj.forecast_start_date isa Number ? Int64(obj.forecast_start_date) :
            String(obj.forecast_start_date),
        ),
        to_china_time(
            obj.forecast_end_date isa Number ? Int64(obj.forecast_end_date) :
            String(obj.forecast_end_date),
        ),
    )
end

struct ForecastEps
    items::Vector{ForecastEpsItem}
end
function construct(::Type{ForecastEps}, obj::JSONObject)
    items = if haskey(obj, :items) && !isnothing(obj.items)
        [construct(ForecastEpsItem, x) for x in obj.items]
    else
        ForecastEpsItem[]
    end
    ForecastEps(items)
end

# ── consensus ──────────────────────────────────────────────────────

struct ConsensusDetail
    key::String
    name::String
    description::String
    actual::Union{Dec64,Nothing}
    estimate::Union{Dec64,Nothing}
    comp_value::Union{Dec64,Nothing}
    comp_desc::String
    comp::String
    is_released::Bool
end
function construct(::Type{ConsensusDetail}, obj::JSONObject)
    ConsensusDetail(
        String(get(obj, :key, "")),
        String(get(obj, :name, "")),
        String(get(obj, :description, "")),
        _parse_optional_decimal(get(obj, :actual, nothing)),
        _parse_optional_decimal(get(obj, :estimate, nothing)),
        _parse_optional_decimal(get(obj, :comp_value, nothing)),
        String(get(obj, :comp_desc, "")),
        String(get(obj, :comp, "")),
        Bool(get(obj, :is_released, false)),
    )
end

struct ConsensusReport
    fiscal_year::Int
    fiscal_period::String
    period_text::String
    details::Vector{ConsensusDetail}
end
function construct(::Type{ConsensusReport}, obj::JSONObject)
    details = if haskey(obj, :details) && !isnothing(obj.details)
        [construct(ConsensusDetail, x) for x in obj.details]
    else
        ConsensusDetail[]
    end
    ConsensusReport(
        Int(get(obj, :fiscal_year, 0)),
        String(get(obj, :fiscal_period, "")),
        String(get(obj, :period_text, "")),
        details,
    )
end

struct FinancialConsensus
    list::Vector{ConsensusReport}
    current_index::Int
    currency::String
    opt_periods::Vector{String}
    current_period::String
end
function construct(::Type{FinancialConsensus}, obj::JSONObject)
    reports = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(ConsensusReport, x) for x in obj.list]
    else
        ConsensusReport[]
    end
    periods = if haskey(obj, :opt_periods) && !isnothing(obj.opt_periods)
        String[String(p) for p in obj.opt_periods]
    else
        String[]
    end
    FinancialConsensus(
        reports,
        Int(get(obj, :current_index, 0)),
        String(get(obj, :currency, "")),
        periods,
        String(get(obj, :current_period, "")),
    )
end

# ── valuation ──────────────────────────────────────────────────────

struct ValuationPoint
    timestamp::DateTime
    value::Union{Dec64,Nothing}
end
function construct(::Type{ValuationPoint}, obj::JSONObject)
    ValuationPoint(
        to_china_time(
            obj.timestamp isa Number ? Int64(obj.timestamp) : String(obj.timestamp),
        ),
        _parse_optional_decimal(get(obj, :value, nothing)),
    )
end

struct ValuationMetricData
    desc::String
    high::Union{Dec64,Nothing}
    low::Union{Dec64,Nothing}
    median::Union{Dec64,Nothing}
    list::Vector{ValuationPoint}
end
function construct(::Type{ValuationMetricData}, obj::JSONObject)
    points = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(ValuationPoint, x) for x in obj.list]
    else
        ValuationPoint[]
    end
    ValuationMetricData(
        String(get(obj, :desc, "")),
        _parse_optional_decimal(get(obj, :high, nothing)),
        _parse_optional_decimal(get(obj, :low, nothing)),
        _parse_optional_decimal(get(obj, :median, nothing)),
        points,
    )
end

_opt_metric(v::Nothing) = nothing
_opt_metric(v) = construct(ValuationMetricData, v)

struct ValuationMetricsData
    pe::Union{ValuationMetricData,Nothing}
    pb::Union{ValuationMetricData,Nothing}
    ps::Union{ValuationMetricData,Nothing}
    dvd_yld::Union{ValuationMetricData,Nothing}
end
function construct(::Type{ValuationMetricsData}, obj::JSONObject)
    ValuationMetricsData(
        _opt_metric(get(obj, :pe, nothing)),
        _opt_metric(get(obj, :pb, nothing)),
        _opt_metric(get(obj, :ps, nothing)),
        _opt_metric(get(obj, :dvd_yld, nothing)),
    )
end

struct ValuationData
    metrics::ValuationMetricsData
end
construct(::Type{ValuationData}, obj::JSONObject) =
    ValuationData(construct(ValuationMetricsData, obj.metrics))

# ── valuation_history ──────────────────────────────────────────────

struct ValuationHistoryMetric
    desc::String
    high::Union{Dec64,Nothing}
    low::Union{Dec64,Nothing}
    median::Union{Dec64,Nothing}
    list::Vector{ValuationPoint}
end
function construct(::Type{ValuationHistoryMetric}, obj::JSONObject)
    points = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(ValuationPoint, x) for x in obj.list]
    else
        ValuationPoint[]
    end
    ValuationHistoryMetric(
        String(get(obj, :desc, "")),
        _parse_optional_decimal(get(obj, :high, nothing)),
        _parse_optional_decimal(get(obj, :low, nothing)),
        _parse_optional_decimal(get(obj, :median, nothing)),
        points,
    )
end

_opt_hmetric(v::Nothing) = nothing
_opt_hmetric(v) = construct(ValuationHistoryMetric, v)

struct ValuationHistoryMetrics
    pe::Union{ValuationHistoryMetric,Nothing}
    pb::Union{ValuationHistoryMetric,Nothing}
    ps::Union{ValuationHistoryMetric,Nothing}
end
function construct(::Type{ValuationHistoryMetrics}, obj::JSONObject)
    ValuationHistoryMetrics(
        _opt_hmetric(get(obj, :pe, nothing)),
        _opt_hmetric(get(obj, :pb, nothing)),
        _opt_hmetric(get(obj, :ps, nothing)),
    )
end

struct ValuationHistoryData
    metrics::ValuationHistoryMetrics
end
construct(::Type{ValuationHistoryData}, obj::JSONObject) =
    ValuationHistoryData(construct(ValuationHistoryMetrics, obj.metrics))

struct ValuationHistoryResponse
    history::ValuationHistoryData
end
construct(::Type{ValuationHistoryResponse}, obj::JSONObject) =
    ValuationHistoryResponse(construct(ValuationHistoryData, obj.history))

# ── industry_valuation ─────────────────────────────────────────────

struct IndustryValuationHistory
    date::String
    pe::Union{Dec64,Nothing}
    pb::Union{Dec64,Nothing}
    ps::Union{Dec64,Nothing}
end
function construct(::Type{IndustryValuationHistory}, obj::JSONObject)
    IndustryValuationHistory(
        String(get(obj, :date, "")),
        _parse_optional_decimal(get(obj, :pe, nothing)),
        _parse_optional_decimal(get(obj, :pb, nothing)),
        _parse_optional_decimal(get(obj, :ps, nothing)),
    )
end

struct IndustryValuationItem
    symbol::String                    # 由 counter_id 转换
    name::String
    currency::String
    assets::Union{Dec64,Nothing}
    bps::Union{Dec64,Nothing}
    eps::Union{Dec64,Nothing}
    dps::Union{Dec64,Nothing}
    div_yld::Union{Dec64,Nothing}
    div_payout_ratio::Union{Dec64,Nothing}
    five_y_avg_dps::Union{Dec64,Nothing}
    pe::Union{Dec64,Nothing}
    history::Vector{IndustryValuationHistory}
end
function construct(::Type{IndustryValuationItem}, obj::JSONObject)
    history = if haskey(obj, :history) && !isnothing(obj.history)
        [construct(IndustryValuationHistory, x) for x in obj.history]
    else
        IndustryValuationHistory[]
    end
    IndustryValuationItem(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :name, "")),
        String(get(obj, :currency, "")),
        _parse_optional_decimal(get(obj, :assets, nothing)),
        _parse_optional_decimal(get(obj, :bps, nothing)),
        _parse_optional_decimal(get(obj, :eps, nothing)),
        _parse_optional_decimal(get(obj, :dps, nothing)),
        _parse_optional_decimal(get(obj, :div_yld, nothing)),
        _parse_optional_decimal(get(obj, :div_payout_ratio, nothing)),
        _parse_optional_decimal(get(obj, :five_y_avg_dps, nothing)),
        _parse_optional_decimal(get(obj, :pe, nothing)),
        history,
    )
end

struct IndustryValuationList
    list::Vector{IndustryValuationItem}
end
function construct(::Type{IndustryValuationList}, obj::JSONObject)
    items = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(IndustryValuationItem, x) for x in obj.list]
    else
        IndustryValuationItem[]
    end
    IndustryValuationList(items)
end

# ── industry_valuation_dist ────────────────────────────────────────

struct ValuationDist
    low::Union{Dec64,Nothing}
    high::Union{Dec64,Nothing}
    median::Union{Dec64,Nothing}
    value::Union{Dec64,Nothing}
    ranking::Union{Dec64,Nothing}
    rank_index::String
    rank_total::String
end
function construct(::Type{ValuationDist}, obj::JSONObject)
    ValuationDist(
        _parse_optional_decimal(get(obj, :low, nothing)),
        _parse_optional_decimal(get(obj, :high, nothing)),
        _parse_optional_decimal(get(obj, :median, nothing)),
        _parse_optional_decimal(get(obj, :value, nothing)),
        _parse_optional_decimal(get(obj, :ranking, nothing)),
        String(get(obj, :rank_index, "")),
        String(get(obj, :rank_total, "")),
    )
end

_opt_dist(v::Nothing) = nothing
_opt_dist(v) = construct(ValuationDist, v)

struct IndustryValuationDist
    pe::Union{ValuationDist,Nothing}
    pb::Union{ValuationDist,Nothing}
    ps::Union{ValuationDist,Nothing}
end
function construct(::Type{IndustryValuationDist}, obj::JSONObject)
    IndustryValuationDist(
        _opt_dist(get(obj, :pe, nothing)),
        _opt_dist(get(obj, :pb, nothing)),
        _opt_dist(get(obj, :ps, nothing)),
    )
end

# ── company ────────────────────────────────────────────────────────

struct CompanyOverview
    name::String
    company_name::String
    founded::String
    listing_date::String
    market::String
    region::String
    address::String
    office_address::String
    website::String
    issue_price::Union{Dec64,Nothing}
    shares_offered::String
    chairman::String
    secretary::String
    audit_inst::String
    category::String
    year_end::String
    employees::String
    phone::String                  # JSON 字段名 "Phone"（首字母大写）
    fax::String
    email::String
    legal_repr::String
    manager::String
    bus_license::String
    accounting_firm::String
    securities_rep::String
    legal_counsel::String
    zip_code::String
    ticker::String
    icon::String
    profile::String
    ads_ratio::String
    sector::Int
end
function construct(::Type{CompanyOverview}, obj::JSONObject)
    CompanyOverview(
        String(get(obj, :name, "")),
        String(get(obj, :company_name, "")),
        String(get(obj, :founded, "")),
        String(get(obj, :listing_date, "")),
        String(get(obj, :market, "")),
        String(get(obj, :region, "")),
        String(get(obj, :address, "")),
        String(get(obj, :office_address, "")),
        String(get(obj, :website, "")),
        _parse_optional_decimal(get(obj, :issue_price, nothing)),
        String(get(obj, :shares_offered, "")),
        String(get(obj, :chairman, "")),
        String(get(obj, :secretary, "")),
        String(get(obj, :audit_inst, "")),
        String(get(obj, :category, "")),
        String(get(obj, :year_end, "")),
        String(get(obj, :employees, "")),
        String(get(obj, :Phone, "")),
        String(get(obj, :fax, "")),
        String(get(obj, :email, "")),
        String(get(obj, :legal_repr, "")),
        String(get(obj, :manager, "")),
        String(get(obj, :bus_license, "")),
        String(get(obj, :accounting_firm, "")),
        String(get(obj, :securities_rep, "")),
        String(get(obj, :legal_counsel, "")),
        String(get(obj, :zip_code, "")),
        String(get(obj, :ticker, "")),
        String(get(obj, :icon, "")),
        String(get(obj, :profile, "")),
        String(get(obj, :ads_ratio, "")),
        Int(get(obj, :sector, 0)),
    )
end

# ── executive ──────────────────────────────────────────────────────

struct Professional
    id::String
    name::String
    name_zhcn::String
    name_en::String
    title::String
    biography::String
    photo::String
    wiki_url::String
end
function construct(::Type{Professional}, obj::JSONObject)
    Professional(
        String(get(obj, :id, "")),
        String(get(obj, :name, "")),
        String(get(obj, :name_zhcn, "")),
        String(get(obj, :name_en, "")),
        String(get(obj, :title, "")),
        String(get(obj, :biography, "")),
        String(get(obj, :photo, "")),
        String(get(obj, :wiki_url, "")),
    )
end

struct ExecutiveGroup
    symbol::String                      # 由 counter_id 转换
    forward_url::String
    total::Int
    professionals::Vector{Professional}
end
function construct(::Type{ExecutiveGroup}, obj::JSONObject)
    pros = if haskey(obj, :professionals) && !isnothing(obj.professionals)
        [construct(Professional, x) for x in obj.professionals]
    else
        Professional[]
    end
    ExecutiveGroup(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :forward_url, "")),
        Int(get(obj, :total, length(pros))),
        pros,
    )
end

struct ExecutiveList
    professional_list::Vector{ExecutiveGroup}
end
function construct(::Type{ExecutiveList}, obj::JSONObject)
    groups = if haskey(obj, :professional_list) && !isnothing(obj.professional_list)
        [construct(ExecutiveGroup, x) for x in obj.professional_list]
    else
        ExecutiveGroup[]
    end
    ExecutiveList(groups)
end

# ── shareholder ────────────────────────────────────────────────────

struct ShareholderStock
    symbol::String
    code::String
    market::String
    chg::String
end
function construct(::Type{ShareholderStock}, obj::JSONObject)
    ShareholderStock(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :code, "")),
        String(get(obj, :market, "")),
        String(get(obj, :chg, "")),
    )
end

struct Shareholder
    shareholder_id::String
    shareholder_name::String
    institution_type::String
    percent_of_shares::Union{Dec64,Nothing}
    shares_changed::Union{Dec64,Nothing}
    report_date::String
    stocks::Vector{ShareholderStock}
end
function construct(::Type{Shareholder}, obj::JSONObject)
    stocks = if haskey(obj, :stocks) && !isnothing(obj.stocks)
        [construct(ShareholderStock, x) for x in obj.stocks]
    else
        ShareholderStock[]
    end
    Shareholder(
        String(get(obj, :shareholder_id, "")),
        String(get(obj, :shareholder_name, "")),
        String(get(obj, :institution_type, "")),
        _parse_optional_decimal(get(obj, :percent_of_shares, nothing)),
        _parse_optional_decimal(get(obj, :shares_changed, nothing)),
        String(get(obj, :report_date, "")),
        stocks,
    )
end

struct ShareholderList
    shareholder_list::Vector{Shareholder}
    forward_url::String
    total::Int
end
function construct(::Type{ShareholderList}, obj::JSONObject)
    list = if haskey(obj, :shareholder_list) && !isnothing(obj.shareholder_list)
        [construct(Shareholder, x) for x in obj.shareholder_list]
    else
        Shareholder[]
    end
    ShareholderList(
        list,
        String(get(obj, :forward_url, "")),
        Int(get(obj, :total, length(list))),
    )
end

# ── fund_holder ────────────────────────────────────────────────────

struct FundHolder
    code::String
    symbol::String
    currency::String
    name::String
    position_ratio::Dec64
    report_date::String
end
function construct(::Type{FundHolder}, obj::JSONObject)
    # position_ratio uses decimal_empty_is_0 in upstream; tolerate "--" placeholder.
    pr_raw = get(obj, :position_ratio, "")
    pr = if isnothing(pr_raw) || (pr_raw isa AbstractString && isempty(pr_raw))
        Dec64(0)
    elseif pr_raw isa Number
        Dec64(pr_raw)
    else
        try
            parse(Dec64, String(pr_raw))
        catch
            Dec64(0)
        end
    end
    FundHolder(
        String(get(obj, :code, "")),
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :currency, "")),
        String(get(obj, :name, "")),
        pr,
        String(get(obj, :report_date, "")),
    )
end

struct FundHolders
    lists::Vector{FundHolder}
end
function construct(::Type{FundHolders}, obj::JSONObject)
    items = if haskey(obj, :lists) && !isnothing(obj.lists)
        [construct(FundHolder, x) for x in obj.lists]
    else
        FundHolder[]
    end
    FundHolders(items)
end

# ── corp_action ────────────────────────────────────────────────────

struct CorpActionLive
    id::String
    status::Any
    started_at::String
    name::String
    icon::String
end
function construct(::Type{CorpActionLive}, obj::JSONObject)
    CorpActionLive(
        String(get(obj, :id, "")),
        get(obj, :status, nothing),
        String(get(obj, :started_at, "")),
        String(get(obj, :name, "")),
        String(get(obj, :icon, "")),
    )
end

_opt_live(::Nothing) = nothing
_opt_live(v) = construct(CorpActionLive, v)

struct CorpActionItem
    id::String
    date::String
    date_str::String
    date_type::String
    date_zone::String
    act_type::String
    act_desc::String
    action::String
    recent::Bool
    is_delay::Bool
    delay_content::String
    live::Union{CorpActionLive,Nothing}
    security::Any              # 通常为 null，保留原值
end
function construct(::Type{CorpActionItem}, obj::JSONObject)
    CorpActionItem(
        String(get(obj, :id, "")),
        String(get(obj, :date, "")),
        String(get(obj, :date_str, "")),
        String(get(obj, :date_type, "")),
        String(get(obj, :date_zone, "")),
        String(get(obj, :act_type, "")),
        String(get(obj, :act_desc, "")),
        String(get(obj, :action, "")),
        Bool(get(obj, :recent, false)),
        Bool(get(obj, :is_delay, false)),
        String(get(obj, :delay_content, "")),
        _opt_live(get(obj, :live, nothing)),
        get(obj, :security, nothing),
    )
end

struct CorpActions
    items::Vector{CorpActionItem}
end
function construct(::Type{CorpActions}, obj::JSONObject)
    items = if haskey(obj, :items) && !isnothing(obj.items)
        [construct(CorpActionItem, x) for x in obj.items]
    else
        CorpActionItem[]
    end
    CorpActions(items)
end

# ── invest_relation ────────────────────────────────────────────────

struct InvestSecurity
    company_id::String
    company_name::String
    company_name_en::String
    company_name_zhcn::String
    symbol::String
    currency::String
    percent_of_shares::Union{Dec64,Nothing}
    shares_rank::String
    shares_value::Union{Dec64,Nothing}
end
function construct(::Type{InvestSecurity}, obj::JSONObject)
    InvestSecurity(
        String(get(obj, :company_id, "")),
        String(get(obj, :company_name, "")),
        String(get(obj, :company_name_en, "")),
        String(get(obj, :company_name_zhcn, "")),
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :currency, "")),
        _parse_optional_decimal(get(obj, :percent_of_shares, nothing)),
        String(get(obj, :shares_rank, "")),
        _parse_optional_decimal(get(obj, :shares_value, nothing)),
    )
end

struct InvestRelations
    forward_url::String
    invest_securities::Vector{InvestSecurity}
end
function construct(::Type{InvestRelations}, obj::JSONObject)
    sec = if haskey(obj, :invest_securities) && !isnothing(obj.invest_securities)
        [construct(InvestSecurity, x) for x in obj.invest_securities]
    else
        InvestSecurity[]
    end
    InvestRelations(String(get(obj, :forward_url, "")), sec)
end

# ── operating ──────────────────────────────────────────────────────

struct OperatingIndicator
    field_name::String
    indicator_name::String
    indicator_value::String
    yoy::Union{Dec64,Nothing}
end
function construct(::Type{OperatingIndicator}, obj::JSONObject)
    OperatingIndicator(
        String(get(obj, :field_name, "")),
        String(get(obj, :indicator_name, "")),
        String(get(obj, :indicator_value, "")),
        _parse_optional_decimal(get(obj, :yoy, nothing)),
    )
end

struct OperatingFinancial
    code::String
    symbol::String                       # 由 counter_id 转换（如 ST/US/AAPL → AAPL.US）
    currency::String
    name::String
    region::String
    report::String
    report_txt::String
    indicators::Vector{OperatingIndicator}
end
function construct(::Type{OperatingFinancial}, obj::JSONObject)
    inds = if haskey(obj, :indicators) && !isnothing(obj.indicators)
        [construct(OperatingIndicator, x) for x in obj.indicators]
    else
        OperatingIndicator[]
    end
    OperatingFinancial(
        String(get(obj, :code, "")),
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :currency, "")),
        String(get(obj, :name, "")),
        String(get(obj, :region, "")),
        String(get(obj, :report, "")),
        String(get(obj, :report_txt, "")),
        inds,
    )
end

struct OperatingItem
    id::String
    report::String
    title::String
    txt::String
    latest::Bool
    keywords::Vector{String}
    web_url::String
    financial::OperatingFinancial
end
function construct(::Type{OperatingItem}, obj::JSONObject)
    kws = if haskey(obj, :keywords) && !isnothing(obj.keywords)
        String[String(k) for k in obj.keywords if !isnothing(k)]
    else
        String[]
    end
    OperatingItem(
        String(get(obj, :id, "")),
        String(get(obj, :report, "")),
        String(get(obj, :title, "")),
        String(get(obj, :txt, "")),
        Bool(get(obj, :latest, false)),
        kws,
        String(get(obj, :web_url, "")),
        construct(OperatingFinancial, obj.financial),
    )
end

struct OperatingList
    list::Vector{OperatingItem}
end
function construct(::Type{OperatingList}, obj::JSONObject)
    items = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(OperatingItem, x) for x in obj.list]
    else
        OperatingItem[]
    end
    OperatingList(items)
end

# ── buyback ────────────────────────────────────────────────────────

struct RecentBuybacks
    currency::String
    net_buyback_ttm::Union{Dec64,Nothing}
    net_buyback_yield_ttm::Union{Dec64,Nothing}
end
function construct(::Type{RecentBuybacks}, obj::JSONObject)
    RecentBuybacks(
        String(get(obj, :currency, "")),
        _parse_optional_decimal(get(obj, :net_buyback_ttm, nothing)),
        _parse_optional_decimal(get(obj, :net_buyback_yield_ttm, nothing)),
    )
end

_opt_recent(::Nothing) = nothing
_opt_recent(v) = construct(RecentBuybacks, v)

struct BuybackHistoryItem
    fiscal_year::String
    fiscal_year_range::String
    net_buyback::Union{Dec64,Nothing}
    net_buyback_yield::Union{Dec64,Nothing}
    net_buyback_growth_rate::Union{Dec64,Nothing}
    currency::String
end
function construct(::Type{BuybackHistoryItem}, obj::JSONObject)
    BuybackHistoryItem(
        String(get(obj, :fiscal_year, "")),
        String(get(obj, :fiscal_year_range, "")),
        _parse_optional_decimal(get(obj, :net_buyback, nothing)),
        _parse_optional_decimal(get(obj, :net_buyback_yield, nothing)),
        _parse_optional_decimal(get(obj, :net_buyback_growth_rate, nothing)),
        String(get(obj, :currency, "")),
    )
end

struct BuybackRatios
    net_buyback_payout_ratio::Union{Dec64,Nothing}
    net_buyback_to_cashflow_ratio::Union{Dec64,Nothing}
end
function construct(::Type{BuybackRatios}, obj::JSONObject)
    BuybackRatios(
        _parse_optional_decimal(get(obj, :net_buyback_payout_ratio, nothing)),
        _parse_optional_decimal(get(obj, :net_buyback_to_cashflow_ratio, nothing)),
    )
end

struct BuybackData
    recent_buybacks::Union{RecentBuybacks,Nothing}
    buyback_history::Vector{BuybackHistoryItem}
    buyback_ratios::Vector{BuybackRatios}
end
function construct(::Type{BuybackData}, obj::JSONObject)
    history = if haskey(obj, :buyback_history) && !isnothing(obj.buyback_history)
        [construct(BuybackHistoryItem, x) for x in obj.buyback_history]
    else
        BuybackHistoryItem[]
    end
    ratios = if haskey(obj, :buyback_ratios) && !isnothing(obj.buyback_ratios)
        [construct(BuybackRatios, x) for x in obj.buyback_ratios]
    else
        BuybackRatios[]
    end
    BuybackData(_opt_recent(get(obj, :recent_buybacks, nothing)), history, ratios)
end

# ── ratings ────────────────────────────────────────────────────────

struct RatingLeafIndicator
    name::String
    value::String
    value_type::String
    score::MaybeNumber         # API 可能返回 int / float / null
    letter::String
end
function construct(::Type{RatingLeafIndicator}, obj::JSONObject)
    RatingLeafIndicator(
        String(get(obj, :name, "")),
        String(get(obj, :value, "")),
        String(get(obj, :value_type, "")),
        _maybe_number(get(obj, :score, nothing)),
        String(get(obj, :letter, "")),
    )
end

struct RatingIndicator
    name::String
    score::MaybeNumber
    letter::String
end
function construct(::Type{RatingIndicator}, obj::JSONObject)
    RatingIndicator(
        String(get(obj, :name, "")),
        _maybe_number(get(obj, :score, nothing)),
        String(get(obj, :letter, "")),
    )
end

struct RatingSubIndicatorGroup
    indicator::RatingIndicator
    sub_indicators::Vector{RatingLeafIndicator}
end
function construct(::Type{RatingSubIndicatorGroup}, obj::JSONObject)
    subs = if haskey(obj, :sub_indicators) && !isnothing(obj.sub_indicators)
        [construct(RatingLeafIndicator, x) for x in obj.sub_indicators]
    else
        RatingLeafIndicator[]
    end
    RatingSubIndicatorGroup(construct(RatingIndicator, obj.indicator), subs)
end

struct RatingCategory
    kind::Int
    sub_indicators::Vector{RatingSubIndicatorGroup}
end
function construct(::Type{RatingCategory}, obj::JSONObject)
    groups = if haskey(obj, :sub_indicators) && !isnothing(obj.sub_indicators)
        [construct(RatingSubIndicatorGroup, x) for x in obj.sub_indicators]
    else
        RatingSubIndicatorGroup[]
    end
    RatingCategory(Int(get(obj, :type, 0)), groups)
end

struct StockRatings
    style_txt_name::String
    scale_txt_name::String
    report_period_txt::String
    multi_score::MaybeNumber
    multi_letter::String
    multi_score_change::Int
    industry_name::String
    industry_rank::MaybeNumber
    industry_total::MaybeNumber
    industry_mean_score::MaybeNumber
    industry_median_score::MaybeNumber
    ratings::Vector{RatingCategory}
end
function construct(::Type{StockRatings}, obj::JSONObject)
    cats = if haskey(obj, :ratings) && !isnothing(obj.ratings)
        [construct(RatingCategory, x) for x in obj.ratings]
    else
        RatingCategory[]
    end
    StockRatings(
        String(get(obj, :style_txt_name, "")),
        String(get(obj, :scale_txt_name, "")),
        String(get(obj, :report_period_txt, "")),
        _maybe_number(get(obj, :multi_score, nothing)),
        String(get(obj, :multi_letter, "")),
        Int(get(obj, :multi_score_change, 0)),
        String(get(obj, :industry_name, "")),
        _maybe_number(get(obj, :industry_rank, nothing)),
        _maybe_number(get(obj, :industry_total, nothing)),
        _maybe_number(get(obj, :industry_mean_score, nothing)),
        _maybe_number(get(obj, :industry_median_score, nothing)),
        cats,
    )
end

# ════════════════════════════════════════════════════════════════════
# v4.2.0 新增类型
# ════════════════════════════════════════════════════════════════════

# ── business_segments ──────────────────────────────────────────────

struct BusinessSegmentItem
    name::String
    percent::String
end
construct(::Type{BusinessSegmentItem}, obj::JSONObject) =
    BusinessSegmentItem(String(get(obj, :name, "")), String(get(obj, :percent, "")))

struct BusinessSegments
    date::String
    total::String
    currency::String
    business::Vector{BusinessSegmentItem}
end
function construct(::Type{BusinessSegments}, obj::JSONObject)
    items = if haskey(obj, :business) && !isnothing(obj.business)
        [construct(BusinessSegmentItem, x) for x in obj.business]
    else
        BusinessSegmentItem[]
    end
    BusinessSegments(
        String(get(obj, :date, "")),
        String(get(obj, :total, "")),
        String(get(obj, :currency, "")),
        items,
    )
end

struct BusinessSegmentHistoryItem
    name::String
    percent::String
    value::String
end
construct(::Type{BusinessSegmentHistoryItem}, obj::JSONObject) =
    BusinessSegmentHistoryItem(
        String(get(obj, :name, "")),
        String(get(obj, :percent, "")),
        String(get(obj, :value, "")),
    )

struct BusinessSegmentsHistoricalItem
    date::String
    total::String
    currency::String
    business::Vector{BusinessSegmentHistoryItem}
    regionals::Vector{BusinessSegmentHistoryItem}
end
function construct(::Type{BusinessSegmentsHistoricalItem}, obj::JSONObject)
    bs = if haskey(obj, :business) && !isnothing(obj.business)
        [construct(BusinessSegmentHistoryItem, x) for x in obj.business]
    else
        BusinessSegmentHistoryItem[]
    end
    rs = if haskey(obj, :regionals) && !isnothing(obj.regionals)
        [construct(BusinessSegmentHistoryItem, x) for x in obj.regionals]
    else
        BusinessSegmentHistoryItem[]
    end
    BusinessSegmentsHistoricalItem(
        String(get(obj, :date, "")),
        String(get(obj, :total, "")),
        String(get(obj, :currency, "")),
        bs,
        rs,
    )
end

struct BusinessSegmentsHistory
    historical::Vector{BusinessSegmentsHistoricalItem}
end
function construct(::Type{BusinessSegmentsHistory}, obj::JSONObject)
    items = if haskey(obj, :historical) && !isnothing(obj.historical)
        [construct(BusinessSegmentsHistoricalItem, x) for x in obj.historical]
    else
        BusinessSegmentsHistoricalItem[]
    end
    BusinessSegmentsHistory(items)
end

# ── institution_rating_views ───────────────────────────────────────

"""
机构评级历史分布的单条快照。`date` 是 unix 时间戳字符串（API 偶尔返回裸整数，原样保留）。
"""
struct InstitutionRatingViewItem
    date::String
    buy::String
    over::String
    hold::String
    under::String
    sell::String
    total::String
end
function construct(::Type{InstitutionRatingViewItem}, obj::JSONObject)
    d = get(obj, :date, "")
    InstitutionRatingViewItem(
        d isa AbstractString ? String(d) : string(d),
        String(get(obj, :buy, "")),
        String(get(obj, :over, "")),
        String(get(obj, :hold, "")),
        String(get(obj, :under, "")),
        String(get(obj, :sell, "")),
        String(get(obj, :total, "")),
    )
end

struct InstitutionRatingViews
    elist::Vector{InstitutionRatingViewItem}
end
function construct(::Type{InstitutionRatingViews}, obj::JSONObject)
    items = if haskey(obj, :elist) && !isnothing(obj.elist)
        [construct(InstitutionRatingViewItem, x) for x in obj.elist]
    else
        InstitutionRatingViewItem[]
    end
    InstitutionRatingViews(items)
end

# ── industry_rank ──────────────────────────────────────────────────

struct IndustryRankItem
    name::String
    counter_id::String
    chg::String
    leading_name::String
    leading_ticker::String
    leading_chg::String
    value_name::String
    value_data::String
end
construct(::Type{IndustryRankItem}, obj::JSONObject) = IndustryRankItem(
    String(get(obj, :name, "")),
    String(get(obj, :counter_id, "")),
    String(get(obj, :chg, "")),
    String(get(obj, :leading_name, "")),
    String(get(obj, :leading_ticker, "")),
    String(get(obj, :leading_chg, "")),
    String(get(obj, :value_name, "")),
    String(get(obj, :value_data, "")),
)

struct IndustryRankGroup
    lists::Vector{IndustryRankItem}
end
function construct(::Type{IndustryRankGroup}, obj::JSONObject)
    items = if haskey(obj, :lists) && !isnothing(obj.lists)
        [construct(IndustryRankItem, x) for x in obj.lists]
    else
        IndustryRankItem[]
    end
    IndustryRankGroup(items)
end

struct IndustryRankResponse
    items::Vector{IndustryRankGroup}
end
function construct(::Type{IndustryRankResponse}, obj::JSONObject)
    groups = if haskey(obj, :items) && !isnothing(obj.items)
        [construct(IndustryRankGroup, x) for x in obj.items]
    else
        IndustryRankGroup[]
    end
    IndustryRankResponse(groups)
end

# ── industry_peers ─────────────────────────────────────────────────

struct IndustryPeersTop
    name::String
    market::String
end
construct(::Type{IndustryPeersTop}, obj::JSONObject) =
    IndustryPeersTop(String(get(obj, :name, "")), String(get(obj, :market, "")))

"""
递归的行业同业节点（`next` 字段含子节点）。
"""
struct IndustryPeerNode
    name::String
    counter_id::String
    stock_num::Int
    chg::String
    ytd_chg::String
    next::Vector{IndustryPeerNode}
end
function construct(::Type{IndustryPeerNode}, obj::JSONObject)
    children = if haskey(obj, :next) && !isnothing(obj.next)
        [construct(IndustryPeerNode, x) for x in obj.next]
    else
        IndustryPeerNode[]
    end
    IndustryPeerNode(
        String(get(obj, :name, "")),
        String(get(obj, :counter_id, "")),
        Int(get(obj, :stock_num, 0)),
        String(get(obj, :chg, "")),
        String(get(obj, :ytd_chg, "")),
        children,
    )
end

struct IndustryPeersResponse
    top::IndustryPeersTop
    chain::Union{IndustryPeerNode,Nothing}
end
function construct(::Type{IndustryPeersResponse}, obj::JSONObject)
    top_obj = get(obj, :top, nothing)
    top =
        top_obj === nothing ? IndustryPeersTop("", "") :
        construct(IndustryPeersTop, top_obj)
    chain_obj = get(obj, :chain, nothing)
    chain =
        chain_obj === nothing ? nothing : construct(IndustryPeerNode, chain_obj)
    IndustryPeersResponse(top, chain)
end

# ── financial_report_snapshot ──────────────────────────────────────

struct SnapshotForecastMetric
    value::String
    yoy::String
    cmp_desc::String
    est_value::String
end
construct(::Type{SnapshotForecastMetric}, obj::JSONObject) =
    SnapshotForecastMetric(
        String(get(obj, :value, "")),
        String(get(obj, :yoy, "")),
        String(get(obj, :cmp_desc, "")),
        String(get(obj, :est_value, "")),
    )

struct SnapshotReportedMetric
    value::String
    yoy::String
end
construct(::Type{SnapshotReportedMetric}, obj::JSONObject) =
    SnapshotReportedMetric(String(get(obj, :value, "")), String(get(obj, :yoy, "")))

struct FinancialReportSnapshot
    name::String
    ticker::String
    fp_start::String
    fp_end::String
    currency::String
    report_desc::String
    fo_revenue::Union{SnapshotForecastMetric,Nothing}
    fo_ebit::Union{SnapshotForecastMetric,Nothing}
    fo_eps::Union{SnapshotForecastMetric,Nothing}
    fr_revenue::Union{SnapshotReportedMetric,Nothing}
    fr_profit::Union{SnapshotReportedMetric,Nothing}
    fr_operate_cash::Union{SnapshotReportedMetric,Nothing}
    fr_invest_cash::Union{SnapshotReportedMetric,Nothing}
    fr_finance_cash::Union{SnapshotReportedMetric,Nothing}
    fr_total_assets::Union{SnapshotReportedMetric,Nothing}
    fr_total_liability::Union{SnapshotReportedMetric,Nothing}
    fr_roe_ttm::String
    fr_profit_margin::String
    fr_profit_margin_ttm::String
    fr_asset_turn_ttm::String
    fr_leverage_ttm::String
    fr_debt_assets_ratio::String
end
function construct(::Type{FinancialReportSnapshot}, obj::JSONObject)
    _opt_f(k) =
        let v = get(obj, k, nothing)
            v === nothing ? nothing : construct(SnapshotForecastMetric, v)
        end
    _opt_r(k) =
        let v = get(obj, k, nothing)
            v === nothing ? nothing : construct(SnapshotReportedMetric, v)
        end
    FinancialReportSnapshot(
        String(get(obj, :name, "")),
        String(get(obj, :ticker, "")),
        String(get(obj, :fp_start, "")),
        String(get(obj, :fp_end, "")),
        String(get(obj, :currency, "")),
        String(get(obj, :report_desc, "")),
        _opt_f(:fo_revenue),
        _opt_f(:fo_ebit),
        _opt_f(:fo_eps),
        _opt_r(:fr_revenue),
        _opt_r(:fr_profit),
        _opt_r(:fr_operate_cash),
        _opt_r(:fr_invest_cash),
        _opt_r(:fr_finance_cash),
        _opt_r(:fr_total_assets),
        _opt_r(:fr_total_liability),
        String(get(obj, :fr_roe_ttm, "")),
        String(get(obj, :fr_profit_margin, "")),
        String(get(obj, :fr_profit_margin_ttm, "")),
        String(get(obj, :fr_asset_turn_ttm, "")),
        String(get(obj, :fr_leverage_ttm, "")),
        String(get(obj, :fr_debt_assets_ratio, "")),
    )
end

# ── shareholder_top / shareholder_detail (raw JSON) ────────────────

"""
`shareholder_top` 的原始 JSON 响应包装。结构因品种而变，保留原 `JSONObject`。
"""
struct ShareholderTopResponse
    data::RawJSON
end
construct(::Type{ShareholderTopResponse}, obj) = ShareholderTopResponse(obj)

"""
`shareholder_detail` 的原始 JSON 响应包装。
"""
struct ShareholderDetailResponse
    data::RawJSON
end
construct(::Type{ShareholderDetailResponse}, obj) =
    ShareholderDetailResponse(obj)

# ── valuation_comparison ───────────────────────────────────────────

"""
一条历史估值数据点。`date` 由 unix 秒字符串转 `DateTime` (UTC)。
"""
struct ValuationHistoryPoint
    date::DateTime
    pe::String
    pb::String
    ps::String
end
function construct(::Type{ValuationHistoryPoint}, obj::JSONObject)
    ts_raw = get(obj, :date, 0)
    ts_int = ts_raw isa AbstractString ? parse(Int64, ts_raw) : Int64(ts_raw)
    ValuationHistoryPoint(
        unix2datetime(ts_int),
        String(get(obj, :pe, "")),
        String(get(obj, :pb, "")),
        String(get(obj, :ps, "")),
    )
end

"""
一只证券在估值对比中的一行。`symbol` 由 `counter_id` 转换。
"""
struct ValuationComparisonItem
    symbol::String
    name::String
    currency::String
    market_value::String
    price_close::String
    pe::String
    pb::String
    ps::String
    roe::String
    eps::String
    bps::String
    dps::String
    div_yld::String
    assets::String
    history::Vector{ValuationHistoryPoint}
end
function construct(::Type{ValuationComparisonItem}, obj::JSONObject)
    hist = if haskey(obj, :history) && !isnothing(obj.history)
        [construct(ValuationHistoryPoint, x) for x in obj.history]
    else
        ValuationHistoryPoint[]
    end
    ValuationComparisonItem(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :name, "")),
        String(get(obj, :currency, "")),
        String(get(obj, :market_value, "")),
        String(get(obj, :price_close, "")),
        String(get(obj, :pe, "")),
        String(get(obj, :pb, "")),
        String(get(obj, :ps, "")),
        String(get(obj, :roe, "")),
        String(get(obj, :eps, "")),
        String(get(obj, :bps, "")),
        String(get(obj, :dps, "")),
        String(get(obj, :div_yld, "")),
        String(get(obj, :assets, "")),
        hist,
    )
end

struct ValuationComparisonResponse
    list::Vector{ValuationComparisonItem}
end
function construct(::Type{ValuationComparisonResponse}, obj::JSONObject)
    items = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(ValuationComparisonItem, x) for x in obj.list]
    else
        ValuationComparisonItem[]
    end
    ValuationComparisonResponse(items)
end

# ── etf_asset_allocation ─────────────────────────────────────────

"""
ETF 持仓资产配置中的持仓明细，仅 holdings 分组通常有值。
"""
struct HoldingDetail
    industry_id::String
    industry_name::String
    index::String
    index_name::String
    holding_type::String
    holding_type_name::String
end
function construct(::Type{HoldingDetail}, obj::JSONObject)
    HoldingDetail(
        String(get(obj, :industry_id, "")),
        String(get(obj, :industry_name, "")),
        String(get(obj, :index, "")),
        String(get(obj, :index_name, "")),
        String(get(obj, :holding_type, "")),
        String(get(obj, :holding_type_name, "")),
    )
end

_opt_holding_detail(::Nothing) = nothing
_opt_holding_detail(v) = construct(HoldingDetail, v)

function _string_map(v)
    d = Dict{String,String}()
    if v isa JSONObject
        for (k, val) in pairs(v)
            d[String(k)] = isnothing(val) ? "" : String(val)
        end
    end
    d
end

"""
ETF 资产配置分组中的单个元素。holdings 分组会包含 `code`、`symbol` 和 `holding_detail`。
"""
struct AssetAllocationItem
    name::String
    code::String
    position_ratio::String
    symbol::String
    name_locales::Dict{String,String}
    holding_detail::Union{HoldingDetail,Nothing}
end
function construct(::Type{AssetAllocationItem}, obj::JSONObject)
    AssetAllocationItem(
        String(get(obj, :name, "")),
        String(get(obj, :code, "")),
        String(get(obj, :position_ratio, "")),
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        _string_map(get(obj, :name_locales_map, nothing)),
        _opt_holding_detail(get(obj, :holding_detail, nothing)),
    )
end

"""
ETF 资产配置分组，`asset_type` 对应 Holdings / Regional / AssetClass / Industry。
"""
struct AssetAllocationGroup
    report_date::String
    asset_type::ElementType.T
    lists::Vector{AssetAllocationItem}
end
function construct(::Type{AssetAllocationGroup}, obj::JSONObject)
    items = if haskey(obj, :lists) && !isnothing(obj.lists)
        [construct(AssetAllocationItem, x) for x in obj.lists]
    else
        AssetAllocationItem[]
    end
    AssetAllocationGroup(
        String(get(obj, :report_date, "")),
        _element_type_from_value(get(obj, :asset_type, 0)),
        items,
    )
end

"""
ETF 资产配置响应。`info` 按元素类型分组。
"""
struct AssetAllocationResponse
    info::Vector{AssetAllocationGroup}
end
function construct(::Type{AssetAllocationResponse}, obj::JSONObject)
    groups = if haskey(obj, :info) && !isnothing(obj.info)
        [construct(AssetAllocationGroup, x) for x in obj.info]
    else
        AssetAllocationGroup[]
    end
    AssetAllocationResponse(groups)
end

# ── macroeconomic ────────────────────────────────────────────────

@enumx MacroeconomicCountry begin
    HongKong = 1   # Hong Kong SAR China
    China = 2   # China (Mainland)
    UnitedStates = 3   # United States
    EuroZone = 4   # Euro Zone
    Japan = 5   # Japan
    Singapore = 6   # Singapore
end

function _macroeconomic_country_str(c::MacroeconomicCountry.T)
    c === MacroeconomicCountry.HongKong ? "Hong Kong SAR China" :
    c === MacroeconomicCountry.China ? "China (Mainland)" :
    c === MacroeconomicCountry.UnitedStates ? "United States" :
    c === MacroeconomicCountry.EuroZone ? "Euro Zone" :
    c === MacroeconomicCountry.Japan ? "Japan" :
    c === MacroeconomicCountry.Singapore ? "Singapore" :
    error("unknown MacroeconomicCountry: $c")
end

@enumx MacroeconomicImportance begin
    Low = 1
    Medium = 2
    High = 3
end

function _macroeconomic_importance_from_int(
    n::Integer,
)::Union{MacroeconomicImportance.T,Nothing}
    n == 1 ? MacroeconomicImportance.Low :
    n == 2 ? MacroeconomicImportance.Medium :
    n == 3 ? MacroeconomicImportance.High : nothing
end

# RFC3339 字符串（如 "2024-03-01T08:30:00Z"、带 ±hh:mm 偏移或小数秒）→ UTC DateTime。
# 空串 / null / 无法解析时返回 nothing。
function _rfc3339_opt(v)::Union{DateTime,Nothing}
    v isa AbstractString || return nothing
    m = match(
        r"^(\d{4}-\d{2}-\d{2})[Tt ](\d{2}:\d{2}:\d{2})(?:\.\d+)?(Z|z|[+-]\d{2}:?\d{2})?$",
        String(v),
    )
    isnothing(m) && return nothing
    dt = DateTime(m[1] * "T" * m[2])
    off = m[3]
    if !isnothing(off) && off != "Z" && off != "z"
        hh = parse(Int, off[2:3])
        mm = parse(Int, off[(end-1):end])
        # 偏移为 +08:00 表示本地比 UTC 快 8 小时，转 UTC 要减
        shift = Hour(hh) + Minute(mm)
        dt = off[1] == '+' ? dt - shift : dt + shift
    end
    dt
end

_int_or_zero(v) = Int(round(something(_maybe_number(v), 0)))

function _macro_text(v)::String
    isnothing(v) && return ""
    v isa AbstractString && return String(v)
    if v isa JSONObject
        for key in (:english, :simplified_chinese, :traditional_chinese)
            text = get(v, key, nothing)
            text isa AbstractString && !isempty(text) && return String(text)
        end
        return ""
    end
    string(v)
end

function _macro_indicator_code(obj::JSONObject)::String
    for key in (:indicator_code, :id, :indicator_id, :macro_id, :macrodata_id, :code)
        haskey(obj, key) && return _macro_text(get(obj, key, nothing))
    end
    ""
end

function _macro_text_field(obj::JSONObject, keys::Tuple)::String
    for key in keys
        haskey(obj, key) && return _macro_text(get(obj, key, nothing))
    end
    ""
end

function _macro_time_field(obj::JSONObject, keys::Tuple)::Union{DateTime,Nothing}
    for key in keys
        haskey(obj, key) && return _rfc3339_opt(get(obj, key, nothing))
    end
    nothing
end

"""
宏观经济指标元数据。`indicator_code` 可作为 `macroeconomic` 的入参。
`importance` 为原始整数（1=低 2=中 3=高），可用 `_macroeconomic_importance_from_int` 转枚举。
"""
struct MacroeconomicIndicator
    indicator_code::String
    source_org::String
    country::String
    name::String
    adjustment_factor::String
    periodicity::String
    category::String
    describe::String
    importance::Int
    start_date::Union{DateTime,Nothing}
end
MacroeconomicIndicator() =
    MacroeconomicIndicator("", "", "", "", "", "", "", "", 0, nothing)
function construct(::Type{MacroeconomicIndicator}, obj::JSONObject)
    MacroeconomicIndicator(
        _macro_indicator_code(obj),
        _macro_text_field(obj, (:source_org, :source_org_name, :source, :source_name)),
        _macro_text_field(obj, (:country, :country_name, :region, :market)),
        _macro_text_field(obj, (:name, :indicator_name, :title, :display_name, :name_cn, :name_zh_cn, :name_en)),
        _macro_text_field(obj, (:adjustment_factor, :adjustment, :seasonal_adjustment)),
        _macro_text_field(obj, (:periodicity, :frequence, :frequency, :period, :interval)),
        _macro_text_field(obj, (:category, :type, :indicator_type)),
        _macro_text_field(obj, (:describe, :description, :desc)),
        _int_or_zero(get(obj, :importance, 0)),
        _macro_time_field(obj, (:start_date, :start_at, :start_time)),
    )
end

"""
`macroeconomic_indicators` 响应：`data` 为指标列表，`count` 为符合条件的总数。
"""
struct MacroeconomicIndicatorListResponse
    data::Vector{MacroeconomicIndicator}
    count::Int
end

function _looks_like_macro_indicator(obj::JSONObject)::Bool
    haskey(obj, :indicator_code) ||
        haskey(obj, :id) ||
        haskey(obj, :indicator_id) ||
        haskey(obj, :indicator_name) ||
        haskey(obj, :source_org) ||
        haskey(obj, :periodicity) ||
        haskey(obj, :frequence) ||
        haskey(obj, :importance)
end

function _macro_indicator_items(raw)::Vector{MacroeconomicIndicator}
    isnothing(raw) && return MacroeconomicIndicator[]
    items = MacroeconomicIndicator[]
    try
        for x in raw
            if x isa JSONObject && _looks_like_macro_indicator(x)
                push!(items, construct(MacroeconomicIndicator, x))
            end
        end
    catch
        return MacroeconomicIndicator[]
    end
    items
end

function _macro_response_count(obj::JSONObject, fallback::Integer)::Int
    for key in (:count, :total_count, :total)
        value = get(obj, key, nothing)
        isnothing(value) || return _int_or_zero(value)
    end
    Int(fallback)
end

function _macro_indicator_items_from_response(obj::JSONObject)::Vector{MacroeconomicIndicator}
    for key in (:list, :indicator_list, :data, :items, :indicators, :results, :rows)
        items = _macro_indicator_items(get(obj, key, nothing))
        isempty(items) || return items
    end

    result = get(obj, :result, nothing)
    if result isa JSONObject
        for key in (:list, :indicator_list, :data, :items, :indicators, :results, :rows)
            items = _macro_indicator_items(get(result, key, nothing))
            isempty(items) || return items
        end
    end
    MacroeconomicIndicator[]
end

function construct(
    ::Type{MacroeconomicIndicatorListResponse},
    obj::JSONObject,
)
    items = _macro_indicator_items_from_response(obj)
    MacroeconomicIndicatorListResponse(items, _macro_response_count(obj, length(items)))
end

function construct(
    ::Type{MacroeconomicIndicatorListResponse},
    obj::AbstractVector,
)
    items = _macro_indicator_items(obj)
    MacroeconomicIndicatorListResponse(items, length(items))
end

"""
宏观经济指标的单个历史数据点（period 如 `2024-Q1`、`2024-03`）。
"""
struct Macroeconomic
    period::String
    release_at::Union{DateTime,Nothing}
    actual_value::String
    previous_value::String
    forecast_value::String
    revised_value::String
    next_release_at::Union{DateTime,Nothing}
    unit::String
    unit_prefix::String
end
function construct(::Type{Macroeconomic}, obj::JSONObject)
    Macroeconomic(
        _macro_text_field(obj, (:period, :observation_date)),
        _rfc3339_opt(get(obj, :release_at, get(obj, :published_time, nothing))),
        _macro_text(get(obj, :actual_value, get(obj, :actual_data, nothing))),
        _macro_text(get(obj, :previous_value, get(obj, :previous_data, nothing))),
        _macro_text(get(obj, :forecast_value, get(obj, :estimated_data, nothing))),
        _macro_text(get(obj, :revised_value, nothing)),
        _rfc3339_opt(get(obj, :next_release_at, nothing)),
        _macro_text(get(obj, :unit, nothing)),
        _macro_text(get(obj, :unit_prefix, nothing)),
    )
end

function _macro_with_default_unit(item::Macroeconomic, unit::String)::Macroeconomic
    isempty(item.unit) && !isempty(unit) || return item
    Macroeconomic(
        item.period,
        item.release_at,
        item.actual_value,
        item.previous_value,
        item.forecast_value,
        item.revised_value,
        item.next_release_at,
        unit,
        item.unit_prefix,
    )
end

"""
`macroeconomic` 响应：`info` 为指标元数据（可能为 null，兜底空结构），
`data` 为历史数据点，`count` 为总数据点数。
"""
struct MacroeconomicResponse
    info::MacroeconomicIndicator
    data::Vector{Macroeconomic}
    count::Int
end
function construct(::Type{MacroeconomicResponse}, obj::JSONObject)
    indicator_raw = get(obj, :indicator, nothing)
    if indicator_raw isa JSONObject
        info = construct(MacroeconomicIndicator, indicator_raw)
        unit = _macro_text(get(indicator_raw, :unit, nothing))
        data_raw = get(indicator_raw, :indicator_data, nothing)
        items = if isnothing(data_raw)
            Macroeconomic[]
        else
            [_macro_with_default_unit(construct(Macroeconomic, x), unit) for x in data_raw]
        end
        return MacroeconomicResponse(info, items, _macro_response_count(obj, length(items)))
    end

    info_raw = get(obj, :info, nothing)
    info =
        info_raw isa JSONObject ?
        construct(MacroeconomicIndicator, info_raw) : MacroeconomicIndicator()
    items = if haskey(obj, :data) && !isnothing(obj.data)
        [construct(Macroeconomic, x) for x in obj.data]
    else
        Macroeconomic[]
    end
    MacroeconomicResponse(info, items, _int_or_zero(get(obj, :count, 0)))
end

end # module FundamentalProtocol
