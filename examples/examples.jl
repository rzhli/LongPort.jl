"""
LongBridge Julia SDK - Test Script
(Tests functions individually using the new Actor-based API)
"""

using LongBridge, Dates

# 1. Use OAuth 2.0 (Recommended)
# First  obtain client_id by:
#=  
  curl -X POST https://openapi.longbridgeapp.com/oauth2/register \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "My Application",
    "redirect_uris": ["http://localhost:60355/callback"],
    "grant_types": ["authorization_code", "refresh_token"]
  }'
=#
# Second build the OAuth handle (opens browser for authorization)
oauth = OAuthBuilder("your_client_id") |> build(url -> run(`xdg-open $url`))
cfg = Config.from_oauth(oauth)

# Or use the legacy Legacy API Key by loading config from TOML file
cfg = Config.from_toml()

# 行情

# Create and connect the QuoteContext
ctx = QuoteContext(cfg)

## 拉取  每次请求支持传入的标的数量上限是 500 个
### 获取标的基础信息 （DataFrame） 后面三个的 board = ""
@time resp = static_info(ctx, ["700.HK", "AAPL.US", "TSLA.US", "NFLX.US"])

### 获取股票实时行情 （DataFrame） （over_night_quote需开通美股LV1实时行情）
@time quotes = realtime_quote(ctx, ["GOOGL.US", "AAPL.US", "TSLA.US", "NFLX.US"])

### 获取期权实时行情 （需开通OPRA美股期权行情）
@time resp = option_quote(ctx, ["AAPL230317P160000.US"])

### 获取轮证实时行情 （DataFrame）
@time resp = warrant_quote(ctx, ["14993.HK", "66642.HK"])

### 获取标的盘口    （DataFrame）
@time depth_df = depth(ctx, "700.HK")

### 获取标的经纪队列 （返回空值）
@time resp = brokers(ctx, "700.HK")

### 获取券商席位 ID   （DataFrame）
@time resp = participants(ctx)

### 获取标的成交明细    (DataFrame)
@time resp = trades(ctx, "700.HK", 500)

### 获取标的当日分时（DataFrame格式）
@time resp = intraday(ctx, "AAPL.US")

# 获取标的历史K线（DataFrame格式）
#=
@enumx AdjustType begin
    NO_ADJUST = 0
    FORWARD_ADJUST = 1
end
=#

# after 2023-01-01
@time history_offset_data = history_candlesticks_by_offset(
    ctx, "700.HK", CandlePeriod.DAY, AdjustType.NO_ADJUST, Direction.FORWARD, 10; date=DateTime(2023, 1, 1)
)
# before 2023-01-01
@time history_offset_data = history_candlesticks_by_offset(
    ctx, "700.HK", CandlePeriod.FOUR_HOUR, AdjustType.NO_ADJUST, Direction.BACKWARD, 10; date = DateTime(2025, 1, 1)
)
# 2023-01-01 to 2023-02-01
@time history_date_data = history_candlesticks_by_date(ctx, "AAPL.US", CandlePeriod.ONE_MINUTE, AdjustType.NO_ADJUST; trade_sessions = TradeSession.Intraday)

### 获取标的的期权链到期日列表
@time expiry_date = option_chain_expiry_date_list(ctx, "AAPL.US")

### 获取标的的期权链到期日期权标的列表 (返回空值，需开通OPRA美股期权行情权限？)
@time info = option_chain_info_by_date(ctx, "AAPL.US", Date(2025, 8, 22))

### 获取轮证发行商ID （DataFrame）
@time resp = warrant_issuers(ctx)

### 获取轮证筛选列表  (DataFrame)
@time data, count = warrant_list(ctx, "700.HK", WarrantSortBy.LastDone, SortOrderType.Descending)

### 获取各市场当日交易时段  （DataFrame）
@time resp = trading_session(ctx)

### 获取市场交易日  （DataFrame）
@time resp = trading_days(ctx, Market.CN, Date(2026, 2, 1), Date(2026, 2,20))

### 获取标的当日资金流向(1分钟)  (DataFrame)
@time resp = capital_flow(ctx, "700.HK")

### 获取标的当日资金分布  (DataFrame)
@time resp = capital_distribution(ctx, "700.HK")

### 获取标的计算指标    (DataFrame)
@time resp = calc_indexes(ctx, ["700.HK", "AAPL.US"])

#=
@enumx CandlePeriod begin
    UNKNOWN_PERIOD = 0
    ONE_MINUTE = 1
    TWO_MINUTE = 2
    THREE_MINUTE = 3
    FIVE_MINUTE = 5
    TEN_MINUTE = 10
    FIFTEEN_MINUTE = 15
    TWENTY_MINUTE = 20
    THIRTY_MINUTE = 30
    FORTY_FIVE_MINUTE = 45
    SIXTY_MINUTE = 60
    TWO_HOUR = 120
    THREE_HOUR = 180
    FOUR_HOUR = 240
    DAY = 1000
    WEEK = 2000
    MONTH = 3000
    QUARTER = 3500
    YEAR = 4000
end
=#

### 获取标的K线     （DataFrame）
# 获取 "688041.SH" 的盘中 K 线
@time candlesticks_data = candlesticks(ctx, "688041.SH", CandlePeriod.DAY, 65; adjust_type = AdjustType.NO_ADJUST)
# 获取 700.HK 的所有 K 线  （TradeSession.All数字代码未知）
@time candlesticks_data = candlesticks(ctx, "700.HK", CandlePeriod.DAY, 1000; adjust_type = AdjustType.FORWARD_ADJUST, trade_sessions = TradeSession.All)
@time candlesticks_data = candlesticks(ctx, "700.HK", CandlePeriod.DAY, 100; trade_sessions = TradeSession.Intraday)

### 当前市场温度
@time resp = market_temperature(ctx, Market.CN)

### 获取历史市场温度（只有日数据，没有周，月数据）
@time type, list = history_market_temperature(ctx, Market.CN, Date(2025, 1, 1), Date(2025, 8, 1))


# 订阅

# 1. Define your callback functions
function on_quote_callback(symbol::String, event::PushQuote)
    china_time = unix2datetime(event.timestamp) + Hour(8)  # Convert UTC to China time (UTC+8)
    println("Quote: $symbol \n Last: $(event.last_done) Volume: $(event.volume) Turnover: $(event.turnover) Timestamp: $(china_time)")
end

function on_depth_callback(symbol::String, event::PushDepth)
    println("Depth: $symbol")
    for ask in event.ask
        println("  Ask: Position = $(ask.position), Price = $(ask.price), Volume = $(ask.volume), Orders = $(ask.order_num)")
    end
    for bid in event.bid
        println("  Bid: Position = $(bid.position), Price = $(bid.price), Volume = $(bid.volume), Orders = $(bid.order_num)")
    end
end

# 2. Set the callbacks
set_on_quote(ctx, on_quote_callback)
set_on_depth(ctx, on_depth_callback)

#= 3. Subscribe 行情订阅类型
@enumx SubType begin
    UNKNOWN_TYPE = 0
    QUOTE = 1
    DEPTH = 2
    BROKERS = 3
    TRADE = 4
end
=#

### 订阅行情数据  实时价格推送，实时盘口推送
@time Quote.subscribe(ctx, ["700.HK"], [SubType.QUOTE, SubType.DEPTH]; is_first_push=true)
### 取消订阅
Quote.unsubscribe(ctx, ["700.HK"], [SubType.QUOTE, SubType.DEPTH])

Quote.subscribe(ctx, ["601816.SH"], [SubType.QUOTE, SubType.DEPTH]; is_first_push=true)
Quote.unsubscribe(ctx, ["601816.SH"], [SubType.QUOTE, SubType.DEPTH])

### 获取当前订阅及订阅类型
subs = subscriptions(ctx)

### 实时经纪队列推送
function on_brokers_callback(symbol::String, event::PushBrokers)
    println("Brokers: $symbol")
    for ask in event.ask_brokers
        println("  Ask: Position = $(ask.position), BrokerIDs = $(ask.broker_ids)")
    end
    for bid in event.bid_brokers
        println("  Bid: Position = $(bid.position), BrokerIDs = $(bid.broker_ids)")
    end
end
set_on_brokers(ctx, on_brokers_callback)

Quote.subscribe(ctx, ["700.HK"], [SubType.BROKERS]; is_first_push=true)
Quote.unsubscribe(ctx, ["700.HK"], [SubType.BROKERS])

### 实时成交明细推送
function on_trades_callback(symbol::String, event::PushTrade)
    println("Trades: $symbol")
    for t in event.trade
        println("  Price: $(t.price), Volume: $(t.volume), Tradetype: $(t.trade_type), Direction: $(t.direction), Tradesession: $(t.trade_session)")
    end
end
set_on_trades(ctx, on_trades_callback)
Quote.subscribe(ctx, ["700.HK"], [SubType.TRADE]; is_first_push = true)
Quote.unsubscribe(ctx, ["700.HK"], [SubType.TRADE])

# 实时数据访问（本地缓存）
# 订阅后，推送数据会自动缓存到本地，可以通过以下方法访问

### 订阅行情数据
Quote.subscribe(ctx, ["700.HK"], [SubType.QUOTE, SubType.DEPTH, SubType.BROKERS, SubType.TRADE]; is_first_push=true)

# 等待一段时间让数据推送
sleep(2)

### 获取缓存的盘口数据
cached_depth = realtime_depth(ctx, "700.HK")
if !isnothing(cached_depth)
    println("Cached depth for 700.HK:")
    println("  Asks: ", length(cached_depth.ask), " levels")
    println("  Bids: ", length(cached_depth.bid), " levels")
end

### 获取缓存的经纪队列
cached_brokers = realtime_brokers(ctx, "700.HK")
if !isnothing(cached_brokers)
    println("Cached brokers for 700.HK:")
    println("  Ask brokers: ", length(cached_brokers.ask_brokers))
    println("  Bid brokers: ", length(cached_brokers.bid_brokers))
end

### 获取缓存的成交明细
cached_trades = realtime_trades(ctx, "700.HK"; count=10)
println("Cached trades for 700.HK: ", length(cached_trades), " trades")

Quote.unsubscribe(ctx, ["700.HK"], [SubType.QUOTE, SubType.DEPTH, SubType.BROKERS, SubType.TRADE])

# K线订阅
# 订阅K线数据，获取初始K线并自动缓存后续推送

### 订阅K线并获取初始数据
initial_candlesticks = subscribe_candlesticks(ctx, "700.HK", CandlePeriod.DAY; count=100)
println("Initial candlesticks: ", length(initial_candlesticks), " bars")

### 获取缓存的K线数据
cached_candlesticks = realtime_candlesticks(ctx, "700.HK", CandlePeriod.DAY; count=10)
println("Cached candlesticks: ", length(cached_candlesticks), " bars")

### 取消K线订阅并清除缓存
unsubscribe_candlesticks(ctx, "700.HK", CandlePeriod.DAY)

### 创建自选股分组
group_id = create_watchlist_group(ctx, "Watchlist1", securities = ["700.HK", "AAPL.US"])

### 查看自选股分组
@time resp = watchlist(ctx)

### 删除自选股
message = delete_watchlist_group(ctx, 4281496, true)

### 更新自选股
update_watchlist_group(ctx, 10086, name = "WatchList2", securities = ["700.HK", "AAPL.US"], mode = SecuritiesUpdateMode.Add)

### 获取标的列表（美股，只有中文名称name_cn）
@time resp = security_list(ctx, Market.US, SecurityListCategory.Overnight)

disconnect!(ctx)





# 交易
using LongBridge, Dates

# Load config from TOML file
cfg = Config.from_toml()

# Create and connect the TradeContext
ctx = TradeContext(cfg)

## 成交
### 获取历史成交明细
@time resp = history_executions(ctx; symbol = "700.HK", start_at = Date(2024, 5, 9), end_at = Date(2025, 5, 12))

### 获取当日成交明细
@time resp = today_executions(ctx; symbol = "700.HK")

## 订单
### 预估最大购买数量
@time resp = estimate_max_purchase_quantity(ctx, EstimateMaxPurchaseQuantityOptions(symbol = "700.HK", order_type = OrderType.LO, side = OrderSide.Buy))

### 委托下单,用于港美股，窝轮，期权的委托下单
# 限价单：  
@time resp = submit_order(
    ctx, SubmitOrderOptions(
        symbol = "700.HK",
        order_type = OrderType.LO,
        side = OrderSide.Buy,
        submitted_quantity = 100,
        time_in_force = TimeInForceType.Day,       # 表示订单当日有效
        submitted_price = 480.0         # 需传递submitted_price
    )
)

# 平仓卖出 
@time resp = submit_order(
    ctx, SubmitOrderOptions(
        symbol = "700.HK",
        order_type = OrderType.MO,      # 市价单
        side = OrderSide.Sell,
        submitted_quantity = 100,
        time_in_force = TimeInForceType.Day,    
        submitted_price = 380.0         # 需传递submitted_price
    )
)

# 到价止盈止损 
@time resp = submit_order(
    ctx, SubmitOrderOptions(
        symbol = "NVDA.US",
        order_type = OrderType.LIT,      # 挂单为触价限价单
        side = OrderSide.Sell,
        submitted_quantity = 100,
        time_in_force = TimeInForceType.GTC,    # 订单撤销前有效
        trigger_price = 1000.0,         # 当行情价格达到触发价格时，订单会被提交
        submitted_price = 999.0         # 以999.0元提交
    )
)

# 跟踪止盈止损 当挂出该条件单以后，如果NVDA.US的市价在下单后的最高点回落0.5%时，
# 比如最高点为1100USD，回落0.5%为1094.5USD，那么订单会以1094.5USD - 1.2 = 1093.3 USD的价格挂出限价单
@time resp = submit_order(
    ctx, SubmitOrderOptions(
        symbol = "NVDA.US",
        side = OrderSide.Sell,
        order_type = OrderType.TSLPPCT, # 挂单为跟踪止损限价单(跟踪涨跌幅)，如果想要使用跟踪金额，可以使用TSLPAMT，需填trailing_amount
        time_in_force = TimeInForceType.GTD,    # 订单到期前有效
        expire_date = "2025-10-30",    # 订单到期时间
        submitted_quantity = 100,
        trailing_percent = 0.5,    # 跟踪涨跌幅0.5表示0.5%
        limit_offset = 1.2,     # 指定价差，1.2 表示 1.2 USD，如果不需要指定价差，可以传递 0 或不传
    )
)

### 修改订单
@time resp = replace_order(
    ctx, ReplaceOrderOptions(
        order_id = "709043056541253632", 
        submitted_quantity = 100, 
        submitted_price = 50.0
    )
)

### 撤销订单
@time resp = cancel_order(ctx, "1200001443583500288")

### 获取当日订单
# 指定股票
@time resp = today_orders(
    ctx; symbol = "700.HK",
    status = [OrderStatus.FilledStatus, OrderStatus.NewStatus, OrderStatus.RejectedStatus],
    side = OrderSide.Buy
)
# 不指定股票
@time resp = today_orders(ctx)

### 获取历史订单
# 指定股票
@time resp = history_orders(
    ctx; symbol = "700.HK",
    status = [OrderStatus.FilledStatus, OrderStatus.NewStatus, OrderStatus.RejectedStatus],
    side = OrderSide.Buy, start_at = Date(2024, 5, 9), end_at = Date(2025, 10, 12)
)
# 不指定股票
@time resp = history_orders(ctx)

### 订单详情
@time resp = order_detail(ctx, "1138677649372094464")


## 交易推送
function on_order_changed(order_changed)
    println("Order changed: ", order_changed)
end

# Set order change callback
set_on_order_changed(ctx, on_order_changed)

### Subscribe to private topic
resp = Trade.subscribe(ctx, [TopicType.Private])

### unsubscribe
resp = Trade.unsubscribe(ctx, [TopicType.Private])


## 资产

### 获取账户资金， 用于获取用户每个币种可用、可取、冻结、待结算金额、在途资金 (基金申购赎回) 信息
@time resp = account_balance(ctx)

### 获取资金流水, 用于获取资金流入/流出方向、资金类别、资金金额、发生时间、关联股票代码和资金流水说明信息
@time resp = cash_flow(ctx; start_at = Date(2024, 5, 9), end_at = Date(2024, 5, 12))

### 获取基金持仓, 用于获取包括账户、基金代码、持有份额、成本净值、当前净值、币种在内的基金持仓信息
@time resp = fund_positions(ctx)

### 获取股票持仓, 用于获取包括账户、股票代码、持仓股数、可用股数、持仓均价（按账户设置计算均价方式）、币种在内的股票持仓信息
@time resp = stock_positions(ctx)

### 获取保证金比例, 用于获取股票初始保证金比例、维持保证金比例、强平保证金比例
@time resp = margin_ratio(ctx, "700.HK")

disconnect!(ctx)