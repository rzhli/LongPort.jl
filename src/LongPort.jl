__precompile__()
module LongPort

    using TOML, Dates
    # Core Modules
    include("Core/Constant.jl")
    include("Core/Errors.jl")
    include("Core/Utils.jl")
    include("Core/Cache.jl")
    include("Core/ControlProtocol.jl")
    include("Core/QuoteProtocol.jl")
    include("Core/TradeProtocol.jl")
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
    using .Cache
    using .Config
    using .Errors
    using .Client
    using .TradePush
    using .Trade
    using .QuotePush
    using .Quote

    export Quote, Trade, Config, disconnect!
    
           # Config 模块    Constant 模块    
    export config, Market, Currency 
           
           # QuoteProtocol模块
    export PushQuote, PushDepth, PushBrokers, PushTrade,                     # 结构体类型Struct
           SubType, CandlePeriod, AdjustType, Direction, WarrantSortBy, SortOrderType,     # 枚举类型Enums
           TradeSession, Granularity, SecuritiesUpdateMode, SecurityListCategory

           # Quote 模块
    export QuoteContext, subscriptions, realtime_quote,
           static_info, depth, brokers, trades, candlesticks,                       # 函数
           history_candlesticks_by_offset, history_candlesticks_by_date,
           option_chain_expiry_date_list, option_chain_info_by_date,
           warrant_list, trading_session, trading_days, 
           set_on_quote, set_on_depth, set_on_brokers, set_on_trades, set_on_candlestick,
           
           intraday, option_quote, warrant_quote, participants,
           option_chain_dates, option_chain_strikes, warrant_issuers, warrant_filter,
           capital_flow, capital_distribution, calc_indexes, market_temperature,
           history_market_temperature, member_id, quote_level,
           watchlist, create_watchlist_group, delete_watchlist_group, update_watchlist_group,  # 自选股
           security_list

           # TradeProtocol 模块       
    export GetHistoryExecutionsOptions, GetTodayExecutionsOptions, EstimateMaxPurchaseQuantityOptions,
           GetHistoryOrdersOptions, ReplaceOrderOptions, SubmitOrderOptions, GetTodayOrdersOptions,   # struct结构体          
           OrderType, OrderSide, OrderStatus, TimeInForceType, TopicType                              # enum枚举类型
           
           # Trade module
    export TradeContext, history_executions, today_executions, estimate_max_purchase_quantity,
           history_orders, order_detail, replace_order, submit_order, today_orders, cancel_order,
           set_on_order_changed, cash_flow, stock_positions, fund_positions, margin_ratio, account_balance

    const VERSION = TOML.parsefile(joinpath(pkgdir(@__MODULE__), "Project.toml"))["version"]

end # module LongPort
