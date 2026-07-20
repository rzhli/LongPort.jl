using Test
using LongBridge
using LongBridge.Config
using LongBridge.OAuth
using LongBridge.Utils: to_dataframe
using Dates

struct _ToDataFrameItem
    name::String
    count::Union{Nothing,Int}
end

# P0 新增 Context 烟测
include("test_p0_smoke.jl")

# P1 新增 Context 烟测
include("test_p1_smoke.jl")

# v0.7.0 上游同步（Asset / filings / UserQuoteProfile / realtime_quote 重命名）
include("test_v0_7_0_sync.jl")

# v0.8.0 上游同步（Screener / short_* unify / top_movers / rank_list / 9 新 Fundamental APIs）
include("test_v0_8_0_sync.jl")

# v0.8.1 上游同步（Screener v4.2.1 / OperatingFinancial.symbol / rank_list ib_ prefix）
include("test_v0_8_1_sync.jl")

# v0.8.5 上游同步（macroeconomic_indicators / macroeconomic + macrodata v2）
include("test_v0_8_5_sync.jl")

# v0.8.6 上游同步（market TradeStatus + macrodata detail fields）
include("test_v0_8_6_sync.jl")

@testset "Config defaults" begin
    direct_cfg = Settings("k", "s", "t", DateTime(2099, 1, 1))
    @test direct_cfg.http_url == LongBridge.Constant.DEFAULT_HTTP_URL_CN
    @test direct_cfg.quote_ws_url == LongBridge.Constant.DEFAULT_QUOTE_WS_CN
    @test direct_cfg.trade_ws_url == LongBridge.Constant.DEFAULT_TRADE_WS_CN

    mktemp() do f, io
        write(io, """
        app_key = "k"
        app_secret = "s"
        access_token = "t"
        token_expire_time = "2099-01-01T00:00:00"
        http_url = "https://example-http.test"
        quote_ws_url = "wss://example-quote.test"
        trade_ws_url = "wss://example-trade.test"
        """)
        close(io)
        cfg = from_toml(f)
        @test cfg.language == LongBridge.Constant.Language.ZH_CN
        @test cfg.enable_overnight == true
        @test cfg.http_url == "https://example-http.test"
        @test cfg.quote_ws_url == "wss://example-quote.test"
        @test cfg.trade_ws_url == "wss://example-trade.test"
    end
end

@testset "to_dataframe typed columns" begin
    df = to_dataframe([_ToDataFrameItem("a", 1), _ToDataFrameItem("b", nothing)])
    @test eltype(df.name) != Any
    @test eltype(df.count) != Any
    @test df.count[2] === missing

    empty_df = to_dataframe(_ToDataFrameItem[])
    @test eltype(empty_df.name) != Any
    @test eltype(empty_df.count) != Any
end

@testset "HTTP query builder" begin
    @test LongBridge.Client._build_query_string(Dict{String,Any}()) == ""
    query = LongBridge.Client._build_query_string(
        Dict{String,Any}(
            "symbol" => ["AAPL.US", "700.HK"],
            "count" => 20,
            "skip" => nothing,
            "space" => "a b",
        ),
    )
    parts = Set(split(query, "&"))
    @test "symbol=AAPL.US" in parts
    @test "symbol=700.HK" in parts
    @test "count=20" in parts
    @test "space=a%20b" in parts
    @test !("skip=nothing" in parts)

    typed_query = LongBridge.Client._build_query_string(Dict("page" => 2, "active" => true))
    @test Set(split(typed_query, "&")) == Set(["page=2", "active=true"])
end

@testset "WebSocket 24-bit length codec" begin
    for value in (0, 1, 0xff, 0x100, 0x123456, 0xffffff)
        io = IOBuffer()
        LongBridge.Client._write_u24(io, value)
        @test position(io) == 3
        seekstart(io)
        @test LongBridge.Client._read_u24(io) == value
    end
    @test_throws ArgumentError LongBridge.Client._write_u24(IOBuffer(), -1)
    @test_throws ArgumentError LongBridge.Client._write_u24(IOBuffer(), 0x1000000)
end

@testset "Generic public collection inputs" begin
    symbols_view = view(["AAPL.US", "700.HK"], 1:1)
    @test hasmethod(
        LongBridge.quote_snapshot,
        Tuple{LongBridge.QuoteContext,typeof(symbols_view)},
    )
    @test hasmethod(
        LongBridge.delete_alerts,
        Tuple{LongBridge.AlertContext,typeof(symbols_view)},
    )
end

@testset "Realtime cache bounds and views" begin
    store = LongBridge.Cache.RealtimeStore{Int,Int,Int,Int,Int}()
    trades = collect(1:600)
    LongBridge.Cache.update_trades!(store, SubString("AAPL.US", 1), view(trades, :))
    @test LongBridge.Cache.get_trades(store, "AAPL.US") == collect(101:600)
    @test LongBridge.Cache.get_trades(store, "AAPL.US"; count = 3) == [598, 599, 600]

    candles = collect(1:1100)
    LongBridge.Cache.update_candlesticks!(store, "AAPL.US", 1, view(candles, :))
    cached = LongBridge.Cache.get_candlesticks(store, "AAPL.US", 1)
    @test length(cached) == 1000
    @test first(cached) == 101
    @test last(cached) == 1100
end

@testset "Disconnect" begin
    cfg = config(
        "test_app_key",
        "test_app_secret",
        "test_access_token",
        DateTime(2099, 1, 1);
        http_url = "https://openapi.longportapp.com",
        quote_ws_url = "wss://openapi-quote.longportapp.com",
        trade_ws_url = "wss://openapi-trade.longportapp.com"
    )

    # Note: These tests will fail to connect without valid credentials,
    # but we can at least verify the context creation works
    @test cfg.app_key == "test_app_key"
    @test cfg.http_url == "https://openapi.longportapp.com"
    @test cfg.auth_mode == :apikey
    @test isnothing(cfg.oauth)
end

@testset "OAuthToken" begin
    token = OAuthToken("test-client", "access123", "refresh456", UInt64(floor(time())) + 7200)
    @test !OAuth.is_expired(token)
    @test !OAuth.expires_soon(token)

    expired_token = OAuthToken("test-client", "access123", nothing, UInt64(0))
    @test OAuth.is_expired(expired_token)
    @test OAuth.expires_soon(expired_token)

    soon_token = OAuthToken("test-client", "access123", "refresh456", UInt64(floor(time())) + 600)
    @test !OAuth.is_expired(soon_token)
    @test OAuth.expires_soon(soon_token)  # < 1 hour
end

@testset "OAuthToken save/load round-trip" begin
    mktempdir() do tmpdir
        old_token_dir = get(ENV, "LONGBRIDGE_TOKEN_DIR", nothing)
        ENV["LONGBRIDGE_TOKEN_DIR"] = tmpdir

        try
            client_id = "test-roundtrip-$(rand(UInt32))"
            token = OAuthToken(client_id, "access_abc", "refresh_xyz", UInt64(floor(time())) + 3600)

            path = OAuth.save_to_path(token)
            @test isfile(path)
            @test dirname(path) == tmpdir

            loaded = OAuth.load_from_path(client_id)
            @test !isnothing(loaded)
            @test loaded.client_id == client_id
            @test loaded.access_token == "access_abc"
            @test loaded.refresh_token == "refresh_xyz"
            @test loaded.expires_at == token.expires_at
        finally
            if isnothing(old_token_dir)
                delete!(ENV, "LONGBRIDGE_TOKEN_DIR")
            else
                ENV["LONGBRIDGE_TOKEN_DIR"] = old_token_dir
            end
        end
    end
end

@testset "from_oauth config" begin
    handle = OAuthHandle("test-oauth-client", UInt16(60355),
        OAuthToken("test-oauth-client", "test-access", "test-refresh", UInt64(floor(time())) + 7200))

    cfg = from_oauth(handle)
    @test cfg.auth_mode == :oauth
    @test cfg.app_key == "test-oauth-client"
    @test cfg.app_secret == ""
    @test !isnothing(cfg.oauth)
    @test cfg.oauth === handle
end
