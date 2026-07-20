module Content

using StructTypes

using ..Config
using ..Client
using ..Errors
using ..ContentProtocol

export ContentContext,
    my_topics,
    create_topic,
    topics_by_symbol,
    topic_detail,
    topic_replies,
    create_topic_reply,
    news

"""
    ContentContext(config::Config.Settings)

社区资讯与话题上下文。HTTP-only。
"""
struct ContentContext
    config::Config.Settings
end

_check(resp) =
    resp.code == 0 ||
    @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))

# 把 Options 结构转 query/body Dict（跳过 nothing）
function _opts_to_dict(opts)
    d = Dict{String,Any}()
    for name in fieldnames(typeof(opts))
        v = getfield(opts, name)
        isnothing(v) || (d[String(name)] = v)
    end
    return d
end

function _construct_items(::Type{T}, data) where {T}
    if !haskey(data, :items) || isnothing(data.items)
        return T[]
    end
    return StructTypes.construct.(T, data.items)
end

# ── my_topics ──────────────────────────────────────────────────────

"""
    my_topics(ctx::ContentContext; page=nothing, size=nothing, topic_type=nothing) -> Vector{OwnedTopic}

当前用户发布的话题。`topic_type` 可为 `"article"`、`"post"` 或 `nothing`（全部）。

端点：`GET /v1/content/topics/mine`
"""
function my_topics(
    ctx::ContentContext;
    page::Union{Integer,Nothing} = nothing,
    size::Union{Integer,Nothing} = nothing,
    topic_type::Union{AbstractString,Nothing} = nothing,
)
    opts = MyTopicsOptions(;
        page = isnothing(page) ? nothing : Int(page),
        size = isnothing(size) ? nothing : Int(size),
        topic_type = isnothing(topic_type) ? nothing : String(topic_type),
    )
    params = _opts_to_dict(opts)
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/content/topics/mine"; params))
    _check(resp)
    return _construct_items(OwnedTopic, resp.data)
end

# ── create_topic ───────────────────────────────────────────────────

"""
    create_topic(ctx, title, body; topic_type=nothing, tickers=nothing, hashtags=nothing) -> String

发布新话题。返回新话题的 ID。

端点：`POST /v1/content/topics`
"""
function create_topic(
    ctx::ContentContext,
    title::AbstractString,
    body_md::AbstractString;
    topic_type::Union{AbstractString,Nothing} = nothing,
    tickers::Union{Vector{<:AbstractString},Nothing} = nothing,
    hashtags::Union{Vector{<:AbstractString},Nothing} = nothing,
)
    opts = CreateTopicOptions(;
        title = String(title),
        body = String(body_md),
        topic_type = isnothing(topic_type) ? nothing : String(topic_type),
        tickers = isnothing(tickers) ? nothing : String[String(t) for t in tickers],
        hashtags = isnothing(hashtags) ? nothing : String[String(h) for h in hashtags],
    )
    body = _opts_to_dict(opts)
    resp = ApiResponse(Client.http_post(ctx.config, "/v1/content/topics"; body))
    _check(resp)
    return String(resp.data.item.id)
end

# ── topics_by_symbol ───────────────────────────────────────────────

"""
    topics_by_symbol(ctx::ContentContext, symbol) -> Vector{TopicItem}

某证券下的话题列表。

端点：`GET /v1/content/{symbol}/topics`
"""
function topics_by_symbol(ctx::ContentContext, symbol::AbstractString)
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/content/$(String(symbol))/topics"))
    _check(resp)
    return _construct_items(TopicItem, resp.data)
end

# ── topic_detail ───────────────────────────────────────────────────

"""
    topic_detail(ctx::ContentContext, id::AbstractString) -> OwnedTopic

某话题的完整详情。

端点：`GET /v1/content/topics/{id}`
"""
function topic_detail(ctx::ContentContext, id::AbstractString)
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/content/topics/$(String(id))"))
    _check(resp)
    StructTypes.construct(OwnedTopic, resp.data.item)
end

# ── topic_replies ──────────────────────────────────────────────────

"""
    topic_replies(ctx, topic_id; page=nothing, size=nothing) -> Vector{TopicReply}

某话题下的评论。

端点：`GET /v1/content/topics/{topic_id}/comments`
"""
function topic_replies(
    ctx::ContentContext,
    topic_id::AbstractString;
    page::Union{Integer,Nothing} = nothing,
    size::Union{Integer,Nothing} = nothing,
)
    opts = ListTopicRepliesOptions(;
        page = isnothing(page) ? nothing : Int(page),
        size = isnothing(size) ? nothing : Int(size),
    )
    params = _opts_to_dict(opts)
    resp = ApiResponse(
        Client.http_get(
            ctx.config,
            "/v1/content/topics/$(String(topic_id))/comments";
            params,
        ),
    )
    _check(resp)
    return _construct_items(TopicReply, resp.data)
end

# ── create_topic_reply ─────────────────────────────────────────────

"""
    create_topic_reply(ctx, topic_id, body; reply_to_id=nothing) -> TopicReply

在某话题下发布评论。`body` 为纯文本（不渲染 Markdown）。如果是对某条评论的回复，
传入 `reply_to_id` 为该评论的 ID。

端点：`POST /v1/content/topics/{topic_id}/comments`
"""
function create_topic_reply(
    ctx::ContentContext,
    topic_id::AbstractString,
    body_text::AbstractString;
    reply_to_id::Union{AbstractString,Nothing} = nothing,
)
    opts = CreateReplyOptions(;
        body = String(body_text),
        reply_to_id = isnothing(reply_to_id) ? nothing : String(reply_to_id),
    )
    body = _opts_to_dict(opts)
    resp = ApiResponse(
        Client.http_post(
            ctx.config,
            "/v1/content/topics/$(String(topic_id))/comments";
            body,
        ),
    )
    _check(resp)
    StructTypes.construct(TopicReply, resp.data.item)
end

# ── news ───────────────────────────────────────────────────────────

"""
    news(ctx::ContentContext, symbol) -> Vector{NewsItem}

某证券的资讯列表。

端点：`GET /v1/content/{symbol}/news`
"""
function news(ctx::ContentContext, symbol::AbstractString)
    resp = ApiResponse(Client.http_get(ctx.config, "/v1/content/$(String(symbol))/news"))
    _check(resp)
    return _construct_items(NewsItem, resp.data)
end

end # module Content
