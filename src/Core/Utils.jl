module Utils

    using Logging, Dates, JSON3, DataFrames, EnumX

    export to_namedtuple, to_china_time, to_dataframe, safeparse, Arc

    # A simple wrapper to mimic Rust's Arc for shared ownership semantics
    struct Arc{T}
        value::T
    end

    Base.getproperty(arc::Arc, sym::Symbol) = getproperty(getfield(arc, :value), sym)
    Base.setproperty!(arc::Arc, sym::Symbol, x) = setproperty!(getfield(arc, :value), sym, x)

    # Utility function to convert UTC timestamp to China time (UTC+8)
    function to_china_time(timestamp::Int64)
        return unix2datetime(timestamp) + Hour(8)
    end

    function to_china_time(timestamp::String)
        return unix2datetime(parse(Int64, timestamp)) + Hour(8)
    end

    """
        to_dataframe(data::Vector{T}) where T

    Converts a vector of structs to a DataFrame.
    """
    function to_dataframe(data::Vector{T}) where {T}
        if isempty(data)
            if isstructtype(T) && !isabstracttype(T)
                fnames = fieldnames(T)
                return DataFrame([name => [] for name in fnames])
            else
                return DataFrame()
            end
        end

        fnames = fieldnames(eltype(data))
        n = length(data)
        df = DataFrame()
        for fname in fnames
            col = Vector{Any}(undef, n)
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
        elseif obj isa Union{JSON3.Array, Vector, SubArray}
            # Convert JSON array or Vector to Vector of converted items
            return [to_namedtuple(item) for item in obj]
        elseif isstructtype(typeof(obj))
            # Handle structs, but exclude types that are problematic or should be treated as values
            if obj isa Union{String, Date, DateTime, Tuple}
                return obj
            end
            field_names = fieldnames(typeof(obj))
            field_values = map(field_names) do name
                field_val = getfield(obj, name)
                if name === :timestamp && (field_val isa Number || field_val isa String)
                    # Convert protobuf timestamp (seconds) to DateTime
                    return to_china_time(field_val)
                # Recursively convert nested objects
                elseif isstructtype(typeof(field_val)) && !(field_val isa Union{String, Date, DateTime, Tuple}) ||
                    field_val isa JSON3.Object || field_val isa JSON3.Array
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
            return parse(T, val)
        end

        # 不支持的类型
        error("safeparse: unsupported type $T")
    end

end
