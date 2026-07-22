[English](./README.md) | [中文](./README.zh-CN.md)

# Julia SDK for LongBridge API
非官方，目前仅自用，交易（Trade）模块某些函数暂未测试，欢迎提issue

## 更新日志
详细更新说明请见 [NEWS.md](NEWS.md)。

最新版本：**v0.9.0** —— 新增美国数据中心自动路由、模拟交易支持、类型化的美区基本面/行情/交易/资产接口，以及分页成交记录查询。

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
# enable_papertrading = false
```

```julia
using LongBridge

cfg = Config.from_toml()
```

`us_` 前缀的凭证会自动使用美国数据中心。如需路由到模拟交易账户，可在 TOML
中设置 `enable_papertrading = true`，或在创建 Context 前调用
`enable_papertrading!(cfg)`。`us_company_overview`、`us_crypto_overview`、
`us_query_orders`、`us_asset_overview` 等美区专属接口会拒绝非美区凭证，
并返回明确错误。

### 行情

```julia
using LongBridge

cfg = Config.from_toml()

# 创建并连接 QuoteContext
ctx = QuoteContext(cfg)

# 获取标的基础信息
resp = static_info(ctx, ["700.HK", "AAPL.US", "TSLA.US"])

# 获取标的实时行情
quotes = quote_snapshot(ctx, ["GOOGL.US", "AAPL.US", "TSLA.US"])

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
using LongBridge, Dates

cfg = Config.from_toml()

# 创建并连接 TradeContext
ctx = TradeContext(cfg)

# 获取账户资金
resp = account_balance(ctx)

# 获取持仓（可按 symbol 过滤）
resp = stock_positions(ctx)
resp = stock_positions(ctx; symbol = "700.HK")

# 获取今日订单
resp = today_orders(ctx)

# 获取历史订单（日期通过关键字参数传入）
resp = history_orders(ctx; start_at = Date(2024, 1, 1), end_at = Date(2024, 2, 1))

# 获取今日成交
resp = today_executions(ctx)

# 获取历史成交
resp = history_executions(ctx; start_at = Date(2024, 1, 1), end_at = Date(2024, 2, 1))

# 下单（通过 SubmitOrderOptions 提交）
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

# 修改订单
resp = replace_order(
    ctx, ReplaceOrderOptions(
        order_id = "709043056541253632",
        submitted_quantity = 100,
        submitted_price = 301.0,
    )
)

# 撤单
resp = cancel_order(ctx, "709043056541253632")

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
- `quote_snapshot(ctx, symbols)`: 获取股票实时行情快照（一次性服务器查询）
- `realtime_quote(ctx, symbol_or_symbols)`: 从本地缓存读取最新推送的行情（需先 `subscribe`）
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
- `set_on_candlestick(ctx, callback)`: 设置 K 线推送的回调函数
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
- `stock_positions(ctx; symbol)`: 获取持仓（symbol 可选过滤）
- `fund_positions(ctx)`: 获取基金持仓
- `today_orders(ctx; symbol, status, side)`: 获取今日订单
- `history_orders(ctx; symbol, status, side, start_at, end_at)`: 获取历史订单
- `today_executions(ctx; symbol)`: 获取今日成交
- `history_executions(ctx; symbol, start_at, end_at)`: 获取历史成交
- `order_detail(ctx, order_id)`: 获取订单详情
- `submit_order(ctx, ::SubmitOrderOptions)`: 下单
- `replace_order(ctx, ::ReplaceOrderOptions)`: 修改订单
- `cancel_order(ctx, order_id)`: 撤单
- `estimate_max_purchase_quantity(ctx, ::EstimateMaxPurchaseQuantityOptions)`: 预估最大购买数量
- `cash_flow(ctx; start_at, end_at)`: 获取资金流水
- `margin_ratio(ctx, symbol)`: 获取保证金比例
- `set_on_order_changed(ctx, callback)`: 设置订单状态变化推送的回调函数
- `Trade.subscribe(ctx, topics::Vector{TopicType.T})`: 订阅交易推送（如 `[TopicType.Private]`）
- `Trade.unsubscribe(ctx, topics::Vector{TopicType.T})`: 取消订阅交易推送

### 基本面（FundamentalContext，v0.6.0 新增）
- `FundamentalContext(config)`: 创建上下文（HTTP-only，无需 disconnect）
- `financial_report(ctx, symbol; kind, period)`: 完整财报（利润表/资产负债表/现金流量表）
- `institution_rating(ctx, symbol)`: 分析师评级（latest + summary，并行 fan-out）
- `institution_rating_detail(ctx, symbol)`: 评级历史明细
- `dividend(ctx, symbol)` / `dividend_detail(ctx, symbol)`: 分红历史 / 详细分配方案
- `forecast_eps(ctx, symbol)`: 分析师 EPS 预测
- `consensus(ctx, symbol)`: 营收/利润/EPS 一致预期 vs 实际
- `valuation(ctx, symbol)` / `valuation_history(ctx, symbol)`: P/E/P/B/P/S/股息率
- `industry_valuation(ctx, symbol)` / `industry_valuation_dist(ctx, symbol)`: 同业对比 / 行业分布
- `company(ctx, symbol)`: 公司概况
- `executive(ctx, symbol)`: 管理层与董事会
- `shareholder(ctx, symbol)`: 主要股东
- `fund_holder(ctx, symbol)`: 持有该证券的基金/ETF
- `corp_action(ctx, symbol)`: 公司行动（分红、拆股、回购）
- `invest_relation(ctx, symbol)`: 对外投资关系
- `operating(ctx, symbol)`: 经营报告与关键指标
- `buyback(ctx, symbol)`: 回购数据
- `ratings(ctx, symbol)`: 多维度评级

### 市场数据（MarketContext，v0.6.0 新增）
- `MarketContext(config)`: 创建上下文
- `market_status(ctx)`: 各市场开/收市状态；状态字段使用 `MarketTradeStatus`
- `broker_holding(ctx, symbol, period)`: 净买/净卖前十券商
- `broker_holding_detail(ctx, symbol)`: 全部券商持仓明细
- `broker_holding_daily(ctx, symbol, broker_id)`: 指定券商日度持仓
- `ah_premium(ctx, symbol, period, count)`: A/H 溢价 K 线
- `ah_premium_intraday(ctx, symbol)`: A/H 溢价分时
- `trade_stats(ctx, symbol)`: 买/卖/中性方向成交统计
- `anomaly(ctx, market)`: 市场异动
- `constituent(ctx, symbol)`: 指数成份股（symbol 传指数如 `"HSI.HK"`）

### 财务日历（CalendarContext，v0.6.0 新增）
- `CalendarContext(config)`: 创建上下文
- `finance_calendar(ctx, category, start, end_; market)`: 财务日历事件
  - `CalendarEventsResponse.next_date`: 下一页游标，可作为下一次请求的 `start`，并保持同一个 `end_`
  - `CalendarCategory`: `Report` / `Dividend` / `Split` / `Ipo` / `MacroData` / `Closed` / `Meeting` / `Merge`

### 组合分析（PortfolioContext，v0.6.0 新增）
- `PortfolioContext(config)`: 创建上下文
- `exchange_rate(ctx)`: 全部支持币种的汇率
- `profit_analysis(ctx; start, end_)`: 账户总盈亏（summary + sublist 并行 fan-out）
- `profit_analysis_by_market(ctx; page, size, market, ...)`: 按市场分页盈亏
- `profit_analysis_detail(ctx, symbol; start, end_)`: 单只证券盈亏明细
- `profit_analysis_flows(ctx, symbol; page, size, derivative, ...)`: 单只证券交易流水

### 价格提醒（AlertContext，v0.6.0 新增）
- `AlertContext(config)`: 创建上下文
- `list_alerts(ctx)`: 查询全部提醒（按证券分组）
- `add_alert(ctx, symbol, condition, trigger_value, frequency)`: 新增提醒
  - `AlertCondition`: `PriceRise` / `PriceFall` / `PercentRise` / `PercentFall`
  - `AlertFrequency`: `Daily` / `EveryTime` / `Once`
- `update_alert(ctx, item::AlertItem)`: 更新提醒
- `delete_alerts(ctx, ids::Vector{String})`: 删除提醒

### 社区自选股（SharelistContext，v0.6.0 新增）
- `SharelistContext(config)`: 创建上下文
- `list_sharelists(ctx; count)`: 我自己 + 已订阅的自选股列表
- `popular_sharelists(ctx; count)`: 热门列表
- `sharelist_detail(ctx, id)`: 列表详情（含成份股）
- `create_sharelist(ctx, name; description)`: 新建列表
- `delete_sharelist(ctx, id)`: 删除列表
- `add_sharelist_securities(ctx, id, symbols)`: 加入证券
- `remove_sharelist_securities(ctx, id, symbols)`: 移除证券
- `sort_sharelist_securities(ctx, id, symbols)`: 重排证券

### 定投计划（DCAContext，v0.6.0 新增）
- `DCAContext(config)`: 创建上下文
- `list_dca(ctx; status, symbol)`: 全部定投计划，可按状态/标的过滤
- `create_dca(ctx, symbol, amount, frequency; day_of_week, day_of_month, allow_margin)`: 新建
  - `DCAFrequency`: `Daily` / `Weekly` / `Fortnightly` / `Monthly`
  - `DCAStatus`: `Active` / `Suspended` / `Finished`
- `update_dca(ctx, plan_id; amount, frequency, ...)`: 更新（只传想改的字段）
- `pause_dca(ctx, plan_id)` / `resume_dca(ctx, plan_id)` / `stop_dca(ctx, plan_id)`: 暂停/恢复/永久停止
- `dca_history(ctx, plan_id; page, limit)`: 计划执行历史
- `dca_stats(ctx; symbol)`: 总览统计
- `dca_check_support(ctx, symbols)`: 批量检查标的是否支持
- `dca_calc_date(ctx, symbol, frequency; day_of_week, day_of_month)`: 计算下次交易日
- `dca_set_reminder(ctx, hours)`: 设置执行前提醒小时数（`"1"`/`"6"`/`"12"`）

### 社区话题与资讯（ContentContext，v0.6.0 新增）
- `ContentContext(config)`: 创建上下文
- `news(ctx, symbol)`: 某证券的资讯列表
- `topics_by_symbol(ctx, symbol)`: 某证券下的话题
- `my_topics(ctx; page, size, topic_type)`: 我自己发布的话题
- `topic_detail(ctx, id)`: 话题详情
- `topic_replies(ctx, topic_id; page, size)`: 话题评论
- `create_topic(ctx, title, body; topic_type, tickers, hashtags)`: 发布新话题，返回 ID
- `create_topic_reply(ctx, topic_id, body; reply_to_id)`: 评论（plain text，提到的 symbol 自动识别）

### 行情（QuoteContext，v0.6.0 新增 4 个方法）
- `short_positions(ctx, symbol)`: 美股做空数据（FINRA 双月公布）
- `option_volume(ctx, symbol)`: 实时期权认购/认沽成交量
- `option_volume_daily(ctx, symbol, timestamp, count)`: 历史日度期权统计
- `update_pinned(ctx, mode::PinnedMode.T, symbols)`: 自选股置顶/取消置顶

### 行情（QuoteContext，v0.7.0 新增）
- `quote_snapshot(ctx, symbols)`: 一次性服务器行情查询（即 v0.6.x 的 `realtime_quote` 行为）
- `realtime_quote(ctx, symbol_or_symbols)`: 从本地缓存读取最新推送的行情（需先 `subscribe`），与 `realtime_depth/brokers/trades` 语义一致
- `filings(ctx, symbol)`: 公司公告列表（REST `/v1/quote/filings`），返回 `Vector{FilingItem}`
- `member_id(ctx)` / `quote_level(ctx)` / `quote_package_details(ctx)`: 连接后通过 `QueryUserQuoteProfile` 拉取的真实值（v0.6.x 是零值桩）

### 账户结算单（AssetContext，v0.7.0 新增）
- `AssetContext(config)`: 创建上下文（HTTP-only，无需 disconnect）
- `statements(ctx, type::StatementType.T; page, page_size)`: 结算单分页列表（`type` 为 `Daily` / `Monthly`）
- `statement_download_url(ctx, file_key)`: 用 `file_key` 换取结算单下载链接

### 选股器（ScreenerContext，v0.8.0 新增；v0.8.1 签名更新）
- `ScreenerContext(config)`: 创建上下文（HTTP-only，无需 disconnect）
- `screener_recommend_strategies(ctx, market)`: 指定市场（如 `"US"` / `"HK"`）的推荐内置策略
- `screener_user_strategies(ctx, market)`: 指定市场已保存的策略列表
- `screener_strategy(ctx, id)`: 单个策略详情（id 走 path 参数）；响应中 `filter_` 前缀自动剥离
- `screener_search(ctx, market; strategy_id=nothing, conditions=ScreenerCondition[], show=String[], page=0, size=20)`:
  Mode A（给 `strategy_id`，内部先拉策略再 POST）或 Mode B（用 `ScreenerCondition` 类型化条件）。`DEFAULT_RETURNS` 始终包含；响应中 `items[].indicators[].key` 的 `filter_` 前缀自动剥离。
- `screener_indicators(ctx)`: 可用指标元数据；`filter_` 前缀剥离 + 由 `tech_indicators` 重组 `tech_values`

### 基本面（FundamentalContext，v0.8.0 新增）
- `business_segments(ctx, symbol)`: 最新业务分部收入构成
- `business_segments_history(ctx, symbol; report, cate)`: 历史业务 + 地区分部
- `institution_rating_views(ctx, symbol)`: 机构评级分布的历史时间序列
- `industry_rank(ctx, market, indicator, sort_type, limit)`: 行业排名
- `industry_peers(ctx, counter_or_symbol, market; industry_id)`: 行业同业链（递归节点）
- `financial_report_snapshot(ctx, symbol; report, fiscal_year, fiscal_period)`: 财报快照（vs 预期对比、关键比率）
- `shareholder_top(ctx, symbol)`: 主要股东排行（原始 JSON）
- `shareholder_detail(ctx, symbol, object_id)`: 指定股东对象的持仓明细（原始 JSON）
- `valuation_comparison(ctx, symbol, currency; comparison_symbols)`: 估值对比（PE/PB/PS 含历史曲线）
- `etf_asset_allocation(ctx, symbol)`: ETF 资产配置（holdings / regional / asset class / industry 分组，v0.8.3 新增）
- `macroeconomic_indicators(ctx; country, keyword, offset, limit)`: 宏观经济指标列表，可按 `MacroeconomicCountry` 和关键字模糊过滤（v0.8.5 新增）
- `macroeconomic(ctx, id; start_date, end_date, offset, limit, sort)`: 指定宏观指标的历史数据，默认最新数据在前（v0.8.5 新增）

### 市场数据（MarketContext，v0.8.0 新增）
- `top_movers(ctx, markets, sort, limit; date)`: 异动榜（对应上游重命名后的 `stock_events`）
- `rank_categories(ctx)`: 可用的排行榜分类（原始 JSON）
- `rank_list(ctx, key; need_article)`: 指定分类的排行榜列表

### 行情（QuoteContext，v0.8.0 破坏性变更 + 新增）
- `short_positions(ctx, symbol; count=20)`：**破坏性** —— HK/US 统一端点（原 US 专用），`ShortPosition` → `ShortPositionsItem` 并新增 HK 字段；响应去掉 `symbol`/`sources` 外层字段；`timestamp` 由 `String` 改为 `DateTime` (UTC)。
- `short_trades(ctx, symbol; count=20)`：HK/US 做空成交记录，按 `.HK` 后缀自动选择端点。

## 许可证

MIT License
