module DCAProtocol

using EnumX, JSON
using ..Utils: Dec64, JSONObject, counter_id_to_symbol
using ..Constant: Market
import ..Utils: _parse_optional_decimal, construct
import ..MarketProtocol: _market_from_str

export DCAFrequency,
    DCAStatus,
    DcaPlan,
    DcaList,
    DcaStats,
    DcaSupportInfo,
    DcaSupportList,
    DcaHistoryRecord,
    DcaHistoryResponse,
    DcaCreateResult,
    DcaCalcDateResult,
    _dca_frequency_str,
    _dca_status_str,
    _dca_status_from_str

@enumx DCAFrequency begin
    Daily = 1
    Weekly = 2
    Fortnightly = 3
    Monthly = 4
end

@enumx DCAStatus begin
    Active = 1
    Suspended = 2
    Finished = 3
end

function _dca_frequency_str(f::DCAFrequency.T)
    f === DCAFrequency.Daily ? "Daily" :
    f === DCAFrequency.Weekly ? "Weekly" :
    f === DCAFrequency.Fortnightly ? "Fortnightly" :
    f === DCAFrequency.Monthly ? "Monthly" : error("unknown DCAFrequency: $f")
end

function _dca_status_str(s::DCAStatus.T)
    s === DCAStatus.Active ? "Active" :
    s === DCAStatus.Suspended ? "Suspended" :
    s === DCAStatus.Finished ? "Finished" : error("unknown DCAStatus: $s")
end

function _dca_status_from_str(s::AbstractString)
    s == "Active" ? DCAStatus.Active :
    s == "Suspended" ? DCAStatus.Suspended :
    s == "Finished" ? DCAStatus.Finished : DCAStatus.Active
end

function _dca_frequency_from_str(s::AbstractString)
    s == "Daily" ? DCAFrequency.Daily :
    s == "Weekly" ? DCAFrequency.Weekly :
    s == "Fortnightly" ? DCAFrequency.Fortnightly :
    s == "Monthly" ? DCAFrequency.Monthly : DCAFrequency.Monthly
end

# ── DcaPlan ────────────────────────────────────────────────────────

# alter_hours 在 API 中可能是整数或字符串，统一转字符串
_to_string_or_empty(::Nothing) = ""
_to_string_or_empty(x::Integer) = string(x)
_to_string_or_empty(x::Number) = string(x)
_to_string_or_empty(x::AbstractString) = String(x)

struct DcaPlan
    plan_id::String
    status::DCAStatus.T
    symbol::String                              # 由 counter_id 转换
    member_id::String
    aaid::String
    account_channel::String
    display_account::String
    market::Market.T
    per_invest_amount::Dec64                    # empty_is_0
    invest_frequency::DCAFrequency.T
    invest_day_of_week::String
    invest_day_of_month::String
    allow_margin_finance::Bool
    alter_hours::String
    created_at::String
    updated_at::String
    next_trd_date::String
    stock_name::String
    cum_amount::Union{Dec64,Nothing}
    issue_number::Int64
    average_cost::Union{Dec64,Nothing}
    cum_profit::Union{Dec64,Nothing}
end
function construct(::Type{DcaPlan}, obj::JSONObject)
    # per_invest_amount: empty_is_0
    pia_raw = get(obj, :per_invest_amount, "")
    per_invest_amount =
        if isnothing(pia_raw) || (pia_raw isa AbstractString && isempty(pia_raw))
            Dec64(0)
        elseif pia_raw isa Number
            Dec64(pia_raw)
        else
            try
                parse(Dec64, String(pia_raw))
            catch
                Dec64(0)
            end
        end

    DcaPlan(
        String(get(obj, :plan_id, "")),
        _dca_status_from_str(String(get(obj, :status, "Active"))),
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :member_id, "")),
        String(get(obj, :aaid, "")),
        String(get(obj, :account_channel, "")),
        String(get(obj, :display_account, "")),
        _market_from_str(String(get(obj, :market, ""))),
        per_invest_amount,
        _dca_frequency_from_str(String(get(obj, :invest_frequency, "Monthly"))),
        String(get(obj, :invest_day_of_week, "")),
        String(get(obj, :invest_day_of_month, "")),
        Bool(get(obj, :allow_margin_finance, false)),
        _to_string_or_empty(get(obj, :alter_hours, nothing)),
        String(get(obj, :created_at, "")),
        String(get(obj, :updated_at, "")),
        String(get(obj, :next_trd_date, "")),
        String(get(obj, :stock_name, "")),
        _parse_optional_decimal(get(obj, :cum_amount, nothing)),
        Int64(get(obj, :issue_number, 0)),
        _parse_optional_decimal(get(obj, :average_cost, nothing)),
        _parse_optional_decimal(get(obj, :cum_profit, nothing)),
    )
end

# ── DcaList ────────────────────────────────────────────────────────

struct DcaList
    plans::Vector{DcaPlan}
end
function construct(::Type{DcaList}, obj::JSONObject)
    items = if haskey(obj, :plans) && !isnothing(obj.plans)
        [construct(DcaPlan, x) for x in obj.plans]
    else
        DcaPlan[]
    end
    DcaList(items)
end

# ── DcaStats ───────────────────────────────────────────────────────

struct DcaStats
    active_count::String
    finished_count::String
    suspended_count::String
    nearest_plans::Vector{DcaPlan}
    rest_days::String
    total_amount::Union{Dec64,Nothing}
    total_profit::Union{Dec64,Nothing}
end
function construct(::Type{DcaStats}, obj::JSONObject)
    nearest = if haskey(obj, :nearest_plans) && !isnothing(obj.nearest_plans)
        [construct(DcaPlan, x) for x in obj.nearest_plans]
    else
        DcaPlan[]
    end
    DcaStats(
        String(get(obj, :active_count, "")),
        String(get(obj, :finished_count, "")),
        String(get(obj, :suspended_count, "")),
        nearest,
        String(get(obj, :rest_days, "")),
        _parse_optional_decimal(get(obj, :total_amount, nothing)),
        _parse_optional_decimal(get(obj, :total_profit, nothing)),
    )
end

# ── DcaSupportInfo / DcaSupportList ────────────────────────────────

struct DcaSupportInfo
    symbol::String                       # 由 counter_id 转换
    support_regular_saving::Bool
end
function construct(::Type{DcaSupportInfo}, obj::JSONObject)
    DcaSupportInfo(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        Bool(get(obj, :support_regular_saving, false)),
    )
end

struct DcaSupportList
    infos::Vector{DcaSupportInfo}
end
function construct(::Type{DcaSupportList}, obj::JSONObject)
    items = if haskey(obj, :infos) && !isnothing(obj.infos)
        [construct(DcaSupportInfo, x) for x in obj.infos]
    else
        DcaSupportInfo[]
    end
    DcaSupportList(items)
end

# ── DcaHistoryRecord / DcaHistoryResponse ──────────────────────────

struct DcaHistoryRecord
    created_at::String
    order_id::String
    status::String
    action::String
    order_type::String
    executed_qty::Union{Dec64,Nothing}
    executed_price::Union{Dec64,Nothing}
    executed_amount::Union{Dec64,Nothing}
    rejected_reason::String
    symbol::String                          # 由 counter_id 转换
end
function construct(::Type{DcaHistoryRecord}, obj::JSONObject)
    DcaHistoryRecord(
        String(get(obj, :created_at, "")),
        String(get(obj, :order_id, "")),
        String(get(obj, :status, "")),
        String(get(obj, :action, "")),
        String(get(obj, :order_type, "")),
        _parse_optional_decimal(get(obj, :executed_qty, nothing)),
        _parse_optional_decimal(get(obj, :executed_price, nothing)),
        _parse_optional_decimal(get(obj, :executed_amount, nothing)),
        String(get(obj, :rejected_reason, "")),
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
    )
end

struct DcaHistoryResponse
    records::Vector{DcaHistoryRecord}
    has_more::Bool
end
function construct(::Type{DcaHistoryResponse}, obj::JSONObject)
    items = if haskey(obj, :records) && !isnothing(obj.records)
        [construct(DcaHistoryRecord, x) for x in obj.records]
    else
        DcaHistoryRecord[]
    end
    DcaHistoryResponse(items, Bool(get(obj, :has_more, false)))
end

# ── DcaCreateResult / DcaCalcDateResult ────────────────────────────

struct DcaCreateResult
    plan_id::String
end
construct(::Type{DcaCreateResult}, obj::JSONObject) =
    DcaCreateResult(String(get(obj, :plan_id, "")))

struct DcaCalcDateResult
    trade_date::String
end
construct(::Type{DcaCalcDateResult}, obj::JSONObject) =
    DcaCalcDateResult(String(get(obj, :trade_date, "")))

end # module DCAProtocol
