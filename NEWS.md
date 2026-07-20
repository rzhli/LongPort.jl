# Release Notes

## v0.8.9 (2026-07-20)

### Performance and API improvements

- WebSocket 24-bit frame length encoding/decoding no longer allocates temporary byte arrays and now validates oversized request bodies.
- Realtime quote caches reuse existing vector storage, enforce configured history limits, and accept `AbstractString` / `AbstractVector` inputs including views.
- Quote and Trade APIs now accept broader string and collection inputs while converting once to concrete protocol types at the wire boundary.
- Reduced avoidable allocations in decimal parsing, prefix normalization, JSON response parsing, OAuth token loading, error rendering, and content response construction.
- Removed unused imports and avoided unnecessary package-load work; package version lookup now works when the source module is included directly.

### Reliability and workflow

- Simplified the WebSocket authentication timeout task and added bounds checks for protocol frame sizes.
- Example and manual test scripts now run through guarded `main()` entry points, so including them does not open OAuth flows or send network requests.
- Expanded tests for typed query dictionaries, WebSocket 24-bit lengths, generic collection inputs, and bounded realtime caches.
- Updated locked dependencies, including HTTP.jl `2.5.5`, PrettyTables `3.4.2`, DataStructures `0.19.6`, and OrderedCollections `2.0.1`.

## v0.8.8 (2026-07-06)

### Fixes — Quote WebSocket 保活与重连对齐上游 Rust wsclient

- **修复空闲连接被 `1006 read idle timeout` 断开后不再恢复**：Quote 长连接的保活模型改为与上游一致——客户端不再主动发 WebSocket ping，改由服务端定期 ping 保活（HTTP.jl 自动回 PONG 并在收到任意帧时重置 read idle 计时器）。
  - 新增 WebSocket 专用常量 `WS_CONNECT_TIMEOUT = 5`（上游 `CONNECT_TIMEOUT`）、`WS_HEARTBEAT_TIMEOUT = 120`（上游 `HEARTBEAT_TIMEOUT`，作为 `read_idle_timeout`）、`WS_WRITE_TIMEOUT = 20`；此前 20s 的 `read_idle_timeout` 过于激进，且依赖 10s 客户端 ping 喂活。REST `HTTP_CLIENT` 仍用独立的 `DEFAULT_TIMEOUT`，不受影响。
  - 移除客户端 `start_heartbeat_loop`（主动 ping）循环。
- **消息循环在连接非正常终止时自动重连**：EOF / 1006 / 协议错误等不再仅 `disconnect!` 导致静默死亡，而是触发 `reconnect!`（优先 `session_id` 快速重连，失败回退完整认证重连），对齐上游 `main_loop err → run() reconnect`；仅显式 `InterruptException` 才停止。
- **快速重连后恢复订阅**：session 快速重连路径此前遗漏重新订阅，会导致 push 静默中断；现与上游一致，在两条重连路径后都调用 `on_reconnect` 恢复订阅。
- **连接建立/网络故障不再杀死 QuoteContext**：`run_quote_loop` 中 `get_otp`/`connect!` 等建连阶段的瞬时失败（如 TLS handshake timeout）改为按指数退避重试（`MAX_CONNECT_ATTEMPTS = 5`），而非直接终止后台 task；此前一次瞬时超时会关闭 `command_ch` 导致后续请求以 `408 Channel is closed` 失败。

### Dependencies

- HTTP.jl `2.4.0` → `2.5.4`（WebSocket read idle timeout 逐帧重置行为依赖此版本），PrettyTables `3.3.2` → `3.4.0`，Tables `1.12.1` → `1.13.0`。

## v0.8.7 (2026-06-29)

- 修复 `account_balance(ctx)` 解析：`cash_infos` 与 `frozen_transaction_fees` 现在会显式构造成 `CashInfo` / `FrozenTransactionFee`，避免 `JSON3.Object` 无法转换为嵌套结构体；`market` 字段同步解析为 `Market.T`。
- 修复 `cash_flow(ctx; ...)` 解析：支持上游返回数字枚举码（如 `direction: 1`、`business_type: 0`）、数字金额和 Unix timestamp 字段；`cash_flow` 改为从 `resp.data.list` 直接构造 `CashFlow`。
- `safeparse` 支持已是 numeric 的 enum / real API 值，减少 JSON 数字字段和字符串字段混用时的解析失败。
- 优化交易资产相关 REPL 显示：`Vector{CashFlow}`、`FundPositionsResponse`、`StockPositionsResponse` 现在输出简洁摘要，避免默认结构体全限定名噪音。

## v0.8.6 (2026-06-26)

- 同步上游 LongBridge OpenAPI v4.3.3：新增 `MarketProtocol.TradeStatus` / 顶层别名 `MarketTradeStatus`，`MarketTimeItem.trade_status` 与 `delay_trade_status` 改为 typed enum，并补齐 market 状态码表、显示名、label、归一化与判断 helper（含 `2001`、`123`/`1009`/`1010` 名称修正）。
- 修复 macrodata v2 detail 解析：`MacroeconomicResponse.info.periodicity` 与 `info.importance` 现在会从上游 `indicator.frequence` / `indicator.importance` 填充；v2 请求参数同步为 `market`、`start_date`、`end_date`。
- 按 Julia async/networking/performance 指南优化运行时路径：HTTP query string 构造减少中间分配并支持 vector 元素统一转字符串；Quote push 队列改为有界通道；长期后台 task 增加 `errormonitor`；少量并发 HTTP fan-out 改用 async I/O task 并避免共享参数 Dict。

## v0.8.5 (2026-06-22)

### New Features — 跟进上游 LongBridge OpenAPI（2 个 macrodata Fundamental API）

- **`FundamentalContext.macroeconomic_indicators(ctx; country=nothing, keyword=nothing, offset=nothing, limit=nothing)`**：宏观经济指标列表，对应 `GET /v2/quote/macrodata`，返回 `MacroeconomicIndicatorListResponse`（`data` 指标列表 + `count` 总数）。`country` 为 `MacroeconomicCountry.T` 枚举（`HongKong` / `China` / `UnitedStates` / `EuroZone` / `Japan` / `Singapore`），内部转 API 要求的全名（如 `"United States"`）；`keyword` 为指标名称模糊过滤。
- **`FundamentalContext.macroeconomic(ctx, id; start_date=nothing, end_date=nothing, offset=nothing, limit=nothing, sort="desc")`**：指定指标的历史数据，对应 `GET /v2/quote/macrodata/{id}`，返回 `MacroeconomicResponse`（`info` 元数据 + `data` 数据点 + `count` 总数）。`start_date`/`end_date` 接受 `"YYYY-MM-DD"` 字符串或 `Date`，按 v2 API 发送为 `start_date` / `end_date`；默认 `sort="desc"`，最新数据在前。
- **新增类型**：`MacroeconomicCountry`、`MacroeconomicImportance`（Low=1 / Medium=2 / High=3）、`MacroeconomicIndicator`、`MacroeconomicIndicatorListResponse`、`Macroeconomic`、`MacroeconomicResponse`。
- **字符串字段**：`MacroeconomicIndicator.name` / `.describe`、`Macroeconomic.unit` / `.unit_prefix` 均为 `String`；这些字段为 `null` 时兜底为空字符串，`MacroeconomicResponse.info` 为 `null` 时兜底为空结构。
- `release_at` / `next_release_at` / `start_date` 等 RFC3339 时间戳解析为 UTC `DateTime`（`Union{DateTime,Nothing}`，空串/null 为 `nothing`）。
- `test/test_v0_8_5_sync.jl`（9 个 testset，覆盖国家全名映射、importance 枚举、RFC3339 解析、字符串字段构造、null 兜底与方法签名）。

### Reference

初始宏观接口对应提交：[longbridge/openapi#540](https://github.com/longbridge/openapi/pull/540)（2026-06-11）；后续同步 macrodata v2 端点、关键字模糊过滤、字符串字段和默认倒序返回。

## v0.8.3 (2026-06-04)

### Changes — 跟进上游 LongBridge OpenAPI v4.3.0

- **`FundamentalContext.etf_asset_allocation(ctx, symbol)`**：新增 ETF 资产配置接口，对应 `GET /v1/quote/etf-asset-allocation`，返回 `AssetAllocationResponse`（holdings / regional / asset class / industry 分组）。
- **`QuoteContext.symbol_to_counter_ids(ctx, symbols)` / `resolve_counter_ids(ctx, symbols)`**：新增批量 symbol → counter_id 解析；`resolve_counter_ids` 本地目录优先，未知 symbol 批量请求远端并写入本地 counter cache。
- **`symbol_to_counter_id`**：同步上游 counter 目录逻辑，除 ETF 外也识别指数和窝轮；`.DJI.US` → `IX/US/.DJI`、`HSI.HK` → `IX/HK/HSI`、`10005.HK` → `WT/HK/10005`，并对纯数字港股代码去前导零。
- **内嵌 counter 目录刷新**：US ETF 列表 `4574 → 7250` 条，新增 index `648` 条和 warrant `17693` 条。

## v0.8.2 (2026-06-02)

- **`CalendarEventsResponse.next_date`**：新增财务日历分页游标，可作为下一次 `finance_calendar` 请求的 `start`，并保持同一个 `end_`。
- **`CalendarEventInfo.symbol`**：确认继续输出标准 symbol（如 `CRM.US`），而不是原始 `counter_id`（如 `ST/US/CRM`）。
- **HTTP.jl 2.x 兼容**：HTTP 客户端和 OAuth 回调响应适配 HTTP.jl 2.x API。

## v0.8.1 (2026-05-24)

### Changes — 跟进上游 LongPort SDK v4.2.1

- **`ScreenerContext` 端点全部迁移到 `/v1/quote/ai/screener/*`**：
  - `screener_recommend_strategies(ctx, market)` —— 新增 `market` 必传参数。
  - `screener_user_strategies(ctx, market)` —— 新增 `market` 必传参数。
  - `screener_strategy(ctx, id)` —— 改为 `GET /v1/quote/ai/screener/strategy/{id}`（id 在 path）；响应中 `filter.filters[].key` 自动剥离 `filter_` 前缀。
  - `screener_search(ctx, market; strategy_id=nothing, conditions=ScreenerCondition[], show=String[], page=0, size=20)` —— 重写为 Mode A（按 `strategy_id`，内部先拉策略再 POST）和 Mode B（用 `ScreenerCondition` 列表）。`DEFAULT_RETURNS`（7 列）始终包含，`show` 列追加。响应中 `items[].indicators[].key` 自动剥离 `filter_` 前缀。`page` 从 0 开始。
  - `screener_indicators(ctx)` —— 响应做两个后处理：`groups[].indicators[].key` 的 `filter_` 前缀剥离 + 由 `tech_indicators` 重组出 `tech_values = {tech_key => [{value, label}]}`。
- **新增 `ScreenerCondition` 结构** —— Mode B 用的类型化筛选条件（`key`、`min`、`max`、`tech_values`），替代上游旧版的字符串拼接。
- **`MarketContext` 排行榜接口前缀处理**：
  - `rank_categories` 响应中 `first_tags[].key` / `second_tags[].key` 的 `ib_` 前缀自动剥离。
  - `rank_list(ctx, key; ...)` 若 `key` 缺少 `ib_` 前缀会自动补上——配合 `rank_categories` 剥离后的干净 key 直接使用。
- **`OperatingFinancial.counter_id` → `OperatingFinancial.symbol`**：字段重命名 + 应用 `counter_id_to_symbol` 转换（如 `ST/US/AAPL` → `AAPL.US`）。

### Migration

```julia
# 旧（v0.8.0）
screener_recommend_strategies(sc)
screener_search(sc, "US", strategy_id, page, size)
of.counter_id   # "ST/US/AAPL"

# 新（v0.8.1）
screener_recommend_strategies(sc, "US")
screener_search(sc, "US"; strategy_id=12345, page=0, size=20)         # Mode A
screener_search(sc, "US"; conditions=[ScreenerCondition("pettm"; min="0", max="20")])  # Mode B
of.symbol       # "AAPL.US"
```

### Internals

- 新增 `Utils.json3_to_mutable`：递归把 `JSON3.Object`/`JSON3.Array` 转 `Dict{String,Any}`/`Vector{Any}`，供需要客户端后处理的端点使用。
- `test/test_v0_8_1_sync.jl`（9 个 testset，覆盖 `ScreenerCondition`、前缀剥离/补齐、`OperatingFinancial.symbol`、`json3_to_mutable`）。

### Reference

上游对应版本：[longbridge/openapi v4.2.1](https://github.com/longbridge/openapi/releases/tag/v4.2.1)（2026-05-23 发布）。

## v0.8.0 (2026-05-22)

### New Features — 跟进上游 LongPort SDK v4.2.0（19 个新 API + 1 个新 Context）

- **新 `ScreenerContext`（5 个方法）** —— 选股器：`screener_recommend_strategies`（推荐策略）、`screener_user_strategies`（我的策略）、`screener_strategy(id)`（策略详情）、`screener_search(market, strategy_id, page, size)`（按策略筛选）、`screener_indicators`（指标元数据）。上游均返回结构多变的 JSON，本端口统一以 `data::Any` 字段保留原始 JSON。
- **`FundamentalContext` +9 个方法** —— `business_segments`（最新业务分部）、`business_segments_history`（历史业务+地区分部）、`institution_rating_views`（机构评级分布历史时间序列）、`industry_rank(market, indicator, sort_type, limit)`（行业排名）、`industry_peers(counter_or_symbol, market; industry_id)`（行业同业链，节点 `next` 递归）、`financial_report_snapshot(symbol; report, fiscal_year, fiscal_period)`（财报快照含 vs 预期对比）、`shareholder_top`（主要股东排行）、`shareholder_detail(symbol, object_id)`（指定股东持仓明细）、`valuation_comparison(symbol, currency; comparison_symbols)`（估值对比含 PE/PB/PS 历史曲线，`history.date` 自动转 `DateTime`）。
- **`MarketContext` +3 个方法** —— `top_movers(markets, sort, limit; date)`（异动榜，对应上游重命名后的端点 `POST /v1/quote/market/stock-events`；`timestamp` 自动转 `DateTime`）、`rank_categories`（排行榜分类元数据）、`rank_list(key; need_article)`（指定分类的排行榜）。
- **`QuoteContext.short_trades(ctx, symbol; count=20)`** —— 新增做空成交端点，按 `symbol` 后缀自动选择 `/v1/quote/short-trades/hk` 或 `/v1/quote/short-trades/us`。

### Breaking changes（与上游对齐）

- **`short_positions` 签名与端点统一**：
  - 旧：`short_positions(ctx, symbol)` 固定走 `/v1/quote/short-positions/us`，参数固定 `last_timestamp=0, page_size=100`。
  - 新：`short_positions(ctx, symbol; count=20)` 按 `symbol` 后缀自动选择 `/hk` 或 `/us`，`last_timestamp` 取当前时间。
- **响应类型 typed**：
  - `ShortPosition` → 重命名并扩展为 `ShortPositionsItem`，新增 HK 字段 `amount`/`balance`/`cost`（与原有 US 字段并存，按品种填充对应字段）。
  - `ShortPositionsResponse` 不再含 `symbol`/`sources` 外层字段，仅保留 `data::Vector{ShortPositionsItem}`。
  - 新增 `ShortTradesItem` / `ShortTradesResponse`。
- **时间戳字段从 `String` 改为 `DateTime` (UTC)**：`ShortPositionsItem.timestamp`、`ShortTradesItem.timestamp`、`TopMoversEvent.timestamp`、`ValuationHistoryPoint.date` 均由原始 unix 秒（API 既返回字符串也返回整数）自动转换。沿用 v0.7 `FilingItem.published_at` 的做法。

### Migration

```julia
# 旧（v0.7.x）—— 美股专用
resp = short_positions(ctx, "AAPL.US")  # 固定查 100 条美股记录

# 新（v0.8.0）—— 美股
resp = short_positions(ctx, "AAPL.US"; count=20)
# 新（v0.8.0）—— 港股（端点自动切到 /short-positions/hk）
resp = short_positions(ctx, "700.HK"; count=20)

# 历史代码访问 ShortPosition 字段：
for item in resp.data
    println(item.timestamp, " ", item.rate, " ", item.current_shares_short)
end
# 注意：item 类型从 `ShortPosition` 改名为 `ShortPositionsItem`；
#       `timestamp` 现在是 `DateTime` 而不是 `String`。
```

### Internals

- 新 `Core/ScreenerProtocol.jl` 模块，5 个原始 JSON 包装结构（`data::Any`）。
- `Core/FundamentalProtocol.jl` 末尾追加 v4.2.0 的 21 个新类型（含递归的 `IndustryPeerNode`）。
- `Core/MarketProtocol.jl` 末尾追加 `TopMoversStock/Event/Response`、`RankListItem/Response`、`RankCategoriesResponse`。
- `Core/QuoteProtocol.jl` 中的 `ShortPosition*` 类型保留为 `Quote.jl` 内的定义（与现状一致）；重写为新结构。
- 精编预热：`ScreenerContext(cfg)` 加入 `@compile_workload`。

### Reference

上游对应版本：[longbridge/openapi v4.2.0](https://github.com/longbridge/openapi/releases/tag/v4.2.0)（2026-05-22 发布）。

## v0.7.0 (2026-05-19)

### New Features — 补齐与上游 LongPort SDK Rust v4.1.0 的完全同步（130 个方法 1:1 对齐）

- **新 `AssetContext`（2 个方法）** —— `statements(ctx, type; page, page_size)` 与 `statement_download_url(ctx, file_key)`，对应上游 `/v1/statement/list` 和 `/v1/statement/download`。新增 `StatementType.{Daily, Monthly}` 枚举与 `StatementItem`/`GetStatementListResponse`/`GetStatementResponse` 结构。
- **`QuoteContext.filings(ctx, symbol)`** —— 公司公告列表（REST `/v1/quote/filings`），`publish_at` unix 秒自动转 `DateTime`。新增 `FilingItem` 结构。
- **`QuoteContext.quote_package_details(ctx)`** —— 当前账户已订阅的行情包详情列表（`Vector{QuotePackageDetail}`，含 `key/name/description/start_at/end_at`）。

### Behavior changes（**破坏性**）

- **`realtime_quote` 语义变更**：原本是「向服务器一次性查询」，现在改为「读本地缓存的最新推送行情」，与 `realtime_depth`/`realtime_brokers`/`realtime_trades` 一致（这是 Rust SDK 的语义）。
  - 旧行为迁移到新方法 **`quote_snapshot(ctx, symbols)`**（一次性服务器请求，仍返回 `DataFrame`）。
  - 新 `realtime_quote(ctx, symbol::String)` 返回单条 `Union{Nothing, PushQuote}`；`realtime_quote(ctx, symbols::Vector{String})` 返回 `Vector{Union{Nothing, PushQuote}}`。
- **`member_id` / `quote_level` 现在会真正拉取**：之前是返回零值的桩。`QuoteContext` 在 WebSocket 鉴权成功后会主动发 `QueryUserQuoteProfile (cmd=4)`，把 `member_id`、`quote_level`、`quote_package_details` 落到 `InnerQuoteContext`。失败只 warn 不阻断。

### Internals

- `QuoteProtocol.jl` 新增手写 protobuf 编解码：`UserQuoteProfileRequest`、`UserQuoteProfileResponse`、`QuotePackageDetail`。`UserQuoteLevelDetail.by_package_key` 是 proto `map<string, PackageDetail>`，按 protobuf 规范展开为 entry 子消息（field 1=key, field 2=value），跳过暂不消费的 `by_market_code` / `rate_limit` / `subscribe_limit`。
- `Config.language` (`Language.{ZH_CN,ZH_HK,EN}`) 按上游 wire 格式转 `"zh-CN"` / `"zh-HK"` / `"en"`。

### Migration

```julia
# 旧（v0.6.x）
df = realtime_quote(ctx, ["AAPL.US", "TSLA.US"])

# 新（v0.7.0）
df = quote_snapshot(ctx, ["AAPL.US", "TSLA.US"])  # 服务器查询，DataFrame

# 想读本地缓存（订阅后才有数据）
subscribe(ctx, ["AAPL.US"], [SubType.QUOTE])
q = realtime_quote(ctx, "AAPL.US")                # Union{Nothing, PushQuote}
```

### Reference comparison tooling

- `.upstream/` 目录加入 `.gitignore`，可用于本地克隆 `longbridge/openapi` 做 1:1 方法对比。

## v0.6.0 (2026-05-18)

### New Features — 移植上游 LongPort SDK v4.1.0 的 9 个新 Context（共 70 个新方法、~5,100 行）

P0（HTTP-only 只读分析，4 个 Context + QuoteContext 扩展）：

- **`FundamentalContext`** — 20 个方法：财报、分析师评级、股息、EPS 预测、一致预期、估值、行业对比、公司概况、高管、股东、基金持仓、公司行动、回购、多维度评级
- **`MarketContext`** — 9 个方法：市场状态、券商持仓（top/明细/日度）、A/H 溢价（K 线/分时）、成交统计、异动、指数成份股
- **`CalendarContext`** — `finance_calendar` 支持 8 种事件类别（财报/分红/拆股/IPO/宏观/休市/会议/合并）
- **`PortfolioContext`** — 5 个方法：汇率、盈亏分析（总览 + 按市场 + 单只明细 + 流水）
- **`QuoteContext`** — 4 个新方法：`short_positions`、`option_volume`、`option_volume_daily`、`update_pinned`

P1（社区/计划管理，4 个 Context）：

- **`AlertContext`** — 4 个方法：价格提醒 CRUD（`list_alerts`/`add_alert`/`update_alert`/`delete_alerts`）
- **`SharelistContext`** — 8 个方法：社区自选股列表（`list_sharelists`/`sharelist_detail`/`popular_sharelists`/`create_sharelist`/`delete_sharelist`/`add_sharelist_securities`/`remove_sharelist_securities`/`sort_sharelist_securities`）
- **`DCAContext`** — 12 个方法：定投全生命周期（`list_dca`/`create_dca`/`update_dca`/`pause_dca`/`resume_dca`/`stop_dca`/`dca_history`/`dca_stats`/`dca_check_support`/`dca_calc_date`/`dca_set_reminder`）
- **`ContentContext`** — 7 个方法：社区话题与资讯（`my_topics`/`create_topic`/`topics_by_symbol`/`topic_detail`/`topic_replies`/`create_topic_reply`/`news`）

### Architecture

- **HTTP-only Context 不用 actor pattern** — 新 Context 都是简单的 `struct X; config::Settings; end`，直接调 `Client.http_get/post/put/delete`。`institution_rating` / `profit_analysis` 用 `Threads.@spawn` 真并行 fan-out 调用两个端点。
- **typed enums via `EnumX.@enumx`** — 所有 API 参数都是类型安全的（`FinancialReportKind`、`CalendarCategory`、`AlertCondition`、`DCAFrequency` 等共 14 个新枚举）。
- **`DecFP.Dec64` 用于货币/价格/比率字段** — 匹配上游 `rust_decimal::Decimal`，避免 Float64 在分红/盈亏计算的精度问题。`_parse_optional_decimal` 对 `""`、`null`、`"--"` 等占位符统一返回 `nothing`。
- **`MarketCtx/` 文件夹（类型名仍叫 `MarketContext`）** — 避免与 `Constant.Market` 枚举命名冲突。
- **`Client.http_delete` 支持 body** — Alert/Sharelist 的 DELETE 接口需要 JSON body。
- **方法命名加前缀避免顶层冲突** — `list_alerts`/`list_sharelists`/`list_dca` 等（Rust 用方法绑定可全叫 `list`，Julia 顶层导出需要消歧）。

### New Utilities (`Core/Utils.jl`)

- `Dec64` 重导出（无需 `using DecFP`）
- `symbol_to_counter_id("TSLA.US") → "ST/US/TSLA"`（含 4574 行嵌入式美股 ETF 表，懒加载）
- `index_symbol_to_counter_id("HSI.HK") → "IX/HK/HSI"`
- `counter_id_to_symbol("ST/HK/700") → "700.HK"`
- `_parse_optional_decimal` 容错占位符

### Dependencies

- 新增 `DecFP = "1"`

### Tests

- 烟测覆盖 240 项：构造、JSON 反序列化、枚举映射、占位符容错；联机端到端测试通过 `examples/p0_analytics.jl` 与 `examples/p1_community.jl` 手验。

### Examples

- 新增 `examples/p0_analytics.jl` — 4 个新 Context 的全部代表性调用
- 新增 `examples/p1_community.jl` — 价格提醒 / 自选股 / 定投 / 社区 的全套用法（写操作默认注释掉）

## v0.5.2 (2026-05-03)

### Bug fixes

- **`get_otp` 与 `refresh_token` 仍调用旧 `get`**：v0.5.1 把 HTTP 辅助函数从 `get`/`post`/`put`/`delete` 改名为 `http_get` 等，但 `Client.jl::get_otp` (line 197) 和 `Client.jl::refresh_token` (line 175) 内部还在用 `get(config, ...)`。重命名后这两个调用变成 `Base.get(::Settings, ::String)`，立刻报 `MethodError`。修：改为 `http_get(config, ...)`。

## v0.5.1 (2026-05-03)

### Bug fixes

- **消息循环立即崩溃**：`v0.5.0` 在 `Client.jl::start_message_loop` 里用 `get(client.pending, request_id, nothing)` 派发响应。但 `Client.jl:148` 早就定义了一个 `get(config::Config.Settings, path::String; params)` HTTP 辅助函数，在 `Client` 模块内屏蔽了 `Base.get`。结果认证响应一到就抛 `MethodError`，连接直接断掉。修：把 4 个 HTTP 辅助函数从 `get`/`post`/`put`/`delete` 改名为 `http_get`/`http_post`/`http_put`/`http_delete`，停止屏蔽 `Base` 名字（julia-style 第 18 条）；同步更新 `Trade.jl` 和 `Quote.jl` 的两处 `Client.get` 调用点。这些函数都不在 `LongBridge` 顶层导出，仅供内部使用。

## v0.5.0 (2026-05-03)

### Bug Fixes

- **OAuth `build` 永久阻塞**：`authorize!` 中的 `@sync` + `Timer` 组合导致即使浏览器授权完成，仍要等满 5 分钟超时才返回。重写为单 `Channel{Tuple{Symbol,String}}(1)` + `Timer(callback)`，回调即时唤醒。
- **Trade 推送 pipeline 完全无法工作**：
  - `Trade/TradePush.jl` 中本地复制了一个错误结构的 `PushOrderChanged`（字段全是 `String`），与协议层定义不一致；调用 `PushOrderChanged()` 无参构造不存在；`PB` 别名未导入。
  - `Trade/Trade.jl` 中 `PB.decode(IOBuffer(body), Notification)` 调用错误——`PB.decode` 期望 `AbstractProtoDecoder`。
  - 修：重写 TradePush 使用协议层的真实 `PushOrderChanged`，按 `ContentType.CONTENT_JSON` 解析 `Notification.data`；用 `Base.invokelatest` 调用回调；修正 decode 调用。
- **`set_on_candlestick(ctx, cb)` 抛 `UndefVarError`**：调用了不存在的 `QuotePush.set_on_candlestick!`。补齐 `QuotePush.Callbacks.candlestick` 字段、`handle_candlestick`、`set_on_candlestick!`，并在 `PushEventDetail` 中加入 `CandlestickEvent`。
- **`LongportError` 旧符号残留** (Trade/Trade.jl:94)：清理为 `LongBridgeError`，并将 `e.code == "ws-disconnected"` 这种类型不匹配的比较改为 `occursin("WebSocket", e.message)`。
- **`LongBridgeException` 旧符号残留** (Client.jl, Config.jl, Quote.jl 共 5 处)：替换为 `LongBridgeError`。

### Performance

- **`ws_request` 不再 busy-wait**：原实现每次 API 调用都 `while sleep(0.01)` 轮询 `pending_responses::Dict`，最差额外 10ms 延迟。改为每个 request 一个 `Channel{Tuple{UInt8,Vector{UInt8}}}(1)`、`take!` 阻塞唤醒，`Timer(callback) close(ch)` 实现超时；新增 `WSClient.send_lock::ReentrantLock` 保证 (alloc seq_id + register channel + send packet) 原子。
- **`connect!` 认证等待不再 busy-wait**：原实现 `while !connected sleep(0.1)` 轮询。改为 `WSClient.auth_event::Threads.Event`，认证响应到达消息循环时 `notify`，`connect!` 端 `wait` 阻塞，配合 `Timer` 实现 30s 超时。
- **Channel 类型收紧**：`InnerQuoteContext.command_ch`、`InnerTradeContext.command_ch` 从 `Channel{Any}` → `Channel{AbstractCommand}`；Quote 的推送通道从 `Channel{Any}` → `Channel{Tuple{UInt8, Vector{UInt8}}}`。
- **删除死缓存字段**：`InnerQuoteContext` 中 4 个 `Vector{Any}` 类型的 cache 字段 (`cache_participants`/`cache_issuers`/`cache_option_chain_*`) 从未被任何函数读写，删除。

### API

- **`Config.config` → `Config.Settings`**：类型名改为 CamelCase 符合风格惯例；`const config = Settings` 别名保留，`Config.config(...)` 仍然 work。`Settings` 同时在顶层导出。
- **`set_on_candlestick(ctx, cb)`** 现在真正工作（之前直接报错）。

### Workflow

- **PrecompileTools 工作负载**：在 `LongBridge.jl` 顶层加 `@compile_workload`，预热 `Config.Settings`、`OAuth.OAuthToken`、`LongBridgeError` 构造路径，降低 TTFX。
- **Revise 移出 `[deps]`**：之前作为运行时硬依赖不合理。现仅在 `[extras]+[targets].test`，使用方按需 `using Revise`。

### Style cleanup

- 删 `__precompile__()`（Julia 1.5+ 默认行为）。
- 删 `Core/QuoteProtocol.jl` 中 16 处 `show(io, x::T) = ...`——未加 `Base.` 前缀，定义在模块本地永远不会被 `print`/`display` 调用，是死代码（`EnumX` 已自动注册 `Base.show`）。
- `set_on_quote/depth/brokers/trades/candlestick` (Quote.jl)、`set_on_order_changed` (Trade.jl)、各 `set_on_*!` (QuotePush/TradePush) 改为单行赋值式，去掉过严的 `cb::Function` 注解。
- `Core/Utils.jl:80` 去除 `if` 条件外的多余括号。

## v0.4.0 (2026-03-14)

### Breaking Changes

- **SDK Renamed**: Module renamed from `LongPort` to `LongBridge` (`using LongBridge`)
- **Error Type Renamed**: `LongPortError` → `LongBridgeError`

### New Features

- **OAuth 2.0 Authentication**: Added `OAuth` module with browser-based authorization code flow
  - `OAuthBuilder("client-id") |> build(open_url_fn)` for one-line setup
  - Automatic token persistence to `.tokens/<client_id>` and transparent refresh
  - `Config.from_oauth(oauth_handle)` to create config from OAuth handle
  - Dual auth mode in Client: OAuth (Bearer token) and API Key (HMAC signature)

### Fixes

- Fixed extra `Bearer ` prefix in API Key mode HMAC signature

### Other

- Removed `TagBot.yml` workflow
- Updated dependencies (HTTP 1.11, ProtoBuf 1.3, etc.)

## v0.3.1 (2026-01-25)

### Performance Optimizations

- **Type Stability**: Made struct fields type-stable across all modules:
  - `Commands.jl`: Made `HttpPostCmd{B}` and `HttpPutCmd{B}` parametric to avoid `body::Any` boxing
  - `Quote.jl`: Made `GenericRequestCmd{R,T}` parametric for type-stable request/response handling
- **Memory Allocation Reduction**:
  - `Client.jl`: `sign()` uses `IOBuffer` + `print()` instead of string interpolation to reduce intermediate allocations
  - `Client.jl`: `send_request_packet()` uses pre-sized `IOBuffer(sizehint=...)` and writes body_len bytes directly instead of creating intermediate array
  - `Client.jl`: Replaced `"quote_response_$(id)"` with `string("quote_response_", id)` for faster string creation

### Breaking Changes

- **Struct Type Changes**: Several struct types are now parametric:
  - `HttpPostCmd{B}` and `HttpPutCmd{B}` in `Commands` (was non-parametric)
  - `GenericRequestCmd{R,T}` in `Quote` (was non-parametric)

## v0.3.0 (2026-01-23)

### New Features

- **RealtimeStore**: Added local data caching for WebSocket push events
  - `RealtimeStore{Q,D,B,T,C}` parametric struct in Cache module
  - Thread-safe storage with `ReentrantLock`
  - Automatically caches all push data (quotes, depth, brokers, trades)

- **Realtime Data Access Methods**: New methods to read cached push data
  - `realtime_depth(ctx, symbol)` - Get cached depth data
  - `realtime_brokers(ctx, symbol)` - Get cached broker queue
  - `realtime_trades(ctx, symbol; count)` - Get cached trades
  - `realtime_candlesticks(ctx, symbol, period; count)` - Get cached K-lines

- **Candlestick Subscription**: New methods for K-line subscription
  - `subscribe_candlesticks(ctx, symbol, period; count)` - Subscribe and get initial data
  - `unsubscribe_candlesticks(ctx, symbol, period)` - Unsubscribe and clear cache

### Breaking Changes

- **Struct Type Changes**: Several struct types are now parametric, which may affect code that explicitly typed these structs:
  - `LongBridgeError{T}` (was `LongBridgeError`)
  - `PushEvent{T}` in `QuotePush` and `TradeProtocol`
  - `CacheItem{T}` in `Cache`

### Performance Optimizations

- **Type Stability**: Made struct fields type-stable across all modules:
  - `Cache.jl`: Fixed `CacheItem{T}` parametric type, typed callbacks with `F where F`
  - `Errors.jl`: Made `LongBridgeError{T}` parametric with typed payload
  - `TradeProtocol.jl`: Made `PushEvent{T}` parametric
  - `QuotePush.jl`: Made `PushEvent{T}` parametric
  - `TradePush.jl`: Changed `AbstractString` to `String` in `PushOrderChanged`
  - `Quote.jl`: Changed `cache_trading_sessions` from `SimpleCache{Any}` to `SimpleCache{DataFrame}`
- **Typed Arrays**: Replaced untyped `[]` with typed arrays (`String[]`, `K[]`) in `Cache.jl` and `Client.jl` to avoid `Vector{Any}`
- **Pre-allocation**: Added `@inbounds` for hot loops in `Utils.jl`
- **Code Cleanup**: Removed `@show` debug statement from `history_candlesticks_by_offset`

### Refactoring

- **`disconnect!` Function**: Moved `disconnect!` implementations back to `Quote.jl` and `Trade.jl` modules (type defines methods pattern)
- **Module Cleanup**: Removed unused `__init__` function from `LongBridge.jl`

### Bug Fixes

- **QuoteProtocol.jl**: Fixed `ProtoBuf.ProtoBuf.AbstractProtoEncoder` typo → `ProtoBuf.AbstractProtoEncoder`
- **test/runtest.jl**: Fixed config constructor calls to use correct parameter names and added required `token_expire_time`

## v0.2.9 (2025-08-25)

### Bug Fixes

- **WebSocket Connection**: Fixed a critical bug where the `config` object was not being passed to the `WSClient` constructor in the `Quote` and `Trade` contexts. This caused connection failures by preventing necessary parameters, such as `enable_overnight`, from being correctly configured.

## v0.2.8 (2025-08-18)

### New Features

- **Intraday Data**: The `intraday` function now supports a `trade_session` parameter, allowing users to fetch data for specific trading sessions (e.g., pre-market, post-market).

### Refactoring

- **`disconnect!` Function**: Moved the `disconnect!` function from the `Quote` and `Trade` modules to the main `LongBridge` module, using multiple dispatch to handle both `QuoteContext` and `TradeContext` types. This simplifies the API and improves code organization.

## v0.2.7 (2025-08-15)

### Major Improvements

- **Dependencies & Compatibility**: Updated `Project.toml` with strict `[compat]` bounds for all dependencies and raised the minimum Julia version to `1.10` for better performance and stability.
- **WebSocket Stability**: Implemented a robust WebSocket handling mechanism, including:
    - Heartbeat (ping/pong) to keep connections alive.
    - Automatic re-subscription of topics upon reconnection.
- **HTTP Performance**: Introduced `HTTP.ConnectionPool` to reuse connections, significantly reducing latency for frequent API calls. Added timeout and retry strategies for GET requests.
- **Protocol Correctness**: Ensured all `@enum` types have explicit integer values matching the server-side protocol, preventing potential misinterpretations.
- **Error Handling**: Replaced the basic exception type with a more informative `Long
