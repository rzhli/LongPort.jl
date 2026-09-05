module USProtocol

using Dates, JSON
using ..Utils: counter_id_to_symbol
import ..Utils: construct

export USRankTag,
    USSharelistItem,
    USAIChatData,
    USCompanyOverview,
    USValuationMetric,
    USValuationOverview,
    USReportPeriod,
    USFinancialISItem,
    USFinancialBSItem,
    USFinancialCFItem,
    USFinancialOverview,
    USFinancialStatementField,
    USFinancialStatementPeriod,
    USFinancialStatement,
    USKeyMetricItem,
    USKeyFinancialMetrics,
    USConsensusEstimate,
    USConsensusItem,
    USAnalystConsensus,
    USFiscalYearDividend,
    USETFDividendInfo,
    USRecentDividend,
    USDividendHistoryItem,
    USDividendPayoutRecord,
    USCompanyDividends,
    USETFFile,
    USETFFilesResponse,
    USCryptoOverview,
    QueryUSOrdersResponse,
    USOrderHistory,
    USButtonControl,
    USChargeItem,
    USChargeDetail,
    USAttachedOrder,
    USOrderDetail,
    USOrderDetailResponse,
    USCashEntry,
    USCryptoEntry,
    USStockEntry,
    USAssetOverview,
    USRealizedPLMetric,
    USRealizedPLEntry,
    USRealizedPL,
    construct_us

@kwarg mutable struct USRankTag
    key::String = ""
    location::Int = 0
    title::String = ""
    text::String = ""
    rank_type::Int = 0
    highlight_text::String = ""
end

@kwarg mutable struct USSharelistItem
    chg::String = ""
    id::String = ""
    name::String = ""
end

@kwarg mutable struct USAIChatData
    agent_id::String = ""
    handoff_agent_id::String = ""
    symbol::String = ""
    text::String = ""
    chat_type::String = "" &(json = (name = "type",),)
    workflow_type::String = ""
end

@kwarg mutable struct USCompanyOverview
    intro::String = ""
    market_cap::String = ""
    ccy_symbol::String = ""
    top_rank_tags::Vector{USRankTag} = USRankTag[]
    detail_url::String = ""
    share_list::Vector{USSharelistItem} = USSharelistItem[]
end

@kwarg mutable struct USValuationMetric
    circle::String = ""
    part::String = ""
    metric::String = ""
    desc::String = ""
    industry_median::String = ""
end

@kwarg mutable struct USValuationOverview
    metrics::Dict{String,USValuationMetric} = Dict{String,USValuationMetric}()
    indicator::String = ""
    range::Int = 0
    date::String = ""
    ccy_symbol::String = ""
    aichat_data::USAIChatData = USAIChatData()
    ai_summary::String = ""
end

@kwarg mutable struct USReportPeriod
    start_date::String = ""
    end_date::String = ""
    report_txt::String = ""
end

@kwarg mutable struct USFinancialISItem
    revenue::String = ""
    net_income::String = ""
    net_margin::String = ""
    report::USReportPeriod = USReportPeriod()
end

@kwarg mutable struct USFinancialBSItem
    debt_assets_ratio::String = ""
    total_assets::String = ""
    total_liabilities::String = ""
    report::USReportPeriod = USReportPeriod()
end

@kwarg mutable struct USFinancialCFItem
    operating::String = ""
    investing::String = ""
    financing::String = ""
    report::USReportPeriod = USReportPeriod()
end

@kwarg mutable struct USFinancialOverview
    ccy_symbol::String = ""
    report_type::String = ""
    is_list::Vector{USFinancialISItem} = USFinancialISItem[]
    bs_list::Vector{USFinancialBSItem} = USFinancialBSItem[]
    cf_list::Vector{USFinancialCFItem} = USFinancialCFItem[]
end

@kwarg mutable struct USFinancialStatementField
    display_order::Int = 0
    field::String = ""
    id::String = ""
    level::Int = 0
    name::String = ""
    value::String = ""
    value_type::String = ""
    yoy::String = ""
end

@kwarg mutable struct USFinancialStatementPeriod
    ff_period::String = ""
    ff_year::Int = 0
    fields::Vector{USFinancialStatementField} = USFinancialStatementField[]
    fp_end::String = ""
    report_txt::String = ""
    rpt_date::String = ""
end

@kwarg mutable struct USFinancialStatement
    currency::String = ""
    report::String = ""
    list::Vector{USFinancialStatementPeriod} = USFinancialStatementPeriod[]
    empty_fields::Vector{String} = String[]
end

@kwarg mutable struct USKeyMetricItem
    ff_period::String = ""
    ff_year::Int = 0
    fp_end::String = ""
    report_txt::String = ""
    rpt_date::String = ""
    fields::Vector{Any} = Any[]
end

@kwarg mutable struct USKeyFinancialMetrics
    currency::String = ""
    report::String = ""
    empty_fields::Vector{String} = String[]
    list::Vector{USKeyMetricItem} = USKeyMetricItem[]
end

@kwarg mutable struct USConsensusEstimate
    actual::String = ""
    estimate::String = ""
end

@kwarg mutable struct USConsensusItem
    ebit::USConsensusEstimate = USConsensusEstimate()
    eps::USConsensusEstimate = USConsensusEstimate()
    fiscal_year::Int = 0
    report_txt::String = ""
    revenue::USConsensusEstimate = USConsensusEstimate()
end

@kwarg mutable struct USAnalystConsensus
    ai_summary::String = ""
    aichat_data::USAIChatData = USAIChatData()
    currency::String = ""
    report::String = ""
    list::Vector{USConsensusItem} = USConsensusItem[]
    opt_reports::Vector{String} = String[]
    h5_data::Any = nothing
end

@kwarg mutable struct USFiscalYearDividend
    dividend::String = ""
    dividend_yield::String = ""
    fiscal_year::String = ""
    currency::String = ""
    fiscal_year_range::String = ""
end

@kwarg mutable struct USETFDividendInfo
    dividend_ttm::String = ""
    dividend_yield_ttm::String = ""
    dividend_frequency::String = ""
    currency::String = ""
    fiscal_year_info::Vector{USFiscalYearDividend} = USFiscalYearDividend[]
end

@kwarg mutable struct USRecentDividend
    dividend_ttm::String = ""
    dividend_yield_ttm::String = ""
    payouts::String = ""
    currency::String = ""
end

@kwarg mutable struct USDividendHistoryItem
    fiscal_year::String = ""
    fiscal_year_range::String = ""
    total_shareholder_yield::String = ""
    dividend::String = ""
    dividend_yield::String = ""
    dividend_growth_rate::String = ""
    dividend_payout_ratio::String = ""
    dividend_to_cashflow_ratio::String = ""
    net_buyback::String = ""
    net_buyback_yield::String = ""
    net_buyback_growth_rate::String = ""
    net_buyback_payout_ratio::String = ""
    net_buyback_to_cashflow_ratio::String = ""
    currency::String = ""
end

@kwarg mutable struct USDividendPayoutRecord
    dividend::String = ""
    dividend_type::String = ""
    currency::String = ""
    ex_date::String = ""
    payment_date::String = ""
    record_date::String = ""
    title::String = ""
    start_time_unix::String = ""
end

@kwarg mutable struct USCompanyDividends
    recent_dividends::USRecentDividend = USRecentDividend()
    dividend_history::Vector{USDividendHistoryItem} = USDividendHistoryItem[]
    payout_ratios::Vector{USDividendHistoryItem} = USDividendHistoryItem[]
    dividend_payout_history::Vector{USDividendPayoutRecord} = USDividendPayoutRecord[]
end

@kwarg mutable struct USETFFile
    file_name::String = ""
    file_path::String = ""
    update_date::String = ""
    code::String = ""
    format::String = ""
end

@kwarg mutable struct USETFFilesResponse
    files::Vector{USETFFile} = USETFFile[]
end

@kwarg mutable struct USCryptoOverview
    name::String = ""
    ticker::String = ""
    currency::String = ""
    all_time_high::String = ""
    all_time_high_date::String = ""
    all_time_low::String = ""
    all_time_low_date::String = ""
    ipo_date::String = ""
    issue_price::String = ""
    shares::String = ""
    symbol::String = "" &(json = (name = "counter_id",),)
    base_asset::String = ""
    official_web_address::String = ""
    logo::String = ""
    wiki_url::String = ""
    profile::String = ""
end

@kwarg mutable struct QueryUSOrdersResponse
    orders::Vector{Any} = Any[]
    total_count::Int = 0
end

@kwarg mutable struct USOrderHistory
    exec_type::Int = 0
    status::String = ""
    price::String = ""
    qty::String = ""
    time::String = ""
    msg::String = ""
    is_manually::Bool = false
    opp_party_id::String = ""
    trd_match_id::String = ""
    operator::String = ""
    op_entrust_way::String = ""
    cxl_rej_response_to::Int = 0
    withdrawal_reason::String = ""
    opp_name::String = ""
    exec_id::String = ""
end

@kwarg mutable struct USButtonControl
    withdraw::Int = 0
    replace::Int = 0
    exceptionable::Vector{String} = String[]
end

@kwarg mutable struct USChargeItem
    code::Int = 0
    name::String = ""
    fees::Vector{String} = String[]
end

@kwarg mutable struct USChargeDetail
    currency::String = ""
    total_amount::String = ""
    items::Vector{USChargeItem} = USChargeItem[]
end

@kwarg mutable struct USAttachedOrder
    attached_type_display::Int = 0
    executed_qty::String = ""
    quantity::String = ""
    status::String = ""
    trigger_price::String = ""
    order_id::String = ""
    gtd::String = ""
    time_in_force::Int = 0
    tag::Int = 0
    activate_order_type::String = ""
    activate_rth::Int = 0
    submit_price::String = ""
    symbol::String = "" &(json = (name = "counter_id",),)
    withdrawn::Bool = false
end

@kwarg mutable struct USOrderDetail
    id::String = ""
    aaid::String = ""
    account_channel::String = ""
    action::Int = 0
    symbol::String = "" &(json = (name = "counter_id",),)
    underlying_symbol::String = "" &(json = (name = "underlying_counter_id",),)
    security_type::String = ""
    name::String = ""
    currency::String = ""
    trade_currency::String = ""
    order_type::String = ""
    status::String = ""
    price::String = ""
    quantity::String = ""
    executed_qty::String = ""
    executed_price::String = ""
    executed_amount::String = ""
    operate_direction::String = ""
    time_in_force::Int = 0
    gtd::String = ""
    tag::Int = 0
    msg::String = ""
    force_only_rth::Int = 0
    submitted_at::String = ""
    done_at::String = ""
    trigger_price::String = ""
    trigger_at::String = ""
    trigger_status::Int = 0
    trigger_exchange::String = ""
    trigger_last_done::String = ""
    trigger_count::Int = 0
    tailing_amount::String = ""
    tailing_percent::String = ""
    limit_offset::String = ""
    limit_depth_level::Int = 0
    market_price::String = ""
    submitted_amount::String = ""
    estimated_fee::String = ""
    free_status::Int = 0
    free_amount::String = ""
    free_currency::String = ""
    deductions_status::Int = 0
    deductions_amount::String = ""
    deductions_currency::String = ""
    platform_deductions_status::Int = 0
    platform_deductions_amount::String = ""
    platform_deductions_currency::String = ""
    display_account::String = ""
    settlement_account::String = ""
    settlement_channel::String = ""
    customer_name::String = ""
    real_name::String = ""
    en_name::String = ""
    joint_real_name::String = ""
    joint_en_name::String = ""
    org_id::String = ""
    bcan::String = ""
    op_entrust_way::Int = 0
    op_entrust_way_name::String = ""
    remark::String = ""
    notice::String = ""
    short_sell_type::Int = 0
    ploy_type::String = ""
    ploy_id::String = ""
    ploy_status::String = ""
    trend::Int = 0
    withdrawal_reason::String = ""
    activate_order_type::String = ""
    activate_rth::Int = 0
    submit_price::String = ""
    contract_direction::String = ""
    strike_price::String = ""
    contract_size::String = ""
    monitor_price::String = ""
    button_control::USButtonControl = USButtonControl()
    charge_detail::Union{USChargeDetail,Nothing} = nothing
    attached_orders::Vector{USAttachedOrder} = USAttachedOrder[]
    order_histories::Vector{USOrderHistory} = USOrderHistory[]
end

@kwarg mutable struct USOrderDetailResponse
    order::Union{USOrderDetail,Nothing} = nothing
    current_attached_order::Union{USOrderDetail,Nothing} = nothing
    current_millisecond::String = ""
end

@kwarg mutable struct USCashEntry
    currency::String = ""
    frozen_buy_cash::String = ""
    outstanding::String = ""
    settled_cash::String = ""
    total_amount::String = ""
    total_cash::String = ""
end

@kwarg mutable struct USCryptoEntry
    asset_type::String = ""
    average_cost::String = ""
    symbol::String = "" &(json = (name = "counter_id",),)
    currency::String = ""
    industry_name::String = ""
end

@kwarg mutable struct USStockEntry
    symbol::String = ""
    full_symbol::String = "" &(json = (name = "counter_id",),)
    asset_type::String = ""
    quantity::String = ""
    currency::String = ""
    average_cost::String = ""
    market::String = ""
    trade_status::String = ""
    prev_close::String = ""
    last_done::String = ""
    market_price::String = ""
    pretrade_close::String = ""
    stock_invest_of_today::String = ""
    today_pl::String = ""
    pretrade_stock_invest_of_today::String = ""
    pretrade_today_pl::String = ""
    night_last_done::String = ""
    night_prev_close::String = ""
    position_side::String = ""
    open_position_time::String = ""
    name::String = ""
    industry_counter_id::String = ""
    industry_name::String = ""
end

@kwarg mutable struct USAssetOverview
    account_type::String = ""
    asset_timestamp::Union{DateTime,Nothing} = nothing
    cash_buy_power::String = ""
    overnight_buy_power::String = ""
    currency::String = ""
    cash_list::Vector{USCashEntry} = USCashEntry[]
    stock_list::Vector{USStockEntry} = USStockEntry[]
    option_list::Vector{Any} = Any[]
    crypto_list::Vector{USCryptoEntry} = USCryptoEntry[]
    multi_leg::Any = nothing
end

@kwarg mutable struct USRealizedPLMetric
    amount::String = ""
    period::Int = 0
    rate::String = ""
end

@kwarg mutable struct USRealizedPLEntry
    category::Int = 0
    currency::String = ""
    metrics::Vector{USRealizedPLMetric} = USRealizedPLMetric[]
end

@kwarg mutable struct USRealizedPL
    realized_pl_list::Vector{USRealizedPLEntry} = USRealizedPLEntry[]
end

# All of the mutable structs above use `@kwarg` (StructUtils' `Base.@kwdef`
# equivalent), so JSON.jl knows their field defaults and keyword constructor and
# can materialize them directly from partial API payloads. No per-type trait
# declaration is needed anymore.

construct_us(::Type{T}, obj) where {T} = JSON.parse(JSON.json(obj), T)
construct_us(::Type{USAssetOverview}, obj) = construct(USAssetOverview, obj)

_get(obj, key::Symbol, default) = haskey(obj, key) ? obj[key] : default

function _construct_vector(::Type{T}, values) where {T}
    isnothing(values) && return T[]
    return T[construct_us(T, value) for value in values]
end

function _unix_datetime(value)
    isnothing(value) && return nothing
    text = String(value)
    isempty(text) && return nothing
    parsed = tryparse(Int64, text)
    return isnothing(parsed) ? nothing : unix2datetime(parsed)
end

function construct(::Type{USAssetOverview}, obj)
    return USAssetOverview(
        account_type = String(_get(obj, :account_type, "")),
        asset_timestamp = _unix_datetime(_get(obj, :asset_timestamp, nothing)),
        cash_buy_power = String(_get(obj, :cash_buy_power, "")),
        overnight_buy_power = String(_get(obj, :overnight_buy_power, "")),
        currency = String(_get(obj, :currency, "")),
        cash_list = _construct_vector(USCashEntry, _get(obj, :cash_list, nothing)),
        stock_list = _construct_vector(USStockEntry, _get(obj, :stock_list, nothing)),
        option_list = Any[value for value in _get(obj, :option_list, Any[])],
        crypto_list = _construct_vector(USCryptoEntry, _get(obj, :crypto_list, nothing)),
        multi_leg = _get(obj, :multi_leg, nothing),
    )
end

function normalize_symbols!(value::USCryptoOverview)
    value.symbol = counter_id_to_symbol(value.symbol)
    return value
end

function normalize_symbols!(value::USAttachedOrder)
    value.symbol = counter_id_to_symbol(value.symbol)
    return value
end


function normalize_symbols!(value::USOrderDetail)
    value.symbol = counter_id_to_symbol(value.symbol)
    value.underlying_symbol = counter_id_to_symbol(value.underlying_symbol)
    normalize_symbols!.(value.attached_orders)
    return value
end

function normalize_symbols!(value::USOrderDetailResponse)
    isnothing(value.order) || normalize_symbols!(value.order)
    isnothing(value.current_attached_order) || normalize_symbols!(value.current_attached_order)
    return value
end

function normalize_symbols!(value::USAssetOverview)
    for stock in value.stock_list
        stock.full_symbol = counter_id_to_symbol(stock.full_symbol)
    end
    for crypto in value.crypto_list
        crypto.symbol = counter_id_to_symbol(crypto.symbol)
    end
    return value
end

end # module USProtocol
