module Asset

using ..Config
using ..Client
using ..Errors
using ..Utils: construct
using ..AssetProtocol

export AssetContext, statements, statement_download_url

"""
    AssetContext(config::Config.Settings)

资产/结算单上下文。无 WebSocket 连接，所有方法都是同步 HTTP 调用。
"""
struct AssetContext
    config::Config.Settings
end

_statement_type_int(t::StatementType.T) =
    t === StatementType.Daily ? 1 :
    t === StatementType.Monthly ? 2 : error("unknown StatementType: $t")

"""
    statements(ctx::AssetContext, statement_type::StatementType.T; page::Integer=1, page_size::Integer=20)

查询账户结算单列表。

# 端点
`GET /v1/statement/list`
"""
function statements(
    ctx::AssetContext,
    statement_type::StatementType.T;
    page::Integer = 1,
    page_size::Integer = 20,
)
    params = Dict{String,Any}(
        "statement_type" => _statement_type_int(statement_type),
        "start_date" => Int(page),
        "limit" => Int(page_size),
    )
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/statement/list"; params))
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    construct(GetStatementListResponse, resp.data)
end

"""
    statement_download_url(ctx::AssetContext, file_key::AbstractString)

获取指定结算单的下载链接。

# 端点
`GET /v1/statement/download`
"""
function statement_download_url(ctx::AssetContext, file_key::AbstractString)
    params = Dict{String,Any}("file_key" => String(file_key))
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/statement/download"; params))
    resp.code == 0 ||
        @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
    construct(GetStatementResponse, resp.data)
end

end # module Asset
