module HttpClient

using HTTP

export HTTP_CLIENT, DEFAULT_TIMEOUT, OAUTH_TIMEOUT

# One process-wide client shares its transport, connection pool, DNS cache, and
# TLS state across REST, OAuth, and token-refresh requests.
const DEFAULT_TIMEOUT = (connect = 10, read = 20, write = 20)
const OAUTH_TIMEOUT = (connect = 10, request = 60, response_header = 10, read = 30)
const HTTP_TRANSPORT =
    HTTP.Transport(max_idle_per_host = 20, max_idle_total = 20, max_conns_per_host = 20)
const HTTP_CLIENT = HTTP.Client(
    transport = HTTP_TRANSPORT,
    cookiejar = nothing,
    connect_timeout = DEFAULT_TIMEOUT.connect,
    read_idle_timeout = DEFAULT_TIMEOUT.read,
    write_idle_timeout = DEFAULT_TIMEOUT.write,
)

end # module HttpClient
