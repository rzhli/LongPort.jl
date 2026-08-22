using Test

@testset "v0.9.2 release metadata" begin
    @test VersionNumber(LongBridge.VERSION) >= v"0.9.2"
    @test isdefined(LongBridge, :subscribe_limit)
    @test isdefined(LongBridge, :history_candlestick_limit)
    @test isdefined(LongBridge, :utc_iso8601)
    @test isdefined(LongBridge, :to_market_time)
end
