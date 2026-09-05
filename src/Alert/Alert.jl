module Alert

using ..Config
using ..Client
using ..Errors
using ..Utils: construct, symbol_to_counter_id
using ..AlertProtocol

export AlertContext, list_alerts, add_alert, update_alert, delete_alerts

"""
    AlertContext(config::Config.Settings)

价格提醒上下文。HTTP-only，无 WebSocket。
"""
struct AlertContext
    config::Config.Settings
end

_check(resp) =
    resp.code == 0 ||
    @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))

"""
    list_alerts(ctx::AlertContext) -> AlertList

查询全部价格提醒（按证券分组）。

端点：`GET /v1/notify/reminders`
"""
function list_alerts(ctx::AlertContext)
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/notify/reminders"))
    _check(resp)
    construct(AlertList, resp.data)
end

"""
    add_alert(ctx, symbol, condition::AlertCondition.T, trigger_value, frequency::AlertFrequency.T)

新增价格提醒。`trigger_value` 是触发值（字符串）：
  - 条件为 `PriceRise/PriceFall` 时是价格（如 `"500"`）
  - 条件为 `PercentRise/PercentFall` 时是百分比（如 `"5"`）

端点：`POST /v1/notify/reminders`
"""
function add_alert(
    ctx::AlertContext,
    symbol::AbstractString,
    condition::AlertCondition.T,
    trigger_value::AbstractString,
    frequency::AlertFrequency.T,
)
    cid = symbol_to_counter_id(symbol)
    key =
        (condition === AlertCondition.PriceRise || condition === AlertCondition.PriceFall) ?
        "price" : "chg"
    indicator_id = Int(condition)
    body = Dict{String,Any}(
        "counter_id" => cid,
        "indicator_id" => string(indicator_id),
        "value_map" => Dict{String,Any}(key => String(trigger_value)),
        "frequency" => Int(frequency),
        "enabled" => true,
        "scope" => 0,
        "state" => [1],
    )
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/notify/reminders"; body))
    _check(resp)
    return resp.data
end

"""
    update_alert(ctx::AlertContext, item::AlertItem) -> Any

更新一条提醒。传入 [`list_alerts`](@ref) 拿到的 `AlertItem`；可在调用前修改 `enabled` 切换启用状态。

端点：`POST /v1/notify/reminders`
"""
function update_alert(ctx::AlertContext, item::AlertItem)
    body = Dict{String,Any}(
        "id" => item.id,
        "indicator_id" => item.indicator_id,
        "frequency" => item.frequency,
        "scope" => item.scope,
        "state" => item.state,
        "value_map" => item.value_map,
        "enabled" => item.enabled,
    )
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/notify/reminders"; body))
    _check(resp)
    return resp.data
end

"""
    delete_alerts(ctx::AlertContext, alert_ids::Vector{String}) -> Any

删除一或多条提醒。

端点：`DELETE /v1/notify/reminders`（body 中带 ids 数组）
"""
function delete_alerts(ctx::AlertContext, alert_ids::AbstractVector{<:AbstractString})
    body = Dict{String,Any}("ids" => String[String(id) for id in alert_ids])
    resp = ApiResponse(Client.http_delete(ctx.config, "/v1/notify/reminders"; body))
    _check(resp)
    return resp.data
end

end # module Alert
