using Test, JSON3, HTTP

@testset "v0.9.1 upstream v4.4.1 sync" begin
    @test VersionNumber(LongBridge.VERSION) >= v"0.9.1"
    @test !isdefined(LongBridge, :all_executions)
    @test !isdefined(LongBridge.Trade, :all_executions)

    headers = [
        "X-Trace-ID" => "trace-463",
        "Server" => "awselb/2.0",
    ]
    response = HTTP.Response(
        463,
        headers,
        "<html><body>Too many IPs in X-Forwarded-For header.</body></html>",
    )
    err = try
        LongBridge.ApiResponse(response)
        nothing
    catch e
        e
    end

    @test err isa LongBridge.UnexpectedHttpResponse
    @test err.status == 463
    @test err.trace_id == "trace-463"
    @test err.headers["server"] == "awselb/2.0"
    @test err.body == String(response.body)

    envelope = HTTP.Response(
        429,
        ["x-trace-id" => "trace-429"],
        JSON3.write(Dict("code" => 429, "message" => "rate limited", "data" => nothing)),
    )
    parsed = LongBridge.ApiResponse(envelope)
    @test parsed.code == 429
    @test parsed.message == "rate limited"
    @test parsed.headers["x-trace-id"] == "trace-429"
end
