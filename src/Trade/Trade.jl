module Trade

using JSON3, Dates, DataFrames, StructTypes
import ProtoBuf as PB
using Base.Threads: Atomic, atomic_xchg!

using ..Constant
using ..Config
using ..Client
using ..Errors
using ..TradePush
using ..TradeProtocol
using ..USProtocol
using ..Utils: to_china_time, safeparse, symbol_to_counter_id
using ..Commands:
    AbstractCommand, HttpGetCmd, HttpPostCmd, HttpPutCmd, HttpDeleteCmd, DisconnectCmd

import ..disconnect!

# --- Public API ---
export TradeContext,
    subscribe,
    unsubscribe,
    history_executions,
    today_executions,
    history_orders,
    today_orders,
    replace_order,
    submit_order,
    cancel_order,
    account_balance,
    cash_flow,
    fund_positions,
    stock_positions,
    margin_ratio,
    order_detail,
    estimate_max_purchase_quantity,
    us_query_orders,
    us_order_detail,
    us_asset_overview,
    us_realized_pl,
    set_on_order_changed

# Trade-specific commands for WebSocket subscription
struct SubscribeCmd <: AbstractCommand
    topics::Vector{String}
    resp_ch::Channel{Any}
end

struct UnsubscribeCmd <: AbstractCommand
    topics::Vector{String}
    resp_ch::Channel{Any}
end

mutable struct InnerTradeContext
    config::Config.Settings
    ws_client::Union{Client.WSClient,Nothing}
    command_ch::Channel{AbstractCommand}
    shutdown::Atomic{Bool}
    background_task::Union{Task,Nothing}
    callbacks::Callbacks
    subscriptions::Set{String}
end

mutable struct TradeContext
    inner::InnerTradeContext
end

const REQUEST_WAIT_TIMEOUT = Client.REQUEST_TIMEOUT + 5.0
const SHUTDOWN_WAIT_TIMEOUT = 5.0
const MAX_RECONNECT_BACKOFF = 30.0

@inline _is_shutdown(inner::InnerTradeContext) = inner.shutdown[]

function _sleep_or_shutdown(inner::InnerTradeContext, seconds::Real)
    deadline = time() + max(Float64(seconds), 0.0)
    while !_is_shutdown(inner)
        remaining = deadline - time()
        remaining <= 0 && return true
        sleep(min(remaining, 0.05))
    end
    return false
end

function _request_shutdown!(inner::InnerTradeContext)
    atomic_xchg!(inner.shutdown, true)
    isopen(inner.command_ch) && close(inner.command_ch)
    if !isnothing(inner.ws_client)
        Client.shutdown!(inner.ws_client)
    end
    return
end

function _wait_for_task(task::Union{Task,Nothing}, name::AbstractString)
    (isnothing(task) || istaskdone(task)) && return
    status = timedwait(() -> istaskdone(task), SHUTDOWN_WAIT_TIMEOUT; pollint = 0.01)
    status === :timed_out && @warn "$name did not stop within $SHUTDOWN_WAIT_TIMEOUT seconds"
    return
end

function _finalize_trade_context!(ctx::TradeContext)
    try
        _request_shutdown!(ctx.inner)
    catch
        # Finalizers must never surface exceptions during GC or process exit.
    end
    return
end

function _is_reconnectable_ws_error(e)
    msg = sprint(showerror, e)
    return (e isa LongBridgeError && (occursin("WebSocket", e.message) || e.code == 408)) ||
           (e isa ArgumentError && occursin("WebSocket", msg)) ||
           e isa EOFError
end

function _submit_command!(ctx::TradeContext, cmd::AbstractCommand)
    inner = ctx.inner
    task = inner.background_task
    if _is_shutdown(inner) || isnothing(task) || istaskdone(task) || !isopen(inner.command_ch)
        throw(LongBridgeError(500, "Trade background task is not running"))
    end

    try
        put!(inner.command_ch, cmd)
    catch e
        if e isa InvalidStateException
            throw(LongBridgeError(500, "Trade command channel is closed"))
        end
        rethrow(e)
    end
end

function _take_task_response!(ch::Channel, context_name::AbstractString)
    timer = Timer(REQUEST_WAIT_TIMEOUT) do _
        isopen(ch) && close(ch)
    end

    try
        return take!(ch)
    catch e
        if e isa InvalidStateException
            throw(
                LongBridgeError(
                    408,
                    "$context_name request timed out waiting for background task",
                ),
            )
        end
        rethrow(e)
    finally
        close(timer)
    end
end

function _resubscribe_trade!(inner::InnerTradeContext)
    (_is_shutdown(inner) || isempty(inner.subscriptions)) && return

    @info "Resubscribing to trade topics..."
    try
        req = TradeProtocol.Sub(collect(inner.subscriptions))
        io_buf = IOBuffer()
        encoder = PB.ProtoEncoder(io_buf)
        PB.encode(encoder, req)
        Client.ws_request(
            inner.ws_client,
            UInt8(TradeProtocol.Command.CMD_SUB),
            take!(io_buf),
        )
    catch e
        _is_shutdown(inner) ||
            @error "Failed to resubscribe to trade topics" exception=(e, catch_backtrace())
    end
end

function run_trade_loop(inner::InnerTradeContext)
    should_run = true
    reconnect_attempts = 0

    while should_run && !_is_shutdown(inner)
        try
            ws = Client.WSClient(inner.config.trade_ws_url, inner.config, inner.shutdown)
            inner.ws_client = ws
            ws.on_push =
                (cmd, body) -> begin
                    command = Command.T(cmd)
                    if command == Command.CMD_NOTIFY
                        n = PB.decode(PB.ProtoDecoder(IOBuffer(body)), Notification)
                        handle_push_event!(inner.callbacks, n)
                    else
                        @warn "Unknown trade push command" cmd = cmd
                    end
                end
            ws.on_reconnect = () -> _resubscribe_trade!(inner)
            ws.auth_data = Client.create_auth_request(inner.config)
            connected = Client.connect!(ws)
            (_is_shutdown(inner) || !connected) && break
            reconnect_attempts = 0

            # Resubscribe to all topics after successful reconnection
            _resubscribe_trade!(inner)

            while !_is_shutdown(inner)
                cmd = take!(inner.command_ch)
                _is_shutdown(inner) && break
                reconnect_needed = handle_command(inner, cmd)
                if cmd isa DisconnectCmd
                    should_run = false
                    break
                elseif reconnect_needed
                    @warn "Trade WebSocket command failed; reconnecting before processing more commands"
                    if !isnothing(inner.ws_client)
                        Client.disconnect!(inner.ws_client)
                        inner.ws_client = nothing
                    end
                    break
                end
            end
        catch e
            if _is_shutdown(inner) || e isa InterruptException
                should_run = false
            elseif e isa InvalidStateException && e.state == :closed
                should_run = false
            elseif _is_reconnectable_ws_error(e)
                reconnect_attempts += 1
                backoff = min(2.0^min(reconnect_attempts, 5), MAX_RECONNECT_BACKOFF)
                if !isnothing(inner.ws_client)
                    Client.disconnect!(inner.ws_client)
                    inner.ws_client = nothing
                end
                @warn "Trade connection failed; retrying in $backoff seconds" exception=(
                    e,
                    catch_backtrace(),
                )
                _sleep_or_shutdown(inner, backoff) || (should_run = false)
            else
                @error "Trade background task failed" exception = (e, catch_backtrace())
                should_run = false
            end
        finally
            if !isnothing(inner.ws_client)
                if _is_shutdown(inner)
                    Client.shutdown!(inner.ws_client)
                else
                    Client.disconnect!(inner.ws_client)
                end
                inner.ws_client = nothing
            end
        end
    end
    isopen(inner.command_ch) && close(inner.command_ch)
end

function handle_command(inner::InnerTradeContext, cmd::AbstractCommand)
    reconnect_needed = false
    resp = try
        if cmd isa DisconnectCmd
            nothing
        elseif cmd isa SubscribeCmd
            req = TradeProtocol.Sub(cmd.topics)
            io_buf = IOBuffer()
            encoder = PB.ProtoEncoder(io_buf)
            PB.encode(encoder, req)
            resp_body = Client.ws_request(
                inner.ws_client,
                UInt8(TradeProtocol.Command.CMD_SUB),
                take!(io_buf),
            )
            decoder = PB.ProtoDecoder(IOBuffer(resp_body))
            PB.decode(decoder, SubResponse)
        elseif cmd isa UnsubscribeCmd
            req = TradeProtocol.Unsub(cmd.topics)
            io_buf = IOBuffer()
            encoder = PB.ProtoEncoder(io_buf)
            PB.encode(encoder, req)
            resp_body = Client.ws_request(
                inner.ws_client,
                UInt8(TradeProtocol.Command.CMD_UNSUB),
                take!(io_buf),
            )
            decoder = PB.ProtoDecoder(IOBuffer(resp_body))
            PB.decode(decoder, UnsubResponse)
        elseif cmd isa HttpGetCmd
            ApiResponse(Client.http_get(inner.config, cmd.path; params = cmd.params))
        elseif cmd isa HttpPostCmd
            ApiResponse(Client.http_post(inner.config, cmd.path; body = cmd.body))
        elseif cmd isa HttpPutCmd
            ApiResponse(Client.http_put(inner.config, cmd.path; body = cmd.body))
        elseif cmd isa HttpDeleteCmd
            ApiResponse(Client.http_delete(inner.config, cmd.path; params = cmd.params))
        end
    catch e
        reconnect_needed =
            (cmd isa SubscribeCmd || cmd isa UnsubscribeCmd) &&
            _is_reconnectable_ws_error(e)
        @error "Failed to handle command" command = typeof(cmd) exception =
            (e, catch_backtrace())
        e
    end

    if !(cmd isa DisconnectCmd) && isopen(cmd.resp_ch)
        put!(cmd.resp_ch, resp)
    end
    return reconnect_needed
end

function _build_trade_context(config::Config.Settings; start_tasks::Bool = true)
    command_ch = Channel{AbstractCommand}(32)
    shutdown = Atomic{Bool}(false)

    inner = InnerTradeContext(
        config,
        nothing,
        command_ch,
        shutdown,
        nothing,
        Callbacks(),
        Set{String}(),
    )
    ctx = TradeContext(inner)
    finalizer(_finalize_trade_context!, ctx)

    if start_tasks
        inner.background_task = errormonitor(@async run_trade_loop(inner))
    end

    return ctx
end

TradeContext(config::Config.Settings) = _build_trade_context(config)


# Type-stable specializations: each command produces a known concrete
# response type, so we assert it after `take!` and let the compiler
# propagate the type to call-site field accesses.
function request(ctx::TradeContext, cmd::SubscribeCmd)
    _submit_command!(ctx, cmd)
    resp = _take_task_response!(cmd.resp_ch, "Trade")
    resp isa Exception && throw(resp)
    return resp::SubResponse
end

function request(ctx::TradeContext, cmd::UnsubscribeCmd)
    _submit_command!(ctx, cmd)
    resp = _take_task_response!(cmd.resp_ch, "Trade")
    resp isa Exception && throw(resp)
    return resp::UnsubResponse
end

function request(
    ctx::TradeContext,
    cmd::Union{HttpGetCmd,HttpPostCmd,HttpPutCmd,HttpDeleteCmd},
)
    _submit_command!(ctx, cmd)
    resp = _take_task_response!(cmd.resp_ch, "Trade")
    resp isa Exception && throw(resp)
    return resp::ApiResponse
end

# Defensive fallback (shouldn't be hit in practice; kept for safety).
function request(ctx::TradeContext, cmd::AbstractCommand)
    _submit_command!(ctx, cmd)
    resp = _take_task_response!(cmd.resp_ch, "Trade")
    resp isa Exception && throw(resp)
    return resp
end

function to_dict(opts)
    d = Dict{String,Any}()
    for name in fieldnames(typeof(opts))
        val = getfield(opts, name)
        if !isnothing(val)
            key = string(name)
            if val isa Date || val isa DateTime
                d[key] = string(round(Int, datetime2unix(DateTime(val))))
            elseif val isa Vector && !isempty(val)
                # Coerce to homogeneous Vector{String} to avoid Union widening
                # from the previous broad comprehension.
                d[key] = String[v isa Enum ? string(Int(v)) : string(v) for v in val]
            elseif val isa OutsideRTH.T
                d[key] = _outside_rth_str(val)
            elseif val isa Enum
                d[key] = Int(val)
            else
                d[key] = val
            end
        end
    end
    d
end

_outside_rth_str(value::OutsideRTH.T) =
    value === OutsideRTH.RTH_ONLY ? "RTH_ONLY" :
    value === OutsideRTH.ANY_TIME ? "ANY_TIME" :
    value === OutsideRTH.OVERNIGHT ? "OVERNIGHT" :
    value === OutsideRTH.OptionPreMarket ? "OPTION_PRE_MARKET" : "UNKNOWN"

# Helper: parse optional timestamp
_parse_optional_time(v) = (isempty(v) || v == "0") ? nothing : to_china_time(v)

# Helper: parse order data from API response
function _parse_order_data(o)
    d = Dict{String,Any}(String(k) => v for (k, v) in o)
    d["quantity"] = safeparse(Int64, d["quantity"])
    d["executed_quantity"] = safeparse(Int64, d["executed_quantity"])
    d["price"] = safeparse(Float64, d["price"])
    d["executed_price"] = safeparse(Float64, d["executed_price"])
    d["submitted_at"] = to_china_time(d["submitted_at"])
    d["updated_at"] = _parse_optional_time(d["updated_at"])
    d["trigger_at"] = _parse_optional_time(d["trigger_at"])
    d["expire_date"] = isempty(d["expire_date"]) ? nothing : Date(d["expire_date"])
    d["last_done"] = safeparse(Float64, d["last_done"])
    d["trigger_price"] = safeparse(Float64, d["trigger_price"])
    d["trailing_amount"] = safeparse(Float64, d["trailing_amount"])
    d["trailing_percent"] = safeparse(Float64, d["trailing_percent"])
    d["limit_offset"] = safeparse(Float64, d["limit_offset"])
    return d
end

# Helper: convert orders to DataFrame
function _orders_to_dataframe(orders::AbstractVector{Order})
    DataFrame(
        "Order ID" => [o.order_id for o in orders],
        "Symbol" => [o.symbol for o in orders],
        "Side" => [o.side for o in orders],
        "Status" => [o.status for o in orders],
        "Order Type" => [o.order_type for o in orders],
        "Quantity" => [o.quantity for o in orders],
        "Price" => [o.price for o in orders],
        "Submitted At" => [o.submitted_at for o in orders],
    )
end

set_on_order_changed(ctx::TradeContext, cb) =
    TradePush.set_on_order_changed!(ctx.inner.callbacks, cb)

function subscribe(ctx::TradeContext, topics::AbstractVector{TopicType.T})
    ch = Channel(1)
    str_topics = [string(t) for t in topics]
    cmd = SubscribeCmd(str_topics, ch)
    request(ctx, cmd)
    union!(ctx.inner.subscriptions, str_topics)
end

function unsubscribe(ctx::TradeContext, topics::AbstractVector{TopicType.T})
    ch = Channel(1)
    str_topics = [string(t) for t in topics]
    cmd = UnsubscribeCmd(str_topics, ch)
    request(ctx, cmd)
    setdiff!(ctx.inner.subscriptions, str_topics)
end

function history_executions(
    ctx::TradeContext;
    symbol::Union{String,Nothing} = nothing,
    start_at::Union{Date,Nothing} = nothing,
    end_at::Union{Date,Nothing} = nothing,
)
    options =
        GetHistoryExecutionsOptions(symbol = symbol, start_at = start_at, end_at = end_at)
    cmd = HttpGetCmd("/v1/trade/execution/history", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        return JSON3.read(JSON3.write(resp.data), ExecutionResponse)
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function today_executions(ctx::TradeContext; symbol::Union{String,Nothing} = nothing)
    options = GetTodayExecutionsOptions(symbol = symbol)
    cmd = HttpGetCmd("/v1/trade/execution/today", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        return JSON3.read(JSON3.write(resp.data), TodayExecutionResponse)
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function history_orders(
    ctx::TradeContext;
    symbol::Union{String,Nothing} = nothing,
    status::Union{Vector{OrderStatus.T},Nothing} = nothing,
    side::Union{OrderSide.T,Nothing} = nothing,
    start_at::Union{Date,Nothing} = nothing,
    end_at::Union{Date,Nothing} = nothing,
)
    options = GetHistoryOrdersOptions(
        symbol = symbol,
        status = status,
        side = side,
        start_at = start_at,
        end_at = end_at,
    )
    cmd = HttpGetCmd("/v1/trade/order/history", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    orders =
        JSON3.read(JSON3.write(map(_parse_order_data, resp.data.orders)), Vector{Order})
    _orders_to_dataframe(orders)
end

function today_orders(
    ctx::TradeContext;
    symbol::Union{String,Nothing} = nothing,
    status::Union{Vector{OrderStatus.T},Nothing} = nothing,
    side::Union{OrderSide.T,Nothing} = nothing,
)
    options = GetTodayOrdersOptions(symbol = symbol, status = status, side = side)
    cmd = HttpGetCmd("/v1/trade/order/today", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    orders =
        JSON3.read(JSON3.write(map(_parse_order_data, resp.data.orders)), Vector{Order})
    _orders_to_dataframe(orders)
end

function replace_order(ctx::TradeContext, options::ReplaceOrderOptions)
    cmd = HttpPutCmd("/v1/trade/order", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    if resp.code != 0
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
    return nothing
end

function submit_order(ctx::TradeContext, options::SubmitOrderOptions)
    cmd = HttpPostCmd("/v1/trade/order", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        return JSON3.read(JSON3.write(resp.data), SubmitOrderResponse)
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function cancel_order(ctx::TradeContext, order_id::AbstractString)
    params = Dict{String,Any}("order_id" => String(order_id))
    cmd = HttpDeleteCmd("/v1/trade/order", params, Channel(1))
    resp = request(ctx, cmd)
    if resp.code != 0
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
    return nothing
end

function account_balance(ctx::TradeContext; currency::Union{Currency.T,Nothing} = nothing)
    params =
        isnothing(currency) ? Dict{String,Any}() :
        Dict{String,Any}("currency" => String(Symbol(currency)))
    cmd = HttpGetCmd("/v1/asset/account", params, Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        return [StructTypes.construct(AccountBalance, item) for item in resp.data["list"]]
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function cash_flow(
    ctx::TradeContext;
    start_at::Date,
    end_at::Date,
    business_type::Union{Vector{BalanceType.T},Nothing} = nothing,
    symbol::Union{String,Nothing} = nothing,
    page::Union{Int,Nothing} = nothing,
    size::Union{Int,Nothing} = nothing,
)

    options = GetCashFlowOptions(
        start_time = Int(datetime2unix(DateTime(start_at))),
        end_time = Int(datetime2unix(DateTime(end_at))),
        business_type = business_type,
        symbol = symbol,
        page = page,
        size = size,
    )
    cmd = HttpGetCmd("/v1/asset/cashflow", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        return [StructTypes.construct(CashFlow, item) for item in resp.data.list]
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function fund_positions(ctx::TradeContext; symbol::Union{Vector{String},Nothing} = nothing)
    options = GetFundPositionsOptions(symbol = symbol)
    cmd = HttpGetCmd("/v1/asset/fund", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        return JSON3.read(JSON3.write(resp.data), FundPositionsResponse)
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function stock_positions(ctx::TradeContext; symbol::Union{String,Nothing} = nothing)
    options = GetStockPositionsOptions(symbol = symbol)
    cmd = HttpGetCmd("/v1/asset/stock", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        return JSON3.read(JSON3.write(resp.data), StockPositionsResponse)
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function margin_ratio(ctx::TradeContext, symbol::AbstractString)
    params = Dict{String,Any}("symbol" => String(symbol))
    cmd = HttpGetCmd("/v1/risk/margin-ratio", params, Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        return StructTypes.construct(MarginRatio, resp.data)
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function order_detail(ctx::TradeContext, order_id::AbstractString)
    params = Dict{String,Any}("order_id" => String(order_id))
    cmd = HttpGetCmd("/v1/trade/order", params, Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        d = Dict{String,Any}(String(k) => v for (k, v) in resp.data)
        d["quantity"] = safeparse(Int64, d["quantity"])
        d["executed_quantity"] = safeparse(Int64, d["executed_quantity"])
        d["price"] = safeparse(Float64, d["price"])
        d["executed_price"] = safeparse(Float64, d["executed_price"])
        d["submitted_at"] = to_china_time(d["submitted_at"])
        d["updated_at"] =
            (isempty(d["updated_at"]) || d["updated_at"] == "0") ? nothing :
            to_china_time(d["updated_at"])
        d["trigger_at"] =
            (isempty(d["trigger_at"]) || d["trigger_at"] == "0") ? nothing :
            to_china_time(d["trigger_at"])
        d["expire_date"] = isempty(d["expire_date"]) ? nothing : Date(d["expire_date"])
        d["last_done"] = safeparse(Float64, d["last_done"])
        d["trigger_price"] = safeparse(Float64, d["trigger_price"])
        d["trailing_amount"] = safeparse(Float64, d["trailing_amount"])
        d["trailing_percent"] = safeparse(Float64, d["trailing_percent"])
        d["limit_offset"] = safeparse(Float64, d["limit_offset"])

        if haskey(d, "free_amount")
            d["free_amount"] = safeparse(Float64, d["free_amount"])
        end
        if haskey(d, "deductions_amount")
            d["deductions_amount"] = safeparse(Float64, d["deductions_amount"])
        end
        if haskey(d, "platform_deducted_amount")
            d["platform_deducted_amount"] =
                safeparse(Float64, d["platform_deducted_amount"])
        end

        if haskey(d, "history") && !isnothing(d["history"])
            d["history"] = map(d["history"]) do h
                h_dict = Dict{String,Any}(String(k) => v for (k, v) in h)
                h_dict["price"] = safeparse(Float64, h_dict["price"])
                h_dict["quantity"] = safeparse(Int64, h_dict["quantity"])
                h_dict["time"] = to_china_time(h_dict["time"])
                return h_dict
            end
        end

        if haskey(d, "charge_detail") && !isnothing(d["charge_detail"])
            cd_dict = Dict{String,Any}(String(k) => v for (k, v) in d["charge_detail"])
            if haskey(cd_dict, "total_charges") && !isnothing(cd_dict["total_charges"])
                cd_dict["total_charges"] = safeparse(Float64, cd_dict["total_charges"])
            end
            if haskey(cd_dict, "items") && !isnothing(cd_dict["items"])
                cd_dict["items"] = map(cd_dict["items"]) do item
                    item_dict = Dict{String,Any}(String(k) => v for (k, v) in item)
                    if haskey(item_dict, "fees") && !isnothing(item_dict["fees"])
                        item_dict["fees"] = map(item_dict["fees"]) do fee
                            fee_dict = Dict{String,Any}(String(k) => v for (k, v) in fee)
                            if haskey(fee_dict, "fee") && !isnothing(fee_dict["fee"])
                                fee_dict["fee"] = safeparse(Float64, fee_dict["fee"])
                            end
                            return fee_dict
                        end
                    end
                    return item_dict
                end
            end
            d["charge_detail"] = cd_dict
        end

        return JSON3.read(JSON3.write(d), OrderDetail)
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function estimate_max_purchase_quantity(
    ctx::TradeContext,
    options::EstimateMaxPurchaseQuantityOptions,
)
    cmd = HttpGetCmd("/v1/trade/estimate/buy_limit", to_dict(options), Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        data = resp.data
        cash_max_qty = safeparse(Int64, data["cash_max_qty"])
        margin_max_qty = safeparse(Int64, data["margin_max_qty"])
        return EstimateMaxPurchaseQuantityResponse(cash_max_qty, margin_max_qty)
    else
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    end
end

function _check_us_response(resp)
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    return resp.data
end

"""Query the paginated US-region order list."""
function _us_query_orders_body(options::GetUSHistoryOrders, now_ts::Int64)
    action =
        options.side === OrderSide.Buy ? 1 : options.side === OrderSide.Sell ? 2 : 0
    counter_ids =
        isnothing(options.symbol) || isempty(options.symbol) ? String[] :
        [symbol_to_counter_id(options.symbol)]
    start_at = options.start_at == 0 ? now_ts - 90 * 24 * 3600 : options.start_at
    end_at = options.end_at == 0 ? now_ts : options.end_at
    return Dict{String,Any}(
        "account_channel" => "",
        "action" => action,
        "start_at" => Float64(start_at),
        "end_at" => Float64(end_at),
        "counter_ids" => counter_ids,
        "security_types" => String[],
        "query_type" => options.query_type,
        "page" => options.page <= 0 ? 1 : options.page,
        "limit" => options.limit <= 0 ? 20 : options.limit,
        "query_version" => Float64(now_ts),
    )
end

function us_query_orders(ctx::TradeContext, options::GetUSHistoryOrders = GetUSHistoryOrders())
    body = _us_query_orders_body(options, floor(Int64, time()))
    resp = ApiResponse(
        Client.http_post(
            ctx.inner.config,
            "/v1/us/orders/query";
            body,
            dc_region = :us,
        ),
    )
    return USProtocol.construct_us(QueryUSOrdersResponse, _check_us_response(resp))
end

"""Get full detail for one US-region order."""
function us_order_detail(ctx::TradeContext, order_id::AbstractString)
    resp = ApiResponse(
        Client.http_get(
            ctx.inner.config,
            "/v1/us/orders/$(String(order_id))";
            dc_region = :us,
        ),
    )
    result = USProtocol.construct_us(USOrderDetailResponse, _check_us_response(resp))
    return USProtocol.normalize_symbols!(result)
end

"""Get the US account asset snapshot."""
function us_asset_overview(ctx::TradeContext)
    resp = ApiResponse(
        Client.http_get(ctx.inner.config, "/v1/us/assets/overview"; dc_region = :us),
    )
    result = USProtocol.construct_us(USAssetOverview, _check_us_response(resp))
    return USProtocol.normalize_symbols!(result)
end

"""Get realized profit and loss for a US-region account."""
function us_realized_pl(
    ctx::TradeContext;
    currency::AbstractString = "USD",
    category::Union{AbstractString,Nothing} = nothing,
)
    params = Dict{String,Any}("currency" => String(currency))
    isnothing(category) || isempty(category) || (params["category"] = String(category))
    resp = ApiResponse(
        Client.http_get(
            ctx.inner.config,
            "/v1/us/assets/pl/realized";
            params,
            dc_region = :us,
        ),
    )
    return USProtocol.construct_us(USRealizedPL, _check_us_response(resp))
end

us_realized_pl(
    ctx::TradeContext,
    currency::AbstractString;
    category::Union{AbstractString,Nothing} = nothing,
) = us_realized_pl(ctx; currency, category)

function disconnect!(ctx::TradeContext)
    inner = ctx.inner
    _request_shutdown!(inner)
    _wait_for_task(inner.background_task, "Trade background task")
    return
end

Base.close(ctx::TradeContext) = disconnect!(ctx)
end # module Trade
