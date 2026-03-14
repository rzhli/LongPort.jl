module Errors

    using JSON3, HTTP

    export LongBridgeError, @lperror, ApiResponse

    struct ApiResponse{T}
        code::Int
        message::String
        data::T
        headers::Dict{String, String}

        function ApiResponse(resp::HTTP.Response)
            json = JSON3.read(resp.body)
            headers = Dict(resp.headers)
            data = get(json, :data, nothing)
            new{typeof(data)}(json.code, json.message, data, headers)
        end
    end

    struct LongBridgeError{T} <: Exception
        code::Int
        message::String
        request_id::Union{Nothing,String}
        payload::T
    end

    # Convenience constructor for nothing payload
    LongBridgeError(code::Int, message::String, request_id::Union{Nothing,String}=nothing) =
        LongBridgeError{Nothing}(code, message, request_id, nothing)

    Base.showerror(io::IO, e::LongBridgeError) = print(io,
        "LongBridgeError(code=$(e.code), message=$(e.message), request_id=$(e.request_id))")

    macro lperror(code, message, request_id=nothing, payload=nothing)
        :(throw(LongBridgeError($(esc(code)), $(esc(message)), $(esc(request_id)), $(esc(payload)))))
    end

end # module Errors
