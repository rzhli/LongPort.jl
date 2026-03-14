[English](./README.md) | [中文](./README.zh-CN.md)

# Julia SDK for LongBridge API
非官方，目前仅自用，交易（Trade）模块某些函数暂未测试，欢迎提issue

## 更新日志
详细更新说明请见 [NEWS.md](NEWS.md)。

参考文档：

1. [官方文档](https://open.longportapp.com/zh-CN/docs)

2. [OpenAPI SDK Base](https://github.com/longportapp/openapi)

## 快速开始

### 安装

```julia
using Pkg
Pkg.add(url="https://github.com/rzhli/LongBridge.jl")
```

### 认证

LongBridge 支持两种认证方式：

#### 1. OAuth 2.0（推荐）

OAuth 2.0 使用 Bearer Token，无需 HMAC 签名。Token 自动持久化到本地并自动刷新。

**第一步：注册 OAuth 客户端**

```bash
curl -X POST https://openapi.longbridgeapp.com/oauth2/register \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "My Application",
    "redirect_uris": ["http://localhost:60355/callback"],
    "grant_types": ["authorization_code", "refresh_token"]
  }'
```

**第二步：构建 OAuth 句柄并创建配置**

```julia
using LongBridge

oauth = OAuthBuilder("your-client-id") |> build(url -> run(`xdg-open $url`))
cfg = Config.from_oauth(oauth)
```

首次运行时会打开浏览器进行授权，后续运行自动使用缓存的 Token。

#### 2. API Key（传统方式）

创建 `config.toml` 文件：

```toml
# 必填项
app_key = "your_app_key"
app_secret = "your_app_secret"
access_token = "your_access_token"
token_expire_time = "2025-07-22T00:00:00"  # ISO8601格式，UTC时间

# 可选项（不填使用默认值，默认为中国大陆节点）
# http_url = "https://openapi.longportapp.com"
# quote_ws_url = "wss://openapi-quote.longportapp.com"
# trade_ws_url = "wss://openapi-trade.longportapp.com"
```

```julia
using LongBridge

cfg = Config.from_toml()
```

### 行情

```julia
using LongBridge

cfg = Config.from_toml()

# 创建并连接 QuoteContext
ctx = QuoteContext(cfg)

# 获取标的基础信息
resp = static_info(ctx, ["700.HK", "AAPL.US", "TSLA.US"])

# 获取标的实时行情
quotes = realtime_quote(ctx, ["GOOGL.US", "AAPL.US", "TSLA.US"])

# 获取期权实时行情
resp = option_quote(ctx, ["AAPL230317P160000.US"])

# 获取轮证实时行情
resp = warrant_quote(ctx, ["14993.HK", "66642.HK"])

# 获取标的盘口
resp = depth(ctx, "700.HK")

# 获取K线数据
candlesticks_data = candlesticks(ctx, "GOOGL.US", CandlePeriod.SIXTY_MINUTE, 365)

# 获取标的成交明细
trades_data = trades(ctx, "AAPL.US", 10)

# 获取标的当日分时
intraday_data = intraday(ctx, "700.HK")

# 获取标的历史 K 线
using Dates
history_data = history_candlesticks_by_date(
    ctx, "700.HK", CandlePeriod.DAY, AdjustType.NO_ADJUST; start_date=Date(2023, 1, 1), end_date=Date(2023, 2, 1)
)

# 获取标的的期权链到期日列表
expiry_dates = option_chain_expiry_date_list(ctx, "AAPL.US")

# 获取市场交易日
trading_days_df = trading_days(ctx, Market.HK, Date(2025, 8, 1), Date(2025, 8, 30))

# 获取标的当日资金流向
capital_flow_data = capital_flow(ctx, "700.HK")

# 获取市场温度
temp = market_temperature(ctx, Market.US)

# 获取历史市场温度
history_temp = history_market_temperature(ctx, Market.US, Date(2025, 7, 1), Date(2025, 7, 31))

# 断开连接
disconnect!(ctx)
```

### 交易

```julia
using LongBridge

cfg = Config.from_toml()

# 创建并连接 TradeContext
ctx = TradeContext(cfg)

# 获取账户资金
resp = account_balance(ctx)

# 获取持仓
resp = stock_positions(ctx, ["700.HK"])

# 获取今日订单
resp = today_orders(ctx)

# 获取历史订单
resp = history_orders(ctx, "2023-01-01", "2023-02-01")

# 获取今日成交
resp = today_executions(ctx)

# 获取历史成交
resp = history_executions(ctx, "2023-01-01", "2023-02-01")

# 下单
resp = submit_order(ctx, "700.HK", OrderType.LO, Side.Buy, 100, 300.0)

# 修改订单
resp = modify_order(ctx, "order_id", 100, 301.0)

# 撤单
resp = cancel_order(ctx, "order_id")

# 断开连接
disconnect!(ctx)
```

### 实时行情订阅

```julia
# 1. 定义回调函数
function on_quote_callback(symbol::String, event::PushQuote)
    println(symbol, event)
end

# 2. 设置回调
set_on_quote(ctx, on_quote_callback)

# 3. 订阅行情 (可选择不同类型: QUOTE, DEPTH, BROKERS, TRADE)
Quote.subscribe(ctx, ["GOOGL.US"], [SubType.DEPTH]; is_first_push=true)

# 4. 取消订阅
Quote.unsubscribe(ctx, ["GOOGL.US"], [SubType.QUOTE, SubType.DEPTH])
```

## API 概览

### 上下文管理
- `Config.from_toml()`: 从 `config.toml` 文件加载配置
- `Config.from_oauth(oauth_handle)`: 从 OAuth 句柄创建配置
- `OAuthBuilder(client_id) |> build(open_url_fn)`: 构建 OAuth 句柄，通过浏览器进行授权
- `QuoteContext(config)`: 创建并连接 `QuoteContext`
- `TradeContext(config)`: 创建并连接 `TradeContext`
- `disconnect!(ctx)`: 断开与服务器的连接

### 行情拉取
- `static_info(ctx, symbols)`: 获取标的基础信息
- `realtime_quote(ctx, symbols)`: 获取股票实时行情
- `option_quote(ctx, symbols)`: 获取期权实时行情
- `warrant_quote(ctx, symbols)`: 获取轮证实时行情
- `depth(ctx, symbol)`: 获取标的盘口数据
- `brokers(ctx, symbol)`: 获取标的经纪队列
- `participants(ctx)`: 获取券商席位 ID 列表
- `trades(ctx, symbol, count)`: 获取标的成交明细
- `intraday(ctx, symbol)`: 获取标的当日分时数据
- `history_candlesticks_by_date(ctx, ...)`: 按日期获取历史 K 线
- `option_chain_expiry_date_list(ctx, symbol)`: 获取期权链到期日列表
- `warrant_issuers(ctx)`: 获取轮证发行商 ID 列表
- `warrant_list(ctx, ...)`: 获取轮证筛选列表
- `trading_session(ctx)`: 获取各市场当日交易时段
- `trading_days(ctx, market, start_date, end_date)`: 获取市场交易日
- `capital_flow(ctx, symbol)`: 获取标的当日资金流向
- `capital_distribution(ctx, symbol)`: 获取标的当日资金分布
- `candlesticks(ctx, symbol, period, count)`: 获取 K 线数据
- `history_candlesticks_by_offset(ctx, ...)`: 按偏移量获取历史 K 线
- `option_chain_info_by_date(ctx, symbol, expiry_date)`: 获取指定到期日的期权链信息
- `subscriptions(ctx)`: 查询当前已订阅的标的
- `calc_indexes(ctx, symbols)`: 获取计算指标
- `market_temperature(ctx, market)`: 获取市场温度
- `history_market_temperature(ctx, market, start_date, end_date)`: 获取历史市场温度
- `security_list(ctx, market, category)`: 获取标的列表

### 实时行情订阅
- `set_on_quote(ctx, callback)`: 设置行情推送的回调函数
- `set_on_depth(ctx, callback)`: 设置盘口推送的回调函数
- `set_on_brokers(ctx, callback)`: 设置经纪队列推送的回调函数
- `set_on_trades(ctx, callback)`: 设置成交明细推送的回调函数
- `subscribe(ctx, symbols, sub_types)`: 订阅行情
- `unsubscribe(ctx, symbols, sub_types)`: 取消订阅

### 实时数据访问（本地缓存）
- `realtime_depth(ctx, symbol)`: 获取已订阅标的的缓存盘口数据
- `realtime_brokers(ctx, symbol)`: 获取已订阅标的的缓存经纪队列
- `realtime_trades(ctx, symbol; count)`: 获取已订阅标的的缓存成交明细
- `realtime_candlesticks(ctx, symbol, period; count)`: 获取缓存的 K 线数据

### K 线订阅
- `subscribe_candlesticks(ctx, symbol, period; count)`: 订阅并获取初始 K 线数据
- `unsubscribe_candlesticks(ctx, symbol, period)`: 取消订阅并清除缓存

### 自选股管理
- `create_watchlist_group(ctx, name; securities)`: 创建自选股分组
- `watchlist(ctx)`: 查看自选股分组
- `delete_watchlist_group(ctx, group_id, with_securities)`: 删除自选股
- `update_watchlist_group(ctx, group_id; name, securities, mode)`: 更新自选股分组

### 交易
- `account_balance(ctx)`: 获取账户资金
- `stock_positions(ctx, symbols)`: 获取持仓
- `today_orders(ctx)`: 获取今日订单
- `history_orders(ctx, start_date, end_date)`: 获取历史订单
- `today_executions(ctx)`: 获取今日成交
- `history_executions(ctx, start_date, end_date)`: 获取历史成交
- `submit_order(ctx, symbol, order_type, side, quantity, price)`: 下单
- `modify_order(ctx, order_id, quantity, price)`: 修改订单
- `cancel_order(ctx, order_id)`: 撤单
- `set_on_order_changed(ctx, callback)`: 设置订单状态变化推送的回调函数
- `set_on_trade_changed(ctx, callback)`: 设置成交回报推送的回调函数
- `subscribe_trade(ctx, topics)`: 订阅交易推送
- `unsubscribe_trade(ctx, topics)`: 取消订阅交易推送

## 许可证

MIT License
