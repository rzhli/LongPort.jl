module Client

using HTTP, JSON3, URIs, SHA, Dates, CodecZlib
using HTTP: WebSockets
import HTTP.WebSockets: send
using Base.Threads

using ..Config
using ..Constant
using ..ControlProtocol
using ..QuoteProtocol
using ..Errors

export WSClient, refresh_token, post, put, delete

# HTTP Client Constants
const DEFAULT_TIMEOUT = (connect=10, read=20, write=20)
const RETRIES = 3
const POOL = HTTP.Pool(20)
# WebSocket Client Constants (参考 Rust 实现)
const REQUEST_TIMEOUT = 30.0  # seconds

# 认证和心跳命令 (use ControlProtocol enum values)
const COMMAND_CODE_AUTH = UInt8(ControlProtocol.ControlCommand.CMD_AUTH)
const COMMAND_CODE_HEARTBEAT = UInt8(ControlCommand.CMD_HEARTBEAT)
const COMMAND_CODE_RECONNECT = UInt8(ControlCommand.CMD_RECONNECT)
const COMMAND_CODE_CLOSE = UInt8(ControlCommand.CMD_CLOSE)

# ==================== Signature Authentication ====================

"""
sign(method::String, path::String, headers::Dict{String, String}, 
     params::String, body::String, config::Config.config)::String

Generate API signature for authentication based on Rust implementation
"""
function sign(
    method::String, path::String, headers::Dict{String, String},
    params::String, body::String, config::Config.config
    )::String
    
    # 获取必要的参数
    app_key = config.app_key
    app_secret = config.app_secret
    access_token = config.access_token
    timestamp = headers["X-Timestamp"]
    
    # 构建signed_headers和signed_values
    if !isnothing(access_token) && !isempty(access_token)
        signed_headers = "authorization;x-api-key;x-timestamp"
        signed_values = "authorization:Bearer $(access_token)\nx-api-key:$(app_key)\nx-timestamp:$(timestamp)\n"
    else
        signed_headers = "x-api-key;x-timestamp"
        signed_values = "x-api-key:$(app_key)\nx-timestamp:$(timestamp)\n"
    end
    
    # 构建待签名字符串
    query = params  # 查询参数
    
    str_to_sign = "$(method)|$(path)|$(query)|$(signed_values)|$(signed_headers)|"
    
    # 如果有body，添加body的SHA1哈希
    if !isempty(body)
        body_hash = bytes2hex(SHA.sha1(body))
        str_to_sign *= body_hash
    end
    
    # 最终的待签名字符串
    final_str_to_sign = "HMAC-SHA256|$(bytes2hex(SHA.sha1(str_to_sign)))"
    
    # 使用HMAC-SHA256生成签名
    signature = bytes2hex(SHA.hmac_sha256(Vector{UInt8}(app_secret), final_str_to_sign))
    
    return "HMAC-SHA256 SignedHeaders=$(signed_headers), Signature=$(signature)"
end

# ==================== HTTP Client (简化版本仅用于获取OTP) ====================

"""
get(config::Config.config, path::String; params::Dict{String, String}=Dict{String, String}()) -> JSON3.Object
通用HTTP get函数
"""

function get(config::Config.config, path::String; params::Dict{String,Any} = Dict{String,Any}())
    try
        # 构建请求URL
        base_url = config.http_url
        query_parts = []
        for (k, v) in params
            if v isa Vector
                for val in v
                    push!(query_parts, "$(k)=$(HTTP.URIs.escapeuri(val))")
                end
            else
                push!(query_parts, "$(k)=$(HTTP.URIs.escapeuri(string(v)))")
            end
        end
        query_string = join(query_parts, "&")
        full_url = base_url * path * (isempty(query_string) ? "" : "?" * query_string)

        # 生成时间戳
        timestamp = string(floor(Int, time() * 1000))
        
        # 构建请求头
        headers = Dict{String, String}(
            "X-Api-Key" => config.app_key,
            "Authorization" => "Bearer $(config.access_token)",
            "X-Timestamp" => timestamp,
            "Content-Type" => "application/json; charset=utf-8"
        )
        
        # 生成签名
        signature = sign("GET", path, headers, query_string, "", config)
        headers["X-Api-Signature"] = signature
        
        # 发送HTTP GET请求
        response = HTTP.get(full_url, headers = headers, pool = POOL, readtimeout=DEFAULT_TIMEOUT.read, retries=RETRIES)
        
        return response
    catch e
        @error "HTTP GET请求异常" path=path exception=(e, catch_backtrace())
        rethrow(e)
    end
end

"""
refresh_token(config::Config.config, expired_at::String) -> Dict

Refresh the access token using the refresh token API
Reference: https://open.longportapp.com/zh-CN/docs/refresh-token-api

# Parameters
- `expired_at`: ISO8601 timestamp of expiration (e.g., "2023-04-14T12:13:57.859Z")

# Returns
- Dictionary containing new token information
"""
function refresh_token(config::Config.config, expired_at::String)::Dict
    try
        params = Dict("expired_at" => expired_at)
        result = ApiResponse(get(config, "/v1/token/refresh"; params=params))
        return result.data
    catch e
        @error "刷新Token失败" exception=(e, catch_backtrace())
        rethrow(e)
    end
end

"""
get_otp(config::Config.config) -> NamedTuple

Get the socket OTP(One Time Password) and connection info
Reference: https://open.longportapp.com/zh-CN/docs/socket-token-api

Returns:
- NamedTuple with fields:
  - otp: String - One-time password for socket connection
  - limit: Int - Total connection limit
  - online: Int - Current online connections
"""
function get_otp(config::Config.config)::NamedTuple{(:otp, :limit, :online), Tuple{String, Int, Int}}
    try
        resp = ApiResponse(get(config, "/v1/socket/token"))
        if resp.code == 0
            return (
                otp = resp.data.otp,
                limit = resp.data.limit,
                online = resp.data.online
            )
        else
            @lperror(resp.code, resp.message, get(resp.headers, "x-request-id", nothing))
        end
    catch e
        @error "获取OTP失败" exception=(e, catch_backtrace())
        rethrow(e)
    end
end

"""
post(config::Config.config, path::String, data::Dict) -> JSON3.Object
通用HTTP POST函数用于交易API
"""
function post(config::Config.config, path::String; body::Dict=Dict())
    try
        # 构建请求URL
        base_url = config.http_url
        full_url = base_url * path
        
        # 生成时间戳
        timestamp = string(floor(Int, time() * 1000))
        
        # 序列化请求体
        body_str = JSON3.write(body)
        
        # 构建请求头
        headers = Dict{String, String}(
            "X-Api-Key" => config.app_key,
            "Authorization" => "Bearer $(config.access_token)",
            "X-Timestamp" => timestamp,
            "Content-Type" => "application/json; charset=utf-8"
        )
        
        # 生成签名
        signature = sign("POST", path, headers, "", body_str, config)
        headers["X-Api-Signature"] = signature
        
        # 发送HTTP POST请求
        response = HTTP.post(full_url, headers = headers, body = body_str, pool = POOL, readtimeout=DEFAULT_TIMEOUT.read, retries=RETRIES)
        
        return response
    catch e
        @error "HTTP POST请求异常" path=path exception=(e, catch_backtrace())
        rethrow(e)
    end
end

function put(config::Config.config, path::String; body::Dict=Dict())
    try
        base_url = config.http_url
        full_url = base_url * path
        timestamp = string(floor(Int, time() * 1000))
        body_str = JSON3.write(body)
        
        headers = Dict{String, String}(
            "X-Api-Key" => config.app_key,
            "Authorization" => "Bearer $(config.access_token)",
            "X-Timestamp" => timestamp,
            "Content-Type" => "application/json; charset=utf-8"
        )
        
        signature = sign("PUT", path, headers, "", body_str, config)
        headers["X-Api-Signature"] = signature
        
        response = HTTP.put(full_url, headers = headers, body = body_str, pool = POOL, readtimeout=DEFAULT_TIMEOUT.read, retries=RETRIES)
        
        return response
    catch e
        @error "HTTP PUT请求异常" path=path exception=(e, catch_backtrace())
        rethrow(e)
    end
end

function delete(config::Config.config, path::String; params::Dict{String,Any} = Dict{String,Any}())
    try
        base_url = config.http_url
        query_parts = []
        for (k, v) in params
            if v isa Vector
                for val in v
                    push!(query_parts, "$(k)=$(HTTP.URIs.escapeuri(val))")
                end
            else
                push!(query_parts, "$(k)=$(HTTP.URIs.escapeuri(string(v)))")
            end
        end
        query_string = join(query_parts, "&")
        full_url = base_url * path * (isempty(query_string) ? "" : "?" * query_string)

        timestamp = string(floor(Int, time() * 1000))
        
        headers = Dict{String, String}(
            "X-Api-Key" => config.app_key,
            "Authorization" => "Bearer $(config.access_token)",
            "X-Timestamp" => timestamp,
            "Content-Type" => "application/json; charset=utf-8"
        )
        
        signature = sign("DELETE", path, headers, query_string, "", config)
        headers["X-Api-Signature"] = signature
        
        response = HTTP.delete(full_url, headers = headers, pool = POOL, readtimeout=DEFAULT_TIMEOUT.read, retries=RETRIES)
        
        return response
    catch e
        @error "HTTP DELETE请求异常" path=path exception=(e, catch_backtrace())
        rethrow(e)
    end
end

# ==================== WebSocket Client ====================

"""
WSClient
    
WebSocket 客户端，用于与长桥服务器建立长连接。

# Fields
- `ws::Union{Nothing, WebSockets.WebSocket}`: WebSocket 连接
- `url::String`: 连接 URL
- `connected::Bool`: 连接状态（包括认证成功）
- `seq_id::UInt32`: 序列号
- `pending_responses::Dict{String, Tuple{UInt8, Vector{UInt8}}}`: 待处理响应
- `auth_data::Union{Nothing,Vector{UInt8}}`: 认证数据
"""
mutable struct WSClient
    ws::Union{Nothing, WebSockets.WebSocket}
    url::String
    connected::Bool
    seq_id::UInt32
    session_id::Union{String, Nothing}
    pending_responses::Dict{String, Tuple{UInt8, Vector{UInt8}}}
    auth_data::Union{Nothing,Vector{UInt8}}
    on_push::Union{Function, Nothing}
    heartbeat_task::Union{Nothing, Task}
    reconnect_attempts::Int
    reconnect_task::Union{Nothing, Task}
    config::Config.config

    function WSClient(url::String, config::Config.config)
        new(
            nothing,                # ws
            url,                    # url
            false,                  # connected (只有认证成功后才为true)
            UInt32(1),              # seq_id
            nothing,                # session_id
            Dict{String, Tuple{UInt8, Vector{UInt8}}}(), # pending_responses
            nothing,                # auth_data
            nothing,
            nothing,                # heartbeat_task
            0,                      # reconnect_attempts
            nothing,                # reconnect_task
            config
        )
    end
end

# ==================== 内部WebSocket函数 ====================

"""
建立 WebSocket 连接并完成认证。
"""
function connect!(client::WSClient)
    if client.connected
        return
    end
    
    @info "正在连接到 WS 服务器: $(client.url)"
    base_url = client.url

    query_params = [
        "version=$(Constant.PROTOCOL_VERSION)", 
        "codec=$(Constant.CODEC_TYPE)", 
        "platform=$(Constant.PLATFORM_TYPE)"
    ]

    full_url = base_url * "?" * join(query_params, "&")
    
    # 创建WebSocket连接
    ws_task = @async begin
        WebSockets.open(full_url; nagle=false, quickack=true) do ws
            client.ws = ws
            client.seq_id = UInt32(1)
            
            # @info "WebSocket 物理连接成功，开始认证..."
            # @info "发送认证包" auth_data_length=length(client.auth_data)
            send_request_packet(client, COMMAND_CODE_AUTH, client.auth_data)
            # @info "认证包已发送，等待响应..."
            
            # 启动消息处理循环
            start_message_loop(client)
            
            # 保持连接开放，直到被外部关闭
            while !isnothing(client.ws) && isopen(client.ws.io)
                sleep(0.1)
            end
        end
    end
    
    # 等待认证完成（而不是仅仅物理连接）
    max_wait = 30.0
    wait_interval = 0.1
    elapsed = 0.0
    
    while !client.connected && elapsed < max_wait
        sleep(wait_interval)
        elapsed += wait_interval
    end
    
    if !client.connected
        @lperror(408, "WebSocket连接或认证超时")
    end
end

"""
disconnect!(client::WSClient)
    
断开 WebSocket 连接。
"""
function disconnect!(client::WSClient)
    if !client.connected
        return
    end
    client.connected = false

    @info "正在断开 WebSocket 连接..." session_id=client.session_id

    if !isnothing(client.heartbeat_task) && !istaskdone(client.heartbeat_task)
        schedule(client.heartbeat_task, InterruptException(); error=true)
        client.heartbeat_task = nothing
    end

    if !isnothing(client.reconnect_task) && !istaskdone(client.reconnect_task)
        schedule(client.reconnect_task, InterruptException(); error=true)
        client.reconnect_task = nothing
    end

    if !isnothing(client.ws) && isopen(client.ws.io)
        try
            WebSockets.close(client.ws)
        catch e
            # Ignore errors during close, as the connection might already be dead
        end
    end

    client.ws = nothing
    
    @info "WebSocket 连接已关闭" session_id=client.session_id
end

"""
send_request_packet(client::WSClient, cmd::UInt8, body::Vector{UInt8})
    
发送请求数据包到服务器。
根据Longport协议格式: [header(1)] + [cmd_code(1)] + [request_id(4)] + [timeout(2)] + [body_len(3)] + [body]
"""
function send_request_packet(client::WSClient, cmd::UInt8, body::Vector{UInt8})
    if isnothing(client.ws) || !isopen(client.ws.io)
        throw(ArgumentError("WebSocket物理连接不存在"))
    end
    
    try
        # 构建数据包
        request_id = client.seq_id
        client.seq_id += 1
        
        # 构建数据包头部
        # 根据长桥协议：[header(1)] + [cmd_code(1)] + [request_id(4)] + [timeout(2)] + [body_len(3)] + [body]
        packet = IOBuffer()
        
        # Header byte: type=1 (request), verify=0, gzip=0, reserve=0
        # Format: [reserve(2)] + [gzip(1)] + [verify(1)] + [type(4)]
        header_byte = 0b00000001  # reserve=0, gzip=0, verify=0, type=1
        write(packet, header_byte)
        
        # Command code (1 byte)
        write(packet, cmd)
        
        # Request ID (4 bytes, big-endian)
        write(packet, hton(request_id))
        
        # Timeout (2 bytes, big-endian) - 30 seconds default
        write(packet, hton(UInt16(REQUEST_TIMEOUT * 1000)))
        
        # Body length (3 bytes, big-endian)
        body_len = length(body)
        body_len_bytes = [
            UInt8((body_len >> 16) & 0xFF),
            UInt8((body_len >> 8) & 0xFF),
            UInt8(body_len & 0xFF)
        ]
        write(packet, body_len_bytes)
        
        # Body
        write(packet, body)
        
        # 发送数据包
        packet_data = take!(packet)
        send(client.ws, packet_data)
        
        @debug "已发送请求数据包" cmd=cmd request_id=request_id body_len=body_len
        
        return request_id
        
    catch e
        @error "发送请求数据包失败" exception=(e, catch_backtrace())
        rethrow(e)
    end
end

"""
start_message_loop(client::WSClient)
    
启动消息处理循环。
"""
function start_heartbeat_loop(client::WSClient)
    client.heartbeat_task = @async begin
        try
            @info "启动心跳循环"
            while client.connected && !isnothing(client.ws) && isopen(client.ws.io)
                sleep(30) # Send a ping every 30 seconds
                
                try
                    # Use WebSocket's built-in ping for network-level keep-alive
                    WebSockets.ping(client.ws)
                    @debug "发送 WebSocket Ping 帧"
                catch e
                    if client.connected
                        @warn "发送 Ping 帧失败，可能连接已断开" exception=(e, catch_backtrace())
                        # Trigger reconnection logic if ping fails
                        full_reconnect!(client)
                    end
                    break # Exit loop on failure
                end
            end
        catch e
            if !(e isa InterruptException)
                @error "心跳循环异常退出" exception=(e, catch_backtrace())
            end
        finally
            @info "心跳循环已停止" session_id=client.session_id
        end
    end
end


"""
start_message_loop(client::WSClient)
    
启动消息处理循环。
"""
function start_message_loop(client::WSClient)
    @async begin
        try
            @info "启动消息处理循环" 
            # 使用HTTP.jl推荐的WebSocket消息循环模式
            try
                for msg in client.ws
                    @debug "接收到WebSocket消息" msg=msg typeof=typeof(msg)
                    data = if msg isa String
                        Vector{UInt8}(codeunits(msg))
                    elseif msg isa Vector{UInt8}
                        msg
                    else
                        @warn "未知消息类型，已忽略" type=typeof(msg)
                        continue
                    end
                    
                    if length(data) < 5  # 最小包头长度: header(1) + cmd(1) + body_len(3)
                        @warn "包长度小于5，忽略" length=length(data)
                        continue
                    end
                    
                    # 解析包头
                    io = IOBuffer(data)
                    header_byte = read(io, UInt8)
                
                    # Format: [reserve(2)] + [gzip(1)] + [verify(1)] + [type(4)]
                    packet_type = header_byte & 0x0F  # Lower 4 bits
                    is_gzipped = (header_byte & 0x20) != 0
                    @debug "解析header字节" header_byte=header_byte packet_type=packet_type is_gzipped=is_gzipped

                    if packet_type == 2  # Response packet
                        # Response格式: [header(1)] + [cmd_code(1)] + [request_id(4)] + [status_code(1)] + [body_len(3)] + [body]
                        if length(data) < 10
                            @warn "响应包长度小于10，忽略" length=length(data)
                            continue
                        end
                        
                        cmd = read(io, UInt8)
                        request_id = ntoh(read(io, UInt32))
                        status_code = read(io, UInt8)
                        
                        # 读取body_len (3 bytes)
                        body_len_bytes = read(io, 3)
                        body_len = (UInt32(body_len_bytes[1]) << 16) | (UInt32(body_len_bytes[2]) << 8) | UInt32(body_len_bytes[3])
                        
                        @debug "解析包头" cmd=cmd request_id=request_id status_code=status_code body_len=body_len
                        if body_len > length(data) - 10
                            @warn "body_len声明超出实际剩余长度" body_len=body_len remaining=length(data)-10
                            continue
                        end
                        
                        # 读取包体
                        body = read(io, body_len)

                        if is_gzipped
                            body = transcode(GzipDecompressor, body)
                        end
                        
                        # @info "收到响应数据包" cmd=cmd request_id=request_id status_code=status_code body_len=body_len hex_preview=bytes2hex(body[1:20])
                        
                        # 处理认证响应
                        if cmd == COMMAND_CODE_AUTH
                            if status_code == 0
                                client.connected = true  # 只有认证成功后才算真正连接
                                auth_resp = ControlProtocol.decode(body, ControlProtocol.AuthResponse)
                                client.session_id = auth_resp.session_id
                                @info "认证成功，连接已建立" session_id=client.session_id
                                # 只有在认证成功后才启动心跳
                                start_heartbeat_loop(client)
                            else
                                @error "认证失败" status_code=status_code
                                client.connected = false
                            end
                        end
                        
                        # 存储响应数据
                        response_key = "quote_response_$(request_id)"
                        client.pending_responses[response_key] = (status_code, body)
                        @debug "存储响应" response_key=response_key pending_keys=keys(client.pending_responses)
                    elseif packet_type == 3  # Push packet
                        # Push格式: [header(1)] + [cmd_code(1)] + [body_len(3)] + [body]
                        if length(data) < 5
                            @warn "推送包长度小于5，忽略" length=length(data)
                            continue
                        end
                        
                        cmd = read(io, UInt8)
                        
                        # 读取body_len (3 bytes)
                        body_len_bytes = read(io, 3)
                        body_len = (UInt32(body_len_bytes[1]) << 16) | (UInt32(body_len_bytes[2]) << 8) | UInt32(body_len_bytes[3])
                        
                        @debug "解析推送包头" cmd=cmd body_len=body_len
                        if body_len > length(data) - 5
                            @warn "推送包body_len声明超出实际剩余长度" body_len=body_len remaining=length(data)-5
                            continue
                        end
                        
                        # 读取包体
                        body = read(io, body_len)
                        
                        # @info "收到推送数据包" cmd=cmd body_len=body_len hex_preview=bytes2hex(body[1:20])
                        if cmd == COMMAND_CODE_CLOSE
                            close_msg = ControlProtocol.decode(body, ControlProtocol.Close)
                            @warn "收到服务器关闭连接指令" code=close_msg.code reason=close_msg.reason
                            disconnect!(client)
                        elseif cmd == COMMAND_CODE_RECONNECT
                            reconnect_msg = ControlProtocol.decode(body, ControlProtocol.ReconnectRequest)
                            @warn "收到服务器重连指令" session_id=reconnect_msg.session_id
                            reconnect!(client)
                        elseif !isnothing(client.on_push)
                            try
                                client.on_push(cmd, body)
                            catch e
                                @error "推送处理函数异常" exception=(e, catch_backtrace())
                            end
                        end
                    else
                        @debug "未知包类型，已忽略" packet_type=packet_type
                    end
                end
            catch e
                if e isa InterruptException
                    @info "消息循环被中断"
                elseif e isa EOFError
                    # 连接已被对方正常关闭，执行清理
                    disconnect!(client)
                else
                    @error "消息循环异常" exception=(e, catch_backtrace())
                    disconnect!(client)
                end
            end            
        catch e
            @error "消息循环外层异常" exception=(e, catch_backtrace())
        finally
            @info "消息处理循环已停止" session_id=client.session_id
        end
    end
end

"""
reconnect!(client::WSClient)

Handles the reconnection logic for the WebSocket client.
"""
function reconnect!(client::WSClient)
    if isnothing(client.session_id)
        @warn "没有 session_id，无法执行快速重连，将执行标准重连"
        return full_reconnect!(client)
    end

    @info "尝试使用 session_id 进行快速重连..."
    try
        # 1. 物理连接
        WebSockets.open(client.url; nagle = false, quickack = true) do ws
            client.ws = ws
            
            # 2. 发送 ReconnectRequest
            metadata = Dict("client_version" => Constant.DEFAULT_CLIENT_VERSION)
            if client.config.enable_overnight
                metadata["need_over_night_quote"] = "true"
            end
            reconnect_req = ControlProtocol.ReconnectRequest(client.session_id, metadata)
            req_body = ControlProtocol.encode(reconnect_req)
            
            # 使用 ws_request 发送并等待响应
            resp_body = ws_request(client, COMMAND_CODE_RECONNECT, req_body)
            
            # 3. 处理响应
            reconnect_resp = ControlProtocol.decode(resp_body, ControlProtocol.ReconnectResponse)
            
            client.connected = true
            client.session_id = reconnect_resp.session_id # 更新 session_id
            @info "快速重连成功" new_session_id=client.session_id
            
            # 重启心跳和消息循环
            start_message_loop(client)
            start_heartbeat_loop(client)
            return true
        end
    catch e
        @error "快速重连失败" exception = (e, catch_backtrace())
        client.connected = false
        return false
    end
    return false # Should not be reached
end

function full_reconnect!(client::WSClient)
    if !isnothing(client.reconnect_task) && !istaskdone(client.reconnect_task)
        @warn "重连任务已在进行中"
        return
    end

    client.reconnect_task = @async begin
        disconnect!(client)
        
        max_attempts = 5
        for attempt in 1:max_attempts
            client.reconnect_attempts = attempt
            @info "尝试完全重连 (第 $attempt/$max_attempts 次)..."
            try
                connect!(client)
                if client.connected
                    @info "完全重连成功"
                    client.reconnect_attempts = 0
                    return
                end
            catch e
                @warn "完全重连失败" exception=(e, catch_backtrace())
            end
            
            # Exponential backoff
            sleep_duration = 2.0^attempt
            @info "等待 $sleep_duration 秒后重试"
            sleep(sleep_duration)
        end
        
        @error "完全重连 $max_attempts 次后仍然失败，放弃重连"
        client.reconnect_attempts = 0
    end
end

# ==================== WebSocket Authentication ====================

"""
create_auth_request(config::Config.config) -> Vector{UInt8}

Creates the serialized body for a WebSocket authentication request.
Automatically gets OTP token for WebSocket authentication.
"""
function create_auth_request(config::Config.config)::Vector{UInt8}
    # 获取OTP令牌用于WebSocket认证
    otp_response = get_otp(config)
    
    metadata = Dict("client_version" => Constant.DEFAULT_CLIENT_VERSION)
    if config.enable_overnight
        metadata["need_over_night_quote"] = "true"
    end
    
    auth_req = ControlProtocol.AuthRequest(
        otp_response.otp,
        metadata
    )
    return ControlProtocol.encode(auth_req)
end

# 使用已有WSClient的版本
function ws_request(
    client::WSClient, command_code::UInt8, request_body::Vector{UInt8}; 
    timeout::Float64 = REQUEST_TIMEOUT
    )::Vector{UInt8}

    if !client.connected
        throw(ArgumentError("WebSocket客户端未连接"))
    end

    request_id = send_request_packet(client, command_code, request_body)
    
    # 等待响应
    response_key = "quote_response_$(request_id)"
    start_time = time()
    
    while !haskey(client.pending_responses, response_key) && (time() - start_time) < timeout
        sleep(0.01)
    end
    
    if !haskey(client.pending_responses, response_key)
        throw(LongportException("请求超时"))
    end
    
    status_code, response_body = pop!(client.pending_responses, response_key)
    if status_code != 0
        # 还需要进一步修改  status_code ∈ [0, 3, 7] ?
        @debug "尝试解析错误响应" status_code=status_code response_body_length=length(response_body) response_body_hex=bytes2hex(response_body)
        
        # 检查response_body是否为空
        if isempty(response_body)
            throw(ArgumentError("空的响应体，无法解析错误信息"))
        end
        
        err_proto = ControlProtocol.decode(response_body, ControlProtocol.Error)
        business_code = err_proto.code
        business_msg = err_proto.msg # Use the message from the decoded response
        
        err_msg = "API请求失败: (协议码=$status_code) - $business_msg"
        @lperror(Int(business_code), err_msg, nothing, response_body)
    end
    return response_body
end

end # end of module Client
