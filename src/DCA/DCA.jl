module DCA

using ..Config
using ..Client
using ..Errors
using ..Utils: construct, symbol_to_counter_id
using ..DCAProtocol
using ..DCAProtocol: _dca_frequency_str, _dca_status_str

export DCAContext,
    list_dca,
    create_dca,
    update_dca,
    pause_dca,
    resume_dca,
    stop_dca,
    dca_history,
    dca_stats,
    dca_check_support,
    dca_calc_date,
    dca_set_reminder

"""
    DCAContext(config::Config.Settings)

定投（DCA）计划管理上下文。HTTP-only。
"""
struct DCAContext
    config::Config.Settings
end

_check(resp) =
    resp.code == 0 ||
    @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))

# ── list_dca ───────────────────────────────────────────────────────

"""
    list_dca(ctx::DCAContext; status=nothing, symbol=nothing) -> DcaList

查询当前所有定投计划。可按状态/标的过滤。

端点：`GET /v1/dailycoins/query`
"""
function list_dca(
    ctx::DCAContext;
    status::Union{DCAStatus.T,Nothing} = nothing,
    symbol::Union{AbstractString,Nothing} = nothing,
)
    params = Dict{String,Any}("page" => 1, "limit" => 100)
    isnothing(status) || (params["status"] = _dca_status_str(status))
    isnothing(symbol) || (params["counter_id"] = symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/dailycoins/query"; params))
    _check(resp)
    construct(DcaList, resp.data)
end

# ── create_dca ─────────────────────────────────────────────────────

"""
    create_dca(ctx, symbol, amount, frequency; day_of_week=nothing, day_of_month=nothing, allow_margin=false)

新建定投计划。

- `amount` 是每期投入金额（字符串，如 `"1000"`）
- `frequency` 是 [`DCAFrequency`](@ref) 之一
- `day_of_week`（如 `"Mon"`）仅周/双周频率有效
- `day_of_month`（1-31）仅月度频率有效
- `allow_margin` 是否允许融资融券

端点：`POST /v1/dailycoins/create`
"""
function create_dca(
    ctx::DCAContext,
    symbol::AbstractString,
    amount::AbstractString,
    frequency::DCAFrequency.T;
    day_of_week::Union{AbstractString,Nothing} = nothing,
    day_of_month::Union{Integer,Nothing} = nothing,
    allow_margin::Bool = false,
)
    body = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "per_invest_amount" => String(amount),
        "invest_frequency" => _dca_frequency_str(frequency),
        "allow_margin_finance" => allow_margin ? 1 : 0,
    )
    isnothing(day_of_week) || (body["invest_day_of_week"] = String(day_of_week))
    isnothing(day_of_month) || (body["invest_day_of_month"] = string(Int(day_of_month)))
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/dailycoins/create"; body))
    _check(resp)
    construct(DcaCreateResult, resp.data)
end

# ── update_dca ─────────────────────────────────────────────────────

"""
    update_dca(ctx, plan_id; amount, frequency, day_of_week, day_of_month, allow_margin)

修改既有定投计划。所有字段都是可选；只传你想改的。

端点：`POST /v1/dailycoins/update`
"""
function update_dca(
    ctx::DCAContext,
    plan_id::AbstractString;
    amount::Union{AbstractString,Nothing} = nothing,
    frequency::Union{DCAFrequency.T,Nothing} = nothing,
    day_of_week::Union{AbstractString,Nothing} = nothing,
    day_of_month::Union{Integer,Nothing} = nothing,
    allow_margin::Union{Bool,Nothing} = nothing,
)
    body = Dict{String,Any}("plan_id" => String(plan_id))
    isnothing(amount) || (body["per_invest_amount"] = String(amount))
    isnothing(frequency) || (body["invest_frequency"] = _dca_frequency_str(frequency))
    isnothing(day_of_week) || (body["invest_day_of_week"] = String(day_of_week))
    isnothing(day_of_month) || (body["invest_day_of_month"] = string(Int(day_of_month)))
    isnothing(allow_margin) || (body["allow_margin_finance"] = allow_margin ? 1 : 0)
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/dailycoins/update"; body))
    _check(resp)
    construct(DcaCreateResult, resp.data)
end

# ── pause / resume / stop ──────────────────────────────────────────

function _toggle_dca(ctx::DCAContext, plan_id::AbstractString, status::AbstractString)
    body = Dict{String,Any}("plan_id" => String(plan_id), "status" => String(status))
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/dailycoins/toggle"; body))
    _check(resp)
    return nothing
end

"""暂停定投计划。"""
pause_dca(ctx::DCAContext, plan_id::AbstractString) = _toggle_dca(ctx, plan_id, "Suspended")

"""恢复已暂停的定投计划。"""
resume_dca(ctx::DCAContext, plan_id::AbstractString) = _toggle_dca(ctx, plan_id, "Active")

"""永久停止定投计划（不可恢复）。"""
stop_dca(ctx::DCAContext, plan_id::AbstractString) = _toggle_dca(ctx, plan_id, "Finished")

# ── dca_history ────────────────────────────────────────────────────

"""
    dca_history(ctx, plan_id; page=1, limit=20) -> DcaHistoryResponse

某计划的执行历史（交易记录）。

端点：`GET /v1/dailycoins/query-records`
"""
function dca_history(
    ctx::DCAContext,
    plan_id::AbstractString;
    page::Integer = 1,
    limit::Integer = 20,
)
    params = Dict{String,Any}(
        "plan_id" => String(plan_id),
        "page" => Int(page),
        "limit" => Int(limit),
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/dailycoins/query-records"; params))
    _check(resp)
    construct(DcaHistoryResponse, resp.data)
end

# ── dca_stats ──────────────────────────────────────────────────────

"""
    dca_stats(ctx; symbol=nothing) -> DcaStats

定投总览统计（活跃/已停止/暂停计数 + 最近计划 + 累计投入/盈亏）。

端点：`GET /v1/dailycoins/statistic`
"""
function dca_stats(ctx::DCAContext; symbol::Union{AbstractString,Nothing} = nothing)
    params = Dict{String,Any}()
    isnothing(symbol) || (params["counter_id"] = symbol_to_counter_id(symbol))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/dailycoins/statistic"; params))
    _check(resp)
    construct(DcaStats, resp.data)
end

# ── dca_check_support ──────────────────────────────────────────────

"""
    dca_check_support(ctx, symbols::AbstractVector{<:AbstractString}) -> DcaSupportList

批量查询标的是否支持定投。

端点：`POST /v1/dailycoins/batch-check-support`
"""
function dca_check_support(ctx::DCAContext, symbols::AbstractVector{<:AbstractString})
    counter_ids = String[symbol_to_counter_id(s) for s in symbols]
    body = Dict{String,Any}("counter_ids" => counter_ids)
    resp = ApiResponse(
        Client.http_post(ctx.config, "/v1/dailycoins/batch-check-support"; body),
    )
    _check(resp)
    construct(DcaSupportList, resp.data)
end

# ── dca_calc_date ──────────────────────────────────────────────────

"""
    dca_calc_date(ctx, symbol, frequency; day_of_week=nothing, day_of_month=nothing) -> DcaCalcDateResult

根据给定调度参数计算下次交易日。返回 unix 时间戳字符串。

端点：`POST /v1/dailycoins/calc-trd-date`
"""
function dca_calc_date(
    ctx::DCAContext,
    symbol::AbstractString,
    frequency::DCAFrequency.T;
    day_of_week::Union{AbstractString,Nothing} = nothing,
    day_of_month::Union{Integer,Nothing} = nothing,
)
    body = Dict{String,Any}(
        "counter_id" => symbol_to_counter_id(symbol),
        "invest_frequency" => _dca_frequency_str(frequency),
    )
    isnothing(day_of_week) || (body["invest_day_of_week"] = String(day_of_week))
    isnothing(day_of_month) || (body["invest_day_of_month"] = string(Int(day_of_month)))
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/dailycoins/calc-trd-date"; body))
    _check(resp)
    construct(DcaCalcDateResult, resp.data)
end

# ── dca_set_reminder ───────────────────────────────────────────────

"""
    dca_set_reminder(ctx, hours::AbstractString)

设置定投执行前的提醒小时数。`hours` 必须是 `"1"`、`"6"`、`"12"` 之一。

端点：`POST /v1/dailycoins/update-alter-hours`
"""
function dca_set_reminder(ctx::DCAContext, hours::AbstractString)
    body = Dict{String,Any}("alter_hours" => String(hours))
    resp =
        ApiResponse(Client.http_post(ctx.config, "/v1/dailycoins/update-alter-hours"; body))
    _check(resp)
    return nothing
end

end # module DCA
