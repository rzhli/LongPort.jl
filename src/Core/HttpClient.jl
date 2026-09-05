module HttpClient

using HTTP

export HTTP_CLIENT, DEFAULT_TIMEOUT, OAUTH_TIMEOUT, TOKEN_REQUEST_KW, USER_AGENT

# `LongBridge.VERSION` 在 include 本文件之前已绑定，因此这里可以直接取用，
# 无需重复解析 Project.toml。
const _SDK_VERSION = getfield(parentmodule(@__MODULE__), :VERSION)::String

# 上游 Rust SDK 固定发送 `User-Agent: openapi-sdk`；保留该标识并附加 Julia SDK
# 版本，否则 HTTP.jl 会发送默认的 `HTTP.jl/<版本>`，服务端无法区分调用方。
const USER_AGENT = "openapi-sdk LongBridge.jl/$(_SDK_VERSION)"

# One process-wide client shares its transport, connection pool, DNS cache, and
# TLS state across REST, OAuth, and token-refresh requests.
#
# HTTP.jl 2.x 的超时是分阶段的，取 0 表示"沿用 Client 上的默认值"：
# - `connect`：DNS + TCP + 代理 + TLS 握手
# - `read`/`write`：读写空转窗口；未单独设置 response_header_timeout 时，
#   等响应头的空转也由 `read` 兜住
# - `request`：整个请求的截止时间。HTTP.jl 的这一截止时间覆盖重试与退避睡眠
#   （见 `_sleep_retry_delay!`），所以取值高于上游 Rust SDK 的 30s
#   （那是单次尝试的超时，重试叠加在其之外）。
const DEFAULT_TIMEOUT = (connect = 10, read = 20, write = 20, request = 60)
const OAUTH_TIMEOUT = (connect = 10, request = 60, response_header = 10, read = 30)
const HTTP_TRANSPORT =
    HTTP.Transport(max_idle_per_host = 20, max_idle_total = 20, max_conns_per_host = 20)
const HTTP_CLIENT = HTTP.Client(
    transport = HTTP_TRANSPORT,
    cookiejar = nothing,
    default_headers = ["User-Agent" => USER_AGENT],
    connect_timeout = DEFAULT_TIMEOUT.connect,
    request_timeout = DEFAULT_TIMEOUT.request,
    read_idle_timeout = DEFAULT_TIMEOUT.read,
    write_idle_timeout = DEFAULT_TIMEOUT.write,
)

# Token 类接口（OAuth 授权/刷新、/v1/token/refresh）共用的请求配置：这些调用比
# 普通 REST 请求更慢也更少，单独放宽超时，splat 到调用点避免四处重复。
const TOKEN_REQUEST_KW = (
    client = HTTP_CLIENT,
    connect_timeout = OAUTH_TIMEOUT.connect,
    request_timeout = OAUTH_TIMEOUT.request,
    response_header_timeout = OAUTH_TIMEOUT.response_header,
    read_idle_timeout = OAUTH_TIMEOUT.read,
)

end # module HttpClient
