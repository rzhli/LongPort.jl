using Test
using LongBridge
using LongBridge.Config
using LongBridge.OAuth
using Dates

@testset "Config defaults" begin
    mktemp() do f, io
        write(io, """
        app_key = "k"
        app_secret = "s"
        access_token = "t"
        token_expire_time = "2099-01-01T00:00:00"
        """)
        close(io)
        cfg = from_toml(f)
        @test cfg.language == LongBridge.Constant.Language.ZH_CN
        @test cfg.enable_overnight == true
    end
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
        # Temporarily override TOKEN_DIR via save/load with custom path
        client_id = "test-roundtrip-$(rand(UInt32))"
        token = OAuthToken(client_id, "access_abc", "refresh_xyz", UInt64(floor(time())) + 3600)

        path = OAuth.save_to_path(token)
        @test isfile(path)

        loaded = OAuth.load_from_path(client_id)
        @test !isnothing(loaded)
        @test loaded.client_id == client_id
        @test loaded.access_token == "access_abc"
        @test loaded.refresh_token == "refresh_xyz"
        @test loaded.expires_at == token.expires_at

        # Cleanup
        rm(path; force=true)
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
