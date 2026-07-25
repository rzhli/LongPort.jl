module Utils

using Dates, JSON3, DataFrames, EnumX
import DecFP: Dec64

export to_namedtuple,
    to_china_time,
    utc_iso8601,
    to_dataframe,
    safeparse,
    symbol_to_counter_id,
    index_symbol_to_counter_id,
    counter_id_to_symbol,
    lookup_counter_id,
    cache_counter_ids,
    is_etf,
    json3_to_mutable,
    Dec64

# Utility function to convert UTC timestamp to China time (UTC+8)
to_china_time(timestamp::Integer) = unix2datetime(timestamp) + Hour(8)
to_china_time(timestamp::AbstractString) =
    unix2datetime(parse(Int64, timestamp)) + Hour(8)

"""
    utc_iso8601(timestamp::DateTime) -> String
    utc_iso8601(timestamp::Integer) -> String

Format a UTC-semantic `DateTime` or Unix timestamp as an ISO-8601 string with
an explicit `Z` suffix. Julia's `DateTime` type itself does not store a time zone.
"""
utc_iso8601(timestamp::DateTime) = string(timestamp, "Z")
utc_iso8601(timestamp::Integer) = utc_iso8601(unix2datetime(timestamp))

"""
    to_dataframe(data::Vector{T}) where T

Converts a vector of structs to a DataFrame.
"""
function to_dataframe(data::AbstractVector{T}) where {T}
    if isempty(data)
        if isstructtype(T) && !isabstracttype(T)
            fnames = fieldnames(T)
            return DataFrame([
                name => Vector{Union{Missing,fieldtype(T, name)}}() for name in fnames
            ])
        else
            return DataFrame()
        end
    end

    fnames = fieldnames(eltype(data))
    n = length(data)
    df = DataFrame()
    for fname in fnames
        col = Vector{Union{Missing,fieldtype(T, fname)}}(undef, n)
        @inbounds for i in eachindex(data)
            v = getfield(data[i], fname)
            col[i] = v === nothing ? missing : v
        end
        df[!, fname] = col
    end

    return df
end

"""
通用结构体转NamedTuple函数
"""
function to_namedtuple(obj)
    if obj === nothing
        return nothing
    elseif obj isa JSON3.Object
        # Convert JSON object to NamedTuple
        keys = Tuple(propertynames(obj))
        values = Tuple(to_namedtuple(obj[key]) for key in keys)
        return NamedTuple{keys}(values)
    elseif obj isa Union{JSON3.Array,AbstractVector}
        # Convert JSON array or Vector to Vector of converted items
        return [to_namedtuple(item) for item in obj]
    elseif isstructtype(typeof(obj))
        # Handle structs, but exclude types that are problematic or should be treated as values
        if obj isa Union{String,Date,DateTime,Tuple}
            return obj
        end
        field_names = fieldnames(typeof(obj))
        field_values = map(field_names) do name
            field_val = getfield(obj, name)
            if name === :timestamp && (field_val isa Number || field_val isa String)
                # Convert protobuf timestamp (seconds) to DateTime
                return to_china_time(field_val)
                # Recursively convert nested objects
            elseif isstructtype(typeof(field_val)) &&
                   !(field_val isa Union{String,Date,DateTime,Tuple}) ||
                   field_val isa JSON3.Object ||
                   field_val isa JSON3.Array
                return to_namedtuple(field_val)
            else
                return field_val
            end
        end
        return NamedTuple{field_names}(Tuple(field_values))
    else
        # Return primitives and other types as-is
        return obj
    end
end

function safeparse(::Type{T}, val) where {T}
    # 空值处理
    if val === "" || val === nothing
        return T <: EnumX.Enum ? T(0) : zero(T)
    end

    # 已经是目标类型
    if val isa T
        return val
    end

    # 枚举类型（EnumX）直接用构造器解析
    if T <: EnumX.Enum
        if val isa Integer
            return T(val)
        end
        sval = String(val)
        for e in instances(T)  # 枚举所有成员
            ename = string(e)
            if ename == sval
                return e
            end
        end
        num = parse(Int, val)
        return T(num)
    end

    # 数字类型
    if T <: Real
        if val isa Real
            return T(val)
        end
        return parse(T, val)
    end

    # 不支持的类型
    error("safeparse: unsupported type $T")
end

"""
解析可选的 Decimal 字段。空串、`nothing`、或非数字占位符（如 `"--"`）都返回 `nothing`。
LongBridge HTTP API 把 `Option<Decimal>` 序列化为字符串：缺失值常见为 `""` 或 `"--"`。
"""
_parse_optional_decimal(::Nothing) = nothing
function _parse_optional_decimal(v::AbstractString)
    s = strip(String(v))
    isempty(s) && return nothing
    return tryparse(Dec64, s)
end
_parse_optional_decimal(v::Number) = Dec64(v)

# ── Symbol ↔ counter_id 转换 ────────────────────────────────────────

const _SPECIAL_COUNTER_IDS = Ref{Union{Nothing,Set{String}}}(nothing)
const _SPECIAL_COUNTER_IDS_LOCK = ReentrantLock()
const _CACHED_COUNTER_IDS = Ref{Union{Nothing,Set{String}}}(nothing)
const _CACHED_COUNTER_IDS_LOCK = ReentrantLock()

function _load_counter_ids(files::Tuple{Vararg{String}})
    ids = Set{String}()
    for file in files
        path = isabspath(file) ? file : joinpath(@__DIR__, file)
        isfile(path) || continue
        for line in eachline(path)
            t = strip(line)
            isempty(t) || push!(ids, String(t))
        end
    end
    ids
end

function _special_counter_ids()
    s = _SPECIAL_COUNTER_IDS[]
    isnothing(s) || return s
    lock(_SPECIAL_COUNTER_IDS_LOCK) do
        s2 = _SPECIAL_COUNTER_IDS[]
        isnothing(s2) || return s2
        new_set = _load_counter_ids((
            "us_etf_counter.csv",
            "index_counter.csv",
            "warrant_counter.csv",
        ))
        _SPECIAL_COUNTER_IDS[] = new_set
        return new_set
    end
end

function _counter_cache_path()
    dir = get(ENV, "LONGBRIDGE_CACHE_DIR", "")
    if isempty(dir)
        home = get(ENV, Sys.iswindows() ? "USERPROFILE" : "HOME", "")
        isempty(home) && return nothing
        dir = joinpath(home, ".longbridge", "cache")
    end
    joinpath(dir, "counter-ids.csv")
end

function _cached_counter_ids()
    s = _CACHED_COUNTER_IDS[]
    isnothing(s) || return s
    lock(_CACHED_COUNTER_IDS_LOCK) do
        s2 = _CACHED_COUNTER_IDS[]
        isnothing(s2) || return s2
        path = _counter_cache_path()
        new_set =
            isnothing(path) ? Set{String}() :
            (isfile(path) ? _load_counter_ids((path,)) : Set{String}())
        _CACHED_COUNTER_IDS[] = new_set
        return new_set
    end
end

_is_ascii_digit(c::Char) = '0' <= c <= '9'
_is_hk_numeric_code(code::AbstractString, market::AbstractString) =
    uppercase(market) == "HK" && all(_is_ascii_digit, code)

function _normalize_symbol_code(code::AbstractString, market::AbstractString)
    if _is_hk_numeric_code(code, market)
        first_nonzero = findfirst(!=('0'), code)
        return isnothing(first_nonzero) ? "" : String(SubString(code, first_nonzero))
    end
    String(code)
end

"""
    cache_counter_ids(counter_ids) -> Nothing

Merge remotely resolved `counter_id`s into the local counter-id cache.
The cache file is `\$LONGBRIDGE_CACHE_DIR/counter-ids.csv`, or
`~/.longbridge/cache/counter-ids.csv` by default.
"""
function cache_counter_ids(counter_ids)
    lock(_CACHED_COUNTER_IDS_LOCK) do
        set = _cached_counter_ids()
        before = length(set)
        for cid in counter_ids
            s = strip(String(cid))
            isempty(s) || push!(set, s)
        end
        length(set) == before && return nothing

        path = _counter_cache_path()
        isnothing(path) && return nothing
        parent = dirname(path)
        isdir(parent) || mkpath(parent)
        lines = sort!(collect(set))
        open(path, "w") do io
            for line in lines
                println(io, line)
            end
        end
    end
    return nothing
end

"""
    lookup_counter_id(symbol) -> Union{String,Nothing}

Resolve `symbol` from local counter directories only: embedded ETF/index/
warrant directories, the remote-resolution cache, and leading-dot US index
notation. Returns `nothing` when the symbol is unknown locally.
"""
function lookup_counter_id(symbol::AbstractString)
    s = String(symbol)
    idx = findlast('.', s)
    isnothing(idx) && return nothing
    code_raw = String(SubString(s, 1, prevind(s, idx)))
    market = uppercase(String(SubString(s, nextind(s, idx))))

    startswith(code_raw, ".") && return string("IX/", market, "/", code_raw)

    code = _normalize_symbol_code(code_raw, market)
    special_ids = _special_counter_ids()
    for prefix in ("ETF", "IX", "WT")
        candidate = string(prefix, "/", market, "/", code)
        candidate ∈ special_ids && return candidate
    end

    cached = _cached_counter_ids()
    for prefix in ("ETF", "IX", "WT", "ST")
        candidate = string(prefix, "/", market, "/", code)
        candidate ∈ cached && return candidate
    end
    return nothing
end

"""
    symbol_to_counter_id(symbol) -> String

把 LongBridge symbol（如 `"TSLA.US"`）转成内部 counter_id（如 `"ST/US/TSLA"`）。
ETF、指数和窝轮通过内置目录识别；未知品种回退到 `"ST/..."`。
"""
function symbol_to_counter_id(symbol::AbstractString)
    s = String(symbol)
    idx = findlast('.', s)
    isnothing(idx) && return s
    cid = lookup_counter_id(s)
    isnothing(cid) || return cid
    code_raw = String(SubString(s, 1, prevind(s, idx)))
    market = uppercase(String(SubString(s, nextind(s, idx))))
    code = _normalize_symbol_code(code_raw, market)
    market == "BKKT" && return string("VA/", market, "/", code)
    return string("ST/", market, "/", code)
end

"""
    index_symbol_to_counter_id(symbol) -> String

把指数 symbol（如 `"HSI.HK"`）转成 counter_id（如 `"IX/HK/HSI"`）。
"""
function index_symbol_to_counter_id(symbol::AbstractString)
    s = String(symbol)
    idx = findlast('.', s)
    isnothing(idx) && return s
    code = SubString(s, 1, prevind(s, idx))
    market = uppercase(SubString(s, nextind(s, idx)))
    return string("IX/", market, "/", code)
end

"""
    counter_id_to_symbol(counter_id) -> String

把 counter_id（如 `"ST/US/TSLA"`）转回 symbol（如 `"TSLA.US"`）。
"""
function counter_id_to_symbol(counter_id::AbstractString)
    s = String(counter_id)
    parts = split(s, '/'; limit = 3)
    length(parts) == 3 ? string(parts[3], '.', parts[2]) : s
end

"""
    is_etf(symbol) -> Bool

Return whether `symbol` resolves to an ETF counter ID.
"""
is_etf(symbol::AbstractString) = startswith(symbol_to_counter_id(symbol), "ETF/")

"""
    json3_to_mutable(x) -> Any

递归地把 `JSON3.Object` / `JSON3.Array` 转成 `Dict{String,Any}` / `Vector{Any}`，
便于对原始响应做客户端后处理（如去 prefix、按字段重组）。其它类型原样返回。
"""
function json3_to_mutable(x)
    if x isa JSON3.Object
        Dict{String,Any}(string(k) => json3_to_mutable(v) for (k, v) in pairs(x))
    elseif x isa JSON3.Array
        Any[json3_to_mutable(v) for v in x]
    else
        x
    end
end

end
