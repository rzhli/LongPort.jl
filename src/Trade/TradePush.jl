"""
Trade Push Event Handler Module

参照Python SDK的trade push事件处理机制，提供完整的交易推送事件处理。
对应Python版本的python/src/trade/push.rs
"""
module TradePush

    using JSON3
    using ..TradeProtocol: Notification, PushOrderChanged, ContentType

    export Callbacks, set_on_order_changed!, handle_push_event!

    """
    回调函数存储结构
    """
    mutable struct Callbacks
        on_order_changed::Union{Function, Nothing}

        Callbacks() = new(nothing)
    end

    set_on_order_changed!(callbacks::Callbacks, callback) =
        (callbacks.on_order_changed = callback; callbacks)

    """
    处理推送事件 — 由 Trade.jl 的 ws.on_push 在收到 CMD_NOTIFY 时调用。

    服务器以 JSON 编码 PushOrderChanged 放在 Notification.data 中（content_type
    = CONTENT_JSON）。其它 content_type 暂不处理。
    """
    function handle_push_event!(cb::Callbacks, n::Notification)
        if n.topic != "private"
            @debug "忽略非 private topic 的 trade 推送" topic=n.topic
            return
        end

        if n.content_type == ContentType.CONTENT_JSON
            isnothing(cb.on_order_changed) && return
            try
                order = JSON3.read(String(n.data), PushOrderChanged)
                Base.invokelatest(cb.on_order_changed, order)
            catch e
                @error "订单变更回调函数执行失败" exception=(e, catch_backtrace())
            end
        else
            @debug "未支持的 trade 推送 content_type" n.content_type
        end
    end

end # module TradePush
