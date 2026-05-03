module QuotePush

    using ..QuoteProtocol: PushQuote, PushDepth, PushBrokers, PushTrade, Candlestick
    using ..Utils: to_namedtuple

    export PushEvent, PushEventDetail, handle_push_event, Callbacks, handle_quote, handle_depth,
           handle_brokers, handle_trades, handle_candlestick

    """
    Push event detail types - matching Python SDK
    """
    @enum PushEventDetail begin
        QuoteEvent = 1
        DepthEvent = 2
        BrokersEvent = 3
        TradeEvent = 4
        CandlestickEvent = 5
    end

    """
    Push event containing symbol and event details
    """
    struct PushEvent{T}
        symbol::String
        detail_type::PushEventDetail
        data::T
    end

    """
    Callback functions structure - matching Python SDK Callbacks
    Note: Using Union{Function, Nothing} is acceptable here since callbacks are
    set once and called via invokelatest, containing any type instability.
    """
    mutable struct Callbacks
        realtime_quote::Union{Function, Nothing}
        depth::Union{Function, Nothing}
        brokers::Union{Function, Nothing}
        trades::Union{Function, Nothing}
        candlestick::Union{Function, Nothing}

        Callbacks() = new(nothing, nothing, nothing, nothing, nothing)
    end

    """
    Handle push event - main dispatch function matching Python SDK handle_push_event
    """
    function handle_push_event(callbacks::Callbacks, event::PushEvent)
        try
            if event.detail_type == QuoteEvent
                handle_quote(callbacks, event.symbol, event.data)
            elseif event.detail_type == DepthEvent
                handle_depth(callbacks, event.symbol, event.data)
            elseif event.detail_type == BrokersEvent
                handle_brokers(callbacks, event.symbol, event.data)
            elseif event.detail_type == TradeEvent
                handle_trades(callbacks, event.symbol, event.data)
            elseif event.detail_type == CandlestickEvent
                handle_candlestick(callbacks, event.symbol, event.data)
            end
        catch e
            @error "Error handling push event" symbol=event.symbol detail_type=event.detail_type exception=e
        end
    end

    """
    Handle Quote push event - matching Python SDK handle_Quote
    """
    function handle_quote(callbacks::Callbacks, symbol::String, quote_data::PushQuote)
        if !isnothing(callbacks.realtime_quote)
            try
                Base.invokelatest(callbacks.realtime_quote, symbol, quote_data)
            catch e
                @error "Error in Quote callback" symbol=symbol exception=e
            end
        end
    end

    """
    Handle depth push event - matching Python SDK handle_depth
    """
    function handle_depth(callbacks::Callbacks, symbol::String, depth::PushDepth)
        if !isnothing(callbacks.depth)
            try
                Base.invokelatest(callbacks.depth, symbol, depth)
            catch e
                @error "Error in depth callback" symbol=symbol exception=e
            end
        end
    end

    """
    Handle brokers push event - matching Python SDK handle_brokers
    """
    function handle_brokers(callbacks::Callbacks, symbol::String, brokers::PushBrokers)
        if !isnothing(callbacks.brokers)
            try
                Base.invokelatest(callbacks.brokers, symbol, brokers)
            catch e
                @error "Error in brokers callback" symbol=symbol exception=e
            end
        end
    end

    """
    Handle trades push event - matching Python SDK handle_trades
    """
    function handle_trades(callbacks::Callbacks, symbol::String, trades::PushTrade)
        if !isnothing(callbacks.trades)
            try
                Base.invokelatest(callbacks.trades, symbol, trades)
            catch e
                @error "Error in trades callback" symbol=symbol exception=e
            end
        end
    end

    """
    Handle candlestick push event.

    Note: the server-side push pipeline for candlestick events is not yet wired
    in this SDK (no PushCandlestickData command code is decoded). The hook is
    provided so user code that registers a callback compiles, and so future
    integration only needs to call `handle_candlestick` from the dispatcher.
    """
    function handle_candlestick(callbacks::Callbacks, symbol::String, candle::Candlestick)
        if !isnothing(callbacks.candlestick)
            try
                Base.invokelatest(callbacks.candlestick, symbol, candle)
            catch e
                @error "Error in candlestick callback" symbol=symbol exception=e
            end
        end
    end

    set_on_quote!(callbacks::Callbacks, callback) = (callbacks.realtime_quote = callback; callbacks)
    set_on_depth!(callbacks::Callbacks, callback) = (callbacks.depth = callback; callbacks)
    set_on_brokers!(callbacks::Callbacks, callback) = (callbacks.brokers = callback; callbacks)
    set_on_trades!(callbacks::Callbacks, callback) = (callbacks.trades = callback; callbacks)
    set_on_candlestick!(callbacks::Callbacks, callback) = (callbacks.candlestick = callback; callbacks)

end # module QuotePush
