module ContentProtocol

using JSON, Dates
using ..Utils: JSONObject, to_china_time
import ..Utils: construct

export TopicAuthor,
    TopicImage,
    OwnedTopic,
    TopicItem,
    TopicReply,
    NewsItem,
    MyTopicsOptions,
    CreateTopicOptions,
    ListTopicRepliesOptions,
    CreateReplyOptions

# ── 通用嵌套类型 ────────────────────────────────────────────────────

struct TopicAuthor
    member_id::String
    name::String
    avatar::String
end
function construct(::Type{TopicAuthor}, obj::JSONObject)
    TopicAuthor(
        String(get(obj, :member_id, "")),
        String(get(obj, :name, "")),
        String(get(obj, :avatar, "")),
    )
end

struct TopicImage
    url::String
    sm::String
    lg::String
end
function construct(::Type{TopicImage}, obj::JSONObject)
    TopicImage(
        String(get(obj, :url, "")),
        String(get(obj, :sm, "")),
        String(get(obj, :lg, "")),
    )
end

# ── Helpers ────────────────────────────────────────────────────────

_ts_to_dt(v::Number) = to_china_time(Int64(v))
_ts_to_dt(v::AbstractString) = to_china_time(String(v))
_ts_to_dt(::Nothing) = DateTime(1970, 1, 1) + Hour(8)

_images_from(obj, key) =
    if haskey(obj, key) && !isnothing(obj[key])
        [construct(TopicImage, x) for x in obj[key]]
    else
        TopicImage[]
    end

_strings_from(obj, key) =
    if haskey(obj, key) && !isnothing(obj[key])
        String[String(x) for x in obj[key]]
    else
        String[]
    end

# ── OwnedTopic（my_topics / topic_detail） ──────────────────────────

struct OwnedTopic
    id::String
    title::String
    description::String
    body::String
    author::TopicAuthor
    tickers::Vector{String}
    hashtags::Vector{String}
    images::Vector{TopicImage}
    likes_count::Int
    comments_count::Int
    views_count::Int
    shares_count::Int
    topic_type::String                # "article" 或 "post"
    detail_url::String
    created_at::DateTime
    updated_at::DateTime
end
function construct(::Type{OwnedTopic}, obj::JSONObject)
    OwnedTopic(
        String(get(obj, :id, "")),
        String(get(obj, :title, "")),
        String(get(obj, :description, "")),
        String(get(obj, :body, "")),
        construct(TopicAuthor, obj.author),
        _strings_from(obj, :tickers),
        _strings_from(obj, :hashtags),
        _images_from(obj, :images),
        Int(get(obj, :likes_count, 0)),
        Int(get(obj, :comments_count, 0)),
        Int(get(obj, :views_count, 0)),
        Int(get(obj, :shares_count, 0)),
        String(get(obj, :topic_type, "")),
        String(get(obj, :detail_url, "")),
        _ts_to_dt(get(obj, :created_at, nothing)),
        _ts_to_dt(get(obj, :updated_at, nothing)),
    )
end

# ── TopicItem（按 symbol 列出的话题） ───────────────────────────────

struct TopicItem
    id::String
    title::String
    description::String
    url::String
    published_at::DateTime
    comments_count::Int
    likes_count::Int
    shares_count::Int
end
function construct(::Type{TopicItem}, obj::JSONObject)
    TopicItem(
        String(get(obj, :id, "")),
        String(get(obj, :title, "")),
        String(get(obj, :description, "")),
        String(get(obj, :url, "")),
        _ts_to_dt(get(obj, :published_at, nothing)),
        Int(get(obj, :comments_count, 0)),
        Int(get(obj, :likes_count, 0)),
        Int(get(obj, :shares_count, 0)),
    )
end

# ── TopicReply ─────────────────────────────────────────────────────

struct TopicReply
    id::String
    topic_id::String
    body::String
    reply_to_id::String                # "0" 表示一级评论
    author::TopicAuthor
    images::Vector{TopicImage}
    likes_count::Int
    comments_count::Int
    created_at::DateTime
end
function construct(::Type{TopicReply}, obj::JSONObject)
    TopicReply(
        String(get(obj, :id, "")),
        String(get(obj, :topic_id, "")),
        String(get(obj, :body, "")),
        String(get(obj, :reply_to_id, "")),
        construct(TopicAuthor, obj.author),
        _images_from(obj, :images),
        Int(get(obj, :likes_count, 0)),
        Int(get(obj, :comments_count, 0)),
        _ts_to_dt(get(obj, :created_at, nothing)),
    )
end

# ── NewsItem ───────────────────────────────────────────────────────

struct NewsItem
    id::String
    title::String
    description::String
    url::String
    published_at::DateTime
    comments_count::Int
    likes_count::Int
    shares_count::Int
end
function construct(::Type{NewsItem}, obj::JSONObject)
    NewsItem(
        String(get(obj, :id, "")),
        String(get(obj, :title, "")),
        String(get(obj, :description, "")),
        String(get(obj, :url, "")),
        _ts_to_dt(get(obj, :published_at, nothing)),
        Int(get(obj, :comments_count, 0)),
        Int(get(obj, :likes_count, 0)),
        Int(get(obj, :shares_count, 0)),
    )
end

# ── Options ────────────────────────────────────────────────────────

Base.@kwdef struct MyTopicsOptions
    page::Union{Int,Nothing} = nothing
    size::Union{Int,Nothing} = nothing
    topic_type::Union{String,Nothing} = nothing   # "article" 或 "post"
end

Base.@kwdef struct CreateTopicOptions
    title::String
    body::String
    topic_type::Union{String,Nothing} = nothing
    tickers::Union{Vector{String},Nothing} = nothing
    hashtags::Union{Vector{String},Nothing} = nothing
end

Base.@kwdef struct ListTopicRepliesOptions
    page::Union{Int,Nothing} = nothing
    size::Union{Int,Nothing} = nothing
end

Base.@kwdef struct CreateReplyOptions
    body::String
    reply_to_id::Union{String,Nothing} = nothing
end

end # module ContentProtocol
