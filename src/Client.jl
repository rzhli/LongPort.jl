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
using ..OAuth: OAuthHandle, access_token as oauth_access_token

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
sign(method, path, headers, params, body, config) -> Union{String, Nothing}

Generate API signature for authentication. Returns `nothing` in OAuth mode (empty app_secret).
"""
function sign(
    method::String, path::String, headers::Dict{String, String},
    params::String, body::String, config::Config.Settings
    )::Union{String, Nothing}

    # OAuth mode: no HMAC signature needed
    if isempty(config.app_secret)
        return nothing
    end

    # 获取必要的参数
    app_key = config.app_key
    app_secret = config.app_secret
    access_token = config.access_token
    timestamp = headers["X-Timestamp"]

    # 构建signed_headers和signed_values
    if !isnothing(access_token) && !isempty(access_token)
        signed_headers = "authorization;x-api-key;x-timestamp"
        signed_values = "authorization:$(access_token)\nx-api-key:$(app_key)\nx-timestamp:$(timestamp)\n"
    else
        signed_headers = "x-api-key;x-timestamp"
        signed_values = "x-api-key:$(app_key)\nx-timestamp:$(timestamp)\n"
    end
    
    # 构建待签名字符串
    query = params  # 查询参数

    # 使用 IOBuffer 避免多次字符串分配
    io = IOBuffer()
    print(io, method, "|", path, "|", query, "|", signed_values, "|", signed_headers, "|")

    # 如果有body，添加body的SHA1哈希
    if !isempty(body)
        print(io, bytes2hex(SHA.sha1(body)))
    end
    str_to_sign = String(take!(io))

    # 最终的待签名字符串
    final_str_to_sign = string("HMAC-SHA256|", bytes2hex(SHA.sha1(str_to_sign)))
    
    # 使用HMAC-SHA256生成签名
    signature = bytes2hex(SHA.hmac_sha256(Vector{UInt8}(app_secret), final_str_to_sign))
    
    return "HMAC-SHA256 SignedHeaders=$(signed_headers), Signature=$(signature)"
end

# ==================== HTTP Client ====================

# 构建 query string
function _build_query_string(params::Dict{String,Any})
    isempty(params) && return ""
    parts = String[]
    for (k, v) in params
        if v isa Vector
            for val in v
                push!(parts, "$(k)=$(HTTP.URIs.escapeuri(val))")
            end
        else
            push!(parts, "$(k)=$(HTTP.URIs.escapeuri(string(v)))")
        end
    end
    join(parts, "&")
end

# 通用 HTTP 请求函数
function _http_request(config::Config.Settings, method::String, path::String;
                       params::Dict{String,Any}=Dict{String,Any}(),
                       body::Union{Dict,Nothing}=nothing)
    try
        base_url = config.http_url
        query_string = _build_query_string(params)
        full_url = base_url * path * (isempty(query_string) ? "" : "?" * query_string)
        body_str = isnothing(body) ? "" : JSON3.write(body)

        if config.auth_mode == :oauth
            # OAuth mode: Bearer token, no HMAC signature
            token = oauth_access_token(config.oauth)
            headers = Dict{String, String}(
                "X-Api-Key" => config.app_key,
                "Authorization" => "Bearer $token",
                "Content-Type" => "application/json; charset=utf-8"
            )
        else
            # API Key mode: HMAC-SHA256 signature
            timestamp = string(floor(Int, time() * 1000))
            headers = Dict{String, String}(
                "X-Api-Key" => config.app_key,
                "Authorization" => config.access_token,
                "X-Timestamp" => timestamp,
                "Content-Type" => "application/json; charset=utf-8"
            )
            signature = sign(method, path, headers, query_string, body_str, config)
            if !isnothing(signature)
                headers["X-Api-Signature"] = signature
            end
        end

        if method in ("GET", "DELETE")
            http_fn = method == "GET" ? HTTP.get : HTTP.delete
            return http_fn(full_url; headers, pool=POOL, readtimeout=DEFAULT_TIMEOUT.read, retries=RETRIES)
        else
            http_fn = method == "POST" ? HTTP.post : HTTP.put
            return http_fn(full_url; headers, body=body_str, pool=POOL, readtimeout=DEFAULT_TIMEOUT.read, retries=RETRIES)
        end
    catch e
        @error "HTTP $method 请求异常" path=path exception=(e, catch_backtrace())
        rethrow(e)
    end
end

get(config::Config.Settings, path::String; params::Dict{String,Any}=Dict{String,Any}()) =
    _http_request(config, "GET", path; params)

post(config::Config.Settings, path::String; body::Dict=Dict()) =
    _http_request(config, "POST", path; body)

put(config::Config.Settings, path::String; body::Dict=Dict()) =
    _http_request(config, "PUT", path; body)

delete(config::Config.Settings, path::String; params::Dict{String,Any}=Dict{String,Any}()) =
    _http_request(config, "DELETE", path; params)

"""
refresh_token(config::Config.Settings, expired_at::String) -> Dict

Refresh the access token using the refresh token API
Reference: https://open.longportapp.com/zh-CN/docs/refresh-token-api

# Parameters
- `expired_at`: ISO8601 timestamp of expiration (e.g., "2023-04-14T12:13:57.859Z")

# Returns
- Dictionary containing new token information
"""
function refresh_token(config::Config.Settings, expired_at::String)::Dict
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
get_otp(config::Config.Settings) -> NamedTuple

Get the socket OTP(One Time Password) and connection info
Reference: https://open.longportapp.com/zh-CN/docs/socket-token-api

Returns:
- NamedTuple with fields:
  - otp: String - One-time password for socket connection
  - limit: Int - Total connection limit
  - online: Int - Current online connections
"""
function get_otp(config::Config.Settings)::NamedTuple{(:otp, :limit, :online), Tuple{String, Int, Int}}
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

# ==================== WebSocket Client ====================

"""
WSClient

WebSocket 客户端，用于与长桥服务器建立长连接。

# Fields
- `ws::Union{Nothing, WebSockets.WebSocket}`: WebSocket 连接
- `url::String`: 连接 URL
- `connected::Bool`: 连接状态（包括认证成功）
- `seq_id::UInt32`: 序列号
- `pending::Dict{UInt32, Channel{Tuple{UInt8, Vector{UInt8}}}}`: 待响应通道，按 request_id 索引
- `send_lock::ReentrantLock`: 序列化发送 + 通道注册
- `auth_data::Union{Nothing,Vector{UInt8}}`: 认证数据
"""
mutable struct WSClient
    ws::Union{Nothing, WebSockets.WebSocket}
    url::String
    connected::Bool
    seq_id::UInt32
    session_id::Union{String, Nothing}
    pending::Dict{UInt32, Channel{Tuple{UInt8, Vector{UInt8}}}}
    send_lock::ReentrantLock
    auth_event::Threads.Event
    auth_data::Union{Nothing,Vector{UInt8}}
    on_push::Union{Function, Nothing}
    heartbeat_task::Union{Nothing, Task}
    reconnect_attempts::Int
    reconnect_task::Union{Nothing, Task}
    config::Config.Settings

    function WSClient(url::String, config::Config.Settings)
        new(
            nothing,                # ws
            url,                    # url
            false,                  # connected (只有认证成功后才为true)
            UInt32(1),              # seq_id
            nothing,                # session_id
            Dict{UInt32, Channel{Tuple{UInt8, Vector{UInt8}}}}(), # pending
            ReentrantLock(),        # send_lock
            Threads.Event(),        # auth_event (set after successful auth)
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

    # Reset auth signal in case this is a reconnect
    client.auth_event = Threads.Event()

    # 创建WebSocket连接
    ws_task = @async begin
        WebSockets.open(full_url; nagle=false, quickack=true) do ws
            client.ws = ws
            client.seq_id = UInt32(1)

            send_request_packet(client, COMMAND_CODE_AUTH, client.auth_data)

            # 启动消息处理循环
            start_message_loop(client)

            # 保持连接开放，直到被外部关闭
            while !isnothing(client.ws) && isopen(client.ws.io)
                sleep(0.1)
            end
        end
    end

    # 等待认证完成（最多 30s）。
    # 在认证响应到达消息循环时，notify(auth_event) 会立即唤醒此处。
    timer = Timer(30.0)
    waiter = @async (try; wait(timer); notify(client.auth_event); catch; end)
    try
        wait(client.auth_event)
    finally
        close(timer)
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

    lock(client.send_lock) do
        request_id = client.seq_id
        client.seq_id += UInt32(1)
        _write_request_frame(client, cmd, body, request_id)
        return request_id
    end
end

# Internal: build and ship a single request frame. Caller must hold send_lock.
function _write_request_frame(client::WSClient, cmd::UInt8, body::Vector{UInt8}, request_id::UInt32)
    body_len = length(body)
    packet = IOBuffer(sizehint = 11 + body_len)

    # Header byte: type=1 (request), verify=0, gzip=0, reserve=0
    write(packet, 0x01)
    write(packet, cmd)
    write(packet, hton(request_id))
    write(packet, hton(UInt16(REQUEST_TIMEOUT * 1000)))
    write(packet, UInt8((body_len >> 16) & 0xFF))
    write(packet, UInt8((body_len >> 8) & 0xFF))
    write(packet, UInt8(body_len & 0xFF))
    write(packet, body)

    send(client.ws, take!(packet))
    @debug "已发送请求数据包" cmd=cmd request_id=request_id body_len=body_len
    return request_id
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
                            notify(client.auth_event)  # 唤醒 connect! 中的等待者
                        end
                        
                        # 派发响应到等待的 channel（如果有 ws_request 在等）
                        ch = lock(client.send_lock) do
                            get(client.pending, request_id, nothing)
                        end
                        if !isnothing(ch)
                            try
                                put!(ch, (status_code, body))
                            catch e
                                @debug "派发响应到通道失败（可能已超时关闭）" request_id=request_id exception=e
                            end
                        else
                            @debug "无等待通道（可能为认证响应或孤儿响应）" request_id=request_id cmd=cmd
                        end
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
create_auth_request(config::Config.Settings) -> Vector{UInt8}

Creates the serialized body for a WebSocket authentication request.
Automatically gets OTP token for WebSocket authentication.
"""
function create_auth_request(config::Config.Settings)::Vector{UInt8}
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
    if isnothing(client.ws) || !isopen(client.ws.io)
        throw(ArgumentError("WebSocket物理连接不存在"))
    end

    # 在持锁状态下：分配 seq_id、注册 channel、发送数据包。
    # 这避免了响应在 send 完成与 register 之间到达造成的丢失。
    ch = Channel{Tuple{UInt8, Vector{UInt8}}}(1)
    request_id = lock(client.send_lock) do
        rid = client.seq_id
        client.seq_id += UInt32(1)
        client.pending[rid] = ch
        _write_request_frame(client, command_code, request_body, rid)
        return rid
    end

    # 等待响应或超时
    timer = Timer(timeout) do _
        # 超时后关闭 channel —— take! 会抛 InvalidStateException
        isopen(ch) && close(ch)
    end

    try
        local status_code::UInt8
        local response_body::Vector{UInt8}
        try
            status_code, response_body = take!(ch)
        catch e
            if e isa InvalidStateException
                throw(LongBridgeError(408, "请求超时"))
            end
            rethrow(e)
        end

        if status_code != 0
            @debug "尝试解析错误响应" status_code=status_code response_body_length=length(response_body) response_body_hex=bytes2hex(response_body)
            if isempty(response_body)
                throw(ArgumentError("空的响应体，无法解析错误信息"))
            end
            err_proto = ControlProtocol.decode(response_body, ControlProtocol.Error)
            err_msg = "API请求失败: (协议码=$status_code) - $(err_proto.msg)"
            @lperror(Int(err_proto.code), err_msg, nothing, response_body)
        end
        return response_body
    finally
        close(timer)
        lock(client.send_lock) do
            delete!(client.pending, request_id)
        end
    end
end

end # end of module Client
