module CalendarProtocol

using EnumX, JSON
using ..Utils: Dec64, JSONObject, counter_id_to_symbol
import ..Utils: _parse_optional_decimal, construct

export CalendarCategory,
    CalendarDataKv,
    CalendarEventInfo,
    CalendarDateGroup,
    CalendarEventsResponse,
    _calendar_category_str

@enumx CalendarCategory begin
    Report = 1   # 财报
    Dividend = 2   # 分红
    Split = 3   # 拆股
    Ipo = 4   # IPO
    MacroData = 5   # 宏观数据
    Closed = 6   # 休市
    Meeting = 7   # 股东/分析师会议
    Merge = 8   # 合并/重组
end

function _calendar_category_str(c::CalendarCategory.T)
    c === CalendarCategory.Report ? "report" :
    c === CalendarCategory.Dividend ? "dividend" :
    c === CalendarCategory.Split ? "split" :
    c === CalendarCategory.Ipo ? "ipo" :
    c === CalendarCategory.MacroData ? "macrodata" :
    c === CalendarCategory.Closed ? "closed" :
    c === CalendarCategory.Meeting ? "meeting" :
    c === CalendarCategory.Merge ? "merge" : error("unknown CalendarCategory: $c")
end

# ── CalendarDataKv ──────────────────────────────────────────────────

struct CalendarDataKv
    key::String
    value::String
    value_type::String                   # JSON 字段名 "type"
    value_raw::Union{Dec64,Nothing}
end
function construct(::Type{CalendarDataKv}, obj::JSONObject)
    CalendarDataKv(
        String(get(obj, :key, "")),
        String(get(obj, :value, "")),
        String(get(obj, :type, "")),
        _parse_optional_decimal(get(obj, :value_raw, nothing)),
    )
end

# ── CalendarEventInfo ───────────────────────────────────────────────

struct CalendarEventInfo
    symbol::String                       # 由 counter_id 转换
    market::String
    content::String
    counter_name::String
    date_type::String
    date::String
    chart_uid::String
    data_kv::Vector{CalendarDataKv}
    event_type::String                   # JSON "type"
    datetime::String                     # unix 时间戳字符串
    icon::String
    star::Int                            # 0-3 重要度
    id::String
    financial_market_time::String
    currency::String
    activity_type::String
end
function construct(::Type{CalendarEventInfo}, obj::JSONObject)
    kvs = if haskey(obj, :data_kv) && !isnothing(obj.data_kv)
        [construct(CalendarDataKv, kv) for kv in obj.data_kv]
    else
        CalendarDataKv[]
    end
    CalendarEventInfo(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :market, "")),
        String(get(obj, :content, "")),
        String(get(obj, :counter_name, "")),
        String(get(obj, :date_type, "")),
        String(get(obj, :date, "")),
        String(get(obj, :chart_uid, "")),
        kvs,
        String(get(obj, :type, "")),
        String(get(obj, :datetime, "")),
        String(get(obj, :icon, "")),
        Int(get(obj, :star, 0)),
        String(get(obj, :id, "")),
        String(get(obj, :financial_market_time, "")),
        String(get(obj, :currency, "")),
        String(get(obj, :activity_type, "")),
    )
end

# ── CalendarDateGroup ───────────────────────────────────────────────

struct CalendarDateGroup
    date::String
    count::Int
    infos::Vector{CalendarEventInfo}
end
function construct(::Type{CalendarDateGroup}, obj::JSONObject)
    infos = if haskey(obj, :infos) && !isnothing(obj.infos)
        [construct(CalendarEventInfo, e) for e in obj.infos]
    else
        CalendarEventInfo[]
    end
    CalendarDateGroup(
        String(get(obj, :date, "")),
        Int(get(obj, :count, length(infos))),
        infos,
    )
end

# ── CalendarEventsResponse ──────────────────────────────────────────

struct CalendarEventsResponse
    date::String
    next_date::String
    list::Vector{CalendarDateGroup}
end
function construct(::Type{CalendarEventsResponse}, obj::JSONObject)
    groups = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(CalendarDateGroup, g) for g in obj.list]
    else
        CalendarDateGroup[]
    end
    CalendarEventsResponse(
        String(get(obj, :date, "")),
        String(get(obj, :next_date, "")),
        groups,
    )
end

end # module CalendarProtocol
