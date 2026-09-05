module Errors

using JSON, HTTP

export LongBridgeError, UnexpectedHttpResponse, @lperror, ApiResponse

function _header_value(headers::Dict{String,String}, name::String)
    lname = lowercase(name)
    for (key, value) in headers
        lowercase(key) == lname && return value
    end
    ""
end

"""An HTTP response that is not a standard LongBridge API envelope.

`status`, `trace_id`, `headers`, and `body` retain the original response
context so intermediary and load-balancer failures remain diagnosable.
"""
struct UnexpectedHttpResponse <: Exception
    status::Int
    trace_id::String
    headers::Dict{String,String}
    body::String
end

Base.showerror(io::IO, e::UnexpectedHttpResponse) = print(
    io,
    "UnexpectedHttpResponse(status=",
    e.status,
    ", trace_id=",
    repr(e.trace_id),
    ", body=",
    repr(e.body),
    ")",
)

struct ApiResponse{T}
    code::Int
    message::String
    data::T
    headers::Dict{String,String}

    function ApiResponse(resp::HTTP.Response)
        status = Int(resp.status)
        body = String(resp.body)
        # HTTP field names are case-insensitive; normalize them so callers can
        # reliably access trace/request IDs with their conventional lowercase names.
        headers = Dict(lowercase(String(k)) => String(v) for (k, v) in resp.headers)
        try
            json = JSON.parse(body)
            # A non-OpenAPI error page may still be valid JSON, but without the
            # standard `code` and `message` envelope fields.
            if !(haskey(json, :code) && haskey(json, :message))
                status < 300 && throw(ArgumentError("response is missing code/message"))
                throw(UnexpectedHttpResponse(
                    status,
                    _header_value(headers, "x-trace-id"),
                    headers,
                    body,
                ))
            end
            data = get(json, :data, nothing)
            return new{typeof(data)}(Int(json.code), String(json.message), data, headers)
        catch err
            err isa UnexpectedHttpResponse && rethrow()
            status >= 300 && throw(UnexpectedHttpResponse(
                status,
                _header_value(headers, "x-trace-id"),
                headers,
                body,
            ))
            rethrow()
        end
    end
end

struct LongBridgeError{T} <: Exception
    code::Int
    message::String
    request_id::Union{Nothing,String}
    payload::T
end

# Convenience constructor for nothing payload
LongBridgeError(code::Int, message::String, request_id::Union{Nothing,String} = nothing) =
    LongBridgeError{Nothing}(code, message, request_id, nothing)

Base.showerror(io::IO, e::LongBridgeError) =
    print(
        io,
        "LongBridgeError(code=",
        e.code,
        ", message=",
        e.message,
        ", request_id=",
        e.request_id,
        ")",
    )

macro lperror(code, message, request_id = nothing, payload = nothing)
    :(throw(
        LongBridgeError($(esc(code)), $(esc(message)), $(esc(request_id)), $(esc(payload))),
    ))
end

end # module Errors
