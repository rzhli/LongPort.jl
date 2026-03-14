"""
缓存机制模块

提供基于时间的缓存功能，用于提高API调用性能。
同时提供实时数据存储，用于缓存WebSocket推送的实时行情数据。
"""
module Cache

using Dates

export SimpleCache, CacheWithKey, get_or_update, RealtimeStore,
       update_quote!, update_depth!, update_brokers!, update_trades!, update_candlesticks!,
       get_quote, get_depth, get_brokers, get_trades, get_candlesticks,
       clear_store!, clear_candlesticks!

"""
CacheItem

缓存项，包含数据和过期时间。
"""
mutable struct CacheItem{T}
    data::T
    expires_at::DateTime
    
    function CacheItem(data::T, ttl_seconds::Float64) where {T}
        new{T}(data, now() + Second(floor(Int, ttl_seconds)))
    end
end

"""
SimpleCache

简单缓存，用于缓存单个值。
"""
mutable struct SimpleCache{T}
    item::Union{Nothing, CacheItem{T}}
    ttl_seconds::Float64

    function SimpleCache{T}(ttl_seconds::Float64) where T
        new{T}(nothing, ttl_seconds)
    end
end

"""
CacheWithKey

带键的缓存，用于缓存多个值。
"""
mutable struct CacheWithKey{K, V}
    items::Dict{K, CacheItem{V}}
    ttl_seconds::Float64
    
    function CacheWithKey{K, V}(ttl_seconds::Float64) where {K, V}
        new(Dict{K, CacheItem{V}}(), ttl_seconds)
    end
end

"""
is_expired(item::CacheItem) -> Bool

检查缓存项是否过期。
"""
function is_expired(item::CacheItem)::Bool
    return now() > item.expires_at
end

"""
get_or_update(cache::SimpleCache{T}, update_func::F) -> T

获取缓存值或更新缓存。

# Arguments
- `cache::SimpleCache{T}`: 缓存对象
- `update_func::F`: 更新函数，应该返回新的值

# Returns
- `T`: 缓存的值

# Examples
```julia
cache = SimpleCache{Vector{String}}(300.0)  # 5分钟TTL
result = get_or_update(cache) do
    # 获取数据的耗时操作
    ["AAPL.US", "GOOGL.US", "MSFT.US"]
end
```
"""
function get_or_update(cache::SimpleCache{T}, update_func::F)::T where {T, F}
    # 检查是否有缓存且未过期
    if !isnothing(cache.item) && !is_expired(cache.item)
        return cache.item.data
    end
    
    # 缓存过期或不存在，更新缓存
    try
        new_data = update_func()
        cache.item = CacheItem(new_data, cache.ttl_seconds)
        return new_data
    catch e
        # 如果更新失败，且有旧缓存，则返回旧缓存
        if !isnothing(cache.item)
            @warn "Cache update failed, using stale data" exception=(e, catch_backtrace())
            return cache.item.data
        else
            rethrow(e)
        end
    end
end

"""
get_or_update(cache::CacheWithKey{K, V}, key::K, update_func::F) -> V

获取带键缓存的值或更新缓存。

# Arguments
- `cache::CacheWithKey{K, V}`: 缓存对象
- `key::K`: 缓存键
- `update_func::F`: 更新函数，接收key作为参数，返回新的值

# Returns
- `V`: 缓存的值

# Examples
```julia
cache = CacheWithKey{String, Vector{String}}(300.0)  # 5分钟TTL
result = get_or_update(cache, "AAPL.US") do symbol
    # 获取该股票相关数据的耗时操作
    get_related_symbols(symbol)
end
```
"""
function get_or_update(cache::CacheWithKey{K, V}, key::K, update_func::F)::V where {K, V, F}
    # 检查是否有缓存且未过期
    if haskey(cache.items, key) && !is_expired(cache.items[key])
        return cache.items[key].data
    end
    
    # 缓存过期或不存在，更新缓存
    try
        new_data = update_func(key)
        cache.items[key] = CacheItem(new_data, cache.ttl_seconds)
        return new_data
    catch e
        # 如果更新失败，且有旧缓存，则返回旧缓存
        if haskey(cache.items, key)
            @warn "Cache update failed for key $key, using stale data" exception=(e, catch_backtrace())
            return cache.items[key].data
        else
            rethrow(e)
        end
    end
end

"""
clear_cache!(cache::SimpleCache)

清空简单缓存。
"""
function clear_cache!(cache::SimpleCache)
    cache.item = nothing
end

"""
clear_cache!(cache::CacheWithKey)

清空带键缓存。
"""
function clear_cache!(cache::CacheWithKey)
    empty!(cache.items)
end

"""
clear_cache!(cache::CacheWithKey, key)

清空带键缓存中指定键的值。
"""
function clear_cache!(cache::CacheWithKey, key)
    delete!(cache.items, key)
end

"""
cleanup_expired!(cache::CacheWithKey)

清理带键缓存中过期的项。
"""
function cleanup_expired!(cache::CacheWithKey{K, V}) where {K, V}
    expired_keys = K[]
    for (key, item) in cache.items
        if is_expired(item)
            push!(expired_keys, key)
        end
    end
    
    for key in expired_keys
        delete!(cache.items, key)
    end
    
    return length(expired_keys)
end

"""
cache_stats(cache::SimpleCache) -> NamedTuple

获取简单缓存的统计信息。
"""
function cache_stats(cache::SimpleCache)
    has_data = !isnothing(cache.item)
    is_valid = has_data && !is_expired(cache.item)
    
    return (
        has_data = has_data,
        is_valid = is_valid,
        ttl_seconds = cache.ttl_seconds
    )
end

"""
cache_stats(cache::CacheWithKey) -> NamedTuple

获取带键缓存的统计信息。
"""
function cache_stats(cache::CacheWithKey)
    total_items = length(cache.items)
    expired_items = count(is_expired, values(cache.items))
    valid_items = total_items - expired_items
    
    return (
        total_items = total_items,
        valid_items = valid_items,
        expired_items = expired_items,
        ttl_seconds = cache.ttl_seconds
    )
end

# =============================================================================
# Realtime Store - 用于缓存WebSocket推送的实时行情数据
# =============================================================================

"""
    SecurityData{Q, D, B, T}

单个证券的实时数据存储。

# Type Parameters
- `Q`: Quote数据类型 (PushQuote)
- `D`: Depth数据类型 (PushDepth)
- `B`: Brokers数据类型 (PushBrokers)
- `T`: Trade数据类型
"""
mutable struct SecurityData{Q, D, B, T}
    quote_data::Union{Nothing, Q}
    depth::Union{Nothing, D}
    brokers::Union{Nothing, B}
    trades::Vector{T}
    max_trades::Int

    function SecurityData{Q, D, B, T}(; max_trades::Int = 500) where {Q, D, B, T}
        new{Q, D, B, T}(nothing, nothing, nothing, T[], max_trades)
    end
end

"""
    CandlestickData{C}

K线数据存储。

# Type Parameters
- `C`: Candlestick数据类型
"""
mutable struct CandlestickData{C}
    candlesticks::Vector{C}
    max_count::Int

    function CandlestickData{C}(; max_count::Int = 1000) where C
        new{C}(C[], max_count)
    end
end

"""
    RealtimeStore{Q, D, B, T, C}

实时数据存储，用于缓存WebSocket推送的行情数据。

# Type Parameters
- `Q`: Quote数据类型 (PushQuote)
- `D`: Depth数据类型 (PushDepth)
- `B`: Brokers数据类型 (PushBrokers)
- `T`: Trade数据类型
- `C`: Candlestick数据类型

# Usage
```julia
using LongBridge.Core.QuoteProtocol: PushQuote, PushDepth, PushBrokers, Trade, Candlestick
store = RealtimeStore{PushQuote, PushDepth, PushBrokers, Trade, Candlestick}()

# Update from push events
update_quote!(store, "700.HK", quote_data)
update_depth!(store, "700.HK", depth_data)

# Get cached data
quote = get_quote(store, "700.HK")
depth = get_depth(store, "700.HK")
```
"""
mutable struct RealtimeStore{Q, D, B, T, C}
    securities::Dict{String, SecurityData{Q, D, B, T}}
    candlesticks::Dict{Tuple{String, Int}, CandlestickData{C}}  # (symbol, period) -> data
    lock::ReentrantLock

    function RealtimeStore{Q, D, B, T, C}() where {Q, D, B, T, C}
        new{Q, D, B, T, C}(
            Dict{String, SecurityData{Q, D, B, T}}(),
            Dict{Tuple{String, Int}, CandlestickData{C}}(),
            ReentrantLock()
        )
    end
end

# Helper to get or create security data
function _get_security!(store::RealtimeStore{Q, D, B, T, C}, symbol::String) where {Q, D, B, T, C}
    get!(store.securities, symbol) do
        SecurityData{Q, D, B, T}()
    end
end

"""
    update_quote!(store::RealtimeStore, symbol::String, quote)

更新证券的实时报价数据。
"""
function update_quote!(store::RealtimeStore{Q, D, B, T, C}, symbol::String, quote_data::Q) where {Q, D, B, T, C}
    lock(store.lock) do
        security = _get_security!(store, symbol)
        security.quote_data = quote_data
    end
end

"""
    update_depth!(store::RealtimeStore, symbol::String, depth)

更新证券的盘口深度数据。
"""
function update_depth!(store::RealtimeStore{Q, D, B, T, C}, symbol::String, depth::D) where {Q, D, B, T, C}
    lock(store.lock) do
        security = _get_security!(store, symbol)
        security.depth = depth
    end
end

"""
    update_brokers!(store::RealtimeStore, symbol::String, brokers)

更新证券的经纪队列数据。
"""
function update_brokers!(store::RealtimeStore{Q, D, B, T, C}, symbol::String, brokers::B) where {Q, D, B, T, C}
    lock(store.lock) do
        security = _get_security!(store, symbol)
        security.brokers = brokers
    end
end

"""
    update_trades!(store::RealtimeStore, symbol::String, trades::Vector)

更新证券的成交明细数据。新成交追加到末尾，超过max_trades时删除最旧的数据。
"""
function update_trades!(store::RealtimeStore{Q, D, B, T, C}, symbol::String, new_trades::Vector{T}) where {Q, D, B, T, C}
    lock(store.lock) do
        security = _get_security!(store, symbol)
        append!(security.trades, new_trades)
        # 保留最新的 max_trades 条记录
        if length(security.trades) > security.max_trades
            deleteat!(security.trades, 1:(length(security.trades) - security.max_trades))
        end
    end
end

"""
    update_candlesticks!(store::RealtimeStore, symbol::String, period::Int, candlesticks::Vector)

更新或初始化证券的K线数据。
"""
function update_candlesticks!(store::RealtimeStore{Q, D, B, T, C}, symbol::String, period::Int, new_candlesticks::Vector{C}) where {Q, D, B, T, C}
    lock(store.lock) do
        key = (symbol, period)
        if !haskey(store.candlesticks, key)
            store.candlesticks[key] = CandlestickData{C}()
        end
        data = store.candlesticks[key]
        # Replace with new data (for initial load)
        data.candlesticks = new_candlesticks
    end
end

"""
    get_quote(store::RealtimeStore, symbol::String) -> Union{Nothing, Q}

获取证券的实时报价数据。
"""
function get_quote(store::RealtimeStore{Q, D, B, T, C}, symbol::String)::Union{Nothing, Q} where {Q, D, B, T, C}
    lock(store.lock) do
        security = get(store.securities, symbol, nothing)
        isnothing(security) ? nothing : security.quote_data
    end
end

"""
    get_depth(store::RealtimeStore, symbol::String) -> Union{Nothing, D}

获取证券的盘口深度数据。
"""
function get_depth(store::RealtimeStore{Q, D, B, T, C}, symbol::String)::Union{Nothing, D} where {Q, D, B, T, C}
    lock(store.lock) do
        security = get(store.securities, symbol, nothing)
        isnothing(security) ? nothing : security.depth
    end
end

"""
    get_brokers(store::RealtimeStore, symbol::String) -> Union{Nothing, B}

获取证券的经纪队列数据。
"""
function get_brokers(store::RealtimeStore{Q, D, B, T, C}, symbol::String)::Union{Nothing, B} where {Q, D, B, T, C}
    lock(store.lock) do
        security = get(store.securities, symbol, nothing)
        isnothing(security) ? nothing : security.brokers
    end
end

"""
    get_trades(store::RealtimeStore, symbol::String; count::Int=0) -> Vector{T}

获取证券的成交明细数据。

# Arguments
- `symbol::String`: 证券代码
- `count::Int=0`: 返回的最大条数，0表示返回全部
"""
function get_trades(store::RealtimeStore{Q, D, B, T, C}, symbol::String; count::Int=0)::Vector{T} where {Q, D, B, T, C}
    lock(store.lock) do
        security = get(store.securities, symbol, nothing)
        if isnothing(security)
            return T[]
        end
        trades = security.trades
        if count > 0 && count < length(trades)
            return trades[end-count+1:end]
        end
        return copy(trades)
    end
end

"""
    get_candlesticks(store::RealtimeStore, symbol::String, period::Int; count::Int=0) -> Vector{C}

获取证券的K线数据。

# Arguments
- `symbol::String`: 证券代码
- `period::Int`: K线周期
- `count::Int=0`: 返回的最大条数，0表示返回全部
"""
function get_candlesticks(store::RealtimeStore{Q, D, B, T, C}, symbol::String, period::Int; count::Int=0)::Vector{C} where {Q, D, B, T, C}
    lock(store.lock) do
        key = (symbol, period)
        data = get(store.candlesticks, key, nothing)
        if isnothing(data)
            return C[]
        end
        candlesticks = data.candlesticks
        if count > 0 && count < length(candlesticks)
            return candlesticks[end-count+1:end]
        end
        return copy(candlesticks)
    end
end

"""
    clear_store!(store::RealtimeStore)

清空所有缓存数据。
"""
function clear_store!(store::RealtimeStore)
    lock(store.lock) do
        empty!(store.securities)
        empty!(store.candlesticks)
    end
end

"""
    clear_candlesticks!(store::RealtimeStore, symbol::String, period::Int)

清除指定证券和周期的K线数据（用于取消订阅时）。
"""
function clear_candlesticks!(store::RealtimeStore, symbol::String, period::Int)
    lock(store.lock) do
        delete!(store.candlesticks, (symbol, period))
    end
end

end # module Cache
