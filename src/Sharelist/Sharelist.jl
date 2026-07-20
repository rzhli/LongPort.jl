module Sharelist

using StructTypes

using ..Config
using ..Client
using ..Errors
using ..Utils: symbol_to_counter_id
using ..SharelistProtocol

export SharelistContext,
    list_sharelists,
    sharelist_detail,
    popular_sharelists,
    create_sharelist,
    delete_sharelist,
    add_sharelist_securities,
    remove_sharelist_securities,
    sort_sharelist_securities

"""
    SharelistContext(config::Config.Settings)

社区自选股列表上下文。HTTP-only。
"""
struct SharelistContext
    config::Config.Settings
end

_check(resp) =
    resp.code == 0 ||
    @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))

# ── list ───────────────────────────────────────────────────────────

"""
    list_sharelists(ctx::SharelistContext; count::Integer=20) -> SharelistList

我自己创建的 + 已订阅的自选股列表。

端点：`GET /v1/sharelists`
"""
function list_sharelists(ctx::SharelistContext; count::Integer = 20)
    params =
        Dict{String,Any}("size" => Int(count), "self" => "true", "subscription" => "true")
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/sharelists"; params))
    _check(resp)
    StructTypes.construct(SharelistList, resp.data)
end

# ── detail ─────────────────────────────────────────────────────────

"""
    sharelist_detail(ctx::SharelistContext, id::Integer) -> SharelistDetail

某个自选股列表的详情（含成份股 + 当前用户订阅状态）。

端点：`GET /v1/sharelists/{id}`
"""
function sharelist_detail(ctx::SharelistContext, id::Integer)
    params = Dict{String,Any}(
        "constituent" => "true",
        "quote" => "true",
        "subscription" => "true",
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/sharelists/$(Int64(id))"; params))
    _check(resp)
    StructTypes.construct(SharelistDetail, resp.data)
end

# ── popular ────────────────────────────────────────────────────────

"""
    popular_sharelists(ctx::SharelistContext; count::Integer=20) -> SharelistList

热门自选股列表。

端点：`GET /v1/sharelists/popular`
"""
function popular_sharelists(ctx::SharelistContext; count::Integer = 20)
    params = Dict{String,Any}("size" => Int(count))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/sharelists/popular"; params))
    _check(resp)
    StructTypes.construct(SharelistList, resp.data)
end

# ── create ─────────────────────────────────────────────────────────

const _DEFAULT_COVER = "https://pub.pbkrs.com/files/202107/kaJSk6BsvPt6NJ3Q/sharelist_v1.png"

"""
    create_sharelist(ctx::SharelistContext, name; description=nothing) -> Any

新建自选股列表。`description` 缺省时用 name 作为描述。

端点：`POST /v1/sharelists`
"""
function create_sharelist(
    ctx::SharelistContext,
    name::AbstractString;
    description::Union{AbstractString,Nothing} = nothing,
)
    body = Dict{String,Any}(
        "name" => String(name),
        "description" => String(isnothing(description) ? name : description),
        "cover" => _DEFAULT_COVER,
    )
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/sharelists"; body))
    _check(resp)
    return resp.data
end

# ── delete ─────────────────────────────────────────────────────────

"""
    delete_sharelist(ctx::SharelistContext, id::Integer) -> Any

删除一个自己创建的自选股列表。

端点：`DELETE /v1/sharelists/{id}`（body 为空 JSON 对象）
"""
function delete_sharelist(ctx::SharelistContext, id::Integer)
    body = Dict{String,Any}()
    resp = ApiResponse(Client.http_delete(ctx.config, "/v1/sharelists/$(Int64(id))"; body))
    _check(resp)
    return resp.data
end

# ── add / remove / sort securities ─────────────────────────────────

_join_counter_ids(symbols::AbstractVector{<:AbstractString}) =
    join((symbol_to_counter_id(s) for s in symbols), ",")

"""
    add_sharelist_securities(ctx::SharelistContext, id::Integer, symbols::AbstractVector{<:AbstractString}) -> Any

向自选股列表追加证券。

端点：`POST /v1/sharelists/{id}/items`
"""
function add_sharelist_securities(
    ctx::SharelistContext,
    id::Integer,
    symbols::AbstractVector{<:AbstractString},
)
    body = Dict{String,Any}("counter_ids" => _join_counter_ids(symbols))
    resp =
        ApiResponse(Client.http_post(ctx.config, "/v1/sharelists/$(Int64(id))/items"; body))
    _check(resp)
    return resp.data
end

"""
    remove_sharelist_securities(ctx::SharelistContext, id::Integer, symbols::AbstractVector{<:AbstractString}) -> Any

从自选股列表移除证券。

端点：`DELETE /v1/sharelists/{id}/items`
"""
function remove_sharelist_securities(
    ctx::SharelistContext,
    id::Integer,
    symbols::AbstractVector{<:AbstractString},
)
    body = Dict{String,Any}("counter_ids" => _join_counter_ids(symbols))
    resp = ApiResponse(
        Client.http_delete(ctx.config, "/v1/sharelists/$(Int64(id))/items"; body),
    )
    _check(resp)
    return resp.data
end

"""
    sort_sharelist_securities(ctx::SharelistContext, id::Integer, symbols::AbstractVector{<:AbstractString}) -> Any

按给定顺序重排自选股列表中的证券。

端点：`POST /v1/sharelists/{id}/items/sort`
"""
function sort_sharelist_securities(
    ctx::SharelistContext,
    id::Integer,
    symbols::AbstractVector{<:AbstractString},
)
    body = Dict{String,Any}("counter_ids" => _join_counter_ids(symbols))
    resp = ApiResponse(
        Client.http_post(ctx.config, "/v1/sharelists/$(Int64(id))/items/sort"; body),
    )
    _check(resp)
    return resp.data
end

end # module Sharelist
