module AlertProtocol

using EnumX, JSON
using ..Utils: Dec64, JSONObject, counter_id_to_symbol
import ..Utils: _parse_optional_decimal, construct

export AlertCondition, AlertFrequency, AlertItem, AlertSymbolGroup, AlertList

@enumx AlertCondition begin
    PriceRise = 1   # 价格涨到
    PriceFall = 2   # 价格跌到
    PercentRise = 3   # 涨幅达到
    PercentFall = 4   # 跌幅达到
end

@enumx AlertFrequency begin
    Daily = 1   # 每天 1 次
    EveryTime = 2   # 每次满足都触发
    Once = 3   # 仅一次
end

function _string_map(obj)
    if obj isa AbstractDict
        return Dict{String,String}(
            String(k) => String(v) for (k, v) in pairs(obj) if !isnothing(v)
        )
    end
    return Dict{String,String}()
end

# ── AlertItem ──────────────────────────────────────────────────────

struct AlertItem
    id::String
    indicator_id::String      # "1"=price_rise, "2"=price_fall, "3"=pct_rise, "4"=pct_fall
    enabled::Bool
    frequency::Int            # 1=daily, 2=every_time, 3=once
    scope::Int
    text::String              # 显示文本（如 "价格涨到 600"）
    state::Vector{Int}
    value_map::Dict{String,String}
end
function construct(::Type{AlertItem}, obj::JSONObject)
    state = if haskey(obj, :state) && !isnothing(obj.state)
        Int[Int(x) for x in obj.state]
    else
        Int[]
    end
    AlertItem(
        String(get(obj, :id, "")),
        String(get(obj, :indicator_id, "")),
        Bool(get(obj, :enabled, false)),
        Int(get(obj, :frequency, 0)),
        Int(get(obj, :scope, 0)),
        String(get(obj, :text, "")),
        state,
        _string_map(get(obj, :value_map, nothing)),
    )
end

# ── AlertSymbolGroup ───────────────────────────────────────────────

struct AlertSymbolGroup
    symbol::String                     # 由 counter_id 转换
    code::String
    market::String
    name::String
    price::Union{Dec64,Nothing}
    chg::Union{Dec64,Nothing}
    p_chg::Union{Dec64,Nothing}
    product::String
    indicators::Vector{AlertItem}
end
function construct(::Type{AlertSymbolGroup}, obj::JSONObject)
    items = if haskey(obj, :indicators) && !isnothing(obj.indicators)
        [construct(AlertItem, x) for x in obj.indicators]
    else
        AlertItem[]
    end
    AlertSymbolGroup(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :code, "")),
        String(get(obj, :market, "")),
        String(get(obj, :name, "")),
        _parse_optional_decimal(get(obj, :price, nothing)),
        _parse_optional_decimal(get(obj, :chg, nothing)),
        _parse_optional_decimal(get(obj, :p_chg, nothing)),
        String(get(obj, :product, "")),
        items,
    )
end

# ── AlertList ──────────────────────────────────────────────────────

struct AlertList
    lists::Vector{AlertSymbolGroup}
end
function construct(::Type{AlertList}, obj::JSONObject)
    items = if haskey(obj, :lists) && !isnothing(obj.lists)
        [construct(AlertSymbolGroup, x) for x in obj.lists]
    else
        AlertSymbolGroup[]
    end
    AlertList(items)
end

end # module AlertProtocol
