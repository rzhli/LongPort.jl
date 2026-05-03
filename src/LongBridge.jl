module LongBridge

    using TOML, Dates
    using PrecompileTools: @setup_workload, @compile_workload

    # Version
    const VERSION = TOML.parsefile(joinpath(pkgdir(@__MODULE__), "Project.toml"))["version"]

    # Forward declaration for multi-dispatch across modules
    function disconnect! end

    # Core Modules
    include("Core/Constant.jl")
    include("Core/Errors.jl")
    include("Core/Utils.jl")
    include("Core/Cache.jl")
    include("Core/Commands.jl")
    include("Core/ControlProtocol.jl")
    include("Core/QuoteProtocol.jl")
    include("Core/TradeProtocol.jl")
    include("OAuth.jl")
    include("Config.jl")
    include("Client.jl")

    include("Quote/QuotePush.jl")
    include("Quote/Quote.jl")
    include("Trade/TradePush.jl")
    include("Trade/Trade.jl")

    using .Constant: Market, Currency
    using .ControlProtocol
    using .QuoteProtocol
    using .TradeProtocol
    using .Commands
    using .Cache
    using .OAuth
    using .Config
    using .Errors
    using .Client
    using .TradePush
    using .Trade
    using .QuotePush
    using .Quote

    #= ==================== Exports ==================== =#

    # --- Module & Core ---
    export Quote, Trade, Config,
           disconnect!,                                     # 断开连接
           VERSION

    # --- Config ---
    export Settings, config, from_oauth                        # 配置加载（config 是 Settings 的兼容别名）

    # --- OAuth ---
    export OAuthBuilder, OAuthHandle, OAuthToken, build

    # --- Constant (Enums) ---
    export Market, Currency

    # --- QuoteProtocol (行情协议) ---
    # Push 结构体
    export PushQuote, PushDepth, PushBrokers, PushTrade
    # 枚举类型
    export SubType, CandlePeriod, AdjustType, Direction,
           TradeSession, Granularity,
           WarrantSortBy, SortOrderType,
           SecuritiesUpdateMode, SecurityListCategory

    # --- Quote (行情模块) ---
    # Context
    export QuoteContext
    # 订阅管理
    export subscribe, unsubscribe, subscriptions,
           set_on_quote, set_on_depth, set_on_brokers, set_on_trades, set_on_candlestick
    # 实时行情
    export realtime_quote, static_info, depth, brokers, trades, intraday
    # 实时数据访问 (从本地缓存)
    export realtime_depth, realtime_brokers, realtime_trades, realtime_candlesticks
    # K线数据
    export candlesticks, history_candlesticks_by_offset, history_candlesticks_by_date
    # K线订阅
    export subscribe_candlesticks, unsubscribe_candlesticks
    # 期权
    export option_quote, option_chain_expiry_date_list, option_chain_info_by_date,
           option_chain_dates, option_chain_strikes
    # 窝轮
    export warrant_quote, warrant_list, warrant_issuers, warrant_filter
    # 市场信息
    export trading_session, trading_days, participants, member_id, quote_level, security_list
    # 资金流
    export capital_flow, capital_distribution, calc_indexes
    # 市场温度
    export market_temperature, history_market_temperature
    # 自选股
    export watchlist, create_watchlist_group, delete_watchlist_group, update_watchlist_group

    # --- TradeProtocol (交易协议) ---
    # Options 结构体
    export GetHistoryExecutionsOptions, GetTodayExecutionsOptions, EstimateMaxPurchaseQuantityOptions,
           GetHistoryOrdersOptions, ReplaceOrderOptions, SubmitOrderOptions, GetTodayOrdersOptions
    # 枚举类型
    export OrderType, OrderSide, OrderStatus, TimeInForceType, TopicType

    # --- Trade (交易模块) ---
    # Context
    export TradeContext
    # 订单操作
    export submit_order, replace_order, cancel_order, order_detail
    # 订单查询
    export today_orders, history_orders, today_executions, history_executions
    # 账户信息
    export account_balance, cash_flow, stock_positions, fund_positions,
           margin_ratio, estimate_max_purchase_quantity
    # 推送
    export set_on_order_changed

    # ==================== Precompile workload ====================
    # Force compilation of the most-used construction paths so a fresh REPL
    # session can hit the network within the first second instead of paying
    # several seconds of inference on the first call.
    @setup_workload begin
        @compile_workload begin
            # Config: both auth modes — exercises the constructor + alias.
            cfg = Config.Settings(
                "k", "s", "t", DateTime(2099, 1, 1);
                http_url = "https://example.test",
                quote_ws_url = "wss://example.test",
                trade_ws_url = "wss://example.test",
            )
            cfg.auth_mode = :apikey

            # OAuth: build a handle without doing real auth.
            tok = OAuth.OAuthToken("k", "a", nothing, UInt64(0))
            OAuth.is_expired(tok)
            OAuth.expires_soon(tok)

            # Errors path
            try
                throw(Errors.LongBridgeError(0, "warm"))
            catch
            end
        end
    end

end # module LongBridge
