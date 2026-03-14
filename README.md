[English](./README.md) | [中文](./README.zh-CN.md)

# Julia SDK for LongBridge API
This is an unofficial SDK, currently for personal use only. Some functions in the Trade module have not been tested yet. Issues are welcome.

## Release Notes
See [NEWS.md](NEWS.md) for detailed release notes.

References:

1. [Official Documentation](https://open.longportapp.com/en/docs)

2. [OpenAPI SDK Base](https://github.com/longportapp/openapi)

### Configuration File

Create a `config.toml` file:

```toml
# Required
app_key = "your_app_key"
app_secret = "your_app_secret"
access_token = "your_access_token"
token_expire_time = "2025-07-22T00:00:00"  # ISO8601 format, UTC time

# Optional (uses China endpoints by default)
# http_url = "https://openapi.longportapp.com"
# quote_ws_url = "wss://openapi-quote.longportapp.com"
# trade_ws_url = "wss://openapi-trade.longportapp.com"
```

## Quick Start

### Installation

```julia
using Pkg
Pkg.add("LongBridge")
```

### Quotes

```julia
using LongBridge

# Load configuration from TOML file
cfg = Config.from_toml()

# Create and connect to QuoteContext
ctx = QuoteContext(cfg)

# Get basic static information for securities
resp = static_info(ctx, ["700.HK", "AAPL.US", "TSLA.US"])

# Get real-time quotes for securities
quotes = realtime_quote(ctx, ["GOOGL.US", "AAPL.US", "TSLA.US"])

# Get real-time option quotes
resp = option_quote(ctx, ["AAPL230317P160000.US"])

# Get real-time warrant quotes
resp = warrant_quote(ctx, ["14993.HK", "66642.HK"])

# Get market depth for a security
resp = depth(ctx, "700.HK")

# Get candlestick data
candlesticks_data = candlesticks(ctx, "GOOGL.US", CandlePeriod.SIXTY_MINUTE, 365)

# Get trade details for a security
trades_data = trades(ctx, "AAPL.US", 10)

# Get intraday data for a security
intraday_data = intraday(ctx, "700.HK")

# Get historical K-line data
using Dates
history_data = history_candlesticks_by_date(
    ctx, "700.HK", CandlePeriod.DAY, AdjustType.NO_ADJUST; start_date=Date(2023, 1, 1), end_date=Date(2023, 2, 1)
)

# Get the list of expiry dates for an option chain
expiry_dates = option_chain_expiry_date_list(ctx, "AAPL.US")

# Get trading days for a market
trading_days_df = trading_days(ctx, Market.HK, Date(2025, 8, 1), Date(2025, 8, 30))

# Get capital flow for a security
capital_flow_data = capital_flow(ctx, "700.HK")

# Get market temperature
temp = market_temperature(ctx, Market.US)

# Get historical market temperature
history_temp = history_market_temperature(ctx, Market.US, Date(2025, 7, 1), Date(2025, 7, 31))

# Disconnect
disconnect!(ctx)
```

### Trading

```julia
using LongBridge

# Load configuration from TOML file
cfg = Config.from_toml()

# Create and connect to TradeContext
ctx = TradeContext(cfg)

# Get account balance
resp = account_balance(ctx)

# Get stock positions
resp = stock_positions(ctx, ["700.HK"])

# Get today's orders
resp = today_orders(ctx)

# Get historical orders
resp = history_orders(ctx, "2023-01-01", "2023-02-01")

# Get today's executions
resp = today_executions(ctx)

# Get historical executions
resp = history_executions(ctx, "2023-01-01", "2023-02-01")

# Submit an order
resp = submit_order(ctx, "700.HK", OrderType.LO, Side.Buy, 100, 300.0)

# Modify an order
resp = modify_order(ctx, "order_id", 100, 301.0)

# Cancel an order
resp = cancel_order(ctx, "order_id")

# Disconnect
disconnect!(ctx)
```

### Real-time Quote Subscription

```julia
# 1. Define a callback function
function on_quote_callback(symbol::String, event::PushQuote)
    println(symbol, event)
end

# 2. Set the callback
set_on_quote(ctx, on_quote_callback)

# 3. Subscribe to quotes (can choose different types: QUOTE, DEPTH, BROKERS, TRADE)
Quote.subscribe(ctx, ["GOOGL.US"], [SubType.DEPTH]; is_first_push=true)

# 4. Unsubscribe from quotes
Quote.unsubscribe(ctx, ["GOOGL.US"], [SubType.QUOTE, SubType.DEPTH])
```

## API Overview

### Context Management
- `Config.from_toml()`: Load configuration from `config.toml` file
- `QuoteContext(config)`: Create and connect to `QuoteContext`
- `TradeContext(config)`: Create and connect to `TradeContext`
- `disconnect!(ctx)`: Disconnect from the server

### Quote Fetching
- `static_info(ctx, symbols)`: Get basic static information for securities
- `realtime_quote(ctx, symbols)`: Get real-time stock quotes
- `option_quote(ctx, symbols)`: Get real-time option quotes
- `warrant_quote(ctx, symbols)`: Get real-time warrant quotes
- `depth(ctx, symbol)`: Get market depth data for a security
- `brokers(ctx, symbol)`: Get broker queue for a security
- `participants(ctx)`: Get a list of broker seat IDs
- `trades(ctx, symbol, count)`: Get trade details for a security
- `intraday(ctx, symbol)`: Get intraday data for a security
- `history_candlesticks_by_date(ctx, ...)`: Get historical K-line data by date
- `option_chain_expiry_date_list(ctx, symbol)`: Get a list of expiry dates for an option chain
- `warrant_issuers(ctx)`: Get a list of warrant issuer IDs
- `warrant_list(ctx, ...)`: Get a filtered list of warrants
- `trading_session(ctx)`: Get the trading session for each market for the current day
- `trading_days(ctx, market, start_date, end_date)`: Get trading days for a market
- `capital_flow(ctx, symbol)`: Get capital flow for a security for the current day
- `capital_distribution(ctx, symbol)`: Get capital distribution for a security for the current day
- `candlesticks(ctx, symbol, period, count)`: Get candlestick data
- `history_candlesticks_by_offset(ctx, ...)`: Get historical K-line data by offset
- `option_chain_info_by_date(ctx, symbol, expiry_date)`: Get option chain information for a specific expiry date
- `subscriptions(ctx)`: Query currently subscribed securities
- `calc_indexes(ctx, symbols)`: Get calculated indexes
- `market_temperature(ctx, market)`: Get market temperature
- `history_market_temperature(ctx, market, start_date, end_date)`: Get historical market temperature
- `security_list(ctx, market, category)`: Get a list of securities

### Real-time Quote Subscription
- `set_on_quote(ctx, callback)`: Set the callback function for quote pushes
- `set_on_depth(ctx, callback)`: Set the callback function for market depth pushes
- `set_on_brokers(ctx, callback)`: Set the callback function for broker queue pushes
- `set_on_trades(ctx, callback)`: Set the callback function for trade detail pushes
- `subscribe(ctx, symbols, sub_types)`: Subscribe to quotes
- `unsubscribe(ctx, symbols, sub_types)`: Unsubscribe from quotes

### Realtime Data Access (Local Cache)
- `realtime_depth(ctx, symbol)`: Get cached depth data for subscribed symbol
- `realtime_brokers(ctx, symbol)`: Get cached broker queue for subscribed symbol
- `realtime_trades(ctx, symbol; count)`: Get cached trades for subscribed symbol
- `realtime_candlesticks(ctx, symbol, period; count)`: Get cached K-line data

### Candlestick Subscription
- `subscribe_candlesticks(ctx, symbol, period; count)`: Subscribe and get initial K-line data
- `unsubscribe_candlesticks(ctx, symbol, period)`: Unsubscribe and clear cached data

### Watchlist Management
- `create_watchlist_group(ctx, name; securities)`: Create a watchlist group
- `watchlist(ctx)`: View watchlist groups
- `delete_watchlist_group(ctx, group_id, with_securities)`: Delete a watchlist
- `update_watchlist_group(ctx, group_id; name, securities, mode)`: Update a watchlist group

### Trading
- `account_balance(ctx)`: Get account balance
- `stock_positions(ctx, symbols)`: Get stock positions
- `today_orders(ctx)`: Get today's orders
- `history_orders(ctx, start_date, end_date)`: Get historical orders
- `today_executions(ctx)`: Get today's executions
- `history_executions(ctx, start_date, end_date)`: Get historical executions
- `submit_order(ctx, symbol, order_type, side, quantity, price)`: Submit an order
- `modify_order(ctx, order_id, quantity, price)`: Modify an order
- `cancel_order(ctx, order_id)`: Cancel an order
- `set_on_order_changed(ctx, callback)`: Set the callback function for order status change pushes
- `set_on_trade_changed(ctx, callback)`: Set the callback function for trade report pushes
- `subscribe_trade(ctx, topics)`: Subscribe to trade pushes
- `unsubscribe_trade(ctx, topics)`: Unsubscribe from trade pushes

## License

MIT License
