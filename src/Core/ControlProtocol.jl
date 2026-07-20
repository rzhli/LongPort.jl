# 基于官方 control.proto 的Julia实现
# 专门用于WebSocket控制协议的Protocol Buffer消息

module ControlProtocol

import ProtoBuf as PB
using EnumX

export ControlCommand, Heartbeat, ReconnectRequest, AuthRequest, var"Close.Code"
export ReconnectResponse, AuthResponse, Close
export encode, decode

@enumx ControlCommand begin
    CMD_CLOSE = 0
    CMD_HEARTBEAT = 1
    CMD_AUTH = 2
    CMD_RECONNECT = 3
end

struct Heartbeat
    timestamp::Int64
    heartbeat_id::Int32
end

PB.default_values(::Type{Heartbeat}) =
    (; timestamp = zero(Int64), heartbeat_id = zero(Int32))
PB.field_numbers(::Type{Heartbeat}) = (; timestamp = 1, heartbeat_id = 2)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:Heartbeat})
    timestamp = zero(Int64)
    heartbeat_id = zero(Int32)
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)

        if field_number == 1
            timestamp = PB.decode(d, Int64)

        elseif field_number == 2
            heartbeat_id = PB.decode(d, Int32)

        else
            PB.skip(d, wire_type)
        end
    end
    return Heartbeat(timestamp, heartbeat_id)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::Heartbeat)
    initpos = position(e.io)
    x.timestamp != zero(Int64) && PB.encode(e, 1, x.timestamp)
    x.heartbeat_id != zero(Int32) && PB.encode(e, 2, x.heartbeat_id)
    return position(e.io) - initpos
end
function PB._encoded_size(x::Heartbeat)
    encoded_size = 0
    x.timestamp != zero(Int64) && (encoded_size += PB._encoded_size(x.timestamp, 1))
    x.heartbeat_id != zero(Int32) && (encoded_size += PB._encoded_size(x.heartbeat_id, 2))
    return encoded_size
end

struct ReconnectRequest
    session_id::String
    metadata::Dict{String,String}
end
PB.default_values(::Type{ReconnectRequest}) =
    (; session_id = "", metadata = Dict{String,String}())
PB.field_numbers(::Type{ReconnectRequest}) = (; session_id = 1, metadata = 2)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:ReconnectRequest})
    session_id = ""
    metadata = Dict{String,String}()
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            session_id = PB.decode(d, String)
        elseif field_number == 2
            PB.decode!(d, metadata)
        else
            PB.skip(d, wire_type)
        end
    end
    return ReconnectRequest(session_id, metadata)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::ReconnectRequest)
    initpos = position(e.io)
    !isempty(x.session_id) && PB.encode(e, 1, x.session_id)
    !isempty(x.metadata) && PB.encode(e, 2, x.metadata)
    return position(e.io) - initpos
end
function PB._encoded_size(x::ReconnectRequest)
    encoded_size = 0
    !isempty(x.session_id) && (encoded_size += PB._encoded_size(x.session_id, 1))
    !isempty(x.metadata) && (encoded_size += PB._encoded_size(x.metadata, 2))
    return encoded_size
end

struct AuthRequest
    token::String
    metadata::Dict{String,String}
end
PB.default_values(::Type{AuthRequest}) = (; token = "", metadata = Dict{String,String}())
PB.field_numbers(::Type{AuthRequest}) = (; token = 1, metadata = 2)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:AuthRequest})
    token = ""
    metadata = Dict{String,String}()
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            token = PB.decode(d, String)
        elseif field_number == 2
            PB.decode!(d, metadata)
        else
            PB.skip(d, wire_type)
        end
    end
    return AuthRequest(token, metadata)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::AuthRequest)
    initpos = position(e.io)
    !isempty(x.token) && PB.encode(e, 1, x.token)
    !isempty(x.metadata) && PB.encode(e, 2, x.metadata)
    return position(e.io) - initpos
end
function PB._encoded_size(x::AuthRequest)
    encoded_size = 0
    !isempty(x.token) && (encoded_size += PB._encoded_size(x.token, 1))
    !isempty(x.metadata) && (encoded_size += PB._encoded_size(x.metadata, 2))
    return encoded_size
end

@enumx var"Close.Code" HeartbeatTimeout=0 ServerError=1 ServerShutdown=2 UnpackError=3 AuthError=4 SessExpired=5 ConnectDuplicate=6

struct ReconnectResponse
    session_id::String
    expires::Int64
    limit::UInt32
    online::UInt32
end
PB.default_values(::Type{ReconnectResponse}) =
    (; session_id = "", expires = zero(Int64), limit = zero(UInt32), online = zero(UInt32))
PB.field_numbers(::Type{ReconnectResponse}) =
    (; session_id = 1, expires = 2, limit = 3, online = 4)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:ReconnectResponse})
    session_id = ""
    expires = zero(Int64)
    limit = zero(UInt32)
    online = zero(UInt32)
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            session_id = PB.decode(d, String)
        elseif field_number == 2
            expires = PB.decode(d, Int64)
        elseif field_number == 3
            limit = PB.decode(d, UInt32)
        elseif field_number == 4
            online = PB.decode(d, UInt32)
        else
            PB.skip(d, wire_type)
        end
    end
    return ReconnectResponse(session_id, expires, limit, online)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::ReconnectResponse)
    initpos = position(e.io)
    !isempty(x.session_id) && PB.encode(e, 1, x.session_id)
    x.expires != zero(Int64) && PB.encode(e, 2, x.expires)
    x.limit != zero(UInt32) && PB.encode(e, 3, x.limit)
    x.online != zero(UInt32) && PB.encode(e, 4, x.online)
    return position(e.io) - initpos
end
function PB._encoded_size(x::ReconnectResponse)
    encoded_size = 0
    !isempty(x.session_id) && (encoded_size += PB._encoded_size(x.session_id, 1))
    x.expires != zero(Int64) && (encoded_size += PB._encoded_size(x.expires, 2))
    x.limit != zero(UInt32) && (encoded_size += PB._encoded_size(x.limit, 3))
    x.online != zero(UInt32) && (encoded_size += PB._encoded_size(x.online, 4))
    return encoded_size
end

struct AuthResponse
    session_id::String
    expires::Int64
    limit::UInt32
    online::UInt32
end
PB.default_values(::Type{AuthResponse}) =
    (; session_id = "", expires = zero(Int64), limit = zero(UInt32), online = zero(UInt32))
PB.field_numbers(::Type{AuthResponse}) =
    (; session_id = 1, expires = 2, limit = 3, online = 4)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:AuthResponse})
    session_id = ""
    expires = zero(Int64)
    limit = zero(UInt32)
    online = zero(UInt32)
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            session_id = PB.decode(d, String)
        elseif field_number == 2
            expires = PB.decode(d, Int64)
        elseif field_number == 3
            limit = PB.decode(d, UInt32)
        elseif field_number == 4
            online = PB.decode(d, UInt32)
        else
            PB.skip(d, wire_type)
        end
    end
    return AuthResponse(session_id, expires, limit, online)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::AuthResponse)
    initpos = position(e.io)
    !isempty(x.session_id) && PB.encode(e, 1, x.session_id)
    x.expires != zero(Int64) && PB.encode(e, 2, x.expires)
    x.limit != zero(UInt32) && PB.encode(e, 3, x.limit)
    x.online != zero(UInt32) && PB.encode(e, 4, x.online)
    return position(e.io) - initpos
end
function PB._encoded_size(x::AuthResponse)
    encoded_size = 0
    !isempty(x.session_id) && (encoded_size += PB._encoded_size(x.session_id, 1))
    x.expires != zero(Int64) && (encoded_size += PB._encoded_size(x.expires, 2))
    x.limit != zero(UInt32) && (encoded_size += PB._encoded_size(x.limit, 3))
    x.online != zero(UInt32) && (encoded_size += PB._encoded_size(x.online, 4))
    return encoded_size
end

struct Close
    code::var"Close.Code".T
    reason::String
end
PB.default_values(::Type{Close}) = (; code = var"Close.Code".HeartbeatTimeout, reason = "")
PB.field_numbers(::Type{Close}) = (; code = 1, reason = 2)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:Close})
    code = var"Close.Code".HeartbeatTimeout
    reason = ""
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            code = PB.decode(d, var"Close.Code".T)
        elseif field_number == 2
            reason = PB.decode(d, String)
        else
            PB.skip(d, wire_type)
        end
    end
    return Close(code, reason)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::Close)
    initpos = position(e.io)
    x.code != var"Close.Code".HeartbeatTimeout && PB.encode(e, 1, x.code)
    !isempty(x.reason) && PB.encode(e, 2, x.reason)
    return position(e.io) - initpos
end
function PB._encoded_size(x::Close)
    encoded_size = 0
    x.code != var"Close.Code".HeartbeatTimeout &&
        (encoded_size += PB._encoded_size(x.code, 1))
    !isempty(x.reason) && (encoded_size += PB._encoded_size(x.reason, 2))
    return encoded_size
end

struct Error
    code::UInt64
    msg::String
end
PB.default_values(::Type{Error}) = (; code = zero(UInt64), msg = "")
PB.field_numbers(::Type{Error}) = (; code = 1, msg = 2)

function PB.decode(d::PB.AbstractProtoDecoder, ::Type{<:Error})
    code = zero(UInt64)
    msg = ""
    while !PB.message_done(d)
        field_number, wire_type = PB.decode_tag(d)
        if field_number == 1
            code = PB.decode(d, UInt64)
        elseif field_number == 2
            msg = PB.decode(d, String)
        else
            PB.skip(d, wire_type)
        end
    end
    return Error(code, msg)
end

function PB.encode(e::PB.AbstractProtoEncoder, x::Error)
    initpos = position(e.io)
    x.code != zero(UInt64) && PB.encode(e, 1, x.code)
    !isempty(x.msg) && PB.encode(e, 2, x.msg)
    return position(e.io) - initpos
end
function PB._encoded_size(x::Error)
    encoded_size = 0
    x.code != zero(UInt64) && (encoded_size += PB._encoded_size(x.code, 1))
    !isempty(x.msg) && (encoded_size += PB._encoded_size(x.msg, 2))
    return encoded_size
end

"""
encode(message) -> Vector{UInt8}

Serializes a Protobuf message struct into a byte vector.
"""
function encode(message)
    io_buf = IOBuffer()
    encoder = PB.ProtoEncoder(io_buf)
    PB.encode(encoder, message)
    return take!(io_buf)
end

"""
decode(data::Vector{UInt8}, message_type)

Deserializes a byte vector into a Protobuf message struct of the given type.
"""
function decode(data::Vector{UInt8}, ::Type{T}) where {T}
    return PB.decode(PB.ProtoDecoder(IOBuffer(data)), T)
end

end # module
