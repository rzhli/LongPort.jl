module Trade

    using JSON3, Dates, Logging, DataFrames, StructTypes
    import ProtoBuf as PB

    using ..Constant
    using ..Config
    using ..Client
    using ..Errors
    using ..TradePush
    using ..TradeProtocol
    using ..Utils: Arc, to_china_time, safeparse

    import ..disconnect!

    # --- Public API ---
    export TradeContext, subscribe, unsubscribe, history_executions, today_executions,
           history_orders, today_orders, replace_order, submit_order, cancel_order, account_balance,
           cash_flow, fund_positions, stock_positions, margin_ratio, order_detail, estimate_max_purchase_quantity,
           set_on_order_changed
    
    # --- Core Actor Implementation ---

    abstract type AbstractCommand end

    struct HttpGetCmd <: AbstractCommand
        path::String
        params::Dict{String,Any}
        resp_ch::Channel{Any}
    end

    struct HttpPostCmd <: AbstractCommand
        path::String
        body::Any
        resp_ch::Channel{Any}
    end

    struct HttpPutCmd <: AbstractCommand
        path::String
        body::Any
        resp_ch::Channel{Any}
    end

    struct HttpDeleteCmd <: AbstractCommand
        path::String
        params::Dict{String,Any}
        resp_ch::Channel{Any}
    end

    struct SubscribeCmd <: AbstractCommand
        topics::Vector{String}
        resp_ch::Channel{Any}
    end

    struct UnsubscribeCmd <: AbstractCommand
        topics::Vector{String}
        resp_ch::Channel{Any}
    end

    struct DisconnectCmd <: AbstractCommand end

mutable struct InnerTradeContext
    config::Config.config
    ws_client::Union{Client.WSClient,Nothing}
    command_ch::Channel{Any}
    core_task::Union{Task,Nothing}
    callbacks::Callbacks
    subscriptions::Set{String}
end

    struct TradeContext
        inner::Arc{InnerTradeContext}
    end

    function core_run(inner::InnerTradeContext)
        should_run = true
        reconnect_attempts = 0

        while should_run
            try
                ws = Client.WSClient(inner.config.trade_ws_url, inner.config)
                inner.ws_client = ws
                ws.on_push =
                    (cmd, body) -> begin
                        command = Command.T(cmd)
                        if command == Command.CMD_NOTIFY
                            n = PB.decode(IOBuffer(body), Notification)
                            handle_push_event!(inner.callbacks, n)
                        else
                            @warn "Unknown trade push command" cmd = cmd
                        end
                    end
                ws.auth_data = Client.create_auth_request(inner.config)
                Client.connect!(ws)
                reconnect_attempts = 0

                # Resubscribe to all topics after successful reconnection
                if !isempty(inner.subscriptions)
                    @info "Resubscribing to trade topics..."
                    try
                        req = TradeProtocol.Sub(collect(inner.subscriptions))
                        io_buf = IOBuffer()
                        encoder = PB.ProtoEncoder(io_buf)
                        PB.encode(encoder, req)
                        Client.ws_request(inner.ws_client, UInt8(TradeProtocol.Command.CMD_SUB), take!(io_buf))
                    catch e
                        @error "Failed to resubscribe to trade topics" exception=(e, catch_backtrace())
                    end
                end

                while isopen(inner.command_ch)
                    cmd = take!(inner.command_ch)
                    handle_command(inner, cmd)
                    if cmd isa DisconnectCmd
                        should_run = false
                        break
                    end
                end
            catch e
                if e isa InvalidStateException && e.state == :closed
                    should_run = false
                elseif e isa LongportError && e.code == "ws-disconnected"
                    Client.full_reconnect!(inner.ws_client)
                else
                    @error "Trade core actor failed" exception = (e, catch_backtrace())
                    should_run = false
                end
            finally
                if !isnothing(inner.ws_client)
                    Client.disconnect!(inner.ws_client)
                    inner.ws_client = nothing
                end
            end
        end
    end

    function handle_command(inner::InnerTradeContext, cmd::AbstractCommand)
        resp = try
            if cmd isa DisconnectCmd
                nothing
            elseif cmd isa SubscribeCmd
                req = TradeProtocol.Sub(cmd.topics)
                io_buf = IOBuffer()
                encoder = PB.ProtoEncoder(io_buf)
                PB.encode(encoder, req)
                resp_body = Client.ws_request(inner.ws_client, UInt8(TradeProtocol.Command.CMD_SUB), take!(io_buf))
                decoder = PB.ProtoDecoder(IOBuffer(resp_body))
                PB.decode(decoder, SubResponse)
            elseif cmd isa UnsubscribeCmd
                req = TradeProtocol.Unsub(cmd.topics)
                io_buf = IOBuffer()
                encoder = PB.ProtoEncoder(io_buf)
                PB.encode(encoder, req)
                resp_body = Client.ws_request(inner.ws_client, UInt8(TradeProtocol.Command.CMD_UNSUB), take!(io_buf))
                decoder = PB.ProtoDecoder(IOBuffer(resp_body))
                PB.decode(decoder, UnsubResponse)
            elseif cmd isa HttpGetCmd
                ApiResponse(Client.get(inner.config, cmd.path; params = cmd.params))
            elseif cmd isa HttpPostCmd
                ApiResponse(Client.post(inner.config, cmd.path; body = cmd.body))
            elseif cmd isa HttpPutCmd
                ApiResponse(Client.put(inner.config, cmd.path; body = cmd.body))
            elseif cmd isa HttpDeleteCmd
                ApiResponse(Client.delete(inner.config, cmd.path; params = cmd.params))
            end
        catch e
            @error "Failed to handle command" command = typeof(cmd) exception = (e, catch_backtrace())
            e
        end

        if !(cmd isa DisconnectCmd) && isopen(cmd.resp_ch)
            put!(cmd.resp_ch, resp)
        end
    end

    function TradeContext(config::Config.config)
        command_ch = Channel{Any}(32)

        inner = InnerTradeContext(config, nothing, command_ch, nothing, Callbacks(), Set{String}())
        ctx = TradeContext(Arc(inner))

        inner.core_task = @async core_run(inner)

        return ctx
    end


    function request(ctx::TradeContext, cmd::AbstractCommand)
        put!(ctx.inner.command_ch, cmd)
        resp = take!(cmd.resp_ch)
        if resp isa Exception
            throw(resp)
        end
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
                    d[key] = [v isa Enum ? Int(v) : string(v) for v in val]
                elseif val isa Enum
                    d[key] = Int(val)
                else
                    d[key] = val
                end
            end
        end
        d
    end

    function set_on_order_changed(ctx::TradeContext, cb::Function); TradePush.set_on_order_changed!(ctx.inner.callbacks, cb); end

    function subscribe(ctx::TradeContext, topics::Vector{TopicType.T})
        ch = Channel(1)
        str_topics = [string(t) for t in topics]
        cmd = SubscribeCmd(str_topics, ch)
        request(ctx, cmd)
        union!(ctx.inner.subscriptions, str_topics)
    end

    function unsubscribe(ctx::TradeContext, topics::Vector{TopicType.T})
        ch = Channel(1)
        str_topics = [string(t) for t in topics]
        cmd = UnsubscribeCmd(str_topics, ch)
        request(ctx, cmd)
        setdiff!(ctx.inner.subscriptions, str_topics)
    end

    function history_executions(
        ctx::TradeContext;
        symbol::Union{String,Nothing}=nothing,
        start_at::Union{Date,Nothing}=nothing,
        end_at::Union{Date,Nothing}=nothing,
    )
        options = GetHistoryExecutionsOptions(symbol=symbol, start_at=start_at, end_at=end_at)
        cmd = HttpGetCmd("/v1/trade/execution/history", to_dict(options), Channel(1))
        resp = request(ctx, cmd)
        if resp.code == 0
            return JSON3.read(JSON3.write(resp.data), ExecutionResponse)
        else
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
    end

    function today_executions(ctx::TradeContext; symbol::Union{String,Nothing}=nothing)
        options = GetTodayExecutionsOptions(symbol=symbol)
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
        symbol::Union{String,Nothing}=nothing,
        status::Union{Vector{OrderStatus.T},Nothing}=nothing,
        side::Union{OrderSide.T,Nothing}=nothing,
        start_at::Union{Date,Nothing}=nothing,
        end_at::Union{Date,Nothing}=nothing,
    )
        options = GetHistoryOrdersOptions(symbol=symbol, status=status, side=side, start_at=start_at, end_at=end_at)
        cmd = HttpGetCmd("/v1/trade/order/history", to_dict(options), Channel(1))
        resp = request(ctx, cmd)
        if resp.code == 0
            orders_data = map(resp.data.orders) do o
                d = Dict{String, Any}(String(k) => v for (k, v) in o)
                d["quantity"] = safeparse(Int64, d["quantity"])
                d["executed_quantity"] = safeparse(Int64, d["executed_quantity"])
                d["price"] = safeparse(Float64, d["price"])
                d["executed_price"] = safeparse(Float64, d["executed_price"])
                d["submitted_at"] = to_china_time(d["submitted_at"])
                d["updated_at"] = (isempty(d["updated_at"]) || d["updated_at"] == "0") ? nothing : to_china_time(d["updated_at"])
                d["trigger_at"] = (isempty(d["trigger_at"]) || d["trigger_at"] == "0") ? nothing : to_china_time(d["trigger_at"])
                d["expire_date"] = isempty(d["expire_date"]) ? nothing : Date(d["expire_date"])
                d["last_done"] = safeparse(Float64, d["last_done"])
                d["trigger_price"] = safeparse(Float64, d["trigger_price"])
                d["trailing_amount"] = safeparse(Float64, d["trailing_amount"])
                d["trailing_percent"] = safeparse(Float64, d["trailing_percent"])
                d["limit_offset"] = safeparse(Float64, d["limit_offset"])
                return d
            end
            orders = JSON3.read(JSON3.write(orders_data), Vector{Order})
            return DataFrame(
                "Order ID" => [o.order_id for o in orders],
                "Symbol" => [o.symbol for o in orders],
                "Side" => [o.side for o in orders],
                "Status" => [o.status for o in orders],
                "Type" => [o.order_type for o in orders],
                "Quantity" => [o.quantity for o in orders],
                "Price" => [o.price for o in orders],
                "Submitted At" => [o.submitted_at for o in orders],
            )
        else
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
    end

    function today_orders(
        ctx::TradeContext;
        symbol::Union{String,Nothing}=nothing,
        status::Union{Vector{OrderStatus.T},Nothing}=nothing,
        side::Union{OrderSide.T,Nothing}=nothing,
    )
        options = GetTodayOrdersOptions(symbol=symbol, status=status, side=side)
        cmd = HttpGetCmd("/v1/trade/order/today", to_dict(options), Channel(1))
        resp = request(ctx, cmd)
        if resp.code == 0
            orders_data = map(resp.data.orders) do o
                d = Dict{String, Any}(String(k) => v for (k, v) in o)
                d["quantity"] = safeparse(Int64, d["quantity"])
                d["executed_quantity"] = safeparse(Int64, d["executed_quantity"])
                d["price"] = safeparse(Float64, d["price"])
                d["executed_price"] = safeparse(Float64, d["executed_price"])
                d["submitted_at"] = to_china_time(d["submitted_at"])
                d["updated_at"] = (isempty(d["updated_at"]) || d["updated_at"] == "0") ? nothing : to_china_time(d["updated_at"])
                d["trigger_at"] = (isempty(d["trigger_at"]) || d["trigger_at"] == "0") ? nothing : to_china_time(d["trigger_at"])
                d["expire_date"] = isempty(d["expire_date"]) ? nothing : Date(d["expire_date"])
                d["last_done"] = safeparse(Float64, d["last_done"])
                d["trigger_price"] = safeparse(Float64, d["trigger_price"])
                d["trailing_amount"] = safeparse(Float64, d["trailing_amount"])
                d["trailing_percent"] = safeparse(Float64, d["trailing_percent"])
                d["limit_offset"] = safeparse(Float64, d["limit_offset"])
                return d
            end
            orders = JSON3.read(JSON3.write(orders_data), Vector{Order})
            return DataFrame(
                "Order ID" => [o.order_id for o in orders],
                "Symbol" => [o.symbol for o in orders],
                "Side" => [o.side for o in orders],
                "Status" => [o.status for o in orders],
                "Order Type" => [o.order_type for o in orders],
                "Quantity" => [o.quantity for o in orders],
                "Price" => [o.price for o in orders],
                "Submitted At" => [o.submitted_at for o in orders],
            )
        else
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
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

    function cancel_order(ctx::TradeContext, order_id::String)
        params = Dict{String,Any}("order_id" => string(order_id))
        cmd = HttpDeleteCmd("/v1/trade/order", params, Channel(1))
        resp = request(ctx, cmd)
        if resp.code != 0
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
        return nothing
    end

    function account_balance(ctx::TradeContext; currency::Union{Currency.T, Nothing} = nothing)
        params = isnothing(currency) ? Dict{String,Any}() : Dict{String,Any}("currency" => String(Symbol(currency)))
        cmd = HttpGetCmd("/v1/asset/account", params, Channel(1))
        resp = request(ctx, cmd)
        if resp.code == 0
            return [StructTypes.construct(AccountBalance, item) for item in resp.data["list"]]
        else
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
    end

    function cash_flow(ctx::TradeContext; start_at::Date, end_at::Date, business_type::Union{Vector{BalanceType.T},Nothing} = nothing,
        symbol::Union{String,Nothing} = nothing, page::Union{Int,Nothing} = nothing, size::Union{Int,Nothing} = nothing)
        
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
            return JSON3.read(JSON3.write(resp.data.list), Vector{CashFlow})
        else
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
    end

    function fund_positions(ctx::TradeContext; symbol::Union{Vector{String},Nothing}=nothing)
        options = GetFundPositionsOptions(symbol=symbol)
        cmd = HttpGetCmd("/v1/asset/fund", to_dict(options), Channel(1))
        resp = request(ctx, cmd)
        if resp.code == 0
            return JSON3.read(JSON3.write(resp.data), FundPositionsResponse)
        else
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
    end

    function stock_positions(ctx::TradeContext; symbol::Union{String,Nothing}=nothing)
        options = GetStockPositionsOptions(symbol=symbol)
        cmd = HttpGetCmd("/v1/asset/stock", to_dict(options), Channel(1))
        resp = request(ctx, cmd)
        if resp.code == 0
            return JSON3.read(JSON3.write(resp.data), StockPositionsResponse)
        else
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
    end

    function margin_ratio(ctx::TradeContext, symbol::String)
        params = Dict{String,Any}("symbol" => string(symbol))
        cmd = HttpGetCmd("/v1/risk/margin-ratio", params, Channel(1))
        resp = request(ctx, cmd)
        if resp.code == 0
            return StructTypes.construct(MarginRatio, resp.data)
        else
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
    end

function order_detail(ctx::TradeContext, order_id::String)
    params = Dict{String,Any}("order_id" => string(order_id))
    cmd = HttpGetCmd("/v1/trade/order", params, Channel(1))
    resp = request(ctx, cmd)
    if resp.code == 0
        d = Dict{String, Any}(String(k) => v for (k, v) in resp.data)
        d["quantity"] = safeparse(Int64, d["quantity"])
        d["executed_quantity"] = safeparse(Int64, d["executed_quantity"])
        d["price"] = safeparse(Float64, d["price"])
        d["executed_price"] = safeparse(Float64, d["executed_price"])
        d["submitted_at"] = to_china_time(d["submitted_at"])
        d["updated_at"] = (isempty(d["updated_at"]) || d["updated_at"] == "0") ? nothing : to_china_time(d["updated_at"])
        d["trigger_at"] = (isempty(d["trigger_at"]) || d["trigger_at"] == "0") ? nothing : to_china_time(d["trigger_at"])
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
            d["platform_deducted_amount"] = safeparse(Float64, d["platform_deducted_amount"])
        end

        if haskey(d, "history") && !isnothing(d["history"])
            d["history"] = map(d["history"]) do h
                h_dict = Dict{String, Any}(String(k) => v for (k, v) in h)
                h_dict["price"] = safeparse(Float64, h_dict["price"])
                h_dict["quantity"] = safeparse(Int64, h_dict["quantity"])
                h_dict["time"] = to_china_time(h_dict["time"])
                return h_dict
            end
        end

        if haskey(d, "charge_detail") && !isnothing(d["charge_detail"])
            cd_dict = Dict{String, Any}(String(k) => v for (k, v) in d["charge_detail"])
            if haskey(cd_dict, "total_charges") && !isnothing(cd_dict["total_charges"])
                cd_dict["total_charges"] = safeparse(Float64, cd_dict["total_charges"])
            end
            if haskey(cd_dict, "items") && !isnothing(cd_dict["items"])
                cd_dict["items"] = map(cd_dict["items"]) do item
                    item_dict = Dict{String, Any}(String(k) => v for (k, v) in item)
                    if haskey(item_dict, "fees") && !isnothing(item_dict["fees"])
                        item_dict["fees"] = map(item_dict["fees"]) do fee
                            fee_dict = Dict{String, Any}(String(k) => v for (k, v) in fee)
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

    function estimate_max_purchase_quantity(ctx::TradeContext, options::EstimateMaxPurchaseQuantityOptions)
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

    function disconnect!(ctx::TradeContext)
        inner = ctx.inner
        if !isnothing(inner.core_task) && !istaskdone(inner.core_task)
            put!(inner.command_ch, DisconnectCmd())
            close(inner.command_ch)
            wait(inner.core_task)
        end
    end
end # module Trade
