using Test
using LongBridge
using LongBridge.Utils: Dec64
using LongBridge.QuoteProtocol: UserQuoteProfileRequest, UserQuoteProfileResponse,
                                 QuotePackageDetail
using JSON3, StructTypes, ProtoBuf, Dates

# =========================================================================
# v0.7.0 同步上游 Rust SDK 4.1.0 的新增/调整
# =========================================================================

@testset "Asset constructor & enum" begin
    cfg = LongBridge.Config.Settings(
        "k", "s", "t", DateTime(2099, 1, 1);
        http_url     = "https://example.test",
        quote_ws_url = "wss://example.test",
        trade_ws_url = "wss://example.test",
    )
    @test AssetContext(cfg) isa AssetContext
    @test Int(StatementType.Daily)   == 1
    @test Int(StatementType.Monthly) == 2
end

@testset "Asset JSON parsing" begin
    sl = StructTypes.construct(GetStatementListResponse, JSON3.read("""
        {"list":[
          {"dt":20260131,"file_key":"abc123"},
          {"dt":20260229,"file_key":"def456"}
        ]}"""))
    @test length(sl.list) == 2
    @test sl.list[1].dt == 20260131
    @test sl.list[1].file_key == "abc123"

    # 空响应兜底
    empty = StructTypes.construct(GetStatementListResponse, JSON3.read("""{}"""))
    @test isempty(empty.list)

    # 下载链接
    dl = StructTypes.construct(GetStatementResponse,
        JSON3.read("""{"url":"https://files.example.com/x"}"""))
    @test dl.url == "https://files.example.com/x"
end

@testset "Quote.filings JSON parsing" begin
    raw = """
    {"id":"f100","title":"年报","description":"2025 年报",
     "file_name":"annual_report.pdf",
     "file_urls":["https://files.example.com/r1.pdf","https://files.example.com/r2.pdf"],
     "publish_at":"1747257600"}
    """
    f = StructTypes.construct(FilingItem, JSON3.read(raw))
    @test f.id == "f100"
    @test f.title == "年报"
    @test length(f.file_urls) == 2
    @test f.published_at == unix2datetime(1747257600)

    # description 缺失（上游标了 #[serde(default)]）
    f2 = StructTypes.construct(FilingItem, JSON3.read("""
        {"id":"f2","title":"t","file_name":"x.pdf","file_urls":[],"publish_at":0}"""))
    @test f2.description == ""
    @test isempty(f2.file_urls)
end

@testset "UserQuoteProfile proto roundtrip" begin
    # 编码 UserQuoteProfileRequest（cmd 4 的请求体）
    req = UserQuoteProfileRequest("zh-CN")
    io = IOBuffer()
    enc = ProtoBuf.ProtoEncoder(io)
    ProtoBuf.encode(enc, req)
    bytes = take!(io)
    # field 1 (language), wire type 2 (LEN), tag = 0x0A
    @test bytes[1] == 0x0A
    @test length(bytes) == 1 + 1 + length("zh-CN")  # tag + len + payload

    # 解码一条合成响应：member_id=42, quote_level="LV2", 一个 package
    # field 1 = varint 42:               0x08 0x2A
    # field 2 = string "LV2":            0x12 0x03 0x4C 0x56 0x32
    # field 6 = embedded UserQuoteLevelDetail (tag=0x32):
    #   field 1 = map entry (tag=0x0A) containing:
    #       field 1 = key "k1":          0x0A 0x02 0x6B 0x31
    #       field 2 = PackageDetail (tag=0x12):
    #           field 1 = "k1":          0x0A 0x02 0x6B 0x31
    #           field 2 = "Name":        0x12 0x04 0x4E 0x61 0x6D 0x65
    #           field 4 = "Desc":        0x22 0x04 0x44 0x65 0x73 0x63
    #           field 5 = varint 1700000000
    #           field 6 = varint 1800000000

    pkg_body = UInt8[
        # key="k1"
        0x0A, 0x02, 0x6B, 0x31,
        # name="Name"
        0x12, 0x04, 0x4E, 0x61, 0x6D, 0x65,
        # description="Desc"
        0x22, 0x04, 0x44, 0x65, 0x73, 0x63,
        # start = 1700000000 (varint, field 5 tag=0x28)
        0x28, 0x80, 0xE2, 0xCF, 0xAA, 0x06,
        # end = 1800000000 (varint, field 6 tag=0x30)
        0x30, 0x80, 0xA4, 0xA7, 0xDA, 0x06,
    ]
    # 嵌入 map entry: field 1 key + field 2 value=pkg
    map_entry_body = vcat(
        UInt8[0x0A, 0x02, 0x6B, 0x31],                            # key="k1"
        UInt8[0x12, UInt8(length(pkg_body))], pkg_body,           # value=PackageDetail
    )
    quote_level_detail_body = vcat(
        UInt8[0x0A, UInt8(length(map_entry_body))], map_entry_body,
    )
    resp_bytes = vcat(
        UInt8[0x08, 0x2A],                                                          # member_id=42
        UInt8[0x12, 0x03, 0x4C, 0x56, 0x32],                                        # quote_level="LV2"
        UInt8[0x18, 0x7B],                                                          # subscribe_limit=123
        UInt8[0x20, 0xC8, 0x03],                                                    # history_candlestick_limit=456
        UInt8[0x32, UInt8(length(quote_level_detail_body))], quote_level_detail_body, # field 6
    )

    dec = ProtoBuf.ProtoDecoder(IOBuffer(resp_bytes))
    resp = ProtoBuf.decode(dec, UserQuoteProfileResponse)
    @test resp.member_id == 42
    @test resp.quote_level == "LV2"
    @test resp.subscribe_limit == 123
    @test resp.history_candlestick_limit == 456
    @test length(resp.quote_package_details) == 1
    pkg = resp.quote_package_details[1]
    @test pkg.key == "k1"
    @test pkg.name == "Name"
    @test pkg.description == "Desc"
    @test pkg.start_at == unix2datetime(1700000000)
    @test pkg.end_at == unix2datetime(1800000000)

    legacy = UserQuoteProfileResponse(42, "LV2", QuotePackageDetail[])
    @test legacy.subscribe_limit == 0
    @test legacy.history_candlestick_limit == 0
end

@testset "Candlestick UTC timestamps" begin
    timestamp = Int64(1781724600)
    candle = LongBridge.QuoteProtocol.Candlestick(
        381.3299,
        381.59,
        380.35,
        382.165,
        12_204,
        4_653_648.315,
        timestamp,
        TradeSession.Intraday,
    )
    response = LongBridge.QuoteProtocol.SecurityCandlestickResponse("COHR.US", [candle])

    default_df = LongBridge.Quote._candlestick_dataframe(response)
    @test default_df.timestamp == [DateTime(2026, 6, 17, 19, 30)]
    @test !hasproperty(default_df, :timestamp_unix)

    raw_df = LongBridge.Quote._candlestick_dataframe(
        response;
        include_timestamp_unix = true,
    )
    @test raw_df.timestamp_unix == [timestamp]
    @test utc_iso8601(raw_df.timestamp[1]) == "2026-06-17T19:30:00Z"
    @test utc_iso8601(timestamp) == "2026-06-17T19:30:00Z"
end

@testset "realtime_quote / quote_snapshot signatures" begin
    # quote_snapshot: Vector{String} only (server call)
    @test length(methods(quote_snapshot)) >= 1
    @test hasmethod(quote_snapshot, (QuoteContext, Vector{String}))

    # realtime_quote now cache-backed: single symbol and vector overloads
    @test hasmethod(realtime_quote, (QuoteContext, String))
    @test hasmethod(realtime_quote, (QuoteContext, Vector{String}))
end

@testset "Public exports v0.7.0" begin
    for s in (
        # Asset
        :AssetContext, :statements, :statement_download_url,
        :StatementType, :StatementItem,
        :GetStatementListResponse, :GetStatementResponse,
        # Quote additions
        :quote_snapshot, :filings, :FilingItem,
        :subscribe_limit, :history_candlestick_limit,
        :quote_package_details, :QuotePackageDetail,
        :utc_iso8601, :to_market_time,
    )
        @test isdefined(LongBridge, s)
    end

    @test hasmethod(subscribe_limit, Tuple{QuoteContext})
    @test hasmethod(history_candlestick_limit, Tuple{QuoteContext})
end
