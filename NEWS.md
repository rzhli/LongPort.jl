# Release Notes

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
