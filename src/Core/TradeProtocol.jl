# 基于官方 trade.proto 的Julia实现
# 专门用于交易WebSocket协议的Protocol Buffer消息

module TradeProtocol

import ProtoBuf as PB
using ProtoBuf: OneOf
using EnumX
using Dates
using JSON
using Printf
using ..QuoteProtocol: SecurityBoard
using ..Constant
using ..Utils
import ..Utils: construct

export Command,
    DispatchType,
    ContentType,
    Sub,
    SubResponse,
    SubResponseFail,
    Unsub,
    UnsubResponse,
    Notification,
    OrderType,
    OrderStatus,
    TopicType,
    Execution,
    OrderSide,
    OrderTag,
    TimeInForceType,
    TriggerStatus,
    OutsideRTH,
    Order,
    PushOrderChanged,
    MarginRatio,
    CommissionFreeStatus,
    DeductionStatus,
    ChargeCategoryCode,
    OrderHistoryDetail,
    OrderChargeFee,
    OrderChargeItem,
    OrderChargeDetail,
    OrderDetail,
    BalanceType,
    EstimateMaxPurchaseQuantityResponse,
    AllExecutionsResponse,
    FrozenTransactionFee,
    CashInfo,
    AccountBalance,
    CashFlow,
    CashFlowDirection,
    FundPositionsResponse,
    FundPositionChannel,
    FundPosition,
    StockPositionsResponse,
    StockPositionChannel,
    StockPosition,
    SubmitOrderResponse,
    ExecutionResponse,
    TodayExecutionResponse,
    RiskLevel,
    SubmitOrderOptions,
    ReplaceOrderOptions,
    GetHistoryExecutionsOptions,
    GetTodayExecutionsOptions,
    GetAllExecutionsOptions,
    GetHistoryOrdersOptions,
    GetUSHistoryOrders,
    QueryUSOrdersOptions,
    GetTodayOrdersOptions,
    GetCashFlowOptions,
    GetFundPositionsOptions,
    GetStockPositionsOptions,
    EstimateMaxPurchaseQuantityOptions,
    PushEvent

# --- Order Type Enum ---
@enumx OrderType begin
    UNKNOWN = 0
    LO = 1      # 限价单 (HK, US)
    ELO = 2     # 增强限价单 (HK)
    MO = 3      # 市价单 (HK, US)
    AO = 4      # 竞价市价单 (HK)
    ALO = 5     # 竞价限价单 (HK)
    ODD = 6     # 碎股单挂单 (HK)
    LIT = 7     # 触价限价单 (HK, US)
    MIT = 8     # 触价市价单 (HK, US)
    TSLPAMT = 9 # 跟踪止损限价单 (跟踪金额) (HK, US)
    TSLPPCT = 10 # 跟踪止损限价单 (跟踪涨跌幅) (HK, US)
    SLO = 11    # 特殊限价单 (HK)
end

# --- Order Status Enum ---
@enumx OrderStatus begin
    Unknown = 0             # 未知
    NotReported = 1         # 待提交
    ReplacedNotReported = 2 # 待提交 (改单成功)
    ProtectedNotReported = 3 # 待提交 (保价订单)
    VarietiesNotReported = 4 # 待提交 (条件单)
    FilledStatus = 5              # 已成交
    WaitToNew = 6           # 已提待报
    NewStatus = 7                 # 已委托
    WaitToReplace = 8       # 修改待报
    PendingReplaceStatus = 9      # 待修改
    ReplacedStatus = 10           # 已修改
    PartialFilledStatus = 11      # 部分成交
    WaitToCancel = 12       # 撤销待报
    PendingCancelStatus = 13      # 待撤回
    RejectedStatus = 14           # 已拒绝
    CanceledStatus = 15           # 已撤单
    ExpiredStatus = 16            # 已过期
    PartialWithdrawal = 17  # 部分撤单
end

# 交易网关命令定义
@enumx Command begin
    CMD_UNKNOWN = 0
    CMD_SUB = 16
    CMD_UNSUB = 17
    CMD_NOTIFY = 18
end

# 分发类型
@enumx DispatchType begin
    DISPATCH_UNDEFINED = 0
    DISPATCH_DIRECT = 1
    DISPATCH_BROADCAST = 2
end

# 内容类型
@enumx ContentType begin
    CONTENT_UNDEFINED = 0
    CONTENT_JSON = 1
    CONTENT_PROTO = 2
end

# SubResponse 失败信息
struct SubResponseFail
    topic::String
    reason::String
end
PB.default_values(::Type{SubResponseFail}) = (; topic = "", reason = "")
PB.field_numbers(::Type{SubResponseFail}) = (; topic = 1, reason = 2)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:SubResponseFail})
    topic = ""
    reason = ""
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            topic = PB.decode(d, String)
        elseif field_number == 2
            reason = PB.decode(d, String)
        else
            PB.skip(d, wire_type)
        end
    end
    return SubResponseFail(topic, reason)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::SubResponseFail)
    initpos = position(e.io)
    !isempty(x.topic) && PB.encode(e, 1, x.topic)
    !isempty(x.reason) && PB.encode(e, 2, x.reason)
    return position(e.io) - initpos
end
function PB._encoded_size(x::SubResponseFail)
    encoded_size = 0
    !isempty(x.topic) && (encoded_size += PB._encoded_size(x.topic, 1))
    !isempty(x.reason) && (encoded_size += PB._encoded_size(x.reason, 2))
    return encoded_size
end

# 订阅请求 - 命令16
struct Sub
    topics::Vector{String}
end
PB.default_values(::Type{Sub}) = (; topics = String[])
PB.field_numbers(::Type{Sub}) = (; topics = 1)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:Sub})
    topics = String[]
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            PB.decode!(d, PB.BufferedVector(topics))
        else
            PB.skip(d, wire_type)
        end
    end
    return Sub(topics)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::Sub)
    initpos = position(e.io)
    !isempty(x.topics) && PB.encode(e, 1, x.topics)
    return position(e.io) - initpos
end
function PB._encoded_size(x::Sub)
    encoded_size = 0
    !isempty(x.topics) && (encoded_size += PB._encoded_size(x.topics, 1))
    return encoded_size
end

# 订阅响应
struct SubResponse
    success::Vector{String}     # 订阅成功
    fail::Vector{SubResponseFail}  # 订阅失败
    current::Vector{String}     # 当前订阅
end
PB.default_values(::Type{SubResponse}) =
    (; success = String[], fail = SubResponseFail[], current = String[])
PB.field_numbers(::Type{SubResponse}) = (; success = 1, fail = 2, current = 3)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:SubResponse})
    success = String[]
    fail = SubResponseFail[]
    current = String[]
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            PB.decode!(d, PB.BufferedVector(success))
        elseif field_number == 2
            PB.decode!(d, PB.BufferedVector(fail))
        elseif field_number == 3
            PB.decode!(d, PB.BufferedVector(current))
        else
            PB.skip(d, wire_type)
        end
    end
    return SubResponse(success, fail, current)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::SubResponse)
    initpos = position(e.io)
    !isempty(x.success) && PB.encode(e, 1, x.success)
    !isempty(x.fail) && PB.encode(e, 2, x.fail)
    !isempty(x.current) && PB.encode(e, 3, x.current)
    return position(e.io) - initpos
end
function PB._encoded_size(x::SubResponse)
    encoded_size = 0
    !isempty(x.success) && (encoded_size += PB._encoded_size(x.success, 1))
    !isempty(x.fail) && (encoded_size += PB._encoded_size(x.fail, 2))
    !isempty(x.current) && (encoded_size += PB._encoded_size(x.current, 3))
    return encoded_size
end

# 取消订阅请求 - 命令17
struct Unsub
    topics::Vector{String}
end
PB.default_values(::Type{Unsub}) = (; topics = String[])
PB.field_numbers(::Type{Unsub}) = (; topics = 1)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:Unsub})
    topics = String[]
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            PB.decode!(d, PB.BufferedVector(topics))
        else
            PB.skip(d, wire_type)
        end
    end
    return Unsub(topics)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::Unsub)
    initpos = position(e.io)
    !isempty(x.topics) && PB.encode(e, 1, x.topics)
    return position(e.io) - initpos
end
function PB._encoded_size(x::Unsub)
    encoded_size = 0
    !isempty(x.topics) && (encoded_size += PB._encoded_size(x.topics, 1))
    return encoded_size
end

# 取消订阅响应
struct UnsubResponse
    current::Vector{String}     # 当前订阅
end
PB.default_values(::Type{UnsubResponse}) = (; current = String[])
PB.field_numbers(::Type{UnsubResponse}) = (; current = 3)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:UnsubResponse})
    current = String[]
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 3
            PB.decode!(d, PB.BufferedVector(current))
        else
            PB.skip(d, wire_type)
        end
    end
    return UnsubResponse(current)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::UnsubResponse)
    initpos = position(e.io)
    !isempty(x.current) && PB.encode(e, 3, x.current)
    return position(e.io) - initpos
end
function PB._encoded_size(x::UnsubResponse)
    encoded_size = 0
    !isempty(x.current) && (encoded_size += PB._encoded_size(x.current, 3))
    return encoded_size
end

# 推送通知 - 命令18
struct Notification
    topic::String
    content_type::ContentType.T
    dispatch_type::DispatchType.T
    data::Vector{UInt8}
end
PB.default_values(::Type{Notification}) = (;
    topic = "",
    content_type = ContentType.CONTENT_UNDEFINED,
    dispatch_type = DispatchType.DISPATCH_UNDEFINED,
    data = UInt8[],
)
PB.field_numbers(::Type{Notification}) =
    (; topic = 1, content_type = 2, dispatch_type = 3, data = 4)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:Notification})
    topic = ""
    content_type = ContentType.CONTENT_UNDEFINED
    dispatch_type = DispatchType.DISPATCH_UNDEFINED
    data = UInt8[]
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            topic = PB.decode(d, String)
        elseif field_number == 2
            content_type = PB.decode(d, ContentType.T)
        elseif field_number == 3
            dispatch_type = PB.decode(d, DispatchType.T)
        elseif field_number == 4
            data = PB.decode(d, Vector{UInt8})
        else
            PB.skip(d, wire_type)
        end
    end
    return Notification(topic, content_type, dispatch_type, data)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::Notification)
    initpos = position(e.io)
    !isempty(x.topic) && PB.encode(e, 1, x.topic)
    x.content_type != ContentType.CONTENT_UNDEFINED && PB.encode(e, 2, x.content_type)
    x.dispatch_type != DispatchType.DISPATCH_UNDEFINED && PB.encode(e, 3, x.dispatch_type)
    !isempty(x.data) && PB.encode(e, 4, x.data)
    return position(e.io) - initpos
end
function PB._encoded_size(x::Notification)
    encoded_size = 0
    !isempty(x.topic) && (encoded_size += PB._encoded_size(x.topic, 1))
    x.content_type != ContentType.CONTENT_UNDEFINED &&
        (encoded_size += PB._encoded_size(x.content_type, 2))
    x.dispatch_type != DispatchType.DISPATCH_UNDEFINED &&
        (encoded_size += PB._encoded_size(x.dispatch_type, 3))
    !isempty(x.data) && (encoded_size += PB._encoded_size(x.data, 4))
    return encoded_size
end

"""
Topic type
"""
@enumx TopicType begin
    Private = 0
end

"""
Order side
"""
@enumx OrderSide begin
    UnknownSide = 0
    Buy = 1
    Sell = 2
end

"""
Order tag
"""
@enumx OrderTag begin
    UnknownTag = 0
    Normal = 1
    LongTerm = 2
    Grey = 3
end

# LongBridge sends `"Gtc"`/`"GTC"` where the enum member is `LongTerm`, so the
# default name-matching `lift` for enums is not enough: JSON.jl calls `JSON.lift`
# whenever a JSON value has to become an `OrderTag.T`.
function JSON.lift(::Type{OrderTag.T}, value::AbstractString)
    value == "Gtc" && return OrderTag.LongTerm
    value == "GTC" && return OrderTag.LongTerm
    value == "Normal" && return OrderTag.Normal
    value == "Grey" && return OrderTag.Grey
    return OrderTag.UnknownTag
end
JSON.lift(::Type{OrderTag.T}, value::Symbol) = JSON.lift(OrderTag.T, String(value))

"""
Time in force type
"""
@enumx TimeInForceType begin
    UnknownTIF = 0
    Day = 1
    GTC = 2     # Good Till Cancelled
    GTD = 7     # Good Till Date
end

"""
Trigger price type
"""
@enumx TriggerPriceType begin
    Unknown = 0
    LIT = 1
    MIT = 2
end

"""
Trigger status
"""
@enumx TriggerStatus begin
    NOT_USED = 0
    Deactive = 1
    Active = 2
    Released = 3
end

"""
Enable or disable outside regular trading hours
"""
@enumx OutsideRTH begin
    UnknownOutsideRth = 0
    RTH_ONLY = 1
    ANY_TIME = 2
    OVERNIGHT = 3
    OptionPreMarket = 4
end

function JSON.lift(::Type{OutsideRTH.T}, value::AbstractString)
    value == "RTH_ONLY" && return OutsideRTH.RTH_ONLY
    value == "ANY_TIME" && return OutsideRTH.ANY_TIME
    value == "OVERNIGHT" && return OutsideRTH.OVERNIGHT
    value == "OPTION_PRE_MARKET" && return OutsideRTH.OptionPreMarket
    return OutsideRTH.UnknownOutsideRth
end
JSON.lift(::Type{OutsideRTH.T}, value::Symbol) = JSON.lift(OutsideRTH.T, String(value))

"""
Commission free status
"""
@enumx CommissionFreeStatus begin
    Unknown = 0
    None = 1
    Calculated = 2
    Pending = 3
    Ready = 4
end

"""
Deduction status
"""
@enumx DeductionStatus begin
    UNKNOWN = 0
    NONE = 1
    NO_DATA = 2
    PENDING = 3
    DONE = 4
end

"""
Charge category code
"""
@enumx ChargeCategoryCode begin
    UNKNOWN = 0
    BROKER_FEES = 1
    THIRD_FEES = 2
end

"""
Balance type
"""
@enumx BalanceType begin
    UnknownBalance = 0
    Cash = 1
    Stock = 2
    Fund = 3
end

"""
Cash flow direction
"""
@enumx CashFlowDirection begin
    UnknownDirection = 0
    Out = 1
    In = 2
end

"""
Risk level
"""
@enumx RiskLevel begin
    Safe = 0
    Moderate = 1
    Warning = 2
    Danger = 3
end

# Data Structures

"""
Execution information
"""
struct Execution
    order_id::String
    trade_id::String
    symbol::String
    trade_done_at::DateTime
    quantity::Int64
    price::Float64
end

"""
Order information
"""
struct Order
    order_id::String
    status::OrderStatus.T
    stock_name::String
    quantity::Int64
    executed_quantity::Int64
    price::Union{Float64,Nothing}
    executed_price::Union{Float64,Nothing}
    submitted_at::DateTime
    side::OrderSide.T
    symbol::String
    order_type::OrderType.T
    last_done::Union{Float64,Nothing}
    trigger_price::Union{Float64,Nothing}
    msg::String
    tag::OrderTag.T
    time_in_force::TimeInForceType.T
    expire_date::Union{Date,Nothing}
    updated_at::Union{DateTime,Nothing}
    trigger_at::Union{DateTime,Nothing}
    trailing_amount::Union{Float64,Nothing}
    trailing_percent::Union{Float64,Nothing}
    limit_offset::Union{Float64,Nothing}
    trigger_status::TriggerStatus.T
    currency::String
    outside_rth::OutsideRTH.T
    remark::String
end


"""
Push order changed information
"""
struct PushOrderChanged
    side::OrderSide.T
    stock_name::String
    submitted_quantity::Union{Int64,Nothing}
    symbol::String
    order_type::OrderType.T
    submitted_price::Union{Float64,Nothing}
    executed_quantity::Union{Int64,Nothing}
    executed_price::Union{Float64,Nothing}
    order_id::String
    currency::String
    status::OrderStatus.T
    submitted_at::Union{DateTime,Nothing}
    updated_at::Union{DateTime,Nothing}
    trigger_price::Union{Float64,Nothing}
    msg::String
    tag::OrderTag.T
    trigger_status::Union{TriggerStatus.T,Nothing}
    trigger_at::Union{DateTime,Nothing}
    trailing_amount::Union{Float64,Nothing}
    trailing_percent::Union{Float64,Nothing}
    limit_offset::Union{Float64,Nothing}
    account_no::String
    last_share::Union{Int64,Nothing}
    last_price::Union{Float64,Nothing}
    remark::String
end

"""
Margin ratio information
"""
struct MarginRatio
    im_factor::Float64
    mm_factor::Float64
    fm_factor::Float64
end

function construct(::Type{MarginRatio}, obj::JSONObject)
    MarginRatio(
        safeparse(Float64, obj.im_factor),
        safeparse(Float64, obj.mm_factor),
        safeparse(Float64, obj.fm_factor),
    )
end

function Base.show(io::IO, r::MarginRatio)
    print(
        io,
        "MarginRatio(im_factor: $(r.im_factor), mm_factor: $(r.mm_factor), fm_factor: $(r.fm_factor))",
    )
end

"""
Order charge fee
"""
struct OrderChargeFee
    code::String
    name::String
    fee::Float64
    currency::String
end

"""
Order charge item
"""
struct OrderChargeItem
    code::String
    name::String
    fees::Vector{OrderChargeFee}
end


"""
Order charge detail
"""
struct OrderChargeDetail
    total_charges::Union{Float64,Nothing}
    currency::String
    items::Vector{OrderChargeItem}
end

"""
Order history detail
"""
struct OrderHistoryDetail
    price::Float64
    quantity::Int64
    status::OrderStatus.T
    msg::String
    time::DateTime
end

"""
Order detail
"""
struct OrderDetail
    order_id::String
    status::OrderStatus.T
    stock_name::String
    quantity::Int64
    executed_quantity::Int64
    price::Union{Float64,Nothing}
    executed_price::Union{Float64,Nothing}
    submitted_at::DateTime
    side::OrderSide.T
    symbol::String
    order_type::OrderType.T
    last_done::Union{Float64,Nothing}
    trigger_price::Union{Float64,Nothing}
    msg::String
    tag::OrderTag.T
    time_in_force::TimeInForceType.T
    expire_date::Union{Date,Nothing}
    updated_at::Union{DateTime,Nothing}
    trigger_at::Union{DateTime,Nothing}
    trailing_amount::Union{Float64,Nothing}
    trailing_percent::Union{Float64,Nothing}
    limit_offset::Union{Float64,Nothing}
    trigger_status::TriggerStatus.T
    currency::String
    outside_rth::OutsideRTH.T
    remark::String
    free_status::CommissionFreeStatus.T
    free_amount::Union{Float64,Nothing}
    free_currency::Union{String,Nothing}
    deductions_status::DeductionStatus.T
    deductions_amount::Union{Float64,Nothing}
    deductions_currency::Union{String,Nothing}
    platform_deducted_status::DeductionStatus.T
    platform_deducted_amount::Union{Float64,Nothing}
    platform_deducted_currency::Union{String,Nothing}
    history::Vector{OrderHistoryDetail}
    charge_detail::OrderChargeDetail
end

function Base.show(io::IO, d::OrderDetail)
    println(io, "Order Details:")
    println(io, "  Order ID: ", d.order_id)
    println(io, "  Symbol: ", d.symbol, " (", d.stock_name, ")")
    println(io, "  Status: ", d.status)
    println(io, "  Side: ", d.side)
    println(io, "  Order Type: ", d.order_type)
    println(io, "  Submitted: ", d.quantity, " @ ", d.price)
    println(io, "  Executed: ", d.executed_quantity, " @ ", d.executed_price)
    println(io, "  Submitted At: ", d.submitted_at)
    println(io, "  Updated At: ", d.updated_at)
    println(io, "  Message: ", d.msg)
end

"""
Estimate max purchase quantity response
"""
struct EstimateMaxPurchaseQuantityResponse
    cash_max_qty::Int64
    margin_max_qty::Int64
end

"""
Frozen transaction fee
"""
struct FrozenTransactionFee
    currency::Currency.T
    frozen_transaction_fee::Float64
end

function construct(::Type{FrozenTransactionFee}, obj::JSONObject)
    FrozenTransactionFee(
        safeparse(Currency.T, obj.currency),
        safeparse(Float64, obj.frozen_transaction_fee),
    )
end

function Base.show(io::IO, fee::FrozenTransactionFee)
    print(io, "    - Currency: ", fee.currency, ", Fee: ", fee.frozen_transaction_fee)
end

"""
Submit order response
"""
struct SubmitOrderResponse
    order_id::String
end

"""
Cash info
"""
struct CashInfo
    withdraw_cash::Float64
    available_cash::Float64
    frozen_cash::Float64
    settling_cash::Float64
    currency::Currency.T
end

function construct(::Type{CashInfo}, obj::JSONObject)
    CashInfo(
        safeparse(Float64, obj.withdraw_cash),
        safeparse(Float64, obj.available_cash),
        safeparse(Float64, obj.frozen_cash),
        safeparse(Float64, obj.settling_cash),
        safeparse(Currency.T, obj.currency),
    )
end

function Base.show(io::IO, info::CashInfo)
    println(io, "    - Currency: ", info.currency)
    println(io, "      Available: ", info.available_cash)
    println(io, "      Withdrawable: ", info.withdraw_cash)
    println(io, "      Frozen: ", info.frozen_cash)
    print(io, "      Settling: ", info.settling_cash)
end

"""
Account balance
"""
struct AccountBalance
    total_cash::Float64
    max_finance_amount::Float64
    remaining_finance_amount::Float64
    risk_level::RiskLevel.T
    margin_call::Float64
    currency::Currency.T
    cash_infos::Vector{CashInfo}
    net_assets::Float64
    init_margin::Float64
    maintenance_margin::Float64
    buy_power::Float64
    frozen_transaction_fees::Vector{FrozenTransactionFee}
    market::Union{Market.T,Nothing}
end

function construct(::Type{AccountBalance}, obj::JSONObject)
    AccountBalance(
        safeparse(Float64, obj.total_cash),
        safeparse(Float64, obj.max_finance_amount),
        safeparse(Float64, obj.remaining_finance_amount),
        safeparse(RiskLevel.T, obj.risk_level),
        safeparse(Float64, obj.margin_call),
        safeparse(Currency.T, obj.currency),
        [construct(CashInfo, item) for item in obj.cash_infos],
        safeparse(Float64, obj.net_assets),
        safeparse(Float64, obj.init_margin),
        safeparse(Float64, obj.maintenance_margin),
        safeparse(Float64, obj.buy_power),
        [construct(FrozenTransactionFee, item) for item in obj.frozen_transaction_fees],
        haskey(obj, :market) && !isnothing(obj.market) ? safeparse(Market.T, obj.market) : nothing,
    )
end

function Base.show(io::IO, balance::AccountBalance)
    print(io, "Account Balance (", balance.currency)
    if !isnothing(balance.market)
        print(io, ", Market: ", balance.market)
    end
    println(io, "):")
    println(io, "  Net Assets: ", balance.net_assets)
    println(io, "  Total Cash: ", balance.total_cash)
    println(io, "  Buy Power: ", balance.buy_power)
    println(io, "  Risk Level: ", balance.risk_level)
    println(io, "  Margin Call: ", balance.margin_call)
    println(io, "  Initial Margin: ", balance.init_margin)
    println(io, "  Maintenance Margin: ", balance.maintenance_margin)
    println(io, "  Max Finance Amount: ", balance.max_finance_amount)
    println(io, "  Remaining Finance Amount: ", balance.remaining_finance_amount)

    println(io, "\n  Cash Details:")
    for info in balance.cash_infos
        println(io, info)
    end

    if !isempty(balance.frozen_transaction_fees)
        println(io, "\n  Frozen Transaction Fees:")
        for fee in balance.frozen_transaction_fees
            println(io, fee)
        end
    end
end

"""
Cash flow
"""
struct CashFlow
    transaction_flow_name::String
    direction::CashFlowDirection.T
    business_type::BalanceType.T
    balance::Float64
    currency::String
    business_time::DateTime
    symbol::Union{String,Nothing}
    description::String
end

function _cash_flow_datetime(val)
    if val isa DateTime
        return val
    elseif val isa Integer
        return unix2datetime(val)
    else
        sval = String(val)
        return all(isdigit, sval) ? unix2datetime(parse(Int64, sval)) : DateTime(sval)
    end
end

function construct(::Type{CashFlow}, obj::JSONObject)
    CashFlow(
        string(obj.transaction_flow_name),
        safeparse(CashFlowDirection.T, obj.direction),
        safeparse(BalanceType.T, obj.business_type),
        safeparse(Float64, obj.balance),
        string(obj.currency),
        _cash_flow_datetime(obj.business_time),
        haskey(obj, :symbol) && !isnothing(obj.symbol) ? string(obj.symbol) : nothing,
        haskey(obj, :description) && !isnothing(obj.description) ? string(obj.description) : "",
    )
end

_short_enum_name(e) = last(split(string(e), "."))
_count_label(n::Integer, singular::String, plural::String = string(singular, "s")) =
    string(n, " ", n == 1 ? singular : plural)

function Base.show(io::IO, flow::CashFlow)
    print(
        io,
        "CashFlow(",
        flow.business_time,
        ", ",
        _short_enum_name(flow.direction),
        ", ",
        flow.balance,
        " ",
        flow.currency,
        ", ",
        flow.transaction_flow_name,
    )
    if !isnothing(flow.symbol) && !isempty(flow.symbol)
        print(io, ", ", flow.symbol)
    end
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", flows::Vector{CashFlow})
    println(io, "Cash Flows: ", length(flows))
    for flow in flows
        println(
            io,
            "  - ",
            flow.business_time,
            " | ",
            _short_enum_name(flow.direction),
            " | ",
            flow.balance,
            " ",
            flow.currency,
            " | ",
            flow.transaction_flow_name,
            !isnothing(flow.symbol) && !isempty(flow.symbol) ? " | $(flow.symbol)" : "",
        )
    end
end

"""
Fund position
"""
struct FundPosition
    symbol::String
    symbol_name::String
    currency::String
    holding_units::String
    current_net_asset_value::String
    cost_net_asset_value::String
    net_asset_value_day::String
end

function Base.show(io::IO, pos::FundPosition)
    print(
        io,
        pos.symbol,
        isempty(pos.symbol_name) ? "" : " ($(pos.symbol_name))",
        ": ",
        pos.holding_units,
        " units, NAV ",
        pos.current_net_asset_value,
        " ",
        pos.currency,
    )
end

"""
Fund position channel
"""
struct FundPositionChannel
    account_channel::String
    fund_info::Vector{FundPosition}
end

function Base.show(io::IO, channel::FundPositionChannel)
    print(io, channel.account_channel, ": ", _count_label(length(channel.fund_info), "fund"))
end

"""
Fund positions response
"""
struct FundPositionsResponse
    list::Vector{FundPositionChannel}
end

function Base.show(io::IO, resp::FundPositionsResponse)
    total = 0
    for channel in resp.list
        total += length(channel.fund_info)
    end
    print(
        io,
        "Fund Positions: ",
        _count_label(total, "fund"),
        " in ",
        _count_label(length(resp.list), "channel"),
    )
    for channel in resp.list
        println(io)
        print(io, "  - ", channel)
        for pos in channel.fund_info
            println(io)
            print(io, "    ", pos)
        end
    end
end

"""
Stock position
"""
struct StockPosition
    symbol::String
    symbol_name::String
    quantity::Float64
    available_quantity::Float64
    currency::String
    cost_price::Float64
    market::String  # 对应Python版本的Market类型
    init_quantity::Union{Float64,Nothing}
end

function Base.show(io::IO, pos::StockPosition)
    print(
        io,
        pos.symbol,
        isempty(pos.symbol_name) ? "" : " ($(pos.symbol_name))",
        ": qty ",
        pos.quantity,
        ", available ",
        pos.available_quantity,
        ", cost ",
        pos.cost_price,
        " ",
        pos.currency,
    )
end

"""
Stock position channel
"""
struct StockPositionChannel
    account_channel::String
    stock_info::Vector{StockPosition}
end

function Base.show(io::IO, channel::StockPositionChannel)
    print(io, channel.account_channel, ": ", _count_label(length(channel.stock_info), "stock"))
end

"""
Stock positions response
"""
struct StockPositionsResponse
    list::Vector{StockPositionChannel}
end

function Base.show(io::IO, resp::StockPositionsResponse)
    total = 0
    for channel in resp.list
        total += length(channel.stock_info)
    end
    print(
        io,
        "Stock Positions: ",
        _count_label(total, "stock"),
        " in ",
        _count_label(length(resp.list), "channel"),
    )
    for channel in resp.list
        println(io)
        print(io, "  - ", channel)
        for pos in channel.stock_info
            println(io)
            print(io, "    ", pos)
        end
    end
end

"""
Today execution response
"""
struct TodayExecutionResponse
    trades::Vector{Execution}
end

"""
History execution response
"""
struct ExecutionResponse
    trades::Vector{Execution}
    has_more::Bool
end

"""Paginated response from `GET /v3/trade/execution/all`."""
struct AllExecutionsResponse
    has_more::Bool
    trades::Vector{Execution}
end

# --- Request Option Structs ---

Base.@kwdef struct SubmitOrderOptions
    symbol::String
    order_type::OrderType.T
    side::OrderSide.T
    submitted_quantity::Int64
    time_in_force::TimeInForceType.T        # 订单有效期类型, Day - 当日有效, GTC - 撤单前有效, GTD - 到期前有效
    expire_date::Union{String,Nothing} = nothing  # 到期日, GTD 订单必填, format: YYYY-MM-DD
    submitted_price::Union{Float64,Nothing} = nothing
    remark::Union{String,Nothing} = nothing     # 备注 (最大 64 字符)
    trigger_price::Union{Float64,Nothing} = nothing     # 触发价格，例如：388.5, LIT / MIT 订单必填
    trigger_price_type::Union{TriggerPriceType.T,Nothing} = nothing
    limit_offset::Union{Float64,Nothing} = nothing      # 指定价差，例如 "1.2" 表示价差1.2USD(如果是美股), TSLPAMT/TSLPPCT 订单必填
    trailing_amount::Union{Float64,Nothing} = nothing   # 跟踪金额, TSLPAMT订单必填
    trailing_percent::Union{Float64,Nothing} = nothing  # 跟踪涨跌幅，单位为百分比，例如 "2.5" 表示 "2.5%", TSLPPCT 订单必填
    outside_rth::Union{OutsideRTH.T,AbstractString,Nothing} = nothing
    limit_depth_level::Union{Int,Nothing} = nothing
    trigger_count::Union{Int,Nothing} = nothing
    monitor_price::Union{Float64,Nothing} = nothing
    client_request_id::Union{String,Nothing} = nothing
end

Base.@kwdef struct ReplaceOrderOptions
    order_id::String
    submitted_quantity::Int
    submitted_price::Union{Float64,Nothing} = nothing
end

Base.@kwdef struct GetHistoryExecutionsOptions
    symbol::Union{String,Nothing} = nothing
    start_at::Union{Date,Nothing} = nothing
    end_at::Union{Date,Nothing} = nothing
end

Base.@kwdef struct GetTodayExecutionsOptions
    symbol::Union{String,Nothing} = nothing
end

Base.@kwdef struct GetAllExecutionsOptions
    symbol::Union{String,Nothing} = nothing
    order_id::Union{String,Nothing} = nothing
    start_at::Union{Date,DateTime,Nothing} = nothing
    end_at::Union{Date,DateTime,Nothing} = nothing
    page::Union{Integer,Nothing} = nothing
end

Base.@kwdef struct GetHistoryOrdersOptions
    symbol::Union{String,Nothing} = nothing
    status::Union{Vector{OrderStatus.T},Nothing} = nothing
    side::Union{OrderSide.T,Nothing} = nothing
    start_at::Union{Date,Nothing} = nothing
    end_at::Union{Date,Nothing} = nothing
end

Base.@kwdef struct GetUSHistoryOrders
    symbol::Union{String,Nothing} = nothing
    side::OrderSide.T = OrderSide.UnknownSide
    start_at::Int64 = 0
    end_at::Int64 = 0
    query_type::Int = 0
    page::Int = 1
    limit::Int = 20
end
const QueryUSOrdersOptions = GetUSHistoryOrders

Base.@kwdef struct GetTodayOrdersOptions
    symbol::Union{String,Nothing} = nothing
    status::Union{Vector{OrderStatus.T},Nothing} = nothing
    side::Union{OrderSide.T,Nothing} = nothing
end

Base.@kwdef struct GetCashFlowOptions
    start_time::Int64
    end_time::Int64
    business_type::Union{Vector{BalanceType.T},Nothing} = nothing
    symbol::Union{String,Nothing} = nothing
    page::Union{Int,Nothing} = nothing
    size::Union{Int,Nothing} = nothing
end

Base.@kwdef struct GetFundPositionsOptions
    symbol::Union{Vector{String},Nothing} = nothing
end

Base.@kwdef struct GetStockPositionsOptions
    symbol::Union{String,Nothing} = nothing
end

Base.@kwdef struct EstimateMaxPurchaseQuantityOptions
    symbol::String
    order_type::OrderType.T
    side::OrderSide.T
    price::Union{Float64,Nothing} = nothing
end

# --- Push Event Types ---
struct PushEvent{T}
    topic::TopicType.T
    data::T
end

end # module
