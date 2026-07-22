[English](./README.md) | [中文](./README.zh-CN.md)

# Julia SDK for LongBridge API
This is an unofficial SDK, currently for personal use only. Some functions in the Trade module have not been tested yet. Issues are welcome.

## Release Notes
See [NEWS.md](NEWS.md) for detailed release notes.

Latest release: **v0.9.0** — US data-center routing, paper-trading support, typed US fundamental/quote/trade/asset APIs, and paginated execution history.

References:

1. [Official Documentation](https://open.longportapp.com/en/docs)

2. [OpenAPI SDK Base](https://github.com/longportapp/openapi)

## Quick Start

### Installation

```julia
using Pkg
Pkg.add(url="https://github.com/rzhli/LongBridge.jl")
```

### Authentication

LongBridge supports two authentication methods:

#### 1. OAuth 2.0 (Recommended)

OAuth 2.0 uses Bearer tokens without requiring HMAC signatures. Tokens are persisted locally and refreshed automatically.

**Step 1: Register an OAuth client**

```bash
curl -X POST https://openapi.longbridgeapp.com/oauth2/register \
  -H "Content-Type: application/json" \
  -d '{
    "client_name": "My Application",
    "redirect_uris": ["http://localhost:60355/callback"],
    "grant_types": ["authorization_code", "refresh_token"]
  }'
```

**Step 2: Build OAuth handle and create config**

```julia
using LongBridge

oauth = OAuthBuilder("your-client-id") |> build(url -> run(`xdg-open $url`))
cfg = Config.from_oauth(oauth)
```

On first run, this opens the browser for authorization. Subsequent runs use the cached token automatically.

#### 2. API Key (Legacy)

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
# enable_papertrading = false
```

```julia
using LongBridge

cfg = Config.from_toml()
```

Credentials prefixed with `us_` automatically use the US data center. To route
requests to a paper-trading account, set `enable_papertrading = true` in TOML or
call `enable_papertrading!(cfg)` before creating a context. US-only endpoints,
such as `us_company_overview`, `us_crypto_overview`, `us_query_orders`, and
`us_asset_overview`, reject non-US credentials with a clear error.

### Quotes

```julia
using LongBridge

cfg = Config.from_toml()

# Create and connect to QuoteContext
ctx = QuoteContext(cfg)

# Get basic static information for securities
resp = static_info(ctx, ["700.HK", "AAPL.US", "TSLA.US"])

# Get real-time quotes for securities (one-shot server snapshot)
quotes = quote_snapshot(ctx, ["GOOGL.US", "AAPL.US", "TSLA.US"])

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
using LongBridge, Dates

cfg = Config.from_toml()

# Create and connect to TradeContext
ctx = TradeContext(cfg)

# Get account balance
resp = account_balance(ctx)

# Get stock positions (optionally filter by symbol)
resp = stock_positions(ctx)
resp = stock_positions(ctx; symbol = "700.HK")

# Get today's orders
resp = today_orders(ctx)

# Get historical orders (date range via keyword args)
resp = history_orders(ctx; start_at = Date(2024, 1, 1), end_at = Date(2024, 2, 1))

# Get today's executions
resp = today_executions(ctx)

# Get historical executions
resp = history_executions(ctx; start_at = Date(2024, 1, 1), end_at = Date(2024, 2, 1))

# Submit an order via SubmitOrderOptions
resp = submit_order(
    ctx, SubmitOrderOptions(
        symbol = "700.HK",
        order_type = OrderType.LO,
        side = OrderSide.Buy,
        submitted_quantity = 100,
        time_in_force = TimeInForceType.Day,
        submitted_price = 300.0,
    )
)

# Modify an order
resp = replace_order(
    ctx, ReplaceOrderOptions(
        order_id = "709043056541253632",
        submitted_quantity = 100,
        submitted_price = 301.0,
    )
)

# Cancel an order
resp = cancel_order(ctx, "709043056541253632")

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
- `Config.from_oauth(oauth_handle)`: Create configuration from an OAuth handle
- `OAuthBuilder(client_id) |> build(open_url_fn)`: Build an OAuth handle with browser-based authorization
- `QuoteContext(config)`: Create and connect to `QuoteContext`
- `TradeContext(config)`: Create and connect to `TradeContext`
- `disconnect!(ctx)`: Disconnect from the server

### Quote Fetching
- `static_info(ctx, symbols)`: Get basic static information for securities
- `quote_snapshot(ctx, symbols)`: Get a one-shot snapshot of real-time stock quotes (server query)
- `realtime_quote(ctx, symbol_or_symbols)`: Read the latest pushed quote from the local cache (requires prior `subscribe`)
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
- `set_on_candlestick(ctx, callback)`: Set the callback function for candlestick pushes
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
- `stock_positions(ctx; symbol)`: Get stock positions (optional symbol filter)
- `fund_positions(ctx)`: Get fund positions
- `today_orders(ctx; symbol, status, side)`: Get today's orders
- `history_orders(ctx; symbol, status, side, start_at, end_at)`: Get historical orders
- `today_executions(ctx; symbol)`: Get today's executions
- `history_executions(ctx; symbol, start_at, end_at)`: Get historical executions
- `order_detail(ctx, order_id)`: Get order detail
- `submit_order(ctx, ::SubmitOrderOptions)`: Submit an order
- `replace_order(ctx, ::ReplaceOrderOptions)`: Modify an order
- `cancel_order(ctx, order_id)`: Cancel an order
- `estimate_max_purchase_quantity(ctx, ::EstimateMaxPurchaseQuantityOptions)`: Estimate max purchase quantity
- `cash_flow(ctx; start_at, end_at)`: Get cash flow records
- `margin_ratio(ctx, symbol)`: Get margin ratio for a security
- `set_on_order_changed(ctx, callback)`: Set the callback function for order status change pushes
- `Trade.subscribe(ctx, topics::Vector{TopicType.T})`: Subscribe to trade pushes (e.g. `[TopicType.Private]`)
- `Trade.unsubscribe(ctx, topics::Vector{TopicType.T})`: Unsubscribe from trade pushes

### Fundamental Data (`FundamentalContext`, new in v0.6.0)
- `FundamentalContext(config)`: Create context (HTTP-only, no disconnect needed)
- `financial_report(ctx, symbol; kind, period)`: Full financial statements (IS/BS/CF/All)
- `institution_rating(ctx, symbol)`: Analyst ratings (latest + summary, parallel fan-out)
- `institution_rating_detail(ctx, symbol)`: Historical rating distribution
- `dividend(ctx, symbol)` / `dividend_detail(ctx, symbol)`: Dividend history / details
- `forecast_eps(ctx, symbol)`: Analyst EPS forecasts
- `consensus(ctx, symbol)`: Revenue / profit / EPS consensus vs actual
- `valuation(ctx, symbol)` / `valuation_history(ctx, symbol)`: PE/PB/PS/dividend yield
- `industry_valuation(ctx, symbol)` / `industry_valuation_dist(ctx, symbol)`: Peer comparison
- `company(ctx, symbol)` / `executive(ctx, symbol)` / `shareholder(ctx, symbol)` / `fund_holder(ctx, symbol)`
- `corp_action(ctx, symbol)`: Corporate actions (dividends, splits, buybacks)
- `invest_relation(ctx, symbol)`, `operating(ctx, symbol)`, `buyback(ctx, symbol)`, `ratings(ctx, symbol)`

### Market Data (`MarketContext`, new in v0.6.0)
- `market_status(ctx)`: Market open/close status across regions; status fields use `MarketTradeStatus`
- `broker_holding(ctx, symbol, period)` / `broker_holding_detail(ctx, symbol)` / `broker_holding_daily(ctx, symbol, broker_id)`
- `ah_premium(ctx, symbol, period, count)` / `ah_premium_intraday(ctx, symbol)`: A/H premium klines & intraday
- `trade_stats(ctx, symbol)`: Buy/sell/neutral trade statistics
- `anomaly(ctx, market)`: Market anomaly events
- `constituent(ctx, symbol)`: Index constituents (e.g. `"HSI.HK"`)

### Calendar (`CalendarContext`, new in v0.6.0)
- `finance_calendar(ctx, category, start, end_; market)`: Financial calendar events
  - `CalendarEventsResponse.next_date`: pass as the next `start` with the same `end_` to fetch the next page
  - `CalendarCategory`: `Report` / `Dividend` / `Split` / `Ipo` / `MacroData` / `Closed` / `Meeting` / `Merge`

### Portfolio Analytics (`PortfolioContext`, new in v0.6.0)
- `exchange_rate(ctx)`: Current rates for all supported currencies
- `profit_analysis(ctx; start, end_)`: Account P&L (summary + sublist parallel fan-out)
- `profit_analysis_by_market(ctx; page, size, market, ...)`: Paginated by market
- `profit_analysis_detail(ctx, symbol; ...)`: Per-security P&L breakdown
- `profit_analysis_flows(ctx, symbol; page, size, derivative, ...)`: Per-security flows

### Price Alerts (`AlertContext`, new in v0.6.0)
- `list_alerts(ctx)`: List all alerts grouped by security
- `add_alert(ctx, symbol, condition, trigger_value, frequency)`: Add alert
  - `AlertCondition`: `PriceRise` / `PriceFall` / `PercentRise` / `PercentFall`
  - `AlertFrequency`: `Daily` / `EveryTime` / `Once`
- `update_alert(ctx, item::AlertItem)`: Update alert (toggle enabled etc.)
- `delete_alerts(ctx, ids::Vector{String})`: Delete alerts

### Community Sharelists (`SharelistContext`, new in v0.6.0)
- `list_sharelists(ctx; count)` / `popular_sharelists(ctx; count)` / `sharelist_detail(ctx, id)`
- `create_sharelist(ctx, name; description)` / `delete_sharelist(ctx, id)`
- `add_sharelist_securities(ctx, id, symbols)` / `remove_sharelist_securities(ctx, id, symbols)` / `sort_sharelist_securities(ctx, id, symbols)`

### DCA Plans (`DCAContext`, new in v0.6.0)
- `list_dca(ctx; status, symbol)` / `dca_stats(ctx; symbol)`
- `create_dca(ctx, symbol, amount, frequency; day_of_week, day_of_month, allow_margin)`
  - `DCAFrequency`: `Daily` / `Weekly` / `Fortnightly` / `Monthly`
  - `DCAStatus`: `Active` / `Suspended` / `Finished`
- `update_dca(ctx, plan_id; amount, frequency, ...)`
- `pause_dca(ctx, plan_id)` / `resume_dca(ctx, plan_id)` / `stop_dca(ctx, plan_id)`
- `dca_history(ctx, plan_id; page, limit)` / `dca_check_support(ctx, symbols)` / `dca_calc_date(ctx, symbol, frequency; ...)` / `dca_set_reminder(ctx, hours)`

### Community Content (`ContentContext`, new in v0.6.0)
- `news(ctx, symbol)`: News for a security
- `topics_by_symbol(ctx, symbol)` / `topic_detail(ctx, id)` / `topic_replies(ctx, topic_id; page, size)`
- `my_topics(ctx; page, size, topic_type)`: List topics you've published
- `create_topic(ctx, title, body; topic_type, tickers, hashtags)`: Publish a topic, returns ID
- `create_topic_reply(ctx, topic_id, body; reply_to_id)`: Post a reply (plain text)

### Quote Additions (v0.6.0)
- `short_positions(ctx, symbol)`: US short interest (FINRA bi-monthly)
- `option_volume(ctx, symbol)` / `option_volume_daily(ctx, symbol, timestamp, count)`: Option volume stats
- `update_pinned(ctx, mode::PinnedMode.T, symbols)`: Pin/unpin watchlist securities

### Quote Additions (v0.7.0)
- `quote_snapshot(ctx, symbols)`: One-shot quote snapshot via WebSocket (was previously `realtime_quote`)
- `realtime_quote(ctx, symbol_or_symbols)`: Read latest pushed quote from local cache (subscribe first); aligned with `realtime_depth/brokers/trades`
- `filings(ctx, symbol)`: Company filings list (REST `/v1/quote/filings`), returns `Vector{FilingItem}`
- `member_id(ctx)` / `quote_level(ctx)` / `quote_package_details(ctx)`: Now backed by a real `QueryUserQuoteProfile` call on connect (previously returned zero-value stubs)

### Account Statements (`AssetContext`, new in v0.7.0)
- `AssetContext(config)`: Create context (HTTP-only, no disconnect needed)
- `statements(ctx, type::StatementType.T; page, page_size)`: Paginated list of statement records (`type` = `Daily` / `Monthly`)
- `statement_download_url(ctx, file_key)`: Resolve a statement record's download URL

### Stock Screener (`ScreenerContext`, new in v0.8.0, signature update in v0.8.1)
- `ScreenerContext(config)`: Create context (HTTP-only, no disconnect needed)
- `screener_recommend_strategies(ctx, market)`: Preset built-in screener strategies for a market (e.g. `"US"`/`"HK"`)
- `screener_user_strategies(ctx, market)`: Current user's saved screener strategies for a market
- `screener_strategy(ctx, id)`: Detail of one strategy (path-param id); `filter_` prefix is stripped from filter keys
- `screener_search(ctx, market; strategy_id=nothing, conditions=ScreenerCondition[], show=String[], page=0, size=20)`:
  Mode A (when `strategy_id` is given — fetches strategy and forwards filters) or Mode B (typed `ScreenerCondition` objects). `DEFAULT_RETURNS` always included; `filter_` prefix is stripped from response indicator keys.
- `screener_indicators(ctx)`: Available indicator definitions; `filter_` prefix stripped + `tech_values` rebuilt from `tech_indicators`

### Fundamental (`FundamentalContext`, new in v0.8.0)
- `business_segments(ctx, symbol)`: Latest business segment revenue breakdown
- `business_segments_history(ctx, symbol; report, cate)`: Historical business + regional segment snapshots
- `institution_rating_views(ctx, symbol)`: Historical analyst rating distribution time series
- `industry_rank(ctx, market, indicator, sort_type, limit)`: Industry rank in a market
- `industry_peers(ctx, counter_or_symbol, market; industry_id)`: Recursive industry peer chain
- `financial_report_snapshot(ctx, symbol; report, fiscal_year, fiscal_period)`: Earnings snapshot (actual vs estimate, key ratios)
- `shareholder_top(ctx, symbol)`: Top-shareholder ranking (raw JSON)
- `shareholder_detail(ctx, symbol, object_id)`: Holding history for one shareholder object (raw JSON)
- `valuation_comparison(ctx, symbol, currency; comparison_symbols)`: Valuation comparison (PE/PB/PS) with historical curve
- `etf_asset_allocation(ctx, symbol)`: ETF asset allocation (holdings / regional / asset class / industry groups, new in v0.8.3)
- `macroeconomic_indicators(ctx; country, keyword, offset, limit)`: List macroeconomic indicators, optional `MacroeconomicCountry` and fuzzy keyword filters (new in v0.8.5)
- `macroeconomic(ctx, id; start_date, end_date, offset, limit, sort)`: Historical data for one macroeconomic indicator, newest-first by default (new in v0.8.5)

### Market (`MarketContext`, new in v0.8.0)
- `top_movers(ctx, markets, sort, limit; date)`: Top movers across one or more markets (renamed from upstream `stock_events`)
- `rank_categories(ctx)`: Available rank category keys/labels (raw JSON)
- `rank_list(ctx, key; need_article)`: Ranked securities for one category

### Quote (`QuoteContext`, breaking + new in v0.8.0)
- `short_positions(ctx, symbol; count=20)`: **Breaking** — unified HK + US short-position endpoint (was US-only with fixed `last_timestamp=0, page_size=100`). The item struct is now `ShortPositionsItem` and the response drops `symbol`/`sources`. Timestamps are `DateTime` (UTC).
- `short_trades(ctx, symbol; count=20)`: HK/US short-trade records, endpoint auto-selected by `.HK` suffix.

## License

MIT License
