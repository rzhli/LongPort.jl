module AssetProtocol

using EnumX, JSON
using ..Utils: JSONObject
import ..Utils: construct

export StatementType, StatementItem, GetStatementListResponse, GetStatementResponse

@enumx StatementType begin
    Daily = 1
    Monthly = 2
end

# ── StatementItem ───────────────────────────────────────────────────

struct StatementItem
    dt::Int32
    file_key::String
end
function construct(::Type{StatementItem}, obj::JSONObject)
    StatementItem(Int32(get(obj, :dt, 0)), String(get(obj, :file_key, "")))
end

# ── GetStatementListResponse ────────────────────────────────────────

struct GetStatementListResponse
    list::Vector{StatementItem}
end
function construct(::Type{GetStatementListResponse}, obj::JSONObject)
    items = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(StatementItem, e) for e in obj.list]
    else
        StatementItem[]
    end
    GetStatementListResponse(items)
end

# ── GetStatementResponse (download url) ─────────────────────────────

struct GetStatementResponse
    url::String
end
function construct(::Type{GetStatementResponse}, obj::JSONObject)
    GetStatementResponse(String(get(obj, :url, "")))
end

end # module AssetProtocol
