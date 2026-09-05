using Test
using LongBridge
using LongBridge.TradeProtocol:
    Execution,
    ExecutionResponse,
    FundPositionsResponse,
    Order,
    OrderDetail,
    OrderSide,
    OrderStatus,
    OrderTag,
    OrderType,
    OutsideRTH,
    PushOrderChanged,
    StockPositionsResponse,
    SubmitOrderResponse,
    TimeInForceType,
    TriggerStatus
using LongBridge.Trade: _parse_order_data
using LongBridge.Utils: construct, json_to_mutable, to_china_time, to_namedtuple
using JSON, Dates

# =========================================================================
# JSON3.jl -> JSON.jl 1.0 迁移：锁定解析行为
#
# 覆盖三条路径：
#   1. 手写构造器 `Utils.construct`（原 StructTypes.CustomStruct + StructTypes.construct）
#   2. 类型化解析 `JSON.parse(json, T)`（原 StructTypes.Struct + JSON3.read）
#   3. 未类型化解析 `JSON.parse(json)` 及其辅助函数
# =========================================================================

@testset "JSON.jl untyped parsing contract" begin
    @test VersionNumber(LongBridge.VERSION) >= v"0.9.5"
    obj = JSON.parse("""{"a":1,"b":{"c":[1,2]},"d":null,"e":"x"}""")

    # `Errors.ApiResponse` 与所有 construct 方法都依赖以下访问方式
    @test obj isa JSON.Object{String,Any}
    @test obj isa LongBridge.Utils.JSONObject
    @test obj["a"] == 1
    @test obj[:a] == 1              # Symbol 键（JSON3 时期的写法）依然可用
    @test obj.b.c == [1, 2]
    @test obj.b.c isa Vector{Any}   # JSON3.Array 已变为 Vector{Any}
    @test haskey(obj, :d) && obj.d === nothing
    @test get(obj, :missing, "fallback") == "fallback"
    @test collect(keys(obj)) == ["a", "b", "d", "e"]   # 保持插入顺序
    @test propertynames(obj) == (:a, :b, :d, :e)

    @test to_namedtuple(obj) == (a = 1, b = (c = [1, 2],), d = nothing, e = "x")

    mutable = json_to_mutable(obj)
    @test mutable isa Dict{String,Any}
    @test mutable["b"] isa Dict{String,Any}
    @test mutable["b"]["c"] == [1, 2]
end

@testset "JSON.lift enum wire values" begin
    # LongBridge 用 "Gtc"/"GTC" 表示 OrderTag.LongTerm，需要自定义 lift
    @test JSON.parse("\"Gtc\"", OrderTag.T) === OrderTag.LongTerm
    @test JSON.parse("\"GTC\"", OrderTag.T) === OrderTag.LongTerm
    @test JSON.parse("\"Normal\"", OrderTag.T) === OrderTag.Normal
    @test JSON.parse("\"nonsense\"", OrderTag.T) === OrderTag.UnknownTag
    @test JSON.parse("\"OPTION_PRE_MARKET\"", OutsideRTH.T) === OutsideRTH.OptionPreMarket
    @test JSON.parse("\"RTH_ONLY\"", OutsideRTH.T) === OutsideRTH.RTH_ONLY
    @test JSON.parse("\"nonsense\"", OutsideRTH.T) === OutsideRTH.UnknownOutsideRth
    # 其余枚举按成员名匹配，由 StructUtils 默认 lift 处理
    @test JSON.parse("\"NotReported\"", OrderStatus.T) === OrderStatus.NotReported
    @test JSON.parse("\"ELO\"", OrderType.T) === OrderType.ELO
end

@testset "Typed parsing of trade responses" begin
    # today_orders / history_orders：Dict 的键顺序是随机的，
    # 因此这里同时验证乱序 JSON 对象也能填对字段。
    order_json = """
    {"currency":"HKD","executed_price":"0","executed_quantity":"0","expire_date":"",
     "last_done":"","limit_offset":"","msg":"","order_id":"706388312699592704",
     "order_type":"ELO","outside_rth":"UnknownOutsideRth","price":"11.9","quantity":"200",
     "side":"Buy","status":"NotReported","stock_name":"东亚银行","submitted_at":"1651644897",
     "symbol":"23.HK","tag":"Normal","time_in_force":"Day","trailing_amount":"",
     "trailing_percent":"","trigger_at":"0","trigger_price":"","trigger_status":"NOT_USED",
     "updated_at":"1651644897","remark":""}
    """
    prepared = _parse_order_data(JSON.parse(order_json))
    orders = JSON.parse(JSON.json([prepared]), Vector{Order})
    @test length(orders) == 1
    order = orders[1]
    @test order.order_id == "706388312699592704"
    @test order.status === OrderStatus.NotReported
    @test order.side === OrderSide.Buy
    @test order.order_type === OrderType.ELO
    @test order.tag === OrderTag.Normal
    @test order.time_in_force === TimeInForceType.Day
    @test order.trigger_status === TriggerStatus.NOT_USED
    @test order.outside_rth === OutsideRTH.UnknownOutsideRth
    @test order.quantity == 200
    @test order.price == 11.9
    @test order.submitted_at == to_china_time("1651644897")
    @test order.expire_date === nothing

    # GTD 单：Date 字段要能经 `JSON.json` -> `JSON.parse` 完整往返
    gtd_json = replace(
        order_json,
        "\"expire_date\":\"\"" => "\"expire_date\":\"2024-12-31\"",
        "\"time_in_force\":\"Day\"" => "\"time_in_force\":\"GTD\"",
        "\"tag\":\"Normal\"" => "\"tag\":\"GTC\"",
    )
    gtd = JSON.parse(
        JSON.json([_parse_order_data(JSON.parse(gtd_json))]),
        Vector{Order},
    )[1]
    @test gtd.expire_date == Date(2024, 12, 31)
    @test gtd.time_in_force === TimeInForceType.GTD
    @test gtd.tag === OrderTag.LongTerm

    executions = JSON.parse(
        """
        {"trades":[{"order_id":"1","trade_id":"t1","symbol":"700.HK",
                    "trade_done_at":"2022-05-04T09:34:57","quantity":100,"price":11.9}],
         "has_more":false}""",
        ExecutionResponse,
    )
    @test executions.has_more === false
    @test executions.trades[1] isa Execution
    @test executions.trades[1].trade_done_at == DateTime(2022, 5, 4, 9, 34, 57)

    detail = JSON.parse(
        """
        {"order_id":"1","status":"FilledStatus","stock_name":"NIKE","quantity":10,
         "executed_quantity":10,"price":100.5,"executed_price":100.5,
         "submitted_at":"2022-05-04T09:34:57","side":"Buy","symbol":"NKE.US",
         "order_type":"LO","last_done":100.5,"trigger_price":null,"msg":"","tag":"Normal",
         "time_in_force":"Day","expire_date":null,"updated_at":null,"trigger_at":null,
         "trailing_amount":null,"trailing_percent":null,"limit_offset":null,
         "trigger_status":"NOT_USED","currency":"USD","outside_rth":"RTH_ONLY","remark":"",
         "free_status":"None","free_amount":null,"free_currency":null,
         "deductions_status":"NONE","deductions_amount":null,"deductions_currency":null,
         "platform_deducted_status":"NONE","platform_deducted_amount":null,
         "platform_deducted_currency":null,
         "history":[{"price":100.5,"quantity":10,"status":"FilledStatus","msg":"",
                     "time":"2022-05-04T09:34:57"}],
         "charge_detail":{"total_charges":1.5,"currency":"USD",
                          "items":[{"code":"BROKER_FEES","name":"broker",
                                    "fees":[{"code":"f1","name":"fee","fee":1.5,
                                             "currency":"USD"}]}]}}""",
        OrderDetail,
    )
    @test detail.outside_rth === OutsideRTH.RTH_ONLY
    @test detail.expire_date === nothing
    @test detail.history[1].status === OrderStatus.FilledStatus
    @test detail.charge_detail.items[1].fees[1].fee == 1.5

    push_changed = JSON.parse(
        """
        {"side":"Buy","stock_name":"NIKE","submitted_quantity":10,"symbol":"NKE.US",
         "order_type":"LO","submitted_price":100.5,"executed_quantity":0,
         "executed_price":null,"order_id":"1","currency":"USD","status":"NewStatus",
         "submitted_at":null,"updated_at":null,"trigger_price":null,"msg":"","tag":"Gtc",
         "trigger_status":null,"trigger_at":null,"trailing_amount":null,
         "trailing_percent":null,"limit_offset":null,"account_no":"a","last_share":null,
         "last_price":null,"remark":""}""",
        PushOrderChanged,
    )
    @test push_changed.tag === OrderTag.LongTerm
    @test push_changed.trigger_status === nothing
    @test push_changed.submitted_at === nothing

    funds = JSON.parse(
        """
        {"list":[{"account_channel":"lb",
                  "fund_info":[{"symbol":"HK0000447943","symbol_name":"F","currency":"HKD",
                                "current_net_asset_value":"1.0",
                                "net_asset_value_day":"1651644897",
                                "cost_net_asset_value":"1.0","holding_units":"100"}]}]}""",
        FundPositionsResponse,
    )
    @test funds.list[1].fund_info[1].symbol == "HK0000447943"

    stocks = JSON.parse(
        """
        {"list":[{"account_channel":"lb",
                  "stock_info":[{"symbol":"700.HK","symbol_name":"腾讯","currency":"HKD",
                                 "quantity":100,"available_quantity":100,
                                 "cost_price":100.0,"market":"HK",
                                 "init_quantity":null}]}]}""",
        StockPositionsResponse,
    )
    @test stocks.list[1].stock_info[1].quantity == 100.0
    @test stocks.list[1].stock_info[1].init_quantity === nothing

    @test JSON.parse("""{"order_id":"9"}""", SubmitOrderResponse).order_id == "9"
end

@testset "construct dispatches on decoded JSON objects" begin
    # construct 只接受 JSON.parse 解出的 JSON.Object（与迁移前的 JSON3.Object 契约一致），
    # 因为构造器内部用的是 Symbol 键访问，而 Dict{String,Any} 不支持 Symbol 键。
    stats = construct(LongBridge.OptionVolumeStats, JSON.parse("""{"c":"100000","p":"50000"}"""))
    @test stats.c == "100000"
    @test stats.p == "50000"
    @test_throws MethodError construct(
        LongBridge.OptionVolumeStats,
        Dict{String,Any}("c" => "100000", "p" => "50000"),
    )

    # 所有 construct 方法都挂在 Utils.construct 上（不再依赖 StructTypes）
    @test !isdefined(LongBridge, :StructTypes)
    @test length(methods(construct)) > 100
end
