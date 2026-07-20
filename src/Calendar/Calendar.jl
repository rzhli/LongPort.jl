module Calendar

using StructTypes, Dates

using ..Config
using ..Client
using ..Errors
using ..CalendarProtocol

export CalendarContext, finance_calendar

"""
    CalendarContext(config::Config.Settings)

财务日历上下文。无 WebSocket 连接，所有方法都是同步 HTTP 调用。
"""
struct CalendarContext
    config::Config.Settings
end

"""
    finance_calendar(ctx::CalendarContext, category::CalendarCategory.T, start::Date, end_::Date; market=nothing)

查询财务日历事件（财报 / 分红 / 拆股 / IPO / 宏观数据 / 休市等）。

# 参数
- `category`: 事件类型，见 [`CalendarCategory`](@ref)
- `start`, `end_`: 起止日期（含）
- `market`: 可选，按市场过滤（如 `"HK"`、`"US"`、`"CN"`）

返回的 `CalendarEventsResponse.next_date` 是下一页游标；继续请求时可将它作为
`start`，并保持同一个 `end_`。

# 端点
`GET /v1/quote/finance_calendar`
"""
function finance_calendar(
    ctx::CalendarContext,
    category::CalendarCategory.T,
    start::Date,
    end_::Date;
    market::Union{AbstractString,Nothing} = nothing,
)
    params = Dict{String,Any}(
        "date" => Dates.format(start, dateformat"yyyy-mm-dd"),
        "date_end" => Dates.format(end_, dateformat"yyyy-mm-dd"),
        "types[]" => _calendar_category_str(category),
    )
    isnothing(market) || (params["markets[]"] = String(market))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/quote/finance_calendar"; params))
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    StructTypes.construct(CalendarEventsResponse, resp.data)
end

end # module Calendar
