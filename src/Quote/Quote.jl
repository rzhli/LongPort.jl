module Quote

using ProtoBuf, JSON3, Dates, Logging, DataFrames, HTTP
using ..Config, ..QuotePush, ..Client, ..QuoteProtocol, ..ControlProtocol, ..Constant

using ..QuoteProtocol: CandlePeriod, AdjustType, TradeSession, SubType, QuoteCommand, Direction,
        SecurityCandlestickRequest, SecurityCandlestickResponse, QuoteSubscribeRequest,
        QuoteSubscribeResponse, QuoteUnsubscribeRequest, QuoteUnsubscribeResponse,
        SubscriptionRequest, SubscriptionResponse,
        MultiSecurityRequest, SecurityQuoteResponse, SecurityRequest, SecurityDepthResponse,
        SecurityStaticInfo, SecurityStaticInfoResponse, OptionQuoteResponse, 
        WarrantQuoteResponse, SecurityBrokersResponse, ParticipantBrokerIdsResponse,
        SecurityTradeRequest, SecurityTradeResponse, SecurityIntradayRequest, SecurityIntradayResponse,
        SecurityHistoryCandlestickRequest, OffsetQuery, DateQuery, HistoryCandlestickQueryType,
        OptionChainDateListResponse, OptionChainDateStrikeInfoRequest, OptionChainDateStrikeInfoResponse,
        IssuerInfoResponse, WarrantFilterListRequest, FilterConfig, WarrantFilterListResponse,
        FilterWarrantExpiryDate, FilterWarrantInOutBoundsType, WarrantStatus, WarrantType, 
        SortOrderType, WarrantSortBy, MarketTradePeriodResponse, MarketTradeDayRequest, MarketTradeDayResponse,
        CapitalFlowIntradayRequest, CapitalFlowIntradayResponse, CapitalDistributionResponse, MarketTemperatureResponse,
        SecurityListCategory, SecuritiesUpdateMode
        
using ..Client: WSClient
using ..Cache: SimpleCache, CacheWithKey, get_or_update
using ..Utils: to_namedtuple, to_china_time, Arc

using ..Errors

export QuoteContext, 
       disconnect!, realtime_quote, subscribe, unsubscribe, static_info, depth, intraday,
       brokers, trades, candlesticks,
       history_candlesticks_by_offset, history_candlesticks_by_date, 
       option_chain_expiry_date_list, option_chain_info_by_date,
       set_on_quote, set_on_depth, set_on_brokers, set_on_trades, set_on_candlestick,
       
       option_quote, warrant_quote, participants, subscriptions,
       option_chain_dates, option_chain_strikes, warrant_issuers, warrant_list,
       trading_session, trading_days, capital_flow, capital_distribution,
       calc_indexes, member_id, quote_level, option_chain_expiry_date_list, 
       market_temperature, history_market_temperature,
       watchlist, create_watchlist_group, delete_watchlist_group, update_watchlist_group,
       security_list

# --- Command Types for the Core Actor ---
abstract type AbstractCommand end

struct GenericRequestCmd <: AbstractCommand
    cmd_code::QuoteCommand.T
    request_pb::Any
    response_type::Type
    resp_ch::Channel{Any}                   # response channel
end

struct HttpGetCmd <: AbstractCommand
    path::String
    params::Dict{String,Any}
    resp_ch::Channel{Any}           # response channel
end

struct HttpPostCmd <: AbstractCommand
    path::String
    body::Dict{String,Any}
    resp_ch::Channel{Any}
end

struct HttpPutCmd <: AbstractCommand
    path::String
    body::Dict{String,Any}
    resp_ch::Channel{Any}
end

struct HttpDeleteCmd <: AbstractCommand
    path::String
    params::Dict{String,Any}
    resp_ch::Channel{Any}
end

struct DisconnectCmd <: AbstractCommand end

# --- Core Actor and Context Structs ---

mutable struct InnerQuoteContext
    config::Config.config
    ws_client::Union{WSClient, Nothing}
    session_id::Union{String, Nothing}
    command_ch::Channel{Any}
    core_task::Union{Task, Nothing}
    push_dispatcher_task::Union{Task, Nothing}
    callbacks::QuotePush.Callbacks
    subscriptions::Set{Tuple{Vector{String}, Vector{SubType.T}}}

    # Caches
    cache_participants::SimpleCache{Vector{Any}}
    cache_issuers::SimpleCache{Vector{Any}}
    cache_option_chain_expiry_dates::CacheWithKey{String, Vector{Any}}
    cache_option_chain_strike_info::CacheWithKey{Tuple{String, Any}, Vector{Any}}
    cache_trading_sessions::SimpleCache{Any}

    # Info from Core
    member_id::Int64
    quote_level::String
end

@doc """
Quote context handle. It is a lightweight wrapper around the core actor.
"""
struct QuoteContext
    inner::Arc{InnerQuoteContext}
end

# --- Core Actor Logic ---

function core_run(inner::InnerQuoteContext, push_tx::Channel)
    # @info "Quote core actor started."
    should_run = true
    reconnect_attempts = 0

    while should_run
        try
            # 1. Establish Connection or Reconnect
            if isnothing(inner.ws_client)
                # First time connection or after a full disconnect
                ws = WSClient(inner.config.quote_ws_url, inner.config)
                inner.ws_client = ws
                ws.on_push = (cmd, body) -> put!(push_tx, (cmd, body))
                ws.auth_data = Client.create_auth_request(inner.config)
                Client.connect!(ws)
                inner.session_id = ws.session_id # Save session_id
                # @info "Quote WebSocket connected."
                reconnect_attempts = 0 # Reset on successful connection

                # Resubscribe to all topics after successful reconnection
                if !isempty(inner.subscriptions)
                    @info "Resubscribing to topics..."
                    for (symbols, sub_types) in inner.subscriptions
                        try
                            req = QuoteSubscribeRequest(symbols, sub_types, true)
                            cmd = GenericRequestCmd(QuoteCommand.Subscribe, req, QuoteSubscribeResponse, Channel(1))
                            handle_command(inner, cmd) # Directly handle, don't wait on channel
                        catch e
                            @error "Failed to resubscribe" symbols=symbols sub_types=sub_types exception=(e, catch_backtrace())
                        end
                    end
                end
            end

            # TODO: Fetch member_id and quote_level after connection
            # For now, we'll leave them as default.
            # inner.member_id = ...
            # inner.quote_level = ...

            # 2. Main Command Processing Loop
            for cmd in inner.command_ch
                handle_command(inner, cmd)
                if cmd isa DisconnectCmd
                    should_run = false
                    break
                end
            end
        catch e
            if e isa InvalidStateException && e.state == :closed
                # @warn "Command channel closed, shutting down core actor."
                should_run = false
            elseif e isa LongportException && occursin("WebSocket", e.message)
                @warn "Connection lost, attempting to reconnect..." exception=(e, catch_backtrace())
                
                # Attempt fast reconnect first
                Client.full_reconnect!(inner.ws_client)

            else
                @error "Quote core actor failed with an unhandled exception" exception=(e, catch_backtrace())
                should_run = false # Exit on unhandled errors
            end
        finally
            # 3. Cleanup on graceful shutdown
            if !should_run && !isnothing(inner.ws_client)
                Client.disconnect!(inner.ws_client)
                inner.ws_client = nothing
            end
        end
    end

    close(push_tx)
    # @info "Quote core actor stopped."
end

function handle_command(inner::InnerQuoteContext, cmd::AbstractCommand)
    resp = try
        if cmd isa DisconnectCmd
            # No response needed, just break the loop
            nothing
        elseif cmd isa GenericRequestCmd
            # Handle Protobuf requests over WebSocket
            if isnothing(inner.ws_client) || !inner.ws_client.connected
                @lperror(404, "WebSocket not connected")
            end
            
            local req_body::Vector{UInt8}
            if cmd.request_pb isa SubscriptionRequest
                req_body = Vector{UInt8}()
            elseif cmd.request_pb isa Vector{UInt8}
                req_body = cmd.request_pb
            else
                io_buf = IOBuffer()
                encoder = ProtoBuf.ProtoEncoder(io_buf)
                ProtoBuf.encode(encoder, cmd.request_pb)
                req_body = take!(io_buf)
            end

            resp_body = Client.ws_request(inner.ws_client, UInt8(cmd.cmd_code), req_body)

            if isempty(resp_body)
                if cmd.cmd_code == QuoteCommand.Unsubscribe
                    # Unsubscribe sends no response body, this is expected.
                    resp = QuoteUnsubscribeResponse()
                else
                    # @warn "Received empty response for command" cmd_code = cmd.cmd_code
                    resp = cmd.response_type() # Return empty response object
                end
            else
                # @info "Received response body" cmd_code=cmd.cmd_code hex_body=bytes2hex(resp_body) length(resp_body)
                decoder = ProtoBuf.ProtoDecoder(IOBuffer(resp_body))
                resp = ProtoBuf.decode(decoder, cmd.response_type)
            end
        elseif cmd isa HttpGetCmd
            # Handle HTTP GET requests
            Client.get(inner.config, cmd.path; params=cmd.params)
        elseif cmd isa HttpPostCmd
            Client.post(inner.config, cmd.path; body=cmd.body)
        elseif cmd isa HttpPutCmd
            Client.put(inner.config, cmd.path; body=cmd.body)
        elseif cmd isa HttpDeleteCmd
            Client.delete(inner.config, cmd.path; params=cmd.params)
        end
    catch e
        @error "Failed to handle command" command=typeof(cmd) exception=(e, catch_backtrace())
        e # Propagate exception as the response
    end

    # Send response back to the caller
    if !(cmd isa DisconnectCmd) && isopen(cmd.resp_ch)
        put!(cmd.resp_ch, resp)
    end
end

# --- Push Dispatcher ---

function dispatch_push_events(ctx::QuoteContext, push_rx::Channel)
    # @info "Push event dispatcher started."
    for (cmd_code, body) in push_rx
        command = QuoteCommand.T(cmd_code)
        io = IOBuffer(body)
        decoder = ProtoBuf.ProtoDecoder(io)
        callbacks = ctx.inner.callbacks

        try
            if command == QuoteCommand.PushQuoteData
                data = ProtoBuf.decode(decoder, QuoteProtocol.PushQuote)
                QuotePush.handle_quote(callbacks, data.symbol, data)
            elseif command == QuoteCommand.PushDepthData
                data = ProtoBuf.decode(decoder, QuoteProtocol.PushDepth)
                QuotePush.handle_depth(callbacks, data.symbol, data)
            elseif command == QuoteCommand.PushBrokersData
                data = ProtoBuf.decode(decoder, QuoteProtocol.PushBrokers)
                QuotePush.handle_brokers(callbacks, data.symbol, data)
            elseif command == QuoteCommand.PushTradeData
                data = ProtoBuf.decode(decoder, QuoteProtocol.PushTrade)
                QuotePush.handle_trades(callbacks, data.symbol, data)
            else
                # @warn "Unknown push command" cmd=cmd_code
            end
        catch e
            @error "Failed to decode or dispatch push event" exception=(e, catch_backtrace())
        end
    end
    # @info "Push event dispatcher stopped."
end

# --- Public API ---

@doc """
Creates and initializes a `QuoteContext`.

This is the main entry point for using the quote API. It sets up the WebSocket connection
and the background processing task (Actor).

# Arguments
- `config::Config.config`: The configuration object.
"""
function QuoteContext(config::Config.config)
    command_ch = Channel{Any}(32)
    push_ch = Channel{Any}(Inf)     # a `Channel` for receiving raw push events

    inner = InnerQuoteContext(
        config,
        nothing, # ws_client
        nothing, # session_id
        command_ch,
        nothing, # core_task
        nothing, # push_dispatcher_task
        QuotePush.Callbacks(),
        Set{Tuple{Vector{String}, Vector{SubType.T}}}(),
        # Caches
        SimpleCache{Vector{Any}}(1800.0),
        SimpleCache{Vector{Any}}(1800.0),
        CacheWithKey{String, Vector{Any}}(1800.0),
        CacheWithKey{Tuple{String, Any}, Vector{Any}}(1800.0),
        SimpleCache{Any}(7200.0),
        # Core info
        0, "",
    )
    
    ctx = QuoteContext(Arc(inner))

    # Start background tasks
    inner.core_task = @async core_run(inner, push_ch)
    inner.push_dispatcher_task = @async dispatch_push_events(ctx, push_ch)

    return ctx
end

@doc """
Disconnects the WebSocket and shuts down the background actor.
"""

# Internal helper to send a command and wait for response
function request(ctx::QuoteContext, cmd::AbstractCommand)
    put!(ctx.inner.command_ch, cmd)
    resp = take!(cmd.resp_ch)

    if resp isa Exception
        throw(resp)
    end

    # 如果是 HTTP.Response，则读取 body 再解析 JSON
    if resp isa HTTP.Messages.Response
        return JSON3.read(String(resp.body))
    end

    if resp isa String
        return JSON3.read(resp)
    end
    
    return resp
end

# --- Callback Setters ---
# The `subscribe` function tells the server to start sending data.
# The callback functions below are used to process the data that the server pushes to us.
# For example, after calling `subscribe` for quote data, you would use `set_on_quote`
# to provide a function that will be executed each time a new quote arrives.
function set_on_quote(ctx::QuoteContext, cb::Function); QuotePush.set_on_quote!(ctx.inner.callbacks, cb); end
function set_on_depth(ctx::QuoteContext, cb::Function); QuotePush.set_on_depth!(ctx.inner.callbacks, cb); end
function set_on_brokers(ctx::QuoteContext, cb::Function); QuotePush.set_on_brokers!(ctx.inner.callbacks, cb); end
function set_on_trades(ctx::QuoteContext, cb::Function); QuotePush.set_on_trades!(ctx.inner.callbacks, cb); end
function set_on_candlestick(ctx::QuoteContext, cb::Function); QuotePush.set_on_candlestick!(ctx.inner.callbacks, cb); end

# --- Data API ---

function subscribe(ctx::QuoteContext, symbols::Vector{String}, sub_types::Vector{SubType.T}; is_first_push::Bool=false)
    req = QuoteSubscribeRequest(symbols, sub_types, is_first_push)
    cmd = GenericRequestCmd(QuoteCommand.Subscribe, req, QuoteSubscribeResponse, Channel(1))
    request(ctx, cmd)
    push!(ctx.inner.subscriptions, (symbols, sub_types))
    return [(symbol = s, sub_types = sub_types) for s in symbols]
end

function unsubscribe(ctx::QuoteContext, symbols::Vector{String}, sub_types::Vector{SubType.T})
    req = QuoteUnsubscribeRequest(symbols, sub_types, false)
    cmd = GenericRequestCmd(QuoteCommand.Unsubscribe, req, QuoteUnsubscribeResponse, Channel(1))
    request(ctx, cmd)
    delete!(ctx.inner.subscriptions, (symbols, sub_types))
    return [(symbol = s, sub_types = sub_types) for s in symbols]
end

function realtime_quote(ctx::QuoteContext, symbols::Vector{String})
    req = MultiSecurityRequest(symbols)
    cmd = GenericRequestCmd(QuoteCommand.QuerySecurityQuote, req, SecurityQuoteResponse, Channel(1))
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.secu_quote))
end

function candlesticks(
    ctx::QuoteContext, symbol::String, period::CandlePeriod.T = DAY, count::Int64 = 365; 
    trade_sessions::TradeSession.T = TradeSession.Intraday, adjust_type::AdjustType.T = AdjustType.FORWARD_ADJUST
    )
    req = SecurityCandlestickRequest(symbol, period, count, adjust_type, trade_sessions)
    cmd = GenericRequestCmd(QuoteCommand.QueryCandlestick, req, SecurityCandlestickResponse, Channel(1))
    resp = request(ctx, cmd)
    
    data = map(resp.candlesticks) do c
        (
            symbol = resp.symbol,
            close = c.close,
            open = c.open,
            low = c.low,
            high = c.high,
            volume = c.volume,
            turnover = c.turnover,
            timestamp = unix2datetime(c.timestamp),
            trade_session = c.trade_session
        )
    end
    return DataFrame(data)
end

function history_candlesticks_by_offset(
    ctx::QuoteContext, symbol::String, period::CandlePeriod.T, adjust_type::AdjustType.T, direction::Direction.T, count::Int; 
    date::Union{DateTime, Nothing}=nothing, trade_sessions::TradeSession.T=TradeSession.Intraday
    )
    
    offset_request = OffsetQuery(
        direction, 
        isnothing(date) ? "" : Dates.format(date, "yyyymmdd"), 
        isnothing(date) ? "" : Dates.format(date, "HHMM"), 
        count
    )

    req = SecurityHistoryCandlestickRequest(symbol, period, adjust_type, HistoryCandlestickQueryType.QUERY_BY_OFFSET, offset_request, nothing, trade_sessions)
    cmd = GenericRequestCmd(QuoteCommand.QueryHistoryCandlestick, req, SecurityCandlestickResponse, Channel(1))
    @show resp = request(ctx, cmd)

    data = map(resp.candlesticks) do c
        (
            symbol = resp.symbol,
            close = c.close,
            open = c.open,
            low = c.low,
            high = c.high,
            volume = c.volume,
            turnover = c.turnover,
            timestamp = unix2datetime(c.timestamp),
            trade_session = c.trade_session
        )
    end
    return DataFrame(data)
end

function history_candlesticks_by_date(
    ctx::QuoteContext, symbol::String, period::CandlePeriod.T, adjust_type::AdjustType.T; 
    start_date::Union{Date, Nothing}=nothing, end_date::Union{Date, Nothing}=nothing, trade_sessions::TradeSession.T=TradeSession.Intraday
    )

    date_request = DateQuery(
        isnothing(start_date) ? "" : Dates.format(start_date, "yyyymmdd"),
        isnothing(end_date) ? "" : Dates.format(end_date, "yyyymmdd")
    )

    req = SecurityHistoryCandlestickRequest(symbol, period, adjust_type, HistoryCandlestickQueryType.QUERY_BY_DATE, nothing, date_request, trade_sessions)
    cmd = GenericRequestCmd(QuoteCommand.QueryHistoryCandlestick, req, SecurityCandlestickResponse, Channel(1))
    resp = request(ctx, cmd)

    data = map(resp.candlesticks) do c
        (
            symbol = resp.symbol,
            close = c.close,
            open = c.open,
            low = c.low,
            high = c.high,
            volume = c.volume,
            turnover = c.turnover,
            timestamp = unix2datetime(c.timestamp),
            trade_session = c.trade_session
        )
    end
    return DataFrame(data)
end

function depth(ctx::QuoteContext, symbol::String)
    req = SecurityRequest(symbol)
    cmd = GenericRequestCmd(QuoteCommand.QueryDepth, req, SecurityDepthResponse, Channel(1))
    resp = request(ctx, cmd)

    asks = to_namedtuple(resp.ask)
    bids = to_namedtuple(resp.bid)

    ask_df = DataFrame(
        symbol=resp.symbol,
        side="ask",
        price=[a.price for a in asks],
        volume=[a.volume for a in asks],
        order_num=[a.order_num for a in asks]
    )

    bid_df = DataFrame(
        symbol=resp.symbol,
        side="bid",
        price=[b.price for b in bids],
        volume=[b.volume for b in bids],
        order_num=[b.order_num for b in bids]
    )

    return vcat(ask_df, bid_df)
end

function participants(ctx::QuoteContext)
    req = Vector{UInt8}()
    cmd = GenericRequestCmd(QuoteCommand.QueryParticipantBrokerIds, req, ParticipantBrokerIdsResponse, Channel(1))
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.participant_broker_numbers))
end

function subscriptions(ctx::QuoteContext)
    req = SubscriptionRequest()
    cmd = GenericRequestCmd(QuoteCommand.Subscription, req, SubscriptionResponse, Channel(1))
    resp = request(ctx, cmd)
    return to_namedtuple(resp.sub_list)
end

function static_info(ctx::QuoteContext, symbols::Vector{String})
    req = MultiSecurityRequest(symbols)
    cmd = GenericRequestCmd(QuoteCommand.QuerySecurityStaticInfo, req, SecurityStaticInfoResponse, Channel(1))
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.secu_static_info))
end

function trades(ctx::QuoteContext, symbol::String, count::Int)
    req = SecurityTradeRequest(symbol, count)
    cmd = GenericRequestCmd(QuoteCommand.QueryTrade, req, SecurityTradeResponse, Channel(1))
    resp = request(ctx, cmd)
    
    trade_list = to_namedtuple(resp.trades)
    df = DataFrame(trade_list)
    
    # Add symbol column and reorder to make it first
    df[!, :symbol] .= resp.symbol
    select!(df, :symbol, Not(:symbol))
    
    return df
end

function brokers(ctx::QuoteContext, symbol::String)
    req = SecurityRequest(symbol)
    cmd = GenericRequestCmd(QuoteCommand.QueryBrokers, req, SecurityBrokersResponse, Channel(1))
    resp = request(ctx, cmd)
    return (symbol = resp.symbol, ask_brokers = to_namedtuple(resp.ask_brokers), bid_brokers = to_namedtuple(resp.bid_brokers))
end

function intraday(ctx::QuoteContext, symbol::String; trade_session::TradeSession.T = TradeSession.All)
    req = SecurityIntradayRequest(symbol, trade_session)
    cmd = GenericRequestCmd(QuoteCommand.QueryIntraday, req, SecurityIntradayResponse, Channel(1))
    resp = request(ctx, cmd)

    data = map(resp.lines) do line
        (
            symbol = resp.symbol,
            timestamp = to_china_time(line.timestamp),
            price = line.price,
            volume = line.volume,
            turnover = line.turnover,
            avg_price = line.avg_price
        )
    end
    return DataFrame(data)
end

function option_chain_expiry_date_list(ctx::QuoteContext, symbol::String)
    req = SecurityRequest(symbol)
    cmd = GenericRequestCmd(QuoteCommand.QueryOptionChainDate, req, OptionChainDateListResponse, Channel(1))
    resp = request(ctx, cmd)
    return resp.expiry_date
end

function option_chain_info_by_date(ctx::QuoteContext, symbol::String, expiry_date::Date)
    req = OptionChainDateStrikeInfoRequest(symbol, expiry_date)
    cmd = GenericRequestCmd(QuoteCommand.QueryOptionChainDateStrikeInfo, req, OptionChainDateStrikeInfoResponse, Channel(1))
    resp = request(ctx, cmd)
    return to_namedtuple(resp.strike_price_info)
end

# --- Additional Market Data Endpoints ---

function option_chain_dates(ctx::QuoteContext, symbol::String)
    """Get option chain expiry dates for a symbol"""
    cmd = HttpGetCmd("/v1/quote/option-chain-dates", Dict{String, Any}("symbol" => symbol), Channel(1))
    return request(ctx, cmd)
end

function option_chain_strikes(ctx::QuoteContext, symbol::String, expiry_date::String)
    """Get option chain strike prices for a symbol and expiry date"""
    cmd = HttpGetCmd("/v1/quote/option-chain-strikes", 
        Dict{String, Any}("symbol" => symbol, "expiry_date" => expiry_date), Channel(1))
    return request(ctx, cmd)
end

function warrant_issuers(ctx::QuoteContext)
    """Get warrant issuer information"""
    req = Vector{UInt8}()
    cmd = GenericRequestCmd(QuoteCommand.QueryWarrantIssuerInfo, req, IssuerInfoResponse, Channel(1))
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.issuer_info))
end

function warrant_list(
    ctx::QuoteContext,
    symbol::String,
    sort_by::WarrantSortBy.T,
    sort_order::SortOrderType.T;
    warrant_type::Union{Nothing,Vector{WarrantType.T}} = nothing,
    issuer::Union{Nothing,Vector{Int32}} = nothing,
    expiry_date::Union{Nothing,Vector{FilterWarrantExpiryDate.T}} = nothing,
    price_type::Union{Nothing,Vector{FilterWarrantInOutBoundsType.T}} = nothing,
    status::Union{Nothing,Vector{WarrantStatus.T}} = nothing,
    language::Language.T = Language.EN,
    )
    """Filter warrants based on criteria"""
    filter_config = FilterConfig(
        sort_by,
        sort_order,
        0, # sort_offset
        20, # sort_count
        isnothing(warrant_type) ? WarrantType.T[] : warrant_type,
        isnothing(issuer) ? Int32[] : issuer,
        isnothing(expiry_date) ? FilterWarrantExpiryDate.T[] : expiry_date,
        isnothing(price_type) ? FilterWarrantInOutBoundsType.T[] : price_type,
        isnothing(status) ? WarrantStatus.T[] : status,
    )
    req = WarrantFilterListRequest(symbol, filter_config, Int32(language))
    cmd = GenericRequestCmd(QuoteCommand.QueryWarrantFilterList, req, WarrantFilterListResponse, Channel(1))
    resp = request(ctx, cmd)

    df = DataFrame(to_namedtuple(resp.warrant_list))

    return (data = df, total_count = resp.total_count)
end

function trading_session(ctx::QuoteContext)
    """Get trading session of the day"""
    return get_or_update(ctx.inner.cache_trading_sessions, function ()
        req = Vector{UInt8}()
        cmd = GenericRequestCmd(QuoteCommand.QueryMarketTradePeriod, req, MarketTradePeriodResponse, Channel(1))
        resp = request(ctx, cmd)

        format_time(t::Int64) = lpad(string(t), 4, '0') |> s -> "$(s[1:2]):$(s[3:4])"

        rows = NamedTuple{(:market, :beg_time, :end_time, :trade_session), Tuple{String, String, String, Any}}[]
        for market_session in to_namedtuple(resp.market_trade_session)
            for session in market_session.trade_session
                push!(rows, (
                    market = market_session.market,
                    beg_time = format_time(session.beg_time),
                    end_time = format_time(session.end_time),
                    trade_session = session.trade_session
                ))
            end
        end
        DataFrame(rows)
    end)
end

function trading_days(ctx::QuoteContext, market::Market.T, start_date::Date, end_date::Date)
    """Get trading days for a market within date range"""
    req = MarketTradeDayRequest(string(market), start_date, end_date)
    cmd = GenericRequestCmd(QuoteCommand.QueryMarketTradeDay, req, MarketTradeDayResponse, Channel(1))
    resp = request(ctx, cmd)

    dates = vcat(resp.trade_day, resp.half_trade_day)
    day_types = vcat(fill("trade_day", length(resp.trade_day)), fill("half_trade_day", length(resp.half_trade_day)))

    return DataFrame(date = dates, day_type = day_types)
end

function capital_flow(ctx::QuoteContext, symbol::String)
    """Get intraday capital flow for a symbol"""
    req = CapitalFlowIntradayRequest(symbol)
    cmd = GenericRequestCmd(QuoteCommand.QueryCapitalFlowIntraday, req, CapitalFlowIntradayResponse, Channel(1))
    resp = request(ctx, cmd)

    data = map(resp.capital_flow_lines) do line
        (
            symbol = resp.symbol,
            inflow = line.inflow,
            timestamp = to_china_time(line.timestamp)
        )
    end
    return DataFrame(data)
end

function capital_distribution(ctx::QuoteContext, symbol::String)
    """Get capital flow distribution for a symbol"""
    req = SecurityRequest(symbol)
    cmd = GenericRequestCmd(QuoteCommand.QueryCapitalFlowDistribution, req, CapitalDistributionResponse, Channel(1))
    resp = request(ctx, cmd)
    nt = to_namedtuple(resp)

    rows = NamedTuple{(:symbol, :timestamp, :flow_type, :capital_size, :value), Tuple{String, DateTime, String, String, Float64}}[]
    if isdefined(nt, :capital_in) && !isnothing(nt.capital_in)
        for (size, value) in pairs(nt.capital_in)
            push!(rows, (
                symbol = nt.symbol,
                timestamp = nt.timestamp,
                flow_type = "in",
                capital_size = string(size),
                value = value,
            ))
        end
    end
    if isdefined(nt, :capital_out) && !isnothing(nt.capital_out)
        for (size, value) in pairs(nt.capital_out)
            push!(rows, (
                symbol = nt.symbol,
                timestamp = nt.timestamp,
                flow_type = "out",
                capital_size = string(size),
                value = value,
            ))
        end
    end

    if isempty(rows)
        return DataFrame(
            symbol = String[],
            timestamp = DateTime[],
            flow_type = String[],
            capital_size = String[],
            value = Float64[],
        )
    else
        return DataFrame(rows)
    end
end

function calc_indexes(ctx::QuoteContext, symbols::Vector{String})
    all_indexes = collect(instances(CalcIndex.T))
    req = SecurityCalcQuoteRequest(symbols, all_indexes)
    cmd = GenericRequestCmd(QuoteCommand.QuerySecurityCalcIndex, req, SecurityCalcQuoteResponse, Channel(1))
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.security_calc_index))
end

function market_temperature(ctx::QuoteContext, market::Market.T)
    """Get market temperature"""
    cmd = HttpGetCmd("/v1/quote/market_temperature", Dict{String, Any}("market" => string(market)), Channel(1))
    res = request(ctx, cmd)

    temp_response = MarketTemperatureResponse(
        res.data.temperature,
        res.data.description,
        res.data.valuation,
        res.data.sentiment,
        to_china_time(res.data.updated_at)
    )
    
    return to_namedtuple(temp_response)
end

function history_market_temperature(ctx::QuoteContext, market::Market.T, start_date::Date, end_date::Date)
    """Get historical market temperature (daily).
    
    Note: This endpoint currently only supports daily granularity.
    """
    params = Dict{String, Any}(
        "market" => string(market),
        "start_date" => Dates.format(start_date, "yyyymmdd"),
        "end_date" => Dates.format(end_date, "yyyymmdd")
    )
    cmd = HttpGetCmd("/v1/quote/history_market_temperature", params, Channel(1))
    res = request(ctx, cmd)

    data = map(res.data.list) do item
        (
            timestamp = to_china_time(item.timestamp),
            temperature = item.temperature,
            valuation = item.valuation,
            sentiment = item.sentiment
        )
    end
    
    df = DataFrame(data)
    return (type = res.data.type, list = df)
end

function option_quote(ctx::QuoteContext, symbols::Vector{String})
    req = MultiSecurityRequest(symbols)
    cmd = GenericRequestCmd(QuoteCommand.QueryOptionQuote, req, OptionQuoteResponse, Channel(1))
    resp = request(ctx, cmd)
    
    # Convert to structured format including option-specific data
    return to_namedtuple(resp.secu_quote)
end

function warrant_quote(ctx::QuoteContext, symbols::Vector{String})
    req = MultiSecurityRequest(symbols)
    cmd = GenericRequestCmd(QuoteCommand.QueryWarrantQuote, req, WarrantQuoteResponse, Channel(1))
    resp = request(ctx, cmd)
    
    # Convert to structured format including warrant-specific data
    return DataFrame(to_namedtuple(resp.secu_quote))
end

member_id(ctx::QuoteContext) = ctx.inner.member_id
quote_level(ctx::QuoteContext) = ctx.inner.quote_level

# --- Watchlist API ---

function watchlist(ctx::QuoteContext)
    """Get watchlist and return a DataFrame with id and name."""
    cmd = HttpGetCmd("/v1/watchlist/groups", Dict{String, Any}(), Channel(1))
    resp = request(ctx, cmd)
    
    groups = resp.data.groups

    watchlist_data = map(groups) do g
        securities_df = if hasproperty(g, :securities) && !isempty(g.securities)
            df = DataFrame(g.securities)
            df.watched_price = parse.(Float64, df.watched_price)
            df.watched_at = to_china_time.(parse.(Int64, df.watched_at))
            df
        else
            DataFrame()
        end
        (id = parse(Int64, g.id), name = g.name, securities = securities_df)
    end

    return DataFrame(watchlist_data)
end

function create_watchlist_group(ctx::QuoteContext, name::String; securities::Union{Nothing,Vector{String}}=nothing)
    """Create watchlist group"""
    body = Dict{String, Any}("name" => name)
    if !isnothing(securities)
        body["securities"] = securities
    end
    cmd = HttpPostCmd("/v1/watchlist/groups", body, Channel(1))
    resp = request(ctx, cmd)
    return parse(Int64, resp.data.id)
end

function delete_watchlist_group(ctx::QuoteContext, group_id::Int64, purge::Bool)
    """Delete watchlist group, purge是否清除分组下的股票,true则此分组下的股票将被取消关注,false则此分组下的股票会保留在全部分组中"""
    params = Dict("id" => group_id, "purge" => purge)
    cmd = HttpDeleteCmd("/v1/watchlist/groups", params, Channel(1))
    resp = request(ctx, cmd)
    return resp.message
end

function update_watchlist_group(
    ctx::QuoteContext,
    group_id::Int64;        # 分组 ID
    name::Union{Nothing,String}=nothing,  # 分组名称，例如 信息产业组 如果不传递此参数，则分组名称不会更新
    securities::Union{Nothing,Vector{String}}=nothing,   # 股票列表，例如 ["BABA.US","AAPL.US"] 配合下面的 mode 参数，可完成添加股票、移除股票、对关注列表进行排序等操作
    mode::SecuritiesUpdateMode.T=SecuritiesUpdateMode.Replace   # 操作方法，可选值：add - 添加，remove - 移除，replace - 替换
)   # 选 add 时，将上面列表中的股票依序添加到此分组中，选 remove 时，将上面列表中的股票从此分组中移除，选 replace 时，将上面列表中的股票全量覆盖此分组下的股票假如原来分组中的股票为 APPL.US, BABA.US, TSLA.US，使用 ["BABA.US","AAPL.US","MSFT.US"] 更新后变为 ["BABA.US","AAPL.US","MSFT.US"]，对比之前，移除了 TSLA.US，添加了 MSFT.US，BABA.US,AAPL.US 调整了顺序
    """Update watchlist group"""
    body = Dict{String, Any}("id" => group_id)
    if !isnothing(name)
        body["name"] = name
    end
    if !isnothing(securities)
        body["securities"] = securities
        body["mode"] = string(mode)
    end
    cmd = HttpPutCmd("/v1/watchlist/groups", body, Channel(1))
    request(ctx, cmd)
    return nothing
end

function security_list(ctx::QuoteContext, market::Market.T, category::SecurityListCategory.T)
    """Get security list"""
    params = Dict{String, Any}("market" => string(market), "category" => string(category))
    cmd = HttpGetCmd("/v1/quote/get_security_list", params, Channel(1))
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.data.list))
end

end # module Quote
