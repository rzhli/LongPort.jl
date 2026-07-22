module Client

using HTTP, JSON3, SHA, CodecZlib
using HTTP: WebSockets
import HTTP.WebSockets: send
using Base.Threads

using ..Config
using ..Constant
using ..ControlProtocol
using ..Errors
using ..OAuth: access_token as oauth_access_token

export WSClient, refresh_token, post, put, delete

# HTTP (REST) Client Constants
const DEFAULT_TIMEOUT = (connect = 10, read = 20, write = 20)
const RETRIES = 3

# WebSocket Client Constants (对齐上游 Rust wsclient)
# 上游模型：客户端不主动发 ping，由服务端定期 ping 保活；
# HTTP.jl 会自动回 PONG 并在收到任意帧时重置 read idle 计时器，
# 因此 WS_HEARTBEAT_TIMEOUT 等价于上游的 HEARTBEAT_TIMEOUT。
const WS_CONNECT_TIMEOUT = 5     # 上游 CONNECT_TIMEOUT
const WS_HEARTBEAT_TIMEOUT = 120 # 上游 HEARTBEAT_TIMEOUT；read idle 窗口，服务端 ping 会刷新
const WS_WRITE_TIMEOUT = 20      # HTTP.jl 中 write_idle_timeout 仅作用于握手阶段
const HTTP_TRANSPORT =
    HTTP.Transport(max_idle_per_host = 20, max_idle_total = 20, max_conns_per_host = 20)
const HTTP_CLIENT = HTTP.Client(
    transport = HTTP_TRANSPORT,
    connect_timeout = DEFAULT_TIMEOUT.connect,
    read_idle_timeout = DEFAULT_TIMEOUT.read,
    write_idle_timeout = DEFAULT_TIMEOUT.write,
)
# WebSocket Client Constants (参考 Rust 实现)
const REQUEST_TIMEOUT = 30.0  # seconds
const QUERY_STRING_SIZE_HINT = 256
const DC_REGION_HEADER = "x-dc-region"
const PAPERTRADING_HEADER = "x-papertrading"

# 认证和心跳命令 (use ControlProtocol enum values)
const COMMAND_CODE_AUTH = UInt8(ControlProtocol.ControlCommand.CMD_AUTH)
const COMMAND_CODE_HEARTBEAT = UInt8(ControlCommand.CMD_HEARTBEAT)
const COMMAND_CODE_RECONNECT = UInt8(ControlCommand.CMD_RECONNECT)
const COMMAND_CODE_CLOSE = UInt8(ControlCommand.CMD_CLOSE)

function _websocket_url(url::String)
    return string(
        url,
        "?version=", Constant.PROTOCOL_VERSION,
        "&codec=", Constant.CODEC_TYPE,
        "&platform=", Constant.PLATFORM_TYPE,
    )
end

# ==================== Signature Authentication ====================

"""
sign(method, path, headers, params, body, config) -> Union{String, Nothing}

Generate API signature for authentication. Returns `nothing` in OAuth mode (empty app_secret).
"""
function sign(
    method::String,
    path::String,
    headers::Dict{String,String},
    params::String,
    body::String,
    config::Config.Settings,
)::Union{String,Nothing}

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
function _build_query_string(params::AbstractDict{<:AbstractString})
    isempty(params) && return ""
    io = IOBuffer(sizehint = QUERY_STRING_SIZE_HINT)
    first = true
    for (k, v) in params
        isnothing(v) && continue
        escaped_key = HTTP.URIs.escapeuri(String(k))
        if v isa AbstractVector
            for val in v
                isnothing(val) && continue
                first || write(io, UInt8('&'))
                first = false
                print(io, escaped_key, "=", HTTP.URIs.escapeuri(string(val)))
            end
        else
            first || write(io, UInt8('&'))
            first = false
            print(io, escaped_key, "=", HTTP.URIs.escapeuri(string(v)))
        end
    end
    first ? "" : String(take!(io))
end

function _regional_http_url(config::Config.Settings, region::Symbol)
    if region === :us && config.http_url == Constant.DEFAULT_HTTP_URL_CN
        return Constant.DEFAULT_HTTP_URL
    end
    return config.http_url
end

function _regional_ws_url(url::String, region::Symbol)
    region === :us || return url
    url == Constant.DEFAULT_QUOTE_WS_CN && return Constant.DEFAULT_QUOTE_WS
    url == Constant.DEFAULT_TRADE_WS_CN && return Constant.DEFAULT_TRADE_WS
    return url
end

function _routing_headers(config::Config.Settings, region::Symbol)
    headers = Pair{String,String}[DC_REGION_HEADER => String(region)]
    config.enable_papertrading && push!(headers, PAPERTRADING_HEADER => "true")
    return headers
end

function _check_dc_region(path::String, current::Symbol, required::Union{Symbol,Nothing})
    isnothing(required) && return
    current === required && return
    throw(LongBridgeError(
        403,
        "API endpoint $path requires $(uppercase(String(required))) data-center credentials; current region is $(uppercase(String(current)))",
    ))
end

# 通用 HTTP 请求函数
function _http_request(
    config::Config.Settings,
    method::String,
    path::String;
    params::Dict{String,Any} = Dict{String,Any}(),
    body::Union{Dict,Nothing} = nothing,
    dc_region::Union{Symbol,Nothing} = nothing,
)
    try
        query_string = _build_query_string(params)
        body_str = isnothing(body) ? "" : JSON3.write(body)

        if config.auth_mode == :oauth
            # OAuth mode: Bearer token, no HMAC signature
            token = oauth_access_token(config.oauth)
            headers = Dict{String,String}(
                "X-Api-Key" => config.app_key,
                "Authorization" => "Bearer $token",
                "Content-Type" => "application/json; charset=utf-8",
            )
            current_region = startswith(token, "us_") ? :us : :ap
        else
            # API Key mode: HMAC-SHA256 signature
            timestamp = string(floor(Int, time() * 1000))
            headers = Dict{String,String}(
                "X-Api-Key" => config.app_key,
                "Authorization" => config.access_token,
                "X-Timestamp" => timestamp,
                "Content-Type" => "application/json; charset=utf-8",
            )
            current_region = Config.dc_region(config)
            signature = sign(method, path, headers, query_string, body_str, config)
            if !isnothing(signature)
                headers["X-Api-Signature"] = signature
            end
        end

        _check_dc_region(path, current_region, dc_region)
        headers[DC_REGION_HEADER] = String(current_region)
        config.enable_papertrading && (headers[PAPERTRADING_HEADER] = "true")
        base_url = _regional_http_url(config, current_region)
        full_url = base_url * path * (isempty(query_string) ? "" : "?" * query_string)

        if method == "GET"
            return HTTP.get(
                full_url;
                headers,
                client = HTTP_CLIENT,
                retries = RETRIES,
                status_exception = false,
            )
        elseif method == "DELETE"
            # DELETE 可带 body（Alert/Sharelist 等接口需要）
            kw =
                isnothing(body) ?
                (; headers, client = HTTP_CLIENT, retries = RETRIES, status_exception = false) :
                (;
                    headers,
                    body = body_str,
                    client = HTTP_CLIENT,
                    retries = RETRIES,
                    status_exception = false,
                )
            return HTTP.delete(full_url; kw...)
        else
            http_fn = method == "POST" ? HTTP.post : HTTP.put
            return http_fn(
                full_url;
                headers,
                body = body_str,
                client = HTTP_CLIENT,
                retries = RETRIES,
                status_exception = false,
            )
        end
    catch e
        @error "HTTP $method 请求异常" path=path exception=(e, catch_backtrace())
        rethrow(e)
    end
end

http_get(
    config::Config.Settings,
    path::String;
    params::Dict{String,Any} = Dict{String,Any}(),
    dc_region::Union{Symbol,Nothing} = nothing,
) = _http_request(config, "GET", path; params, dc_region)

http_post(
    config::Config.Settings,
    path::String;
    body::Dict = Dict(),
    dc_region::Union{Symbol,Nothing} = nothing,
) = _http_request(config, "POST", path; body, dc_region)

http_put(
    config::Config.Settings,
    path::String;
    body::Dict = Dict(),
    dc_region::Union{Symbol,Nothing} = nothing,
) = _http_request(config, "PUT", path; body, dc_region)

http_delete(
    config::Config.Settings,
    path::String;
    params::Dict{String,Any} = Dict{String,Any}(),
    body::Union{Dict,Nothing} = nothing,
    dc_region::Union{Symbol,Nothing} = nothing,
) = _http_request(config, "DELETE", path; params, body, dc_region)

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
        result = ApiResponse(http_get(config, "/v1/token/refresh"; params = params))
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
function get_otp(
    config::Config.Settings,
)::NamedTuple{(:otp, :limit, :online),Tuple{String,Int,Int}}
    try
        resp = ApiResponse(http_get(config, "/v1/socket/token"))
        if resp.code == 0
            return (otp = resp.data.otp, limit = resp.data.limit, online = resp.data.online)
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
    ws::Union{Nothing,WebSockets.WebSocket}
    url::String
    connected::Bool
    seq_id::UInt32
    session_id::Union{String,Nothing}
    pending::Dict{UInt32,Channel{Tuple{UInt8,Vector{UInt8}}}}
    send_lock::ReentrantLock
    auth_event::Threads.Event
    auth_data::Union{Nothing,Vector{UInt8}}
    on_push::Union{Function,Nothing}
    on_reconnect::Union{Function,Nothing}
    heartbeat_task::Union{Nothing,Task}
    reconnect_attempts::Int
    reconnect_task::Union{Nothing,Task}
    config::Config.Settings

    function WSClient(url::String, config::Config.Settings)
        new(
            nothing,                # ws
            url,                    # url
            false,                  # connected (只有认证成功后才为true)
            UInt32(1),              # seq_id
            nothing,                # session_id
            Dict{UInt32,Channel{Tuple{UInt8,Vector{UInt8}}}}(), # pending
            ReentrantLock(),        # send_lock
            Threads.Event(),        # auth_event (set after successful auth)
            nothing,                # auth_data
            nothing,
            nothing,
            nothing,                # heartbeat_task
            0,                      # reconnect_attempts
            nothing,                # reconnect_task
            config,
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
    region = Config.dc_region(client.config)
    full_url = _websocket_url(_regional_ws_url(client.url, region))
    ws_headers = _routing_headers(client.config, region)

    # Reset auth signal in case this is a reconnect
    client.auth_event = Threads.Event()
    connect_error = Ref{Any}(nothing)

    # 创建WebSocket连接
    errormonitor(@async begin
        try
            WebSockets.open(
                full_url;
                headers = ws_headers,
                connect_timeout = WS_CONNECT_TIMEOUT,
                read_idle_timeout = WS_HEARTBEAT_TIMEOUT,
                write_idle_timeout = WS_WRITE_TIMEOUT,
            ) do ws
                client.ws = ws
                client.seq_id = UInt32(1)

                send_request_packet(client, COMMAND_CODE_AUTH, client.auth_data)

                # 启动消息处理循环
                start_message_loop(client)

                # 保持连接开放，直到被外部关闭
                while client.ws === ws && _ws_is_open(ws)
                    sleep(0.1)
                end
            end
        catch e
            connect_error[] = (e, catch_backtrace())
            client.connected = false
            notify(client.auth_event)
        end
    end)

    # 等待认证完成（最多 30s）。
    # 在认证响应到达消息循环时，notify(auth_event) 会立即唤醒此处。
    timer = Timer(30.0) do _
        notify(client.auth_event)
    end
    try
        wait(client.auth_event)
    finally
        close(timer)
    end

    if !isnothing(connect_error[])
        err, bt = connect_error[]
        @error "WebSocket连接任务异常" exception=(err, bt)
        throw(err)
    end

    if !client.connected
        @lperror(408, "WebSocket连接或认证超时")
    end
end

_ws_is_open(ws::Nothing) = false
_ws_is_open(ws::WebSockets.WebSocket) = !WebSockets.isclosed(ws)

"""
disconnect!(client::WSClient)
    
断开 WebSocket 连接。
"""
function disconnect!(client::WSClient)
    if !client.connected && isnothing(client.ws)
        return
    end
    client.connected = false

    @info "正在断开 WebSocket 连接..." session_id=client.session_id

    if !isnothing(client.heartbeat_task) && !istaskdone(client.heartbeat_task)
        schedule(client.heartbeat_task, InterruptException(); error = true)
        client.heartbeat_task = nothing
    end

    if !isnothing(client.reconnect_task) && !istaskdone(client.reconnect_task)
        schedule(client.reconnect_task, InterruptException(); error = true)
        client.reconnect_task = nothing
    end

    if _ws_is_open(client.ws)
        try
            WebSockets.close(client.ws)
        catch
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
    if !_ws_is_open(client.ws)
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
function _write_request_frame(
    client::WSClient,
    cmd::UInt8,
    body::Vector{UInt8},
    request_id::UInt32,
)
    body_len = length(body)
    body_len <= 0x00ff_ffff || throw(ArgumentError("WebSocket request body is too large"))
    packet = IOBuffer(sizehint = 11 + body_len)

    # Header byte: type=1 (request), verify=0, gzip=0, reserve=0
    write(packet, 0x01)
    write(packet, cmd)
    write(packet, hton(request_id))
    write(packet, hton(UInt16(REQUEST_TIMEOUT * 1000)))
    _write_u24(packet, body_len)
    write(packet, body)

    send(client.ws, take!(packet))
    @debug "已发送请求数据包" cmd=cmd request_id=request_id body_len=body_len
    return request_id
end

@inline function _write_u24(io::IO, value::Integer)
    0 <= value <= 0x00ff_ffff || throw(ArgumentError("value does not fit in 24 bits"))
    write(
        io,
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    )
end

@inline function _read_u24(io::IO)::Int
    return (Int(read(io, UInt8)) << 16) |
           (Int(read(io, UInt8)) << 8) |
           Int(read(io, UInt8))
end

"""
start_message_loop(client::WSClient)
    
启动消息处理循环。
"""
function start_message_loop(client::WSClient)
    ws = client.ws
    isnothing(ws) && return

    errormonitor(@async begin
        try
            @info "启动消息处理循环"
            # 使用HTTP.jl推荐的WebSocket消息循环模式
            try
                for msg in ws
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
                        body_len = _read_u24(io)

                        @debug "解析包头" cmd=cmd request_id=request_id status_code=status_code body_len=body_len
                        if body_len > length(data) - 10
                            @warn "body_len声明超出实际剩余长度" body_len=body_len remaining=length(
                                data,
                            )-10
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
                                auth_resp = ControlProtocol.decode(
                                    body,
                                    ControlProtocol.AuthResponse,
                                )
                                client.session_id = auth_resp.session_id
                                @info "认证成功，连接已建立" session_id=client.session_id
                                # 对齐上游：客户端不主动发心跳，由服务端 ping 保活
                                # （HTTP.jl 自动回 PONG 并刷新 read idle 计时器）
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
                        body_len = _read_u24(io)

                        @debug "解析推送包头" cmd=cmd body_len=body_len
                        if body_len > length(data) - 5
                            @warn "推送包body_len声明超出实际剩余长度" body_len=body_len remaining=length(
                                data,
                            )-5
                            continue
                        end

                        # 读取包体
                        body = read(io, body_len)

                        # @info "收到推送数据包" cmd=cmd body_len=body_len hex_preview=bytes2hex(body[1:20])
                        if cmd == COMMAND_CODE_CLOSE
                            close_msg = ControlProtocol.decode(body, ControlProtocol.Close)
                            @warn "收到服务器关闭连接指令" code=close_msg.code reason=close_msg.reason
                            client.ws === ws && disconnect!(client)
                        elseif cmd == COMMAND_CODE_RECONNECT
                            reconnect_msg = ControlProtocol.decode(
                                body,
                                ControlProtocol.ReconnectRequest,
                            )
                            @warn "收到服务器重连指令" session_id=reconnect_msg.session_id
                            client.ws === ws && reconnect!(client)
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
                elseif client.ws === ws
                    # 连接非正常终止（EOF / 1006 read idle / 协议错误等）。
                    # 对齐上游：连接断开即触发重连（优先用 session_id 快速重连，
                    # 失败再回退完整认证重连），而不是仅断开导致静默死亡。
                    if e isa EOFError
                        @info "消息循环检测到连接关闭，尝试重连" session_id=client.session_id
                    else
                        @error "消息循环异常，尝试重连" exception=(e, catch_backtrace())
                    end
                    reconnect!(client)
                end
            end
        catch e
            @error "消息循环外层异常" exception=(e, catch_backtrace())
        finally
            @info "消息处理循环已停止" session_id=client.session_id
        end
    end)
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

    if !isnothing(client.heartbeat_task) && !istaskdone(client.heartbeat_task)
        schedule(client.heartbeat_task, InterruptException(); error = true)
        client.heartbeat_task = nothing
    end

    old_ws = client.ws
    reconnect_event = Threads.Event()
    reconnect_error = Ref{Any}(nothing)
    reconnect_ok = Ref(false)

    errormonitor(@async begin
        try
            region = Config.dc_region(client.config)
            full_url = _websocket_url(_regional_ws_url(client.url, region))

            # 1. 物理连接
            WebSockets.open(
                full_url;
                headers = _routing_headers(client.config, region),
                connect_timeout = WS_CONNECT_TIMEOUT,
                read_idle_timeout = WS_HEARTBEAT_TIMEOUT,
                write_idle_timeout = WS_WRITE_TIMEOUT,
            ) do ws
                client.ws = ws
                client.seq_id = UInt32(1)
                client.connected = true

                # ws_request relies on the message loop to dispatch the
                # reconnect response into client.pending.
                start_message_loop(client)

                # 2. 发送 ReconnectRequest
                metadata = Dict("client_version" => Constant.DEFAULT_CLIENT_VERSION)
                if client.config.enable_overnight
                    metadata["need_over_night_quote"] = "true"
                end
                reconnect_req =
                    ControlProtocol.ReconnectRequest(client.session_id, metadata)
                req_body = ControlProtocol.encode(reconnect_req)

                # 使用 ws_request 发送并等待响应
                resp_body = ws_request(client, COMMAND_CODE_RECONNECT, req_body)

                # 3. 处理响应
                reconnect_resp =
                    ControlProtocol.decode(resp_body, ControlProtocol.ReconnectResponse)

                client.connected = true
                client.session_id = reconnect_resp.session_id # 更新 session_id
                @info "快速重连成功" new_session_id=client.session_id

                reconnect_ok[] = true
                notify(client.auth_event)
                notify(reconnect_event)

                if !isnothing(old_ws) && old_ws !== ws && _ws_is_open(old_ws)
                    try
                        WebSockets.close(old_ws)
                    catch
                    end
                end

                # 对齐上游：不重启客户端心跳，由服务端 ping 保活。
                # 上游在 reconnect 后无条件重新订阅，这里同样恢复订阅。
                if !isnothing(client.on_reconnect)
                    try
                        Base.invokelatest(client.on_reconnect)
                    catch e
                        @error "快速重连后恢复订阅失败" exception=(e, catch_backtrace())
                    end
                end

                # Keep HTTP.WebSockets.open's do-block alive for the new socket.
                while client.ws === ws && _ws_is_open(ws)
                    sleep(0.1)
                end
            end
        catch e
            reconnect_error[] = (e, catch_backtrace())
            client.connected = false
            notify(reconnect_event)
        end
    end)

    timer = Timer(REQUEST_TIMEOUT) do _
        notify(reconnect_event)
    end
    try
        wait(reconnect_event)
    finally
        close(timer)
    end

    if reconnect_ok[]
        return true
    end

    if !isnothing(reconnect_error[])
        err, bt = reconnect_error[]
        @error "快速重连失败" exception=(err, bt)
    else
        @error "快速重连超时"
    end
    full_reconnect!(client)
    return false
end

function full_reconnect!(client::WSClient)
    if !isnothing(client.reconnect_task) && !istaskdone(client.reconnect_task)
        @warn "重连任务已在进行中"
        return
    end

    client.reconnect_task = errormonitor(@async begin
        disconnect!(client)

        max_attempts = 5
        for attempt = 1:max_attempts
            client.reconnect_attempts = attempt
            @info "尝试完全重连 (第 $attempt/$max_attempts 次)..."
            try
                connect!(client)
                if client.connected
                    @info "完全重连成功"
                    client.reconnect_attempts = 0
                    if !isnothing(client.on_reconnect)
                        try
                            Base.invokelatest(client.on_reconnect)
                        catch e
                            @error "重连后恢复订阅失败" exception=(e, catch_backtrace())
                        end
                    end
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
    end)
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

    auth_req = ControlProtocol.AuthRequest(otp_response.otp, metadata)
    return ControlProtocol.encode(auth_req)
end

# 使用已有WSClient的版本
function ws_request(
    client::WSClient,
    command_code::UInt8,
    request_body::Vector{UInt8};
    timeout::Float64 = REQUEST_TIMEOUT,
)::Vector{UInt8}

    if !client.connected
        throw(ArgumentError("WebSocket客户端未连接"))
    end
    if !_ws_is_open(client.ws)
        throw(ArgumentError("WebSocket物理连接不存在"))
    end

    # 在持锁状态下：分配 seq_id、注册 channel、发送数据包。
    # 这避免了响应在 send 完成与 register 之间到达造成的丢失。
    ch = Channel{Tuple{UInt8,Vector{UInt8}}}(1)
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
            @debug "尝试解析错误响应" status_code=status_code response_body_length=length(
                response_body,
            ) response_body_hex=bytes2hex(response_body)
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
