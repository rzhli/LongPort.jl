# Release Notes

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
