using Test, Dates, JSON3

@testset "v0.9.0 data-center routing" begin
    ap = Settings("ap_key", "ap_secret", "ap_token", DateTime(2099, 1, 1))
    us = Settings("us_key", "ap_secret", "ap_token", DateTime(2099, 1, 1))
    @test dc_region(ap) === :ap
    @test dc_region(us) === :us
    @test LongBridge.Client._regional_http_url(us, :us) ==
          LongBridge.Constant.DEFAULT_HTTP_URL
    @test LongBridge.Client._regional_ws_url(
        LongBridge.Constant.DEFAULT_QUOTE_WS_CN,
        :us,
    ) == LongBridge.Constant.DEFAULT_QUOTE_WS

    enable_papertrading!(us)
    headers = Dict(LongBridge.Client._routing_headers(us, :us))
    @test headers["x-dc-region"] == "us"
    @test headers["x-papertrading"] == "true"
    @test_throws LongBridgeError LongBridge.Client._check_dc_region(
        "/v1/us/test",
        :ap,
        :us,
    )
end

@testset "v0.9.0 symbol and enum wire values" begin
    @test LongBridge.Utils.symbol_to_counter_id("BTCUSD.BKKT") == "VA/BKKT/BTCUSD"
    @test LongBridge.Utils.counter_id_to_symbol("VA/BKKT/BTCUSD") == "BTCUSD.BKKT"
    @test JSON3.read("\"Gtc\"", OrderTag.T) === OrderTag.LongTerm
    @test JSON3.read("\"GTC\"", OrderTag.T) === OrderTag.LongTerm
    @test JSON3.read("\"OPTION_PRE_MARKET\"", OutsideRTH.T) ===
          OutsideRTH.OptionPreMarket
    @test !isdefined(OrderTag, :MarginCall)
end

@testset "v0.9.0 trade request options" begin
    options = SubmitOrderOptions(
        symbol = "AAPL.US",
        order_type = OrderType.LO,
        side = OrderSide.Buy,
        submitted_quantity = 1,
        time_in_force = TimeInForceType.Day,
        outside_rth = OutsideRTH.OptionPreMarket,
        client_request_id = "req-123",
    )
    body = LongBridge.Trade.to_dict(options)
    @test body["outside_rth"] == "OPTION_PRE_MARKET"
    @test body["client_request_id"] == "req-123"

    us_options = GetUSHistoryOrders(
        symbol = "AAPL.US",
        side = OrderSide.Buy,
        start_at = 100,
        end_at = 200,
        query_type = 2,
        page = 3,
        limit = 50,
    )
    query = LongBridge.Trade._us_query_orders_body(us_options, Int64(300))
    @test query["action"] == 1
    @test query["counter_ids"] == ["ST/US/AAPL"]
    @test query["start_at"] == 100.0
    @test query["query_version"] == 300.0
end

@testset "v0.9.0 US response models" begin
    company = LongBridge.USProtocol.construct_us(
        USCompanyOverview,
        JSON3.read("""
        {"intro":"Apple", "market_cap":"1", "top_rank_tags":[{"key":"cap","location":1}]}
        """),
    )
    @test company.intro == "Apple"
    @test company.top_rank_tags[1].key == "cap"

    crypto = LongBridge.USProtocol.construct_us(
        USCryptoOverview,
        JSON3.read("""{"counter_id":"VA/BKKT/BTCUSD","ticker":"BTC"}"""),
    )
    LongBridge.USProtocol.normalize_symbols!(crypto)
    @test crypto.symbol == "BTCUSD.BKKT"

    assets = LongBridge.USProtocol.construct_us(
        USAssetOverview,
        JSON3.read("""
        {"asset_timestamp":"1700000000","stock_list":[{"symbol":"AAPL","counter_id":"ST/US/AAPL"}],"crypto_list":[{"counter_id":"VA/BKKT/BTCUSD"}]}
        """),
    )
    LongBridge.USProtocol.normalize_symbols!(assets)
    @test assets.asset_timestamp == unix2datetime(1700000000)
    @test assets.stock_list[1].full_symbol == "AAPL.US"
    @test assets.crypto_list[1].symbol == "BTCUSD.BKKT"

    detail = LongBridge.USProtocol.construct_us(
        USOrderDetailResponse,
        JSON3.read("""
        {"order":{"id":"1","counter_id":"ST/US/NKE","underlying_counter_id":"ST/US/NKE","order_histories":[{"status":"Filled"}]},"current_millisecond":"1"}
        """),
    )
    LongBridge.USProtocol.normalize_symbols!(detail)
    @test detail.order.symbol == "NKE.US"
    @test detail.order.order_histories[1].status == "Filled"

    realized = LongBridge.USProtocol.construct_us(
        USRealizedPL,
        JSON3.read("""{"realized_pl_list":[{"category":1,"currency":"USD","metrics":[{"amount":"12.3","period":2}]}]}"""),
    )
    @test realized.realized_pl_list[1].metrics[1].amount == "12.3"
end

@testset "v0.9.0 method signatures and exports" begin
    @test hasmethod(us_company_overview, Tuple{FundamentalContext,String})
    @test hasmethod(us_valuation_overview, Tuple{FundamentalContext,String})
    @test hasmethod(us_financial_overview, Tuple{FundamentalContext,String,String})
    @test hasmethod(
        us_financial_statement,
        Tuple{FundamentalContext,String,String,String},
    )
    @test hasmethod(us_key_financial_metrics, Tuple{FundamentalContext,String,String})
    @test hasmethod(us_analyst_consensus, Tuple{FundamentalContext,String,String})
    @test hasmethod(us_etf_dividend_info, Tuple{FundamentalContext,String})
    @test hasmethod(us_company_dividends, Tuple{FundamentalContext,String})
    @test hasmethod(us_etf_files, Tuple{FundamentalContext,String})
    @test hasmethod(us_crypto_overview, Tuple{QuoteContext,String})
    @test hasmethod(us_query_orders, Tuple{TradeContext,GetUSHistoryOrders})
    @test hasmethod(us_order_detail, Tuple{TradeContext,String})
    @test hasmethod(us_asset_overview, Tuple{TradeContext})
    @test hasmethod(us_realized_pl, Tuple{TradeContext,String})
    @test hasmethod(all_executions, Tuple{TradeContext,GetAllExecutionsOptions})

    for name in (
        :USCompanyOverview,
        :USCryptoOverview,
        :USAssetOverview,
        :GetUSHistoryOrders,
        :GetAllExecutionsOptions,
        :OutsideRTH,
    )
        @test name in names(LongBridge)
    end
end
