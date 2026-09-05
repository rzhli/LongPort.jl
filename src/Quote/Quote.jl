module Quote

using ProtoBuf, JSON, Dates, DataFrames, HTTP, EnumX
using Dates: datetime2unix
using Base.Threads: Atomic, atomic_xchg!
using ..Config, ..QuotePush, ..Client, ..QuoteProtocol, ..ControlProtocol, ..Constant
using ..Commands:
    AbstractCommand, HttpGetCmd, HttpPostCmd, HttpPutCmd, HttpDeleteCmd, DisconnectCmd

using ..QuoteProtocol:
    CandlePeriod,
    AdjustType,
    TradeSession,
    SubType,
    QuoteCommand,
    Direction,
    SecurityCandlestickRequest,
    SecurityCandlestickResponse,
    QuoteSubscribeRequest,
    QuoteSubscribeResponse,
    QuoteUnsubscribeRequest,
    QuoteUnsubscribeResponse,
    SubscriptionRequest,
    SubscriptionResponse,
    MultiSecurityRequest,
    SecurityQuoteResponse,
    SecurityRequest,
    SecurityDepthResponse,
    SecurityStaticInfo,
    SecurityStaticInfoResponse,
    OptionQuoteResponse,
    WarrantQuoteResponse,
    SecurityBrokersResponse,
    ParticipantBrokerIdsResponse,
    SecurityTradeRequest,
    SecurityTradeResponse,
    SecurityIntradayRequest,
    SecurityIntradayResponse,
    SecurityHistoryCandlestickRequest,
    OffsetQuery,
    DateQuery,
    HistoryCandlestickQueryType,
    OptionChainDateListResponse,
    OptionChainDateStrikeInfoRequest,
    OptionChainDateStrikeInfoResponse,
    IssuerInfoResponse,
    WarrantFilterListRequest,
    FilterConfig,
    WarrantFilterListResponse,
    FilterWarrantExpiryDate,
    FilterWarrantInOutBoundsType,
    WarrantStatus,
    WarrantType,
    SortOrderType,
    WarrantSortBy,
    MarketTradePeriodResponse,
    MarketTradeDayRequest,
    MarketTradeDayResponse,
    CapitalFlowIntradayRequest,
    CapitalFlowIntradayResponse,
    CapitalDistributionResponse,
    MarketTemperatureResponse,
    SecurityListCategory,
    SecuritiesUpdateMode,
    UserQuoteProfileRequest,
    UserQuoteProfileResponse,
    QuotePackageDetail

using ..Client: WSClient
using ..Cache:
    SimpleCache,
    CacheWithKey,
    get_or_update,
    RealtimeStore,
    update_quote!,
    update_depth!,
    update_brokers!,
    update_trades!,
    get_quote,
    get_depth,
    get_brokers,
    get_trades,
    get_candlesticks,
    update_candlesticks!,
    clear_candlesticks!
using ..Utils:
    JSONObject,
    to_namedtuple,
    to_china_time,
    symbol_to_counter_id,
    counter_id_to_symbol,
    lookup_counter_id,
    cache_counter_ids
import ..Utils: construct
using ..QuoteProtocol: PushQuote, PushDepth, PushBrokers, Trade, Candlestick
using ..USProtocol

using ..Errors

import ..disconnect!

export QuoteContext,
    quote_snapshot,
    realtime_quote,
    subscribe,
    unsubscribe,
    static_info,
    depth,
    intraday,
    brokers,
    trades,
    candlesticks,
    history_candlesticks_by_offset,
    history_candlesticks_by_date,
    option_chain_expiry_date_list,
    option_chain_info_by_date,
    set_on_quote,
    set_on_depth,
    set_on_brokers,
    set_on_trades,
    set_on_candlestick,
    option_quote,
    warrant_quote,
    participants,
    subscriptions,
    warrant_issuers,
    warrant_list,
    trading_session,
    trading_days,
    capital_flow,
    capital_distribution,
    calc_indexes,
    member_id,
    quote_level,
    subscribe_limit,
    history_candlestick_limit,
    quote_package_details,
    filings,
    option_chain_expiry_date_list,
    market_temperature,
    history_market_temperature,
    watchlist,
    create_watchlist_group,
    delete_watchlist_group,
    update_watchlist_group,
    security_list,
    symbol_to_counter_ids,
    resolve_counter_ids,
    # Realtime cache methods
    realtime_depth,
    realtime_brokers,
    realtime_trades,
    realtime_candlesticks,
    subscribe_candlesticks,
    unsubscribe_candlesticks,
    us_crypto_overview,
    FilingItem

# Quote-specific command for WebSocket protobuf requests
struct GenericRequestCmd{R,T} <: AbstractCommand
    cmd_code::QuoteCommand.T
    request_pb::R
    response_type::Type{T}
    resp_ch::Channel{Any}
end

# --- Background Task and Context Structs ---

"""
    InnerQuoteContext

Internal, mutable worker state owned by [`QuoteContext`](@ref). The background
`run_quote_loop` and `dispatch_push_events` tasks operate directly on this object.
It is `mutable` because the connection, `session_id`, the background tasks, and
the runtime caches/store are all created or replaced after construction.

This type is private to the `Quote` module — nothing outside it should reach for
`inner` or rebind it. Do not hold the outer `QuoteContext` from inside a
background task; these tasks retain only this object, so the outer handle stays
collectable and its finalizer can signal both loops to stop.
"""
mutable struct InnerQuoteContext
    config::Config.Settings
    ws_client::Union{WSClient,Nothing}
    session_id::Union{String,Nothing}
    command_ch::Channel{AbstractCommand}
    push_ch::Channel{Tuple{UInt8,Vector{UInt8}}}
    shutdown::Atomic{Bool}
    background_task::Union{Task,Nothing}
    push_dispatcher_task::Union{Task,Nothing}
    callbacks::QuotePush.Callbacks
    subscriptions::Set{Tuple{Vector{String},Vector{SubType.T}}}

    # Caches
    cache_trading_sessions::SimpleCache{DataFrame}

    # Realtime data store for subscribed data
    store::RealtimeStore{PushQuote,PushDepth,PushBrokers,Trade,Candlestick}

    # Info from Core
    member_id::Int64
    quote_level::String
    subscribe_limit::Union{Nothing,Int32}
    history_candlestick_limit::Union{Nothing,Int32}
    quote_package_details::Vector{QuotePackageDetail}
end

@doc """
    QuoteContext

Public handle to a quote SDK session.

The session's mutable state lives in the internal [`InnerQuoteContext`](@ref)
(`ctx.inner`); this handle only ever routes to that single shared `inner`
reference. The handle is a `mutable struct` not because users mutate it — they
never do, and `inner` is private — but because Julia requires a mutable object to
attach a finalizer, which is what implements the automatic cleanup when the last
reference to the handle is dropped.

Keep this outer/inner split. The background `run_quote_loop` /
`dispatch_push_events` tasks retain only `inner`, never the outer `QuoteContext`,
so the handle is not pinned by them and can be collected once the last user
reference goes away. Do not rebind `ctx.inner`, and do not fold the state fields
into `QuoteContext`.
"""
mutable struct QuoteContext
    inner::InnerQuoteContext
end

const REQUEST_WAIT_TIMEOUT = Client.REQUEST_TIMEOUT + 5.0
const PUSH_CHANNEL_CAPACITY = 1024
const SHUTDOWN_WAIT_TIMEOUT = 5.0
# Max consecutive connection-setup failures (e.g. get_otp TLS timeout) before
# the background task gives up. Below this it retries with exponential backoff.
const MAX_CONNECT_ATTEMPTS = 5

@inline _is_shutdown(inner::InnerQuoteContext) = inner.shutdown[]

function _sleep_or_shutdown(inner::InnerQuoteContext, seconds::Real)
    deadline = time() + max(Float64(seconds), 0.0)
    while !_is_shutdown(inner)
        remaining = deadline - time()
        remaining <= 0 && return true
        sleep(min(remaining, 0.05))
    end
    return false
end

function _request_shutdown!(inner::InnerQuoteContext)
    atomic_xchg!(inner.shutdown, true)
    isopen(inner.command_ch) && close(inner.command_ch)
    isopen(inner.push_ch) && close(inner.push_ch)
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

function _finalize_quote_context!(ctx::QuoteContext)
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

function _wait_for_quote_reconnect!(inner::InnerQuoteContext; timeout::Real = REQUEST_WAIT_TIMEOUT)
    _is_shutdown(inner) && return false
    ws = inner.ws_client
    isnothing(ws) && return false

    Client.full_reconnect!(ws)
    deadline = time() + timeout
    while !_is_shutdown(inner) && time() < deadline
        if !isnothing(inner.ws_client) && inner.ws_client.connected
            return true
        end
        sleep(0.05)
    end
    return !_is_shutdown(inner) &&
           !isnothing(inner.ws_client) &&
           inner.ws_client.connected
end

function _submit_command!(ctx::QuoteContext, cmd::AbstractCommand)
    inner = ctx.inner
    task = inner.background_task
    if _is_shutdown(inner) || isnothing(task) || istaskdone(task) || !isopen(inner.command_ch)
        throw(LongBridgeError(500, "Quote background task is not running"))
    end

    try
        put!(inner.command_ch, cmd)
    catch e
        if e isa InvalidStateException
            throw(LongBridgeError(500, "Quote command channel is closed"))
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

function _resubscribe_quote!(inner::InnerQuoteContext)
    (_is_shutdown(inner) || isempty(inner.subscriptions)) && return

    @info "Resubscribing to topics..."
    for (symbols, sub_types) in inner.subscriptions
        _is_shutdown(inner) && return
        try
            req = QuoteSubscribeRequest(symbols, sub_types, true)
            cmd = GenericRequestCmd(
                QuoteCommand.Subscribe,
                req,
                QuoteSubscribeResponse,
                Channel(1),
            )
            handle_command(inner, cmd)
        catch e
            _is_shutdown(inner) ||
                @error "Failed to resubscribe" symbols=symbols sub_types=sub_types exception=(
                    e,
                    catch_backtrace(),
                )
        end
    end
end

# --- Background Task Logic ---

function run_quote_loop(inner::InnerQuoteContext)
    # @info "Quote background task started."
    should_run = true
    reconnect_attempts = 0
    push_tx = inner.push_ch

    while should_run && !_is_shutdown(inner)
        try
            # 1. Establish Connection or Reconnect
            if isnothing(inner.ws_client)
                # First time connection or after a full disconnect
                ws = WSClient(inner.config.quote_ws_url, inner.config, inner.shutdown)
                inner.ws_client = ws
                ws.on_push = (cmd, body) -> put!(push_tx, (cmd, body))
                ws.on_reconnect = () -> _resubscribe_quote!(inner)
                ws.auth_data = Client.create_auth_request(inner.config)
                connected = Client.connect!(ws)
                (_is_shutdown(inner) || !connected) && break
                inner.session_id = ws.session_id # Save session_id
                # @info "Quote WebSocket connected."
                reconnect_attempts = 0 # Reset on successful connection

                # Resubscribe to all topics after successful reconnection
                _resubscribe_quote!(inner)
            end

            # Fetch user profile and account quote limits.
            try
                lang = inner.config.language
                lang_str =
                    lang === Constant.Language.ZH_CN ? "zh-CN" :
                    lang === Constant.Language.ZH_HK ? "zh-HK" :
                    lang === Constant.Language.EN ? "en" : "zh-CN"
                profile_req = UserQuoteProfileRequest(lang_str)
                io_buf = IOBuffer()
                encoder = ProtoBuf.ProtoEncoder(io_buf)
                ProtoBuf.encode(encoder, profile_req)
                resp_body = Client.ws_request(
                    inner.ws_client,
                    UInt8(QuoteCommand.QueryUserQuoteProfile),
                    take!(io_buf),
                )
                if !isempty(resp_body)
                    decoder = ProtoBuf.ProtoDecoder(IOBuffer(resp_body))
                    profile = ProtoBuf.decode(decoder, UserQuoteProfileResponse)
                    inner.member_id = profile.member_id
                    inner.quote_level = profile.quote_level
                    inner.subscribe_limit = profile.subscribe_limit
                    inner.history_candlestick_limit = profile.history_candlestick_limit
                    inner.quote_package_details = profile.quote_package_details
                end
            catch e
                _is_shutdown(inner) ||
                    @warn "Failed to fetch user quote profile" exception=(e, catch_backtrace())
            end

            # 2. Main Command Processing Loop
            while !_is_shutdown(inner)
                cmd = take!(inner.command_ch)
                _is_shutdown(inner) && break
                reconnect_needed = handle_command(inner, cmd)
                if cmd isa DisconnectCmd
                    should_run = false
                    break
                elseif reconnect_needed
                    @warn "Quote WebSocket command failed; reconnecting before processing more commands"
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
                # @warn "Command channel closed, shutting down quote task."
                should_run = false
            elseif e isa LongBridgeError && occursin("WebSocket", e.message)
                @warn "Connection lost, attempting to reconnect..." exception=(
                    e,
                    catch_backtrace(),
                )

                # Attempt fast reconnect first
                isnothing(inner.ws_client) || Client.full_reconnect!(inner.ws_client)

            else
                # Connection setup / network failure (e.g. get_otp TLS timeout,
                # WSClient connect failure). Don't kill the context on a transient
                # hiccup — drop any half-open client and retry with backoff.
                reconnect_attempts += 1
                if !isnothing(inner.ws_client)
                    try
                        Client.disconnect!(inner.ws_client)
                    catch
                    end
                    inner.ws_client = nothing
                end

                if reconnect_attempts >= MAX_CONNECT_ATTEMPTS
                    @error "Quote background task giving up after $reconnect_attempts consecutive connection failures" exception=(
                        e,
                        catch_backtrace(),
                    )
                    should_run = false
                else
                    backoff = min(2.0^reconnect_attempts, 30.0)
                    @warn "Quote connection setup failed (attempt $reconnect_attempts/$MAX_CONNECT_ATTEMPTS); retrying in $backoff s" exception=(
                        e,
                        catch_backtrace(),
                    )
                    _sleep_or_shutdown(inner, backoff) || (should_run = false)
                end
            end
        finally
            # 3. Cleanup on graceful shutdown
            if (!should_run || _is_shutdown(inner)) && !isnothing(inner.ws_client)
                if _is_shutdown(inner)
                    Client.shutdown!(inner.ws_client)
                else
                    Client.disconnect!(inner.ws_client)
                end
                inner.ws_client = nothing
            end
        end
    end

    isopen(push_tx) && close(push_tx)
    isopen(inner.command_ch) && close(inner.command_ch)
    # @info "Quote background task stopped."
end

function _execute_command_once(inner::InnerQuoteContext, cmd::AbstractCommand)
    if cmd isa DisconnectCmd
        return nothing
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
                return QuoteUnsubscribeResponse()
            else
                # @warn "Received empty response for command" cmd_code = cmd.cmd_code
                return cmd.response_type() # Return empty response object
            end
        else
            # @info "Received response body" cmd_code=cmd.cmd_code hex_body=bytes2hex(resp_body) length(resp_body)
            decoder = ProtoBuf.ProtoDecoder(IOBuffer(resp_body))
            return ProtoBuf.decode(decoder, cmd.response_type)
        end
    elseif cmd isa HttpGetCmd
        # Handle HTTP GET requests
        return Client.http_get(inner.config, cmd.path; params = cmd.params)
    elseif cmd isa HttpPostCmd
        return Client.http_post(inner.config, cmd.path; body = cmd.body)
    elseif cmd isa HttpPutCmd
        return Client.http_put(inner.config, cmd.path; body = cmd.body)
    elseif cmd isa HttpDeleteCmd
        return Client.http_delete(inner.config, cmd.path; params = cmd.params)
    end
end

function handle_command(inner::InnerQuoteContext, cmd::AbstractCommand)
    reconnect_needed = false
    resp = try
        _execute_command_once(inner, cmd)
    catch e
        if cmd isa GenericRequestCmd && _is_reconnectable_ws_error(e)
            @warn "Quote WebSocket command failed; reconnecting and retrying once" command=typeof(cmd) exception=(
                e,
                catch_backtrace(),
            )
            try
                if _wait_for_quote_reconnect!(inner)
                    _execute_command_once(inner, cmd)
                else
                    reconnect_needed = true
                    e
                end
            catch retry_error
                reconnect_needed = _is_reconnectable_ws_error(retry_error)
                @error "Failed to handle command after reconnect retry" command=typeof(cmd) exception=(
                    retry_error,
                    catch_backtrace(),
                )
                retry_error
            end
        else
            @error "Failed to handle command" command=typeof(cmd) exception=(
                e,
                catch_backtrace(),
            )
            e # Propagate exception as the response
        end
    end

    # Send response back to the caller
    if !(cmd isa DisconnectCmd) && isopen(cmd.resp_ch)
        put!(cmd.resp_ch, resp)
    end
    return reconnect_needed
end

# --- Push Dispatcher ---

function dispatch_push_events(
    inner::InnerQuoteContext,
    push_rx::Channel{Tuple{UInt8,Vector{UInt8}}},
)
    # @info "Push event dispatcher started."
    store = inner.store
    for (cmd_code, body) in push_rx
        _is_shutdown(inner) && break
        command = QuoteCommand.T(cmd_code)
        io = IOBuffer(body)
        decoder = ProtoBuf.ProtoDecoder(io)
        callbacks = inner.callbacks

        try
            if command == QuoteCommand.PushQuoteData
                data = ProtoBuf.decode(decoder, QuoteProtocol.PushQuote)
                update_quote!(store, data.symbol, data)
                QuotePush.handle_quote(callbacks, data.symbol, data)
            elseif command == QuoteCommand.PushDepthData
                data = ProtoBuf.decode(decoder, QuoteProtocol.PushDepth)
                update_depth!(store, data.symbol, data)
                QuotePush.handle_depth(callbacks, data.symbol, data)
            elseif command == QuoteCommand.PushBrokersData
                data = ProtoBuf.decode(decoder, QuoteProtocol.PushBrokers)
                update_brokers!(store, data.symbol, data)
                QuotePush.handle_brokers(callbacks, data.symbol, data)
            elseif command == QuoteCommand.PushTradeData
                data = ProtoBuf.decode(decoder, QuoteProtocol.PushTrade)
                update_trades!(store, data.symbol, data.trade)
                QuotePush.handle_trades(callbacks, data.symbol, data)
            else
                # @warn "Unknown push command" cmd=cmd_code
            end
        catch e
            @error "Failed to decode or dispatch push event" exception=(
                e,
                catch_backtrace(),
            )
        end
    end
    # @info "Push event dispatcher stopped."
end

# --- Public API ---

@doc """
Creates and initializes a `QuoteContext`.

This is the main entry point for using the quote API. It sets up the WebSocket
connection and the background tasks.

# Arguments
- `config::Config.Settings`: The configuration object.
"""
function _build_quote_context(config::Config.Settings; start_tasks::Bool = true)
    command_ch = Channel{AbstractCommand}(32)
    push_ch = Channel{Tuple{UInt8,Vector{UInt8}}}(PUSH_CHANNEL_CAPACITY)
    shutdown = Atomic{Bool}(false)

    inner = InnerQuoteContext(
        config,
        nothing, # ws_client
        nothing, # session_id
        command_ch,
        push_ch,
        shutdown,
        nothing, # background_task
        nothing, # push_dispatcher_task
        QuotePush.Callbacks(),
        Set{Tuple{Vector{String},Vector{SubType.T}}}(),
        # Caches
        SimpleCache{DataFrame}(7200.0),
        # Realtime store
        RealtimeStore{PushQuote,PushDepth,PushBrokers,Trade,Candlestick}(),
        # Core info
        0,
        "",
        nothing,
        nothing,
        QuotePackageDetail[],
    )

    ctx = QuoteContext(inner)
    finalizer(_finalize_quote_context!, ctx)

    if start_tasks
        # Tasks retain only `inner`, so dropping the outer Context can run its
        # finalizer and signal both loops to stop.
        inner.background_task = errormonitor(@async run_quote_loop(inner))
        inner.push_dispatcher_task =
            errormonitor(@async dispatch_push_events(inner, push_ch))
    end

    return ctx
end

QuoteContext(config::Config.Settings) = _build_quote_context(config)

@doc """
Disconnects the WebSocket and shuts down the background tasks.
"""

# Internal helper to send a command and wait for response
#
# Type-stable fast path for protobuf WS requests: the cmd carries the
# response Type as a parameter, so we can assert ::T after `take!` and
# propagate concrete type info to every downstream `.field` access at
# the call site (eliminates the previous Any → field-access widening).
function request(ctx::QuoteContext, cmd::GenericRequestCmd{R,T}) where {R,T}
    _submit_command!(ctx, cmd)
    resp = _take_task_response!(cmd.resp_ch, "Quote")
    resp isa Exception && throw(resp)
    return resp::T
end

# Generic fallback for HTTP* commands (no compile-time response type).
function request(ctx::QuoteContext, cmd::AbstractCommand)
    _submit_command!(ctx, cmd)
    resp = _take_task_response!(cmd.resp_ch, "Quote")

    if resp isa Exception
        throw(resp)
    end

    # 如果是 HTTP.Response，则读取 body 再解析 JSON
    if resp isa HTTP.Response
        return JSON.parse(resp.body)
    end

    if resp isa String
        return JSON.parse(resp)
    end

    return resp
end

# --- Callback Setters ---
# The `subscribe` function tells the server to start sending data.
# The callback functions below are used to process the data that the server pushes to us.
# For example, after calling `subscribe` for quote data, you would use `set_on_quote`
# to provide a function that will be executed each time a new quote arrives.
set_on_quote(ctx::QuoteContext, cb) = QuotePush.set_on_quote!(ctx.inner.callbacks, cb)
set_on_depth(ctx::QuoteContext, cb) = QuotePush.set_on_depth!(ctx.inner.callbacks, cb)
set_on_brokers(ctx::QuoteContext, cb) = QuotePush.set_on_brokers!(ctx.inner.callbacks, cb)
set_on_trades(ctx::QuoteContext, cb) = QuotePush.set_on_trades!(ctx.inner.callbacks, cb)
set_on_candlestick(ctx::QuoteContext, cb) =
    QuotePush.set_on_candlestick!(ctx.inner.callbacks, cb)

# --- Data API ---

function subscribe(
    ctx::QuoteContext,
    symbols::AbstractVector{<:AbstractString},
    sub_types::AbstractVector{SubType.T};
    is_first_push::Bool = false,
)
    symbol_list = String[String(symbol) for symbol in symbols]
    type_list = collect(sub_types)
    req = QuoteSubscribeRequest(symbol_list, type_list, is_first_push)
    cmd = GenericRequestCmd(QuoteCommand.Subscribe, req, QuoteSubscribeResponse, Channel(1))
    request(ctx, cmd)
    push!(ctx.inner.subscriptions, (symbol_list, type_list))
    return [(symbol = symbol, sub_types = type_list) for symbol in symbol_list]
end

function unsubscribe(
    ctx::QuoteContext,
    symbols::AbstractVector{<:AbstractString},
    sub_types::AbstractVector{SubType.T},
)
    symbol_list = String[String(symbol) for symbol in symbols]
    type_list = collect(sub_types)
    req = QuoteUnsubscribeRequest(symbol_list, type_list, false)
    cmd = GenericRequestCmd(
        QuoteCommand.Unsubscribe,
        req,
        QuoteUnsubscribeResponse,
        Channel(1),
    )
    request(ctx, cmd)
    delete!(ctx.inner.subscriptions, (symbol_list, type_list))
    return [(symbol = symbol, sub_types = type_list) for symbol in symbol_list]
end

"""
    quote_snapshot(ctx::QuoteContext, symbols::Vector{String}) -> DataFrame

Fetch a one-shot quote snapshot from the server (WebSocket request).
Use [`realtime_quote`](@ref) instead when you have an active subscription and want the
locally cached latest push.

Mirrors Rust SDK `QuoteContext::quote`.
"""
function quote_snapshot(ctx::QuoteContext, symbols::AbstractVector{<:AbstractString})
    req = MultiSecurityRequest(String[String(symbol) for symbol in symbols])
    cmd = GenericRequestCmd(
        QuoteCommand.QuerySecurityQuote,
        req,
        SecurityQuoteResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.secu_quote))
end

"""
    realtime_quote(ctx::QuoteContext, symbol::String) -> Union{Nothing, PushQuote}
    realtime_quote(ctx::QuoteContext, symbols::Vector{String}) -> Vector{Union{Nothing, PushQuote}}

Read the latest quote(s) pushed by the server from the local store. Returns `nothing`
for any symbol that has not received a push yet (subscribe first via [`subscribe`](@ref)).

Mirrors Rust SDK `QuoteContext::realtime_quote`. For a one-shot server query, use
[`quote_snapshot`](@ref).
"""
realtime_quote(ctx::QuoteContext, symbol::AbstractString) = get_quote(ctx.inner.store, symbol)
realtime_quote(ctx::QuoteContext, symbols::AbstractVector{<:AbstractString}) =
    [get_quote(ctx.inner.store, s) for s in symbols]

function _candlestick_dataframe(
    resp::SecurityCandlestickResponse;
    include_timestamp_unix::Bool = false,
)
    data = if include_timestamp_unix
        map(resp.candlesticks) do c
            (
                symbol = resp.symbol,
                close = c.close,
                open = c.open,
                low = c.low,
                high = c.high,
                volume = c.volume,
                turnover = c.turnover,
                timestamp = unix2datetime(c.timestamp),
                timestamp_unix = c.timestamp,
                trade_session = c.trade_session,
            )
        end
    else
        map(resp.candlesticks) do c
            (
                symbol = resp.symbol,
                close = c.close,
                open = c.open,
                low = c.low,
                high = c.high,
                volume = c.volume,
                turnover = c.turnover,
                timestamp = unix2datetime(c.timestamp),
                trade_session = c.trade_session,
            )
        end
    end
    return DataFrame(data)
end

"""
    candlesticks(ctx, symbol, period=DAY, count=365; kwargs...) -> DataFrame

Get recent candlesticks. The `timestamp` column is a timezone-naive `DateTime`
whose value is UTC. Set `include_timestamp_unix=true` to include the exact raw
Unix-seconds value in a `timestamp_unix` column.
"""
function candlesticks(
    ctx::QuoteContext,
    symbol::AbstractString,
    period::CandlePeriod.T = DAY,
    count::Int64 = 365;
    trade_sessions::TradeSession.T = TradeSession.Intraday,
    adjust_type::AdjustType.T = AdjustType.FORWARD_ADJUST,
    include_timestamp_unix::Bool = false,
)
    req = SecurityCandlestickRequest(String(symbol), period, count, adjust_type, trade_sessions)
    cmd = GenericRequestCmd(
        QuoteCommand.QueryCandlestick,
        req,
        SecurityCandlestickResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)

    return _candlestick_dataframe(resp; include_timestamp_unix)
end

"""
    history_candlesticks_by_offset(ctx, symbol, period, adjust_type, direction, count; kwargs...) -> DataFrame

Get historical candlesticks relative to an offset. Returned `timestamp` values
are UTC-semantic `DateTime`s. Set `include_timestamp_unix=true` to retain the
raw Unix-seconds value in a `timestamp_unix` column.
"""
function history_candlesticks_by_offset(
    ctx::QuoteContext,
    symbol::AbstractString,
    period::CandlePeriod.T,
    adjust_type::AdjustType.T,
    direction::Direction.T,
    count::Int;
    date::Union{DateTime,Nothing} = nothing,
    trade_sessions::TradeSession.T = TradeSession.Intraday,
    include_timestamp_unix::Bool = false,
)

    offset_request = OffsetQuery(
        direction,
        isnothing(date) ? "" : Dates.format(date, "yyyymmdd"),
        isnothing(date) ? "" : Dates.format(date, "HHMM"),
        count,
    )

    req = SecurityHistoryCandlestickRequest(
        String(symbol),
        period,
        adjust_type,
        HistoryCandlestickQueryType.QUERY_BY_OFFSET,
        offset_request,
        nothing,
        trade_sessions,
    )
    cmd = GenericRequestCmd(
        QuoteCommand.QueryHistoryCandlestick,
        req,
        SecurityCandlestickResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)

    return _candlestick_dataframe(resp; include_timestamp_unix)
end

"""
    history_candlesticks_by_date(ctx, symbol, period, adjust_type; kwargs...) -> DataFrame

Get historical candlesticks for a date range. Returned `timestamp` values are
UTC-semantic `DateTime`s; for example, `2026-06-17T19:30:00` represents
`2026-06-17T15:30:00-04:00` in New York. Set `include_timestamp_unix=true` to
include the raw Unix-seconds value.
"""
function history_candlesticks_by_date(
    ctx::QuoteContext,
    symbol::AbstractString,
    period::CandlePeriod.T,
    adjust_type::AdjustType.T;
    start_date::Union{Date,Nothing} = nothing,
    end_date::Union{Date,Nothing} = nothing,
    trade_sessions::TradeSession.T = TradeSession.Intraday,
    include_timestamp_unix::Bool = false,
)

    date_request = DateQuery(
        isnothing(start_date) ? "" : Dates.format(start_date, "yyyymmdd"),
        isnothing(end_date) ? "" : Dates.format(end_date, "yyyymmdd"),
    )

    req = SecurityHistoryCandlestickRequest(
        String(symbol),
        period,
        adjust_type,
        HistoryCandlestickQueryType.QUERY_BY_DATE,
        nothing,
        date_request,
        trade_sessions,
    )
    cmd = GenericRequestCmd(
        QuoteCommand.QueryHistoryCandlestick,
        req,
        SecurityCandlestickResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)

    return _candlestick_dataframe(resp; include_timestamp_unix)
end

function depth(ctx::QuoteContext, symbol::AbstractString)
    req = SecurityRequest(String(symbol))
    cmd = GenericRequestCmd(QuoteCommand.QueryDepth, req, SecurityDepthResponse, Channel(1))
    resp = request(ctx, cmd)

    asks = to_namedtuple(resp.ask)
    bids = to_namedtuple(resp.bid)

    ask_df = DataFrame(
        symbol = resp.symbol,
        side = "ask",
        price = [a.price for a in asks],
        volume = [a.volume for a in asks],
        order_num = [a.order_num for a in asks],
    )

    bid_df = DataFrame(
        symbol = resp.symbol,
        side = "bid",
        price = [b.price for b in bids],
        volume = [b.volume for b in bids],
        order_num = [b.order_num for b in bids],
    )

    return vcat(ask_df, bid_df)
end

function participants(ctx::QuoteContext)
    req = Vector{UInt8}()
    cmd = GenericRequestCmd(
        QuoteCommand.QueryParticipantBrokerIds,
        req,
        ParticipantBrokerIdsResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.participant_broker_numbers))
end

function subscriptions(ctx::QuoteContext)
    req = SubscriptionRequest()
    cmd =
        GenericRequestCmd(QuoteCommand.Subscription, req, SubscriptionResponse, Channel(1))
    resp = request(ctx, cmd)
    return to_namedtuple(resp.sub_list)
end

function static_info(ctx::QuoteContext, symbols::AbstractVector{<:AbstractString})
    req = MultiSecurityRequest(String[String(symbol) for symbol in symbols])
    cmd = GenericRequestCmd(
        QuoteCommand.QuerySecurityStaticInfo,
        req,
        SecurityStaticInfoResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.secu_static_info))
end

function trades(ctx::QuoteContext, symbol::AbstractString, count::Integer)
    req = SecurityTradeRequest(String(symbol), Int(count))
    cmd = GenericRequestCmd(QuoteCommand.QueryTrade, req, SecurityTradeResponse, Channel(1))
    resp = request(ctx, cmd)

    trade_list = to_namedtuple(resp.trades)
    df = DataFrame(trade_list)

    # Add symbol column and reorder to make it first
    df[!, :symbol] .= resp.symbol
    select!(df, :symbol, Not(:symbol))

    return df
end

function brokers(ctx::QuoteContext, symbol::AbstractString)
    req = SecurityRequest(String(symbol))
    cmd = GenericRequestCmd(
        QuoteCommand.QueryBrokers,
        req,
        SecurityBrokersResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)
    return (
        symbol = resp.symbol,
        ask_brokers = to_namedtuple(resp.ask_brokers),
        bid_brokers = to_namedtuple(resp.bid_brokers),
    )
end

function intraday(
    ctx::QuoteContext,
    symbol::AbstractString;
    trade_session::TradeSession.T = TradeSession.All,
)
    req = SecurityIntradayRequest(String(symbol), trade_session)
    cmd = GenericRequestCmd(
        QuoteCommand.QueryIntraday,
        req,
        SecurityIntradayResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)

    data = map(resp.lines) do line
        (
            symbol = resp.symbol,
            timestamp = to_china_time(line.timestamp),
            price = line.price,
            volume = line.volume,
            turnover = line.turnover,
            avg_price = line.avg_price,
        )
    end
    return DataFrame(data)
end

function option_chain_expiry_date_list(ctx::QuoteContext, symbol::AbstractString)
    req = SecurityRequest(String(symbol))
    cmd = GenericRequestCmd(
        QuoteCommand.QueryOptionChainDate,
        req,
        OptionChainDateListResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)
    return resp.expiry_date
end

function option_chain_info_by_date(
    ctx::QuoteContext,
    symbol::AbstractString,
    expiry_date::Date,
)
    req = OptionChainDateStrikeInfoRequest(String(symbol), expiry_date)
    cmd = GenericRequestCmd(
        QuoteCommand.QueryOptionChainDateStrikeInfo,
        req,
        OptionChainDateStrikeInfoResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)
    return to_namedtuple(resp.strike_price_info)
end

function warrant_issuers(ctx::QuoteContext)
    """Get warrant issuer information"""
    req = Vector{UInt8}()
    cmd = GenericRequestCmd(
        QuoteCommand.QueryWarrantIssuerInfo,
        req,
        IssuerInfoResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.issuer_info))
end

function warrant_list(
    ctx::QuoteContext,
    symbol::AbstractString,
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
    req = WarrantFilterListRequest(String(symbol), filter_config, Int32(language))
    cmd = GenericRequestCmd(
        QuoteCommand.QueryWarrantFilterList,
        req,
        WarrantFilterListResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)

    df = DataFrame(to_namedtuple(resp.warrant_list))

    return (data = df, total_count = resp.total_count)
end

function trading_session(ctx::QuoteContext)
    """Get trading session of the day"""
    return get_or_update(
        ctx.inner.cache_trading_sessions,
        function ()
            req = Vector{UInt8}()
            cmd = GenericRequestCmd(
                QuoteCommand.QueryMarketTradePeriod,
                req,
                MarketTradePeriodResponse,
                Channel(1),
            )
            resp = request(ctx, cmd)

            format_time(t::Int64) = lpad(string(t), 4, '0') |> s -> "$(s[1:2]):$(s[3:4])"

            rows = NamedTuple{
                (:market, :beg_time, :end_time, :trade_session),
                Tuple{String,String,String,Any},
            }[]
            for market_session in to_namedtuple(resp.market_trade_session)
                for session in market_session.trade_session
                    push!(
                        rows,
                        (
                            market = market_session.market,
                            beg_time = format_time(session.beg_time),
                            end_time = format_time(session.end_time),
                            trade_session = session.trade_session,
                        ),
                    )
                end
            end
            DataFrame(rows)
        end,
    )
end

function trading_days(ctx::QuoteContext, market::Market.T, start_date::Date, end_date::Date)
    """Get trading days for a market within date range"""
    req = MarketTradeDayRequest(string(market), start_date, end_date)
    cmd = GenericRequestCmd(
        QuoteCommand.QueryMarketTradeDay,
        req,
        MarketTradeDayResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)

    dates = vcat(resp.trade_day, resp.half_trade_day)
    day_types = vcat(
        fill("trade_day", length(resp.trade_day)),
        fill("half_trade_day", length(resp.half_trade_day)),
    )

    return DataFrame(date = dates, day_type = day_types)
end

function capital_flow(ctx::QuoteContext, symbol::AbstractString)
    """Get intraday capital flow for a symbol"""
    req = CapitalFlowIntradayRequest(String(symbol))
    cmd = GenericRequestCmd(
        QuoteCommand.QueryCapitalFlowIntraday,
        req,
        CapitalFlowIntradayResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)

    data = map(resp.capital_flow_lines) do line
        (symbol = resp.symbol, inflow = line.inflow, timestamp = to_china_time(line.timestamp))
    end
    return DataFrame(data)
end

function capital_distribution(ctx::QuoteContext, symbol::AbstractString)
    """Get capital flow distribution for a symbol"""
    req = SecurityRequest(String(symbol))
    cmd = GenericRequestCmd(
        QuoteCommand.QueryCapitalFlowDistribution,
        req,
        CapitalDistributionResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)
    nt = to_namedtuple(resp)

    rows = NamedTuple{
        (:symbol, :timestamp, :flow_type, :capital_size, :value),
        Tuple{String,DateTime,String,String,Float64},
    }[]
    if isdefined(nt, :capital_in) && !isnothing(nt.capital_in)
        for (size, value) in pairs(nt.capital_in)
            push!(
                rows,
                (
                    symbol = nt.symbol,
                    timestamp = nt.timestamp,
                    flow_type = "in",
                    capital_size = string(size),
                    value = value,
                ),
            )
        end
    end
    if isdefined(nt, :capital_out) && !isnothing(nt.capital_out)
        for (size, value) in pairs(nt.capital_out)
            push!(
                rows,
                (
                    symbol = nt.symbol,
                    timestamp = nt.timestamp,
                    flow_type = "out",
                    capital_size = string(size),
                    value = value,
                ),
            )
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

function calc_indexes(ctx::QuoteContext, symbols::AbstractVector{<:AbstractString})
    all_indexes = collect(instances(CalcIndex.T))
    req = SecurityCalcQuoteRequest(String[String(symbol) for symbol in symbols], all_indexes)
    cmd = GenericRequestCmd(
        QuoteCommand.QuerySecurityCalcIndex,
        req,
        SecurityCalcQuoteResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.security_calc_index))
end

function market_temperature(ctx::QuoteContext, market::Market.T)
    """Get market temperature"""
    cmd = HttpGetCmd(
        "/v1/quote/market_temperature",
        Dict{String,Any}("market" => string(market)),
        Channel(1),
    )
    res = request(ctx, cmd)

    temp_response = MarketTemperatureResponse(
        res.data.temperature,
        res.data.description,
        res.data.valuation,
        res.data.sentiment,
        to_china_time(res.data.updated_at),
    )

    return to_namedtuple(temp_response)
end

function history_market_temperature(
    ctx::QuoteContext,
    market::Market.T,
    start_date::Date,
    end_date::Date,
)
    """Get historical market temperature (daily).

    Note: This endpoint currently only supports daily granularity.
    """
    params = Dict{String,Any}(
        "market" => string(market),
        "start_date" => Dates.format(start_date, "yyyymmdd"),
        "end_date" => Dates.format(end_date, "yyyymmdd"),
    )
    cmd = HttpGetCmd("/v1/quote/history_market_temperature", params, Channel(1))
    res = request(ctx, cmd)

    data = map(res.data.list) do item
        (
            timestamp = to_china_time(item.timestamp),
            temperature = item.temperature,
            valuation = item.valuation,
            sentiment = item.sentiment,
        )
    end

    df = DataFrame(data)
    return (type = res.data.type, list = df)
end

function option_quote(ctx::QuoteContext, symbols::AbstractVector{<:AbstractString})
    req = MultiSecurityRequest(String[String(symbol) for symbol in symbols])
    cmd = GenericRequestCmd(
        QuoteCommand.QueryOptionQuote,
        req,
        OptionQuoteResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)

    # Convert to structured format including option-specific data
    return to_namedtuple(resp.secu_quote)
end

function warrant_quote(ctx::QuoteContext, symbols::AbstractVector{<:AbstractString})
    req = MultiSecurityRequest(String[String(symbol) for symbol in symbols])
    cmd = GenericRequestCmd(
        QuoteCommand.QueryWarrantQuote,
        req,
        WarrantQuoteResponse,
        Channel(1),
    )
    resp = request(ctx, cmd)

    # Convert to structured format including warrant-specific data
    return DataFrame(to_namedtuple(resp.secu_quote))
end

"""
    us_crypto_overview(ctx, symbol) -> USCryptoOverview

Get the US-region cryptocurrency overview (for example `"BTCUSD.BKKT"`).
Requires credentials whose token/key prefix is `us_`.
"""
function us_crypto_overview(ctx::QuoteContext, symbol::AbstractString)
    params = Dict{String,Any}("counter_id" => symbol_to_counter_id(symbol))
    resp = Errors.ApiResponse(
        Client.http_get(
            ctx.inner.config,
            "/v1/us/gemini/crypto-overview";
            params,
            dc_region = :us,
        ),
    )
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    result = USProtocol.construct_us(USCryptoOverview, resp.data)
    return USProtocol.normalize_symbols!(result)
end

member_id(ctx::QuoteContext) = ctx.inner.member_id
quote_level(ctx::QuoteContext) = ctx.inner.quote_level

"""Return the account subscription limit, or `nothing` until profile loading completes."""
subscribe_limit(ctx::QuoteContext) = ctx.inner.subscribe_limit

"""Return the account history-candlestick limit, or `nothing` until profile loading completes."""
history_candlestick_limit(ctx::QuoteContext) = ctx.inner.history_candlestick_limit

quote_package_details(ctx::QuoteContext) = ctx.inner.quote_package_details

# --- Watchlist API ---

function watchlist(ctx::QuoteContext)
    """Get watchlist and return a DataFrame with id and name."""
    cmd = HttpGetCmd("/v1/watchlist/groups", Dict{String,Any}(), Channel(1))
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

function create_watchlist_group(
    ctx::QuoteContext,
    name::String;
    securities::Union{Nothing,Vector{String}} = nothing,
)
    """Create watchlist group"""
    body = Dict{String,Any}("name" => name)
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
    name::Union{Nothing,String} = nothing,  # 分组名称，例如 信息产业组 如果不传递此参数，则分组名称不会更新
    securities::Union{Nothing,Vector{String}} = nothing,   # 股票列表，例如 ["BABA.US","AAPL.US"] 配合下面的 mode 参数，可完成添加股票、移除股票、对关注列表进行排序等操作
    mode::SecuritiesUpdateMode.T = SecuritiesUpdateMode.Replace,   # 操作方法，可选值：add - 添加，remove - 移除，replace - 替换
)   # 选 add 时，将上面列表中的股票依序添加到此分组中，选 remove 时，将上面列表中的股票从此分组中移除，选 replace 时，将上面列表中的股票全量覆盖此分组下的股票假如原来分组中的股票为 APPL.US, BABA.US, TSLA.US，使用 ["BABA.US","AAPL.US","MSFT.US"] 更新后变为 ["BABA.US","AAPL.US","MSFT.US"]，对比之前，移除了 TSLA.US，添加了 MSFT.US，BABA.US,AAPL.US 调整了顺序
    """Update watchlist group"""
    body = Dict{String,Any}("id" => group_id)
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

function security_list(
    ctx::QuoteContext,
    market::Market.T,
    category::SecurityListCategory.T,
)
    """Get security list"""
    params = Dict{String,Any}("market" => string(market), "category" => string(category))
    cmd = HttpGetCmd("/v1/quote/get_security_list", params, Channel(1))
    resp = request(ctx, cmd)
    return DataFrame(to_namedtuple(resp.data.list))
end

# =============================================================================
# Realtime Data Access (from local store)
# =============================================================================

"""
    realtime_depth(ctx::QuoteContext, symbol::String) -> Union{Nothing, PushDepth}

Get real-time depth data from local cache for a subscribed symbol.
Returns `nothing` if no data is available (symbol not subscribed or no push received yet).
"""
function realtime_depth(ctx::QuoteContext, symbol::AbstractString)
    get_depth(ctx.inner.store, symbol)
end

"""
    realtime_brokers(ctx::QuoteContext, symbol::String) -> Union{Nothing, PushBrokers}

Get real-time broker queue data from local cache for a subscribed symbol.
Returns `nothing` if no data is available.
"""
function realtime_brokers(ctx::QuoteContext, symbol::AbstractString)
    get_brokers(ctx.inner.store, symbol)
end

"""
    realtime_trades(ctx::QuoteContext, symbol::String; count::Int=0) -> Vector{Trade}

Get real-time trade data from local cache for a subscribed symbol.

# Arguments
- `symbol::String`: Security symbol
- `count::Int=0`: Maximum number of trades to return (0 = all available)
"""
function realtime_trades(ctx::QuoteContext, symbol::AbstractString; count::Int = 0)
    get_trades(ctx.inner.store, symbol; count = count)
end

"""
    realtime_candlesticks(ctx::QuoteContext, symbol::String, period::CandlePeriod.T; count::Int=0) -> Vector{Candlestick}

Get real-time candlestick data from local cache for a subscribed symbol and period.

# Arguments
- `symbol::String`: Security symbol
- `period::CandlePeriod.T`: Candlestick period
- `count::Int=0`: Maximum number of candlesticks to return (0 = all available)
"""
function realtime_candlesticks(
    ctx::QuoteContext,
    symbol::AbstractString,
    period::CandlePeriod.T;
    count::Int = 0,
)
    get_candlesticks(ctx.inner.store, symbol, Int(period); count = count)
end

# =============================================================================
# Candlestick Subscription
# =============================================================================

"""
    subscribe_candlesticks(ctx::QuoteContext, symbol::String, period::CandlePeriod.T; count::Int=1000) -> Vector{Candlestick}

Subscribe to real-time candlestick updates for a symbol and period.
Returns initial candlestick data after subscribing.

# Arguments
- `symbol::String`: Security symbol (e.g., "700.HK")
- `period::CandlePeriod.T`: Candlestick period (e.g., CandlePeriod.DAY)
- `count::Int=1000`: Number of historical candlesticks to fetch initially

# Returns
- `Vector{Candlestick}`: Initial candlestick data
"""
function subscribe_candlesticks(
    ctx::QuoteContext,
    symbol::String,
    period::CandlePeriod.T;
    count::Int = 1000,
)
    # First subscribe to candlestick push events
    subscribe(ctx, [symbol], [SubType.QUOTE])  # Need quote subscription for candlestick updates

    # Fetch initial candlesticks
    initial_data =
        candlesticks(ctx, symbol, period, Int64(count); adjust_type = AdjustType.NO_ADJUST)

    # Convert DataFrame to Vector{Candlestick} and store
    candlestick_vec = Candlestick[]
    if nrow(initial_data) > 0
        for row in eachrow(initial_data)
            push!(
                candlestick_vec,
                Candlestick(
                    row.close,
                    row.open,
                    row.low,
                    row.high,
                    row.volume,
                    row.turnover,
                    row.timestamp isa DateTime ? Int64(datetime2unix(row.timestamp)) :
                    row.timestamp,
                    TradeSession.Intraday,
                ),
            )
        end
    end

    update_candlesticks!(ctx.inner.store, symbol, Int(period), candlestick_vec)

    return candlestick_vec
end

"""
    unsubscribe_candlesticks(ctx::QuoteContext, symbol::String, period::CandlePeriod.T)

Unsubscribe from real-time candlestick updates and clear cached data.
"""
function unsubscribe_candlesticks(ctx::QuoteContext, symbol::String, period::CandlePeriod.T)
    clear_candlesticks!(ctx.inner.store, symbol, Int(period))
end

function disconnect!(ctx::QuoteContext)
    inner = ctx.inner
    _request_shutdown!(inner)
    _wait_for_task(inner.background_task, "Quote background task")
    _wait_for_task(inner.push_dispatcher_task, "Quote push dispatcher")
    return
end

Base.close(ctx::QuoteContext) = disconnect!(ctx)

# ════════════════════════════════════════════════════════════════════════
# v4.1.0 新增 HTTP-only 方法（直接走 Client.http_get/post，不经后台任务）
# ════════════════════════════════════════════════════════════════════════


# ── short_positions ────────────────────────────────────────────────────

"""
做空数据中的一条记录（US 由 FINRA 双月公布；HK 由港交所公布）。
美股字段：`current_shares_short`、`avg_daily_share_volume`、`days_to_cover`。
港股字段：`amount`、`balance`、`cost`。共有字段：`timestamp`、`rate`、`close`。
所有数值字段在原始 API 中均为字符串（保留原样以避免精度损失）。
"""
struct ShortPositionsItem
    timestamp::DateTime               # 从 unix 秒转 DateTime (UTC)
    rate::String
    close::String
    # US
    current_shares_short::String
    avg_daily_share_volume::String
    days_to_cover::String
    # HK
    amount::String
    balance::String
    cost::String
end
function construct(::Type{ShortPositionsItem}, obj::JSONObject)
    ts_raw = get(obj, :timestamp, 0)
    ts_int = ts_raw isa AbstractString ? parse(Int64, ts_raw) : Int64(ts_raw)
    ShortPositionsItem(
        unix2datetime(ts_int),
        String(get(obj, :rate, "")),
        String(get(obj, :close, "")),
        String(get(obj, :current_shares_short, "")),
        String(get(obj, :avg_daily_share_volume, "")),
        String(get(obj, :days_to_cover, "")),
        String(get(obj, :amount, "")),
        String(get(obj, :balance, "")),
        String(get(obj, :cost, "")),
    )
end

struct ShortPositionsResponse
    data::Vector{ShortPositionsItem}
end
function construct(::Type{ShortPositionsResponse}, obj::JSONObject)
    items = if haskey(obj, :data) && !isnothing(obj.data)
        [construct(ShortPositionsItem, x) for x in obj.data]
    else
        ShortPositionsItem[]
    end
    ShortPositionsResponse(items)
end

"""
    short_positions(ctx::QuoteContext, symbol::AbstractString; count::Integer=20) -> ShortPositionsResponse

做空数据，US/HK 通用——根据 `symbol` 后缀自动选择端点：
- `.HK` → `GET /v1/quote/short-positions/hk`
- 其它 → `GET /v1/quote/short-positions/us`

`count` 为返回记录条数（1–100，默认 20）。
"""
function short_positions(ctx::QuoteContext, symbol::AbstractString; count::Integer = 20)
    sym = String(symbol)
    path =
        endswith(uppercase(sym), ".HK") ? "/v1/quote/short-positions/hk" :
        "/v1/quote/short-positions/us"
    ts = string(round(Int64, datetime2unix(now(UTC))))
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(sym),
        "last_timestamp" => ts,
        "count" => Int(count),
    )
    resp = Errors.ApiResponse(Client.http_get(ctx.inner.config, path; params))
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    construct(ShortPositionsResponse, resp.data)
end

# ── short_trades ───────────────────────────────────────────────────────

"""
做空成交数据中的一条记录。
美股字段：`nus_amount`、`ny_amount`、`total_amount`。
港股字段：`amount`、`balance`。共有字段：`timestamp`、`rate`、`close`。
"""
struct ShortTradesItem
    timestamp::DateTime
    rate::String
    close::String
    # US
    nus_amount::String
    ny_amount::String
    total_amount::String
    # HK
    amount::String
    balance::String
end
function construct(::Type{ShortTradesItem}, obj::JSONObject)
    ts_raw = get(obj, :timestamp, 0)
    ts_int = ts_raw isa AbstractString ? parse(Int64, ts_raw) : Int64(ts_raw)
    ShortTradesItem(
        unix2datetime(ts_int),
        String(get(obj, :rate, "")),
        String(get(obj, :close, "")),
        String(get(obj, :nus_amount, "")),
        String(get(obj, :ny_amount, "")),
        String(get(obj, :total_amount, "")),
        String(get(obj, :amount, "")),
        String(get(obj, :balance, "")),
    )
end

struct ShortTradesResponse
    data::Vector{ShortTradesItem}
end
function construct(::Type{ShortTradesResponse}, obj::JSONObject)
    items = if haskey(obj, :data) && !isnothing(obj.data)
        [construct(ShortTradesItem, x) for x in obj.data]
    else
        ShortTradesItem[]
    end
    ShortTradesResponse(items)
end

"""
    short_trades(ctx::QuoteContext, symbol::AbstractString; count::Integer=20) -> ShortTradesResponse

做空成交数据，US/HK 通用——根据 `symbol` 后缀自动选择端点：
- `.HK` → `GET /v1/quote/short-trades/hk`
- 其它 → `GET /v1/quote/short-trades/us`
"""
function short_trades(ctx::QuoteContext, symbol::AbstractString; count::Integer = 20)
    sym = String(symbol)
    path =
        endswith(uppercase(sym), ".HK") ? "/v1/quote/short-trades/hk" :
        "/v1/quote/short-trades/us"
    ts = string(round(Int64, datetime2unix(now(UTC))))
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(sym),
        "last_timestamp" => ts,
        "page_size" => string(Int(count)),
    )
    resp = Errors.ApiResponse(Client.http_get(ctx.inner.config, path; params))
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    construct(ShortTradesResponse, resp.data)
end

# ── option_volume ──────────────────────────────────────────────────────

"""
认购/认沽实时成交量统计。`c` 为 call 总量，`p` 为 put 总量（均为字符串）。
"""
struct OptionVolumeStats
    c::String
    p::String
end
function construct(::Type{OptionVolumeStats}, obj::JSONObject)
    OptionVolumeStats(String(get(obj, :c, "")), String(get(obj, :p, "")))
end

"""
    option_volume(ctx::QuoteContext, symbol) -> OptionVolumeStats

某标的的实时期权认购/认沽成交量。

端点：`GET /v1/quote/option-volume-stats`（query 参数名是 `underlying_counter_id`）
"""
function option_volume(ctx::QuoteContext, symbol::AbstractString)
    params = Dict{String,Any}("underlying_counter_id" => symbol_to_counter_id(symbol))
    resp = Errors.ApiResponse(
        Client.http_get(ctx.inner.config, "/v1/quote/option-volume-stats"; params),
    )
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    construct(OptionVolumeStats, resp.data)
end

# ── option_volume_daily ────────────────────────────────────────────────

"""
某一日的期权成交统计（含 call/put 量、未平仓量及比率），所有数值字段在 API 中为字符串。
"""
struct OptionVolumeDailyStat
    symbol::String                     # 由 underlying_counter_id 转换
    timestamp::String
    total_volume::String
    total_put_volume::String
    total_call_volume::String
    put_call_volume_ratio::String
    total_open_interest::String
    total_put_open_interest::String
    total_call_open_interest::String
    put_call_open_interest_ratio::String
end
function construct(::Type{OptionVolumeDailyStat}, obj::JSONObject)
    OptionVolumeDailyStat(
        counter_id_to_symbol(String(get(obj, :underlying_counter_id, ""))),
        String(get(obj, :timestamp, "")),
        String(get(obj, :total_volume, "")),
        String(get(obj, :total_put_volume, "")),
        String(get(obj, :total_call_volume, "")),
        String(get(obj, :put_call_volume_ratio, "")),
        String(get(obj, :total_open_interest, "")),
        String(get(obj, :total_put_open_interest, "")),
        String(get(obj, :total_call_open_interest, "")),
        String(get(obj, :put_call_open_interest_ratio, "")),
    )
end

struct OptionVolumeDaily
    stats::Vector{OptionVolumeDailyStat}
end
function construct(::Type{OptionVolumeDaily}, obj::JSONObject)
    items = if haskey(obj, :stats) && !isnothing(obj.stats)
        [construct(OptionVolumeDailyStat, x) for x in obj.stats]
    else
        OptionVolumeDailyStat[]
    end
    OptionVolumeDaily(items)
end

"""
    option_volume_daily(ctx::QuoteContext, symbol, timestamp::Integer, count::Integer) -> OptionVolumeDaily

历史日度期权成交统计。`timestamp` 是 unix 起始秒数；`count` 是要拿的日数（作为 `line_num`，方向固定向后）。

端点：`GET /v1/quote/option-volume-stats/daily`
"""
function option_volume_daily(
    ctx::QuoteContext,
    symbol::AbstractString,
    timestamp::Integer,
    count::Integer,
)
    params = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "timestamp" => Int64(timestamp),
        "line_num" => Int(count),
        "direction" => 1,
    )
    resp = Errors.ApiResponse(
        Client.http_get(ctx.inner.config, "/v1/quote/option-volume-stats/daily"; params),
    )
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    construct(OptionVolumeDaily, resp.data)
end

# ── update_pinned ──────────────────────────────────────────────────────

@enumx PinnedMode begin
    Add = 1   # 置顶
    Remove = 2   # 取消置顶
end

_pinned_mode_str(m::PinnedMode.T) =
    m === PinnedMode.Add ? "add" :
    m === PinnedMode.Remove ? "remove" : error("unknown PinnedMode: $m")

"""
    update_pinned(ctx::QuoteContext, mode::PinnedMode.T, symbols::Vector{String})

把指定证券置顶（或取消置顶）到自选股分组顶部。

端点：`POST /v1/watchlist/pinned`
"""
function update_pinned(
    ctx::QuoteContext,
    mode::PinnedMode.T,
    symbols::AbstractVector{<:AbstractString},
)
    body = Dict{String,Any}(
        "mode" => _pinned_mode_str(mode),
        "securities" => String[String(symbol) for symbol in symbols],
    )
    resp =
        Errors.ApiResponse(Client.http_post(ctx.inner.config, "/v1/watchlist/pinned"; body))
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    return nothing
end

export ShortPositionsItem,
    ShortPositionsResponse,
    ShortTradesItem,
    ShortTradesResponse,
    OptionVolumeStats,
    OptionVolumeDailyStat,
    OptionVolumeDaily,
    PinnedMode,
    short_positions,
    short_trades,
    option_volume,
    option_volume_daily,
    update_pinned

# ── filings ────────────────────────────────────────────────────────────

"""
公司公告（filings）单条记录。
"""
struct FilingItem
    id::String
    title::String
    description::String
    file_name::String
    file_urls::Vector{String}
    published_at::DateTime          # converted from unix seconds (publish_at)
end
function construct(::Type{FilingItem}, obj::JSONObject)
    urls = if haskey(obj, :file_urls) && !isnothing(obj.file_urls)
        [String(u) for u in obj.file_urls]
    else
        String[]
    end
    ts = get(obj, :publish_at, 0)
    ts_int = ts isa AbstractString ? parse(Int64, ts) : Int64(ts)
    FilingItem(
        String(get(obj, :id, "")),
        String(get(obj, :title, "")),
        String(get(obj, :description, "")),
        String(get(obj, :file_name, "")),
        urls,
        unix2datetime(ts_int),
    )
end

"""
    filings(ctx::QuoteContext, symbol::AbstractString) -> Vector{FilingItem}

公司公告列表（REST）。

端点：`GET /v1/quote/filings`
"""
function filings(ctx::QuoteContext, symbol::AbstractString)
    params = Dict{String,Any}("symbol" => String(symbol))
    resp =
        Errors.ApiResponse(Client.http_get(ctx.inner.config, "/v1/quote/filings"; params))
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    items_obj = haskey(resp.data, :items) ? resp.data.items : ()
    return [construct(FilingItem, x) for x in items_obj]
end

# ── symbol_to_counter_ids / resolve_counter_ids ─────────────────────

function _string_dict(obj)
    d = Dict{String,String}()
    if obj isa AbstractDict
        for (k, v) in pairs(obj)
            d[String(k)] = isnothing(v) ? "" : String(v)
        end
    end
    d
end

"""
    symbol_to_counter_ids(ctx::QuoteContext, symbols) -> Dict{String,String}

Batch convert symbols to counter IDs via `POST /v1/quote/symbol-to-counter-ids`.
Symbols not recognized by the backend are omitted from the returned dictionary.
"""
function symbol_to_counter_ids(ctx::QuoteContext, symbols::AbstractVector{<:AbstractString})
    isempty(symbols) && return Dict{String,String}()
    body = Dict{String,Any}("ticker_regions" => String[String(s) for s in symbols])
    resp = Errors.ApiResponse(
        Client.http_post(ctx.inner.config, "/v1/quote/symbol-to-counter-ids"; body),
    )
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    return _string_dict(get(resp.data, :list, nothing))
end

"""
    resolve_counter_ids(ctx::QuoteContext, symbols) -> Dict{String,String}

Resolve symbols local-first using embedded ETF/index/warrant directories and
the local counter cache. Unknown symbols are resolved in one remote batch and
the returned counter IDs are cached for future local lookups. Symbols still
unknown after the remote call fall back to the default `ST/...` conversion.
"""
function resolve_counter_ids(ctx::QuoteContext, symbols::AbstractVector{<:AbstractString})
    result = Dict{String,String}()
    unknown = String[]
    for sym in symbols
        symbol = String(sym)
        cid = lookup_counter_id(symbol)
        if isnothing(cid)
            push!(unknown, symbol)
        else
            result[symbol] = cid
        end
    end

    if !isempty(unknown)
        resolved = symbol_to_counter_ids(ctx, unknown)
        cache_counter_ids(values(resolved))
        for symbol in unknown
            result[symbol] = get(resolved, symbol, symbol_to_counter_id(symbol))
        end
    end

    return result
end

end # module Quote
