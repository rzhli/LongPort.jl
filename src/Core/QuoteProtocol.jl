# 基于官方 api.proto 的Julia实现  https://github.com/longportapp/openapi-protobufs/blob/main/quote/api.proto
# 专门用于行情 WebSocket 协议的 Protocol Buffer 消息

module QuoteProtocol

    using ProtoBuf
    using EnumX
    using ProtoBuf.Codecs: BufferedVector
    using Dates
    import ProtoBuf: ProtoDecoder, decode, encode, _encoded_size, skip, message_done, decode_tag, default_values, field_numbers
    import Base: show

    export QuoteCommand, SubType, TradeStatus, TradeSession, AdjustType, CandlePeriod, Direction, TradeDirection,       # 枚举类型Enums
           SecurityBoard, PushQuoteTag, CalcIndex, FilterWarrantExpiryDate, FilterWarrantInOutBoundsType,
           WarrantStatus, WarrantType, WarrantSortBy, SortOrderType,
           
           SecurityRequest, MultiSecurityRequest, PrePostQuote, SecurityQuote, SecurityQuoteResponse,         # 结构体类型Struct
           SecurityStaticInfo, SecurityStaticInfoResponse,
           
           HistoryCandlestickQueryType,                                                          # 枚举类型Enums

           Candlestick, SecurityCandlestickRequest, SecurityHistoryCandlestickRequest,
           SecurityCandlestickResponse,                              # 结构体类型Struct
           QuoteSubscribeRequest, QuoteSubscribeResponse, QuoteUnsubscribeRequest,                            # 结构体类型Struct
           QuoteUnsubscribeResponse, SubscriptionRequest, SubscriptionResponse, SubTypeList,

           Depth, Brokers, PushQuote, PushDepth, PushBrokers, PushTrade,                   # 结构体类型Struct
           OptionExtend, WarrantExtend, StrikePriceInfo, SecurityDepthResponse, SecurityBrokersResponse,
           SecurityTradeRequest, SecurityTradeResponse,
           OptionQuote, OptionQuoteResponse, WarrantQuote, WarrantQuoteResponse, 
           ParticipantInfo, ParticipantBrokerIdsResponse,
           SecurityIntradayRequest, SecurityIntradayResponse, Line,
           OptionChainDateListResponse, OptionChainDateStrikeInfoRequest, OptionChainDateStrikeInfoResponse,
           IssuerInfo, IssuerInfoResponse, WarrantFilterListRequest, FilterConfig,
           WarrantFilterListResponse, FilterWarrant,
           MarketTradePeriodResponse, MarketTradePeriod, TradePeriod,
           MarketTradeDayRequest, MarketTradeDayResponse,
           CapitalFlowLine, CapitalFlowIntradayRequest, CapitalFlowIntradayResponse,
           CapitalDistribution, CapitalDistributionResponse,
           SecurityCalcQuoteRequest, SecurityCalcQuoteResponse, SecurityCalcIndex, MarketTemperatureResponse,
           MarketTemperature, HistoryMarketTemperatureResponse, SecurityListCategory, SecuritiesUpdateMode
           
    # 行情协议指令定义 - 基于api.proto
    @enumx QuoteCommand begin
        UNKNOWN_COMMAND = 0
        HEART_BEAT = 1                  # 心跳
        AUTH = 2                        # 鉴权
        RECONNECT = 3                   # 重新连接

        QueryUserQuoteProfile = 4       # 查询用户行情信息
        Subscription = 5                # 查询连接的已订阅数据
        Subscribe = 6                   # 订阅行情数据
        Unsubscribe = 7                 # 取消订阅行情数据
        QueryMarketTradePeriod = 8      # 查询各市场的当日交易时段
        QueryMarketTradeDay = 9         # 查询交易日
        QuerySecurityStaticInfo = 10    # 查询标的基础信息
        QuerySecurityQuote = 11         # 查询标的行情(所有标的通用行情)
        QueryOptionQuote = 12           # 查询期权行情(仅支持期权)
        QueryWarrantQuote = 13          # 查询轮证行情(仅支持轮证)
        QueryDepth = 14                 # 查询盘口
        QueryBrokers = 15               # 查询经纪队列
        QueryParticipantBrokerIds = 16  # 查询券商经纪席位
        QueryTrade = 17                 # 查询成交明细
        QueryIntraday = 18              # 查询当日分时
        QueryCandlestick = 19           # 查询k线
        QueryOptionChainDate = 20       # 查询标的期权链日期列表
        QueryOptionChainDateStrikeInfo = 21 # 查询标的期权链某日的行权价信息
        QueryWarrantIssuerInfo = 22     # 查询轮证发行商对应Id
        QueryWarrantFilterList = 23     # 查询轮证筛选列表
        QueryCapitalFlowIntraday = 24   # 查询标的的资金流分时
        QueryCapitalFlowDistribution = 25 # 查询标的资金流大小单
        QuerySecurityCalcIndex = 26     # 查询标的指标数据
        QueryHistoryCandlestick = 27    # 查询标的历史 k 线

        PushQuoteData = 101             # 推送行情
        PushDepthData = 102             # 推送盘口
        PushBrokersData = 103           # 推送经纪队列
        PushTradeData = 104             # 推送成交明细
    end

    # 行情订阅类型
    @enumx SubType begin
        UNKNOWN_TYPE = 0
        QUOTE = 1
        DEPTH = 2
        BROKERS = 3
        TRADE = 4
    end

    # 交易状态
    @enumx TradeStatus begin
        Normal = 0
        Halted = 1          # 停牌
        Delisted = 2
        Fuse = 3
        PrepareList = 4
        CodeMoved = 5
        ToBeOpened = 6
        SplitStockHalts = 7
        Expired = 8
        WarrantPrepareList = 9
        SuspendTrade = 10
    end

    # 交易时段
    @enumx TradeSession begin
        Intraday = 0               # 盘中、日内
        PreTrade = 1               # 盘前
        PostTrade = 2              # 盘后
        OvernightTrade = 3         # 夜盘
        All = 4
    end

    # 复权类型
    @enumx AdjustType begin
        NO_ADJUST = 0
        FORWARD_ADJUST = 1
    end

    # K线周期
    @enumx CandlePeriod begin
        UNKNOWN_PERIOD = 0
        ONE_MINUTE = 1
        TWO_MINUTE = 2
        THREE_MINUTE = 3
        FIVE_MINUTE = 5
        TEN_MINUTE = 10
        FIFTEEN_MINUTE = 15
        TWENTY_MINUTE = 20
        THIRTY_MINUTE = 30
        FORTY_FIVE_MINUTE = 45
        SIXTY_MINUTE = 60
        TWO_HOUR = 120
        THREE_HOUR = 180
        FOUR_HOUR = 240
        DAY = 1000
        WEEK = 2000
        MONTH = 3000
        QUARTER = 3500
        YEAR = 4000
    end

    # 交易方向
    @enumx TradeDirection begin
        Neutral = 0
        Down = 1
        Up = 2
    end

    # 推送行情标签
    @enumx PushQuoteTag begin
        Normal = 0              # 实时行情
        Eod = 1                 # 日终数据
    end

    # 计算指标
    @enumx CalcIndex begin
        CALCINDEX_UNKNOWN = 0
        CALCINDEX_LAST_DONE = 1
        CALCINDEX_CHANGE_VAL = 2
        CALCINDEX_CHANGE_RATE = 3
        CALCINDEX_VOLUME = 4
        CALCINDEX_TURNOVER = 5
        CALCINDEX_YTD_CHANGE_RATE = 6
        CALCINDEX_TURNOVER_RATE = 7
        CALCINDEX_TOTAL_MARKET_VALUE = 8
        CALCINDEX_CAPITAL_FLOW = 9
        CALCINDEX_AMPLITUDE = 10
        CALCINDEX_VOLUME_RATIO = 11
        CALCINDEX_PE_TTM_RATIO = 12
        CALCINDEX_PB_RATIO = 13
        CALCINDEX_DIVIDEND_RATIO_TTM = 14
        CALCINDEX_FIVE_DAY_CHANGE_RATE = 15
        CALCINDEX_TEN_DAY_CHANGE_RATE = 16
        CALCINDEX_HALF_YEAR_CHANGE_RATE = 17
        CALCINDEX_FIVE_MINUTES_CHANGE_RATE = 18
        CALCINDEX_EXPIRY_DATE = 19
        CALCINDEX_STRIKE_PRICE = 20
        CALCINDEX_UPPER_STRIKE_PRICE = 21
        CALCINDEX_LOWER_STRIKE_PRICE = 22
        CALCINDEX_OUTSTANDING_QTY = 23
        CALCINDEX_OUTSTANDING_RATIO = 24
        CALCINDEX_PREMIUM = 25
        CALCINDEX_ITM_OTM = 26
        CALCINDEX_IMPLIED_VOLATILITY = 27
        CALCINDEX_WARRANT_DELTA = 28
        CALCINDEX_CALL_PRICE = 29
        CALCINDEX_TO_CALL_PRICE = 30
        CALCINDEX_EFFECTIVE_LEVERAGE = 31
        CALCINDEX_LEVERAGE_RATIO = 32
        CALCINDEX_CONVERSION_RATIO = 33
        CALCINDEX_BALANCE_POINT = 34
        CALCINDEX_OPEN_INTEREST = 35
        CALCINDEX_DELTA = 36
        CALCINDEX_GAMMA = 37
        CALCINDEX_THETA = 38
        CALCINDEX_VEGA = 39
        CALCINDEX_RHO = 40
    end

    # 证券板块
    @enumx SecurityBoard begin
        UnknownBoard     = 0
        USMain           = 1  # 美股主板
        USPink           = 2  # 粉单市场
        USDJI            = 3  # 道琼斯指数
        USNSDQ           = 4  # 纳斯达克指数
        USSector         = 5  # 美股行业概念
        USOption         = 6  # 美股期权
        USOptionS        = 7  # 美股特殊期权（收盘时间为 16:15）
        HKEquity         = 8  # 港股股本证券
        HKPreIPO         = 9  # 港股暗盘
        HKWarrant        = 10 # 港股轮证
        HKCBBC           = 11 # 港股牛熊证
        HKSector         = 12 # 港股行业概念
        SHMainConnect    = 13 # 上证主板 - 互联互通
        SHMainNonConnect = 14 # 上证主板 - 非互联互通
        SHSTAR           = 15 # 科创板
        CNIX             = 16 # 沪深指数
        CNSector         = 17 # 沪深行业概念
        SZMainConnect    = 18 # 深证主板 - 互联互通
        SZMainNonConnect = 19 # 深证主板 - 非互联互通
        SZGEMConnect     = 20 # 创业板 - 互联互通
        SZGEMNonConnect  = 21 # 创业板 - 非互联互通
        SGMain           = 22 # 新加坡主板
        STI              = 23 # 新加坡海峡指数
        SGSector         = 24 # 新加坡行业概念
    end

    @enumx FilterWarrantExpiryDate begin
        LT_3 = 1
        Between_3_6 = 2
        Between_6_12 = 3
        GT_12 = 4
    end

    @enumx FilterWarrantInOutBoundsType begin
        In = 1
        Out = 2
    end

    @enumx WarrantStatus begin
        Suspend = 2
        PrepareList = 3
        Normal = 4
    end

    """
    Warrant type
    """
    @enumx WarrantType begin
        UnknownWarrantType = 0
        Call = 1
        Put = 2
        Bull = 3
        Bear = 4
        Inline = 5
    end

    """
    Sort order type
    """
    @enumx SortOrderType begin
        Ascending = 0
        Descending = 1
    end

    """
    Warrant sort by field
    """
    @enumx WarrantSortBy begin
        LastDone = 0
        ChangeRate = 1
        ChangeValue = 2
        Volume = 3
        Turnover = 4
        ExpiryDate = 5
        StrikePrice = 6
        UpperStrikePrice = 7
        LowerStrikePrice = 8
        OutstandingQuantity = 9
        OutstandingRatio = 10
        Premium = 11
        ItmOtm = 12
        ImpliedVolatility = 13
        Delta = 14
        CallPrice = 15
        ToCallPrice = 16
        EffectiveLeverage = 17
        LeverageRatio = 18
        ConversionRatio = 19
        BalancePoint = 20
        Status = 21
    end

    """
    交易类型
    """
    @enumx TradeType begin
        # Common
        Automatch = 0                   # 自动对盘
        # HK
        OutsideMarket = 1            # 场外交易
        OddLot = 2                   # 碎股交易
        NonAutomatch = 3             # 非自动对盘
        PreMarket = 4                # 开市前成交盘
        Auction = 5                  # 竞价交易
        SameBrokerNonAutomatch = 6   # 同一券商非自动对盘
        SameBrokerAutomatch = 7      # 同一券商自动对盘
        # US
        Acquisition = 8              # 收购
        BatchTrade = 9               # 批量交易
        Distribution = 10            # 分配
        IntermarketSweep = 11        # 跨市扫盘单
        BatchSell = 12               # 批量卖出
        OffPriceTrade = 13           # 离价交易
        USOddLot = 14                  # 碎股交易
        Rule155Trade = 15            # 第 155 条交易（纽交所规则）
        ExchangeClosingPrice = 16    # 交易所收盘价
        PriorReferencePrice = 17     # 前参考价
        ExchangeOpeningPrice = 18    # 交易所开盘价
        SplitTrade = 19              # 拆单交易
        AffiliateTrade = 20          # 附属交易
        AveragePriceTrade = 21       # 平均价成交
        CrossMarketTrade = 22        # 跨市场交易
        StoppedStock = 23            # 停售股票（常规交易）
        UnknownTradeType = 24
    end

    function trade_type_from_string(s::String, symbol::String)
        market = uppercase(last(split(symbol, '.')))
        if market == "HK"
            return if s == ""
                TradeType.Automatch             # 自动对盘
            elseif s == "*"
                TradeType.OutsideMarket      # 场外交易
            elseif s == "D"
                TradeType.OddLot             # 碎股交易
            elseif s == "M"
                TradeType.NonAutomatch       # 非自动对盘
            elseif s == "P"
                TradeType.PreMarket          # 开市前成交盘
            elseif s == "U"
                TradeType.Auction            # 竞价交易
            elseif s == "X"
                TradeType.SameBrokerNonAutomatch # 同一券商非自动对盘
            elseif s == "Y"
                TradeType.SameBrokerAutomatch    # 同一券商自动对盘
            else
                TradeType.UnknownTradeType
            end
        elseif market == "US"
            return if s == ""
                TradeType.Automatch                 # 自动对盘
            elseif s == "A"
                TradeType.Acquisition            # 收购
            elseif s == "B"
                TradeType.BatchTrade             # 批量交易
            elseif s == "D"
                TradeType.Distribution           # 分配
            elseif s == "F"
                TradeType.IntermarketSweep       # 跨市扫盘单
            elseif s == "G"
                TradeType.BatchSell              # 批量卖出
            elseif s == "H"
                TradeType.OffPriceTrade          # 离价交易
            elseif s == "I"
                TradeType.USOddLot                 # 碎股交易
            elseif s == "K"
                TradeType.Rule155Trade           # 第 155 条交易（纽交所规则）
            elseif s == "M"
                TradeType.ExchangeClosingPrice   # 交易所收盘价
            elseif s == "P"
                TradeType.PriorReferencePrice    # 前参考价
            elseif s == "Q"
                TradeType.ExchangeOpeningPrice   # 交易所开盘价
            elseif s == "S"
                TradeType.SplitTrade             # 拆单交易
            elseif s == "V"
                TradeType.AffiliateTrade         # 附属交易
            elseif s == "W"
                TradeType.AveragePriceTrade      # 平均价成交
            elseif s == "X"
                TradeType.CrossMarketTrade       # 跨市场交易
            elseif s == "1"
                TradeType.StoppedStock           # 停售股票（常规交易）
            else
                TradeType.UnknownTradeType
            end
        else
            return TradeType.UnknownTradeType
        end
    end

    # 市场下分类，目前只支持 Overnight
    @enumx SecurityListCategory begin
        Overnight = 0
    end
    function Base.string(c::SecurityListCategory.T)
        c == SecurityListCategory.Overnight && return "Overnight"
        throw(ArgumentError("Invalid SecurityListCategory value"))
    end

    # 历史温度数据颗粒度（暂时没用到）
    @enumx Granularity begin
        Day = 0
        Week = 1
        Month = 2
    end
    function Base.string(g::Granularity.T)
        g == Granularity.Day && return "day"
        g == Granularity.Week && return "week"
        g == Granularity.Month && return "month"
        throw(ArgumentError("Invalid Granularity value"))
    end

    # 自选股更新操作方法
    @enumx SecuritiesUpdateMode begin
        Add = 0
        Remove = 1
        Replace = 2
    end
    function Base.string(s::SecuritiesUpdateMode.T)
        s == SecuritiesUpdateMode.Add && return "add"
        s == SecuritiesUpdateMode.Remove && return "remove"
        s == SecuritiesUpdateMode.Replace && return "replace"
        throw(ArgumentError("Invalid SecuritiesUpdateMode value"))
    end

    # 基础请求结构
    struct SecurityRequest
        symbol::String
    end
    default_values(::Type{SecurityRequest}) = (;symbol = "")
    field_numbers(::Type{SecurityRequest}) = (;symbol = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityRequest})
        symbol = ""
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            else
                skip(d, wire_type)
            end
        end
        return SecurityRequest(symbol)
    end
    function encode(e::ProtoBuf.AbstractProtoEncoder, x::SecurityRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        return position(e.io) - initpos
    end
    function _encoded_size(x::SecurityRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        return encoded_size
    end

    # 多标的请求结构
    struct MultiSecurityRequest
        symbol::Vector{String}
    end
    default_values(::Type{MultiSecurityRequest}) = (;symbol = String[])
    field_numbers(::Type{MultiSecurityRequest}) = (;symbol = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:MultiSecurityRequest})
        symbol = String[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                decode!(d, wire_type, symbol)
            else
                skip(d, wire_type)
            end
        end
        return MultiSecurityRequest(symbol)
    end
    function encode(e::ProtoBuf.AbstractProtoEncoder, x::MultiSecurityRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        return position(e.io) - initpos
    end
    function _encoded_size(x::MultiSecurityRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        return encoded_size
    end

    struct SecurityStaticInfo
        symbol::String
        name_cn::String
        name_en::String
        name_hk::String
        listing_date::String
        exchange::String
        currency::String
        lot_size::Int64
        total_shares::Int64
        circulating_shares::Int64
        hk_shares::Int64
        eps::Float64
        eps_ttm::Float64
        bps::Float64
        dividend_yield::Float64
        stock_derivatives::Vector{Int64}
        board::String
    end
    default_values(::Type{SecurityStaticInfo}) = (;symbol = "", name_cn = "", name_en = "", name_hk = "", listing_date = "", exchange = "", currency = "", lot_size = zero(Int64), total_shares = zero(Int64), circulating_shares = zero(Int64), hk_shares = zero(Int64), eps = 0.0, eps_ttm = 0.0, bps = 0.0, dividend_yield = 0.0, stock_derivatives = Int64[], board = "")
    field_numbers(::Type{SecurityStaticInfo}) = (;symbol = 1, name_cn = 2, name_en = 3, name_hk = 4, listing_date = 5, exchange = 6, currency = 7, lot_size = 8, total_shares = 9, circulating_shares = 10, hk_shares = 11, eps = 12, eps_ttm = 13, bps = 14, dividend_yield = 15, stock_derivatives = 16, board = 17)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityStaticInfo})
        symbol = ""
        name_cn = ""
        name_en = ""
        name_hk = ""
        listing_date = ""
        exchange = ""
        currency = ""
        lot_size = zero(Int64)
        total_shares = zero(Int64)
        circulating_shares = zero(Int64)
        hk_shares = zero(Int64)
        eps = 0.0
        eps_ttm = 0.0
        bps = 0.0
        dividend_yield = 0.0
        stock_derivatives = BufferedVector{Int64}()
        board = ""
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                name_cn = decode(d, String)
            elseif field_number == 3
                name_en = decode(d, String)
            elseif field_number == 4
                name_hk = decode(d, String)
            elseif field_number == 5
                listing_date = decode(d, String)
            elseif field_number == 6
                exchange = decode(d, String)
            elseif field_number == 7
                currency = decode(d, String)
            elseif field_number == 8
                lot_size = decode(d, Int64)
            elseif field_number == 9
                total_shares = decode(d, Int64)
            elseif field_number == 10
                circulating_shares = decode(d, Int64)
            elseif field_number == 11
                hk_shares = decode(d, Int64)
            elseif field_number == 12
                eps = parse(Float64, decode(d, String))
            elseif field_number == 13
                eps_ttm = parse(Float64, decode(d, String))
            elseif field_number == 14
                bps = parse(Float64, decode(d, String))
            elseif field_number == 15
                dividend_yield = parse(Float64, decode(d, String))
            elseif field_number == 16
                decode!(d, wire_type, stock_derivatives)
            elseif field_number == 17
                board = decode(d, String)
            else
                skip(d, wire_type)
            end
        end
        return SecurityStaticInfo(
            symbol, name_cn, name_en, name_hk, listing_date, exchange, currency, lot_size, 
            total_shares, circulating_shares, hk_shares, eps, eps_ttm, bps, dividend_yield, 
            getindex(stock_derivatives), board
        )
    end

    # 证券静态信息响应
    struct SecurityStaticInfoResponse
        secu_static_info::Vector{SecurityStaticInfo}
    end
    SecurityStaticInfoResponse() = SecurityStaticInfoResponse(SecurityStaticInfo[])
    default_values(::Type{SecurityStaticInfoResponse}) = (;secu_static_info = SecurityStaticInfo[])
    field_numbers(::Type{SecurityStaticInfoResponse}) = (;secu_static_info = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityStaticInfoResponse})
        secu_static_info = SecurityStaticInfo[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(secu_static_info, decode(sub_d, SecurityStaticInfo))
            else
                skip(d, wire_type)
            end
        end
        return SecurityStaticInfoResponse(secu_static_info)
    end
  
    struct PrePostQuote
        last_done::Float64       # 最新成交价
        timestamp::Int64
        volume::Int64
        turnover::Float64        # 成交额，当前报价时累计的成交金额
        high::Float64
        low::Float64
        prev_close::Float64
    end
    function show(io::IO, q::PrePostQuote)
        print(io, "{ last: $(q.last_done), high: $(q.high), low: $(q.low), volume: $(q.volume), turnover: $(q.turnover) }")
    end
    default_values(::Type{PrePostQuote}) = (
        last_done = 0.0,
        timestamp = zero(Int64),
        volume = zero(Int64),
        turnover = 0.0,
        high = 0.0,
        low = 0.0,
        prev_close = 0.0
    )
    field_numbers(::Type{PrePostQuote}) = (
        last_done = 1,
        timestamp = 2,
        volume = 3,
        turnover = 4,
        high = 5,
        low = 6,
        prev_close = 7
    )

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:PrePostQuote})
        last_done = 0.0
        timestamp = zero(Int64)
        volume = zero(Int64)
        turnover = 0.0
        high = 0.0
        low = 0.0
        prev_close = 0.0

        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                last_done = parse(Float64, decode(d, String))
            elseif field_number == 2
                timestamp = decode(d, Int64)
            elseif field_number == 3
                volume = decode(d, Int64)
            elseif field_number == 4
                turnover = parse(Float64, decode(d, String))
            elseif field_number == 5
                high = parse(Float64, decode(d, String))
            elseif field_number == 6
                low = parse(Float64, decode(d, String))
            elseif field_number == 7
                prev_close = parse(Float64, decode(d, String))
            else
                skip(d, wire_type)
            end
        end

        return PrePostQuote(last_done, timestamp, volume, turnover, high, low, prev_close)
    end
  
    # 证券行情数据
    struct SecurityQuote
        symbol::String
        last_done::Float64
        prev_close::Float64
        open::Float64
        high::Float64
        low::Float64
        timestamp::Int64
        volume::Int64
        turnover::Float64
        trade_status::TradeStatus.T
        pre_market_quote::Union{PrePostQuote, Nothing}
        post_market_quote::Union{PrePostQuote, Nothing}
        over_night_quote::Union{PrePostQuote, Nothing}
    end
    default_values(::Type{SecurityQuote}) = (
        symbol = "",
        last_done = 0.0,
        prev_close = 0.0,
        open = 0.0,
        high = 0.0,
        low = 0.0,
        timestamp = zero(Int64),
        volume = 0,
        turnover = 0.0,
        trade_status = TradeStatus.Normal,
        pre_market_quote = nothing,
        post_market_quote = nothing,
        over_night_quote = nothing
    )
    field_numbers(::Type{SecurityQuote}) = (
        symbol = 1,
        last_done = 2,
        prev_close = 3,
        open = 4,
        high = 5,
        low = 6,
        timestamp = 7,
        volume = 8,
        turnover = 9,
        trade_status = 10,
        pre_market_quote = 11,
        post_market_quote = 12,
        over_night_quote = 13
    )

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityQuote})
        symbol = ""
        last_done = 0.0
        prev_close = 0.0
        open = 0.0
        high = 0.0
        low = 0.0
        timestamp = zero(Int64)
        volume = 0
        turnover = 0.0
        trade_status = TradeStatus.Normal
        pre_market_quote = nothing
        post_market_quote = nothing
        over_night_quote = nothing

        try
            while !message_done(d)
                field_number, wire_type = decode_tag(d)
                if field_number == 1
                    symbol = decode(d, String)
                elseif field_number == 2
                    last_done = parse(Float64, decode(d, String))
                elseif field_number == 3
                    prev_close = parse(Float64, decode(d, String))
                elseif field_number == 4
                    open = parse(Float64, decode(d, String))
                elseif field_number == 5
                    high = parse(Float64, decode(d, String))
                elseif field_number == 6
                    low = parse(Float64, decode(d, String))
                elseif field_number == 7
                    timestamp = decode(d, Int64)
                elseif field_number == 8
                    volume = decode(d, Int64)
                elseif field_number == 9
                    turnover = parse(Float64, decode(d, String))
                elseif field_number == 10
                    trade_status = decode(d, TradeStatus.T)
                elseif field_number == 11
                    len = decode(d, UInt64)
                    sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                    pre_market_quote = decode(sub_d, PrePostQuote)
                elseif field_number == 12
                    len = decode(d, UInt64)
                    sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                    post_market_quote = decode(sub_d, PrePostQuote)
                elseif field_number == 13
                    len = decode(d, UInt64)
                    sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                    over_night_quote = decode(sub_d, PrePostQuote)
                else
                    skip(d, wire_type)
                end
            end
        catch e
            @error "SecurityQuote decode error" exception=e position=position(d.io)
            rethrow(e)
        end

        return SecurityQuote(
            symbol, last_done, prev_close, open, high, low,
            timestamp, volume, turnover, trade_status,
            pre_market_quote, post_market_quote, over_night_quote
        )
    end

    # 证券行情响应
    struct SecurityQuoteResponse
        secu_quote::Vector{SecurityQuote}
    end
    SecurityQuoteResponse() = SecurityQuoteResponse(SecurityQuote[])
    default_values(::Type{SecurityQuoteResponse}) = (;secu_quote = SecurityQuote[])
    field_numbers(::Type{SecurityQuoteResponse}) = (;secu_quote = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityQuoteResponse})
        secu_quote = SecurityQuote[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(secu_quote, decode(sub_d, SecurityQuote))
            else
                skip(d, wire_type)
            end
        end
        return SecurityQuoteResponse(secu_quote)
    end

    # 历史K线查询类型
    @enumx HistoryCandlestickQueryType begin
        UNKNOWN_QUERY_TYPE = 0
        QUERY_BY_OFFSET = 1
        QUERY_BY_DATE = 2
    end

    # 查询方向
    @enumx Direction begin
        BACKWARD = 0  # 老数据，从最新的数据往历史数据翻页
        FORWARD = 1   # 新数据，从当前数据往最新数据翻页
    end

    # K线数据
    struct Candlestick
        close::Float64
        open::Float64
        low::Float64
        high::Float64
        volume::Int64
        turnover::Float64
        timestamp::Int64
        trade_session::TradeSession.T
    end
    default_values(::Type{Candlestick}) = (;close = 0.0, open = 0.0, low = 0.0, high = 0.0, volume = zero(Int64), turnover = 0.0, timestamp = zero(Int64), trade_session = TradeSession.Intraday)
    field_numbers(::Type{Candlestick}) = (;close = 1, open = 2, low = 3, high = 4, volume = 5, turnover = 6, timestamp = 7, trade_session = 8)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:Candlestick})
        close = 0.0
        open = 0.0
        low = 0.0
        high = 0.0
        volume = zero(Int64)
        turnover = 0.0
        timestamp = zero(Int64)
        trade_session = TradeSession.Intraday
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                close = parse(Float64, decode(d, String))
            elseif field_number == 2
                open = parse(Float64, decode(d, String))
            elseif field_number == 3
                low = parse(Float64, decode(d, String))
            elseif field_number == 4
                high = parse(Float64, decode(d, String))
            elseif field_number == 5
                volume = decode(d, Int64)
            elseif field_number == 6
                turnover = parse(Float64, decode(d, String))
            elseif field_number == 7
                timestamp = decode(d, Int64)
            elseif field_number == 8
                trade_session = decode(d, TradeSession.T)
            else
                skip(d, wire_type)
            end
        end
        return Candlestick(close, open, low, high, volume, turnover, timestamp, trade_session)
    end


    # K线请求
    struct SecurityCandlestickRequest
        symbol::String
        period::CandlePeriod.T
        count::Int64
        adjust_type::AdjustType.T
        trade_session::TradeSession.T
    end
    default_values(::Type{SecurityCandlestickRequest}) = (
        ;symbol = "", period = CandlePeriod.UNKNOWN_PERIOD, count = 0, 
        adjust_type = AdjustType.NO_ADJUST, trade_session = TradeSession.Intraday
    )
    field_numbers(::Type{SecurityCandlestickRequest}) = (;symbol = 1, period = 2, count = 3, adjust_type = 4, trade_session = 5)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityCandlestickRequest})
        symbol = ""
        period = CandlePeriod.UNKNOWN_PERIOD
        count = zero(Int64)
        adjust_type = AdjustType.NO_ADJUST
        trade_session = TradeSession.Intraday
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                period = decode(d, CandlePeriod.T)
            elseif field_number == 3
                count = decode(d, Int64)
            elseif field_number == 4
                adjust_type = decode(d, AdjustType.T)
            elseif field_number == 5
                trade_session = decode(d, TradeSession.T)
            else
                skip(d, wire_type)
            end
        end
        return SecurityCandlestickRequest(symbol, period, count, adjust_type, trade_session)
    end
    function encode(e::ProtoBuf.AbstractProtoEncoder, x::SecurityCandlestickRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        x.period != CandlePeriod.UNKNOWN_PERIOD && encode(e, 2, x.period)
        x.count != 0 && encode(e, 3, x.count)
        x.adjust_type != AdjustType.NO_ADJUST && encode(e, 4, x.adjust_type)
        x.trade_session != TradeSession.Intraday && encode(e, 5, x.trade_session)
        return position(e.io) - initpos
    end
    function _encoded_size(x::SecurityCandlestickRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        x.period != CandlePeriod.UNKNOWN_PERIOD && (encoded_size += _encoded_size(x.period, 2))
        x.count != 0 && (encoded_size += _encoded_size(x.count, 3))
        x.adjust_type != AdjustType.NO_ADJUST && (encoded_size += _encoded_size(x.adjust_type, 4))
        x.trade_session != TradeSession.Intraday && (encoded_size += _encoded_size(x.trade_session, 5))
        return encoded_size
    end

    # 历史K线请求
    struct OffsetQuery
        direction::Direction.T
        date::String
        minute::String
        count::Int64
    end
    default_values(::Type{OffsetQuery}) = (;direction = Direction.BACKWARD, date = "", minute = "", count = 0)
    field_numbers(::Type{OffsetQuery}) = (;direction = 1, date = 2, minute = 3, count = 4)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::OffsetQuery)
        initpos = position(e.io)
        x.direction != Direction.BACKWARD && encode(e, 1, x.direction)
        !isempty(x.date) && encode(e, 2, x.date)
        !isempty(x.minute) && encode(e, 3, x.minute)
        x.count != 0 && encode(e, 4, x.count)
        return position(e.io) - initpos
    end

    function _encoded_size(x::OffsetQuery)
        encoded_size = 0
        x.direction != Direction.BACKWARD && (encoded_size += _encoded_size(x.direction, 1))
        !isempty(x.date) && (encoded_size += _encoded_size(x.date, 2))
        !isempty(x.minute) && (encoded_size += _encoded_size(x.minute, 3))
        x.count != 0 && (encoded_size += _encoded_size(x.count, 4))
        return encoded_size
    end

    struct DateQuery
        start_date::String
        end_date::String
    end
    default_values(::Type{DateQuery}) = (;start_date = "", end_date = "")
    field_numbers(::Type{DateQuery}) = (;start_date = 1, end_date = 2)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::DateQuery)
        initpos = position(e.io)
        !isempty(x.start_date) && encode(e, 1, x.start_date)
        !isempty(x.end_date) && encode(e, 2, x.end_date)
        return position(e.io) - initpos
    end

    function _encoded_size(x::DateQuery)
        encoded_size = 0
        !isempty(x.start_date) && (encoded_size += _encoded_size(x.start_date, 1))
        !isempty(x.end_date) && (encoded_size += _encoded_size(x.end_date, 2))
        return encoded_size
    end

    struct SecurityHistoryCandlestickRequest
        symbol::String
        period::CandlePeriod.T
        adjust_type::AdjustType.T
        query_type::HistoryCandlestickQueryType.T
        offset_request::Union{OffsetQuery, Nothing}
        date_request::Union{DateQuery, Nothing}
        trade_session::TradeSession.T
    end
    default_values(::Type{SecurityHistoryCandlestickRequest}) = (;symbol = "", period = CandlePeriod.UNKNOWN_PERIOD, adjust_type = AdjustType.NO_ADJUST, query_type = HistoryCandlestickQueryType.UNKNOWN_QUERY_TYPE, offset_request = nothing, date_request = nothing, trade_session = TradeSession.Intraday)
    field_numbers(::Type{SecurityHistoryCandlestickRequest}) = (;symbol = 1, period = 2, adjust_type = 3, query_type = 4, offset_request = 5, date_request = 6, trade_session = 7)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::SecurityHistoryCandlestickRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        x.period != CandlePeriod.UNKNOWN_PERIOD && encode(e, 2, x.period)
        x.adjust_type != AdjustType.NO_ADJUST && encode(e, 3, x.adjust_type)
        x.query_type != HistoryCandlestickQueryType.UNKNOWN_QUERY_TYPE && encode(e, 4, x.query_type)
        x.offset_request !== nothing && encode(e, 5, x.offset_request)
        x.date_request !== nothing && encode(e, 6, x.date_request)
        x.trade_session != TradeSession.Intraday && encode(e, 7, x.trade_session)
        return position(e.io) - initpos
    end

    function _encoded_size(x::SecurityHistoryCandlestickRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        x.period != CandlePeriod.UNKNOWN_PERIOD && (encoded_size += _encoded_size(x.period, 2))
        x.adjust_type != AdjustType.NO_ADJUST && (encoded_size += _encoded_size(x.adjust_type, 3))
        x.query_type != HistoryCandlestickQueryType.UNKNOWN_QUERY_TYPE && (encoded_size += _encoded_size(x.query_type, 4))
        x.offset_request !== nothing && (encoded_size += _encoded_size(x.offset_request, 5))
        x.date_request !== nothing && (encoded_size += _encoded_size(x.date_request, 6))
        x.trade_session != TradeSession.Intraday && (encoded_size += _encoded_size(x.trade_session, 7))
        return encoded_size
    end

    # K线响应
    struct SecurityCandlestickResponse
        symbol::String
        candlesticks::Vector{Candlestick}
    end
    SecurityCandlestickResponse() = SecurityCandlestickResponse("", Candlestick[])
    default_values(::Type{SecurityCandlestickResponse}) = (;symbol = "", candlesticks = Candlestick[])
    field_numbers(::Type{SecurityCandlestickResponse}) = (;symbol = 1, candlesticks = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityCandlestickResponse})
        symbol = ""
        candlesticks = Candlestick[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(candlesticks, decode(sub_d, Candlestick))
            else
                skip(d, wire_type)
            end
        end
        return SecurityCandlestickResponse(symbol, candlesticks)
    end

    # 行情订阅请求
    struct QuoteSubscribeRequest
        symbol::Vector{String}
        sub_type::Vector{SubType.T}
        is_first_push::Bool
    end
    default_values(::Type{QuoteSubscribeRequest}) = (;symbol = String[], sub_type = SubType.T[], is_first_push = false)
    field_numbers(::Type{QuoteSubscribeRequest}) = (;symbol = 1, sub_type = 2, is_first_push = 3)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:QuoteSubscribeRequest})
        symbol = String[]
        sub_type = BufferedVector{SubType.T}()
        is_first_push = false
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                decode!(d, wire_type, symbol)
            elseif field_number == 2
                decode!(d, wire_type, sub_type)
            elseif field_number == 3
                is_first_push = decode(d, Bool)
            else
                skip(d, wire_type)
            end
        end
        return QuoteSubscribeRequest(symbol, getindex(sub_type), is_first_push)
    end
    function encode(e::ProtoBuf.AbstractProtoEncoder, x::QuoteSubscribeRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        !isempty(x.sub_type) && encode(e, 2, x.sub_type)
        x.is_first_push != false && encode(e, 3, x.is_first_push)
        return position(e.io) - initpos
    end
    function _encoded_size(x::QuoteSubscribeRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        !isempty(x.sub_type) && (encoded_size += _encoded_size(x.sub_type, 2))
        x.is_first_push != false && (encoded_size += _encoded_size(x.is_first_push, 3))
        return encoded_size
    end

    # 行情订阅响应（空消息）
    struct QuoteSubscribeResponse
    end
    default_values(::Type{QuoteSubscribeResponse}) = NamedTuple()
    field_numbers(::Type{QuoteSubscribeResponse}) = NamedTuple()

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:QuoteSubscribeResponse})
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            skip(d, wire_type)
        end
        return QuoteSubscribeResponse()
    end
    function _encoded_size(x::QuoteSubscribeResponse)
        return 0
    end

    # 行情取消订阅请求
    struct QuoteUnsubscribeRequest
        symbol::Vector{String}
        sub_type::Vector{SubType.T}
        unsub_all::Bool
    end
    default_values(::Type{QuoteUnsubscribeRequest}) = (;symbol = String[], sub_type = SubType.T[], unsub_all = false)
    field_numbers(::Type{QuoteUnsubscribeRequest}) = (;symbol = 1, sub_type = 2, unsub_all = 3)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:QuoteUnsubscribeRequest})
        symbol = String[]
        sub_type = BufferedVector{SubType.T}()
        unsub_all = false
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                decode!(d, wire_type, symbol)
            elseif field_number == 2
                decode!(d, wire_type, sub_type)
            elseif field_number == 3
                unsub_all = decode(d, Bool)
            else
                skip(d, wire_type)
            end
        end
        return QuoteUnsubscribeRequest(symbol, getindex(sub_type), unsub_all)
    end
    function encode(e::ProtoBuf.AbstractProtoEncoder, x::QuoteUnsubscribeRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        !isempty(x.sub_type) && encode(e, 2, x.sub_type)
        x.unsub_all != false && encode(e, 3, x.unsub_all)
        return position(e.io) - initpos
    end
    function _encoded_size(x::QuoteUnsubscribeRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        !isempty(x.sub_type) && (encoded_size += _encoded_size(x.sub_type, 2))
        x.unsub_all != false && (encoded_size += _encoded_size(x.unsub_all, 3))
        return encoded_size
    end

    # 行情取消订阅响应（空消息）
    struct QuoteUnsubscribeResponse
    end
    default_values(::Type{QuoteUnsubscribeResponse}) = NamedTuple()
    field_numbers(::Type{QuoteUnsubscribeResponse}) = NamedTuple()

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:QuoteUnsubscribeResponse})
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            skip(d, wire_type)
        end
        return QuoteUnsubscribeResponse()
    end
    function _encoded_size(x::QuoteUnsubscribeResponse)
        return 0
    end

    struct SubscriptionRequest
    end
    default_values(::Type{SubscriptionRequest}) = NamedTuple()
    field_numbers(::Type{SubscriptionRequest}) = NamedTuple()

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SubscriptionRequest})
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            skip(d, wire_type)
        end
        return SubscriptionRequest()
    end
    function _encoded_size(x::SubscriptionRequest)
        return 0
    end

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::SubscriptionRequest)
        return 0
    end

    struct SubTypeList
        symbol::String
        sub_type::Vector{SubType.T}
    end
    default_values(::Type{SubTypeList}) = (;symbol = "", sub_type = SubType.T[])
    field_numbers(::Type{SubTypeList}) = (;symbol = 1, sub_type = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SubTypeList})
        symbol = ""
        sub_type = BufferedVector{SubType.T}()
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                decode!(d, wire_type, sub_type)
            else
                skip(d, wire_type)
            end
        end
        return SubTypeList(symbol, getindex(sub_type))
    end

    struct SubscriptionResponse
        sub_list::Vector{SubTypeList}
    end
    SubscriptionResponse() = SubscriptionResponse(SubTypeList[])
    default_values(::Type{SubscriptionResponse}) = (;sub_list = SubTypeList[])
    field_numbers(::Type{SubscriptionResponse}) = (;sub_list = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SubscriptionResponse})
        sub_list = SubTypeList[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(sub_list, decode(sub_d, SubTypeList))
            else
                skip(d, wire_type)
            end
        end
        return SubscriptionResponse(sub_list)
    end

    # 推送行情数据
    struct PushQuote
        symbol::String
        sequence::Int64                 # 推送序列号，用于标识消息的顺序
        last_done::Float64
        open::Float64
        high::Float64
        low::Float64
        timestamp::Int64
        volume::Int64                   # 成交量，到当前时间为止的总成交股数
        turnover::Float64               # 成交额，到当前时间为止的总成交金额
        trade_status::TradeStatus.T
        trade_session::TradeSession.T
        current_volume::Int64           # 当前单笔成交量（可能指最近一笔或一个极短时间窗口内的成交，区别于`volume`的日内累计值）
        current_turnover::Float64       # 当前单笔成交额
        tag::PushQuoteTag.T
    end
    default_values(::Type{PushQuote}) = (
        ; symbol = "", sequence = zero(Int64), last_done = 0.0, open = 0.0, high = 0.0, low = 0.0, timestamp = zero(Int64), volume = zero(Int64), turnover = 0.0, 
        trade_status = TradeStatus.Normal, trade_session = TradeSession.Intraday, current_volume = zero(Int64), current_turnover = 0.0, tag = PushQuoteTag.Normal
    )
    field_numbers(::Type{PushQuote}) = (
        ; symbol = 1, sequence = 2, last_done = 3, open = 4, high = 5, low = 6, timestamp = 7, volume = 8, turnover = 9, 
        trade_status = 10, trade_session = 11, current_volume = 12, current_turnover = 13, tag = 14
    )

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:PushQuote})
        symbol = ""
        sequence = zero(Int64)
        last_done = 0.0
        open = 0.0
        high = 0.0
        low = 0.0
        timestamp = zero(Int64)
        volume = zero(Int64)
        turnover = 0.0
        trade_status = TradeStatus.Normal
        trade_session = TradeSession.Intraday
        current_volume = zero(Int64)
        current_turnover = 0.0
        tag = PushQuoteTag.Normal
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                sequence = decode(d, Int64)
            elseif field_number == 3
                last_done = parse(Float64, decode(d, String))
            elseif field_number == 4
                open = parse(Float64, decode(d, String))
            elseif field_number == 5
                high = parse(Float64, decode(d, String))
            elseif field_number == 6
                low = parse(Float64, decode(d, String))
            elseif field_number == 7
                timestamp = decode(d, Int64)
            elseif field_number == 8
                volume = decode(d, Int64)
            elseif field_number == 9
                turnover = parse(Float64, decode(d, String))
            elseif field_number == 10
                trade_status = decode(d, TradeStatus.T)
            elseif field_number == 11
                trade_session = decode(d, TradeSession.T)
            elseif field_number == 12
                current_volume = decode(d, Int64)
            elseif field_number == 13
                current_turnover = parse(Float64, decode(d, String))
            elseif field_number == 14
                tag = decode(d, PushQuoteTag.T)
            else
                skip(d, wire_type)
            end
        end
        return PushQuote(symbol, sequence, last_done, open, high, low, timestamp, volume, turnover, trade_status, trade_session, current_volume, current_turnover, tag)
    end

    # 盘口数据
    struct Depth
        position::Int64
        price::Float64
        volume::Int64           # 挂单量
        order_num::Int64        # 订单数量
    end
    default_values(::Type{Depth}) = (;position = zero(Int64), price = 0.0, volume = zero(Int64), order_num = zero(Int64))
    field_numbers(::Type{Depth}) = (;position = 1, price = 2, volume = 3, order_num = 4)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:Depth})
        position = zero(Int64)
        price = 0.0
        volume = zero(Int64)
        order_num = zero(Int64)
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                position = decode(d, Int64)
            elseif field_number == 2
                price = parse(Float64, decode(d, String))
            elseif field_number == 3
                volume = decode(d, Int64)
                elseif field_number == 4
                order_num = decode(d, Int64)
            else
                skip(d, wire_type)
            end
        end
        return Depth(position, price, volume, order_num)
    end

    # 推送盘口数据
    struct PushDepth
        symbol::String
        sequence::Int64
        ask::Vector{Depth}
        bid::Vector{Depth}
    end
    default_values(::Type{PushDepth}) = (;symbol = "", sequence = zero(Int64), ask = Depth[], bid = Depth[])
    field_numbers(::Type{PushDepth}) = (;symbol = 1, sequence = 2, ask = 3, bid = 4)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:PushDepth})
        symbol = ""
        sequence = zero(Int64)
        ask = Depth[]
        bid = Depth[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                sequence = decode(d, Int64)
            elseif field_number == 3
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(ask, decode(sub_d, Depth))
            elseif field_number == 4
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(bid, decode(sub_d, Depth))
            else
                skip(d, wire_type)
            end
        end
        return PushDepth(symbol, sequence, ask, bid)
    end

    # 经纪队列
    struct Brokers
        position::Int64
        broker_ids::Vector{Int64}
    end
    default_values(::Type{Brokers}) = (;position = zero(Int64), broker_ids = Int64[])
    field_numbers(::Type{Brokers}) = (;position = 1, broker_ids = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:Brokers})
        position = zero(Int64)
        broker_ids = BufferedVector{Int64}()
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                position = decode(d, Int64)
            elseif field_number == 2
                decode!(d, wire_type, broker_ids)
            else
                skip(d, wire_type)
            end
        end
        return Brokers(position, getindex(broker_ids))
    end

    # 推送经纪队列数据
    struct PushBrokers
        symbol::String
        sequence::Int64
        ask_brokers::Vector{Brokers}
        bid_brokers::Vector{Brokers}
    end

    default_values(::Type{PushBrokers}) = (;symbol = "", sequence = zero(Int64), ask_brokers = Brokers[], bid_brokers = Brokers[])
    field_numbers(::Type{PushBrokers}) = (;symbol = 1, sequence = 2, ask_brokers = 3, bid_brokers = 4)
    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:PushBrokers})
        symbol = ""
        sequence = zero(Int64)
        ask_brokers = Brokers[]
        bid_brokers = Brokers[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                sequence = decode(d, Int64)
            elseif field_number == 3
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(ask_brokers, decode(sub_d, Brokers))
            elseif field_number == 4
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(bid_brokers, decode(sub_d, Brokers))
            else
                skip(d, wire_type)
            end
        end
        return PushBrokers(symbol, sequence, ask_brokers, bid_brokers)
    end

    # 成交明细
    struct Trade
        price::Float64
        volume::Int64
        timestamp::Int64
        trade_type::TradeType.T
        direction::TradeDirection.T
        trade_session::TradeSession.T
    end
    default_values(::Type{Trade}) = (;price = 0.0, volume = zero(Int64), timestamp = zero(Int64), trade_type = TradeType.UnknownTradeType, direction = TradeDirection.Neutral, trade_session = TradeSession.Intraday)
    field_numbers(::Type{Trade}) = (;price = 1, volume = 2, timestamp = 3, trade_type = 4, direction = 5, trade_session = 6)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:Trade}; symbol::String = "")
        price = 0.0
        volume = zero(Int64)
        timestamp = zero(Int64)
        trade_type_str = ""
        direction = TradeDirection.Neutral
        trade_session = TradeSession.Intraday
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                price = parse(Float64, decode(d, String))
            elseif field_number == 2
                volume = decode(d, Int64)
            elseif field_number == 3
                timestamp = decode(d, Int64)
            elseif field_number == 4
                trade_type_str = decode(d, String)
            elseif field_number == 5
                direction = TradeDirection.T(decode(d, Int64))
            elseif field_number == 6
                trade_session = decode(d, TradeSession.T)
            else
                skip(d, wire_type)
            end
        end
        trade_type = trade_type_from_string(trade_type_str, symbol)
        return Trade(price, volume, timestamp, trade_type, direction, trade_session)
    end

    # 推送成交明细数据
    struct PushTrade
        symbol::String
        sequence::Int64
        trade::Vector{Trade}
    end
    default_values(::Type{PushTrade}) = (;symbol = "", sequence = zero(Int64), trade = Trade[])
    field_numbers(::Type{PushTrade}) = (;symbol = 1, sequence = 2, trade = 3)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:PushTrade})
        symbol = ""
        sequence = zero(Int64)
        trade = Trade[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                sequence = decode(d, Int64)
            elseif field_number == 3
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(trade, decode(sub_d, Trade; symbol=symbol))
            else
                skip(d, wire_type)
            end
        end
        return PushTrade(symbol, sequence, trade)
    end

    # 期权扩展信息
    struct OptionExtend
        implied_volatility::String
        open_interest::Int64
        expiry_date::Date
        strike_price::String
        contract_multiplier::String
        contract_type::String
        contract_size::String
        direction::String
        historical_volatility::String
        underlying_symbol::String
    end
    default_values(::Type{OptionExtend}) = (;implied_volatility = "", open_interest = zero(Int64), expiry_date = Date(1970,1,1), strike_price = "", contract_multiplier = "", contract_type = "", contract_size = "", direction = "", historical_volatility = "", underlying_symbol = "")
    field_numbers(::Type{OptionExtend}) = (;implied_volatility = 1, open_interest = 2, expiry_date = 3, strike_price = 4, contract_multiplier = 5, contract_type = 6, contract_size = 7, direction = 8, historical_volatility = 9, underlying_symbol = 10)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:OptionExtend})
        implied_volatility = ""
        open_interest = zero(Int64)
        expiry_date = Date(1970,1,1)
        strike_price = ""
        contract_multiplier = ""
        contract_type = ""
        contract_size = ""
        direction = ""
        historical_volatility = ""
        underlying_symbol = ""
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                implied_volatility = decode(d, String)
            elseif field_number == 2
                open_interest = decode(d, Int64)
            elseif field_number == 3
                expiry_date = Date(decode(d, String), "yyyymmdd")
            elseif field_number == 4
                strike_price = decode(d, String)
            elseif field_number == 5
                contract_multiplier = decode(d, String)
            elseif field_number == 6
                contract_type = decode(d, String)
            elseif field_number == 7
                contract_size = decode(d, String)
            elseif field_number == 8
                direction = decode(d, String)
            elseif field_number == 9
                historical_volatility = decode(d, String)
            elseif field_number == 10
                underlying_symbol = decode(d, String)
            else
                skip(d, wire_type)
            end
        end
        return OptionExtend(implied_volatility, open_interest, expiry_date, strike_price, contract_multiplier, contract_type, contract_size, direction, historical_volatility, underlying_symbol)
    end

    # 权证扩展信息
    struct WarrantExtend
        implied_volatility::Float64
        expiry_date::Date
        last_trade_date::Date
        outstanding_ratio::Float64
        outstanding_qty::Int64
        conversion_ratio::Float64
        category::String
        strike_price::Float64
        upper_strike_price::Float64
        lower_strike_price::Float64
        call_price::Float64
        underlying_symbol::String
    end
    default_values(::Type{WarrantExtend}) = (;implied_volatility = 0.0, expiry_date = Date(1970,1,1), last_trade_date = Date(1970,1,1), outstanding_ratio = 0.0, outstanding_qty = zero(Int64), conversion_ratio = 0.0, category = "", strike_price = 0.0, upper_strike_price = 0.0, lower_strike_price = 0.0, call_price = 0.0, underlying_symbol = "")
    field_numbers(::Type{WarrantExtend}) = (;implied_volatility = 1, expiry_date = 2, last_trade_date = 3, outstanding_ratio = 4, outstanding_qty = 5, conversion_ratio = 6, category = 7, strike_price = 8, upper_strike_price = 9, lower_strike_price = 10, call_price = 11, underlying_symbol = 12)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:WarrantExtend})
        implied_volatility = 0.0
        expiry_date = Date(1970,1,1)
        last_trade_date = Date(1970,1,1)
        outstanding_ratio = 0.0
        outstanding_qty = zero(Int64)
        conversion_ratio = 0.0
        category = ""
        strike_price = 0.0
        upper_strike_price = 0.0
        lower_strike_price = 0.0
        call_price = 0.0
        underlying_symbol = ""
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                implied_volatility = parse(Float64, decode(d, String))
            elseif field_number == 2
                expiry_date = Date(decode(d, String), "yyyymmdd")
            elseif field_number == 3
                last_trade_date = Date(decode(d, String), "yyyymmdd")
            elseif field_number == 4
                outstanding_ratio = parse(Float64, decode(d, String))
            elseif field_number == 5
                outstanding_qty = decode(d, Int64)
            elseif field_number == 6
                conversion_ratio = parse(Float64, decode(d, String))
            elseif field_number == 7
                category = decode(d, String)
            elseif field_number == 8
                strike_price = parse(Float64, decode(d, String))
            elseif field_number == 9
                upper_strike_price = parse(Float64, decode(d, String))
            elseif field_number == 10
                lower_strike_price = parse(Float64, decode(d, String))
            elseif field_number == 11
                call_price = parse(Float64, decode(d, String))
            elseif field_number == 12
                underlying_symbol = decode(d, String)
            else
                skip(d, wire_type)
            end
        end
        return WarrantExtend(
            implied_volatility, expiry_date, last_trade_date, outstanding_ratio, outstanding_qty, 
            conversion_ratio, category, strike_price, upper_strike_price, lower_strike_price, call_price,
            underlying_symbol
        )
    end

    # 期权行情数据
    struct OptionQuote
        symbol::String
        last_done::String
        prev_close::String
        open::String
        high::String
        low::String
        timestamp::Int64
        volume::Int64
        turnover::String
        trade_status::TradeStatus.T
        option_extend::OptionExtend
    end
    default_values(::Type{OptionQuote}) = (;symbol = "", last_done = "", prev_close = "", open = "", high = "", low = "", timestamp = zero(Int64), volume = zero(Int64), turnover = "", trade_status = TradeStatus.Normal, option_extend = OptionExtend("", 0, "", "", "", "", "", "", "", ""))
    field_numbers(::Type{OptionQuote}) = (;symbol = 1, last_done = 2, prev_close = 3, open = 4, high = 5, low = 6, timestamp = 7, volume = 8, turnover = 9, trade_status = 10, option_extend = 11)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:OptionQuote})
        symbol = ""
        last_done = ""
        prev_close = ""
        open = ""
        high = ""
        low = ""
        timestamp = zero(Int64)
        volume = zero(Int64)
        turnover = ""
        trade_status = TradeStatus.Normal
        option_extend = nothing
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                last_done = decode(d, String)
            elseif field_number == 3
                prev_close = decode(d, String)
            elseif field_number == 4
                open = decode(d, String)
            elseif field_number == 5
                high = decode(d, String)
            elseif field_number == 6
                low = decode(d, String)
            elseif field_number == 7
                timestamp = decode(d, Int64)
            elseif field_number == 8
                volume = decode(d, Int64)
            elseif field_number == 9
                turnover = decode(d, String)
            elseif field_number == 10
                trade_status = decode(d, TradeStatus.T)
            elseif field_number == 11
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                option_extend = decode(sub_d, OptionExtend)
            else
                skip(d, wire_type)
            end
        end
        return OptionQuote(symbol, last_done, prev_close, open, high, low, timestamp, volume, turnover, trade_status, option_extend)
    end


    # 期权行情响应
    struct OptionQuoteResponse
        secu_quote::Vector{OptionQuote}
    end
    OptionQuoteResponse() = OptionQuoteResponse(OptionQuote[])
    default_values(::Type{OptionQuoteResponse}) = (;secu_quote = OptionQuote[])
    field_numbers(::Type{OptionQuoteResponse}) = (;secu_quote = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:OptionQuoteResponse})
        secu_quote = OptionQuote[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(secu_quote, decode(sub_d, OptionQuote))
            else
                skip(d, wire_type)
            end
        end
        return OptionQuoteResponse(secu_quote)
    end


    # 轮证行情数据
    struct WarrantQuote
        symbol::String
        last_done::Float64
        prev_close::Float64
        open::Float64
        high::Float64
        low::Float64
        timestamp::Int64
        volume::Int64
        turnover::Float64
        trade_status::TradeStatus.T
        warrant_extend::WarrantExtend
    end
    default_values(::Type{WarrantQuote}) = (;symbol = "", last_done = 0.0, prev_close = 0.0, open = 0.0, high = 0.0, low = 0.0, timestamp = zero(Int64), volume = zero(Int64), turnover = 0.0, trade_status = TradeStatus.Normal, warrant_extend = WarrantExtend(0.0, Date(1970,1,1), Date(1970,1,1), 0.0, 0, 0.0, "", 0.0, 0.0, 0.0, 0.0, ""))
    field_numbers(::Type{WarrantQuote}) = (;symbol = 1, last_done = 2, prev_close = 3, open = 4, high = 5, low = 6, timestamp = 7, volume = 8, turnover = 9, trade_status = 10, warrant_extend = 11)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:WarrantQuote})
        symbol = ""
        last_done = 0.0
        prev_close = 0.0
        open = 0.0
        high = 0.0
        low = 0.0
        timestamp = zero(Int64)
        volume = zero(Int64)
        turnover = 0.0
        trade_status = TradeStatus.Normal
        warrant_extend = WarrantExtend(0.0, Date(1970,1,1), Date(1970,1,1), 0.0, 0, 0.0, "", 0.0, 0.0, 0.0, 0.0, "")
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                last_done = parse(Float64, decode(d, String))
            elseif field_number == 3
                prev_close = parse(Float64, decode(d, String))
            elseif field_number == 4
                open = parse(Float64, decode(d, String))
            elseif field_number == 5
                high = parse(Float64, decode(d, String))
            elseif field_number == 6
                low = parse(Float64, decode(d, String))
            elseif field_number == 7
                timestamp = decode(d, Int64)
            elseif field_number == 8
                volume = decode(d, Int64)
            elseif field_number == 9
                turnover = parse(Float64, decode(d, String))
            elseif field_number == 10
                trade_status = decode(d, TradeStatus.T)
            elseif field_number == 11
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                warrant_extend = decode(sub_d, WarrantExtend)
            else
                skip(d, wire_type)
            end
        end
        return WarrantQuote(symbol, last_done, prev_close, open, high, low, timestamp, volume, turnover, trade_status, warrant_extend)
    end


    # 轮证行情响应
    struct WarrantQuoteResponse
        secu_quote::Vector{WarrantQuote}
    end
    WarrantQuoteResponse() = WarrantQuoteResponse(WarrantQuote[])
    default_values(::Type{WarrantQuoteResponse}) = (;secu_quote = WarrantQuote[])
    field_numbers(::Type{WarrantQuoteResponse}) = (;secu_quote = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:WarrantQuoteResponse})
        secu_quote = WarrantQuote[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 2
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(secu_quote, decode(sub_d, WarrantQuote))
            else
                skip(d, wire_type)
            end
        end
        return WarrantQuoteResponse(secu_quote)
    end

    # 证券盘口响应
    struct SecurityDepthResponse
        symbol::String
        ask::Vector{Depth}
        bid::Vector{Depth}
    end
    
    default_values(::Type{SecurityDepthResponse}) = (;symbol = "", ask = Depth[], bid = Depth[])
    field_numbers(::Type{SecurityDepthResponse}) = (;symbol = 1, ask = 2, bid = 3)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityDepthResponse})
        symbol = ""
        ask = Depth[]
        bid = Depth[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                len = decode(d, Int)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(ask, decode(sub_d, Depth))
            elseif field_number == 3
                len = decode(d, Int)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(bid, decode(sub_d, Depth))
            else
                skip(d, wire_type)
            end
        end
        return SecurityDepthResponse(symbol, ask, bid)
    end

    # 经纪队列响应
    struct SecurityBrokersResponse
        symbol::String
        ask_brokers::Vector{Brokers}
        bid_brokers::Vector{Brokers}
    end

    default_values(::Type{SecurityBrokersResponse}) = (;symbol = "", ask_brokers = Brokers[], bid_brokers = Brokers[])
    field_numbers(::Type{SecurityBrokersResponse}) = (;symbol = 1, ask_brokers = 2, bid_brokers = 3)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityBrokersResponse})
        symbol = ""
        ask_brokers = Brokers[]
        bid_brokers = Brokers[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                len = decode(d, Int)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(ask_brokers, decode(sub_d, Brokers))
            elseif field_number == 3
                len = decode(d, Int)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(bid_brokers, decode(sub_d, Brokers))
            else
                skip(d, wire_type)
            end
        end
        return SecurityBrokersResponse(symbol, ask_brokers, bid_brokers)
    end

    # 查询成交明细请求
    struct SecurityTradeRequest
        symbol::String
        count::Int64
    end
    default_values(::Type{SecurityTradeRequest}) = (;symbol = "", count = zero(Int64))
    field_numbers(::Type{SecurityTradeRequest}) = (;symbol = 1, count = 2)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::SecurityTradeRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        x.count != 0 && encode(e, 2, x.count)
        return position(e.io) - initpos
    end

    function _encoded_size(x::SecurityTradeRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        x.count != 0 && (encoded_size += _encoded_size(x.count, 2))
        return encoded_size
    end

    # 查询成交明细响应
    struct SecurityTradeResponse
        symbol::String
        trades::Vector{Trade}
    end
    SecurityTradeResponse() = SecurityTradeResponse("", Trade[])
    default_values(::Type{SecurityTradeResponse}) = (;symbol = "", trades = Trade[])
    field_numbers(::Type{SecurityTradeResponse}) = (;symbol = 1, trades = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityTradeResponse})
        symbol = ""
        trades = Trade[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(trades, decode(sub_d, Trade; symbol=symbol))
            else
                skip(d, wire_type)
            end
        end
        return SecurityTradeResponse(symbol, trades)
    end

    struct ParticipantInfo
        broker_ids::Vector{Int64}
        participant_name_cn::String
        participant_name_en::String
        participant_name_hk::String
    end

    default_values(::Type{ParticipantInfo}) = (;broker_ids = Int64[], participant_name_cn = "", participant_name_en = "", participant_name_hk = "")
    field_numbers(::Type{ParticipantInfo}) = (;broker_ids = 1, participant_name_cn = 2, participant_name_en = 3, participant_name_hk = 4)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:ParticipantInfo})
        broker_ids = BufferedVector{Int64}()
        participant_name_cn = ""
        participant_name_en = ""
        participant_name_hk = ""
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                decode!(d, wire_type, broker_ids)
            elseif field_number == 2
                participant_name_cn = decode(d, String)
            elseif field_number == 3
                participant_name_en = decode(d, String)
            elseif field_number == 4
                participant_name_hk = decode(d, String)
            else
                skip(d, wire_type)
            end
        end
        return ParticipantInfo(getindex(broker_ids), participant_name_cn, participant_name_en, participant_name_hk)
    end

    struct ParticipantBrokerIdsResponse
        participant_broker_numbers::Vector{ParticipantInfo}
    end

    ParticipantBrokerIdsResponse() = ParticipantBrokerIdsResponse(ParticipantInfo[])
    default_values(::Type{ParticipantBrokerIdsResponse}) = (;participant_broker_numbers = ParticipantInfo[])
    field_numbers(::Type{ParticipantBrokerIdsResponse}) = (;participant_broker_numbers = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:ParticipantBrokerIdsResponse})
        participant_broker_numbers = ParticipantInfo[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(participant_broker_numbers, decode(sub_d, ParticipantInfo))
            else
                skip(d, wire_type)
            end
        end
        return ParticipantBrokerIdsResponse(participant_broker_numbers)
    end

    # 分时数据
    struct Line
        price::Float64
        timestamp::Int64
        volume::Int64
        turnover::Float64
        avg_price::Float64
    end
    default_values(::Type{Line}) = (;price = 0.0, timestamp = zero(Int64), volume = zero(Int64), turnover = 0.0, avg_price = 0.0)
    field_numbers(::Type{Line}) = (;price = 1, timestamp = 2, volume = 3, turnover = 4, avg_price = 5)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:Line})
        price = 0.0
        timestamp = zero(Int64)
        volume = zero(Int64)
        turnover = 0.0
        avg_price = 0.0
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                price = parse(Float64, decode(d, String))
            elseif field_number == 2
                timestamp = decode(d, Int64)
            elseif field_number == 3
                volume = decode(d, Int64)
            elseif field_number == 4
                turnover = parse(Float64, decode(d, String))
            elseif field_number == 5
                avg_price = parse(Float64, decode(d, String))
            else
                skip(d, wire_type)
            end
        end
        return Line(price, timestamp, volume, turnover, avg_price)
    end

    # 查询当日分时请求
    struct SecurityIntradayRequest
        symbol::String
        trade_session::TradeSession.T
    end
    default_values(::Type{SecurityIntradayRequest}) = (;symbol = "", trade_session = TradeSession.All)
    field_numbers(::Type{SecurityIntradayRequest}) = (;symbol = 1, trade_session = 2)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::SecurityIntradayRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        x.trade_session != TradeSession.All && encode(e, 2, x.trade_session)
        return position(e.io) - initpos
    end

    function _encoded_size(x::SecurityIntradayRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        x.trade_session != TradeSession.All && (encoded_size += _encoded_size(x.trade_session, 2))
        return encoded_size
    end

    # 查询当日分时响应
    struct SecurityIntradayResponse
        symbol::String
        lines::Vector{Line}
    end
    SecurityIntradayResponse() = SecurityIntradayResponse("", Line[])
    default_values(::Type{SecurityIntradayResponse}) = (;symbol = "", lines = Line[])
    field_numbers(::Type{SecurityIntradayResponse}) = (;symbol = 1, lines = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityIntradayResponse})
        symbol = ""
        lines = Line[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(lines, decode(sub_d, Line))
            else
                skip(d, wire_type)
            end
        end
        return SecurityIntradayResponse(symbol, lines)
    end

    struct OptionChainDateListResponse
        expiry_date::Vector{Date}
    end
    default_values(::Type{OptionChainDateListResponse}) = (;expiry_date = Date[])
    field_numbers(::Type{OptionChainDateListResponse}) = (;expiry_date = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:OptionChainDateListResponse})
        expiry_date = Date[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                push!(expiry_date, Date(decode(d, String), "yyyymmdd"))
            else
                skip(d, wire_type)
            end
        end
        return OptionChainDateListResponse(expiry_date)
    end

    struct OptionChainDateStrikeInfoRequest
        symbol::String
        expiry_date::Date
    end
    default_values(::Type{OptionChainDateStrikeInfoRequest}) = (;symbol = "", expiry_date = Date(1970,1,1))
    field_numbers(::Type{OptionChainDateStrikeInfoRequest}) = (;symbol = 1, expiry_date = 2)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::OptionChainDateStrikeInfoRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        date_str = Dates.format(x.expiry_date, "yyyymmdd")
        !isempty(date_str) && encode(e, 2, date_str)
        return position(e.io) - initpos
    end

    function _encoded_size(x::OptionChainDateStrikeInfoRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        date_str = Dates.format(x.expiry_date, "yyyymmdd")
        !isempty(date_str) && (encoded_size += _encoded_size(date_str, 2))
        return encoded_size
    end

    # 行权价信息
    struct StrikePriceInfo
        price::Float64
        call_symbol::String
        put_symbol::String
        standard::Bool
    end
    default_values(::Type{StrikePriceInfo}) = (;price = 0.0, call_symbol = "", put_symbol = "", standard = false)
    field_numbers(::Type{StrikePriceInfo}) = (;price = 1, call_symbol = 2, put_symbol = 3, standard = 4)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:StrikePriceInfo})
        price = 0.0
        call_symbol = ""
        put_symbol = ""
        standard = false
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                price = parse(Float64, decode(d, String))
            elseif field_number == 2
                call_symbol = decode(d, String)
            elseif field_number == 3
                put_symbol = decode(d, String)
            elseif field_number == 4
                standard = decode(d, Bool)
            else
                skip(d, wire_type)
            end
        end
        return StrikePriceInfo(price, call_symbol, put_symbol, standard)
    end

    struct OptionChainDateStrikeInfoResponse
        strike_price_info::Vector{StrikePriceInfo}
    end
    OptionChainDateStrikeInfoResponse() = OptionChainDateStrikeInfoResponse(StrikePriceInfo[])
    default_values(::Type{OptionChainDateStrikeInfoResponse}) = (;strike_price_info = StrikePriceInfo[])
    field_numbers(::Type{OptionChainDateStrikeInfoResponse}) = (;strike_price_info = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:OptionChainDateStrikeInfoResponse})
        strike_price_info = StrikePriceInfo[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(strike_price_info, decode(sub_d, StrikePriceInfo))
            else
                skip(d, wire_type)
            end
        end
        return OptionChainDateStrikeInfoResponse(strike_price_info)
    end

    struct IssuerInfo
        id::Int64
        name_cn::String
        name_en::String
        name_hk::String
    end
    default_values(::Type{IssuerInfo}) = (;id = zero(Int64), name_cn = "", name_en = "", name_hk = "")
    field_numbers(::Type{IssuerInfo}) = (;id = 1, name_cn = 2, name_en = 3, name_hk = 4)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:IssuerInfo})
        id = zero(Int64)
        name_cn = ""
        name_en = ""
        name_hk = ""
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                id = decode(d, Int64)
            elseif field_number == 2
                name_cn = decode(d, String)
            elseif field_number == 3
                name_en = decode(d, String)
            elseif field_number == 4
                name_hk = decode(d, String)
            else
                skip(d, wire_type)
            end
        end
        return IssuerInfo(id, name_cn, name_en, name_hk)
    end

    struct IssuerInfoResponse
        issuer_info::Vector{IssuerInfo}
    end
    IssuerInfoResponse() = IssuerInfoResponse(IssuerInfo[])
    default_values(::Type{IssuerInfoResponse}) = (;issuer_info = IssuerInfo[])
    field_numbers(::Type{IssuerInfoResponse}) = (;issuer_info = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:IssuerInfoResponse})
        issuer_info = IssuerInfo[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(issuer_info, decode(sub_d, IssuerInfo))
            else
                skip(d, wire_type)
            end
        end
        return IssuerInfoResponse(issuer_info)
    end







    """
    Order book
    """
    struct OrderBook
        symbol::String
        sequence::Int64
        asks::Vector{Depth}
        bids::Vector{Depth}
    end
    struct FilterConfig
        sort_by::WarrantSortBy.T
        sort_order::SortOrderType.T
        sort_offset::Int64
        sort_count::Int64
        type::Vector{WarrantType.T}
        issuer::Vector{Int64}
        expiry_date::Vector{FilterWarrantExpiryDate.T}
        price_type::Vector{FilterWarrantInOutBoundsType.T}
        status::Vector{WarrantStatus.T}
    end
    default_values(::Type{FilterConfig}) = (;sort_by = WarrantSortBy.LastDone, sort_order = SortOrderType.Ascending, sort_offset = zero(Int64), sort_count = zero(Int64), type = WarrantType.T[], issuer = Int64[], expiry_date = FilterWarrantExpiryDate.T[], price_type = FilterWarrantInOutBoundsType.T[], status = WarrantStatus.T[])
    field_numbers(::Type{FilterConfig}) = (;sort_by = 1, sort_order = 2, sort_offset = 3, sort_count = 4, type = 5, issuer = 6, expiry_date = 7, price_type = 8, status = 9)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::FilterConfig)
        initpos = position(e.io)
        x.sort_by != 0 && encode(e, 1, x.sort_by)
        x.sort_order != 0 && encode(e, 2, x.sort_order)
        x.sort_offset != 0 && encode(e, 3, x.sort_offset)
        x.sort_count != 0 && encode(e, 4, x.sort_count)
        !isempty(x.type) && encode(e, 5, x.type)
        !isempty(x.issuer) && encode(e, 6, x.issuer)
        !isempty(x.expiry_date) && encode(e, 7, x.expiry_date)
        !isempty(x.price_type) && encode(e, 8, x.price_type)
        !isempty(x.status) && encode(e, 9, x.status)
        return position(e.io) - initpos
    end

    function _encoded_size(x::FilterConfig)
        encoded_size = 0
        x.sort_by != 0 && (encoded_size += _encoded_size(x.sort_by, 1))
        x.sort_order != 0 && (encoded_size += _encoded_size(x.sort_order, 2))
        x.sort_offset != 0 && (encoded_size += _encoded_size(x.sort_offset, 3))
        x.sort_count != 0 && (encoded_size += _encoded_size(x.sort_count, 4))
        !isempty(x.type) && (encoded_size += _encoded_size(x.type, 5))
        !isempty(x.issuer) && (encoded_size += _encoded_size(x.issuer, 6))
        !isempty(x.expiry_date) && (encoded_size += _encoded_size(x.expiry_date, 7))
        !isempty(x.price_type) && (encoded_size += _encoded_size(x.price_type, 8))
        !isempty(x.status) && (encoded_size += _encoded_size(x.status, 9))
        return encoded_size
    end

    struct WarrantFilterListRequest
        symbol::String
        filter_config::FilterConfig
        language::Int64
    end
    default_values(::Type{WarrantFilterListRequest}) = (;symbol = "", filter_config = FilterConfig(WarrantSortBy.LastDone, SortOrderType.Ascending, 0, 0, [], [], [], [], []), language = 0)
    field_numbers(::Type{WarrantFilterListRequest}) = (;symbol = 1, filter_config = 2, language = 3)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::WarrantFilterListRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        encode(e, 2, x.filter_config)
        x.language != 0 && encode(e, 3, x.language)
        return position(e.io) - initpos
    end

    function _encoded_size(x::WarrantFilterListRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        encoded_size += _encoded_size(x.filter_config, 2)
        x.language != 0 && (encoded_size += _encoded_size(x.language, 3))
        return encoded_size
    end

    struct FilterWarrant
        symbol::String
        name::String
        last_done::Float64                                   # 最新价
        change_rate::Float64                                 # 涨跌幅
        change_val::Float64                                  # 涨跌额
        volume::Int64                                       # 成交量
        turnover::Float64                                    # 成交额
        expiry_date::Date                                   # 到期日
        strike_price::Float64                                # 行权价
        upper_strike_price::Float64                          # 上限价
        lower_strike_price::Float64                          # 下限价
        outstanding_qty::Int64                             # 街货量
        outstanding_ratio::Float64                           # 街货比
        premium::Float64                                     # 溢价率
        itm_otm::Float64                                     # 价内/价外
        implied_volatility::Float64                          # 引伸波幅
        delta::Float64                                       # 对冲值
        call_price::Float64                                  # 收回价
        to_call_price::Float64                               # 距收回价
        effective_leverage::Float64                          # 有效杠杆
        leverage_ratio::Float64                              # 杠杆比率
        conversion_ratio::Float64                            # 换股比率
        balance_point::Float64                               # 打和点
        status::Int64                                        # 状态状态，可选值：2-终止交易，3-等待上市，4-正常交易
    end
    default_values(::Type{FilterWarrant}) = (;symbol = "", name = "", last_done = 0.0, change_rate = 0.0, change_val = 0.0, volume = zero(Int64), turnover = 0.0, expiry_date = Date(1970,1,1), strike_price = 0.0, upper_strike_price = 0.0, lower_strike_price = 0.0, outstanding_qty = zero(Int64), outstanding_ratio = 0.0, premium = 0.0, itm_otm = 0.0, implied_volatility = 0.0, delta = 0.0, call_price = 0.0, to_call_price = 0.0, effective_leverage = 0.0, leverage_ratio = 0.0, conversion_ratio = 0.0, balance_point = 0.0, status = zero(Int64))
    field_numbers(::Type{FilterWarrant}) = (;symbol = 1, name = 2, last_done = 3, change_rate = 4, change_val = 5, volume = 6, turnover = 7, expiry_date = 8, strike_price = 9, upper_strike_price = 10, lower_strike_price = 11, outstanding_qty = 12, outstanding_ratio = 13, premium = 14, itm_otm = 15, implied_volatility = 16, delta = 17, call_price = 18, to_call_price = 19, effective_leverage = 20, leverage_ratio = 21, conversion_ratio = 22, balance_point = 23, status = 24)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:FilterWarrant})
        symbol = ""
        name = ""
        last_done = 0.0
        change_rate = 0.0
        change_val = 0.0
        volume = zero(Int64)
        turnover = 0.0
        expiry_date = Date(1970,1,1)
        strike_price = 0.0
        upper_strike_price = 0.0
        lower_strike_price = 0.0
        outstanding_qty = zero(Int64)
        outstanding_ratio = 0.0
        premium = 0.0
        itm_otm = 0.0
        implied_volatility = 0.0
        delta = 0.0
        call_price = 0.0
        to_call_price = 0.0
        effective_leverage = 0.0
        leverage_ratio = 0.0
        conversion_ratio = 0.0
        balance_point = 0.0
        status = zero(Int64)
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                name = decode(d, String)
            elseif field_number == 3
                last_done = parse(Float64, decode(d, String))
            elseif field_number == 4
                change_rate = parse(Float64, decode(d, String))
            elseif field_number == 5
                change_val = parse(Float64, decode(d, String))
            elseif field_number == 6
                volume = decode(d, Int64)
            elseif field_number == 7
                turnover = parse(Float64, decode(d, String))
            elseif field_number == 8
                expiry_date = Date(decode(d, String), "yyyymmdd")
            elseif field_number == 9
                strike_price = parse(Float64, decode(d, String))
            elseif field_number == 10
                upper_strike_price = parse(Float64, decode(d, String))
            elseif field_number == 11
                lower_strike_price = parse(Float64, decode(d, String))
            elseif field_number == 12
                outstanding_qty = parse(Int64, decode(d, String))
            elseif field_number == 13
                outstanding_ratio = parse(Float64, decode(d, String))
            elseif field_number == 14
                premium = parse(Float64, decode(d, String))
            elseif field_number == 15
                itm_otm = parse(Float64, decode(d, String))
            elseif field_number == 16
                implied_volatility = parse(Float64, decode(d, String))
            elseif field_number == 17
                delta = parse(Float64, decode(d, String))
            elseif field_number == 18
                call_price = parse(Float64, decode(d, String))
            elseif field_number == 19
                to_call_price = parse(Float64, decode(d, String))
            elseif field_number == 20
                effective_leverage = parse(Float64, decode(d, String))
            elseif field_number == 21
                leverage_ratio = parse(Float64, decode(d, String))
            elseif field_number == 22
                conversion_ratio = parse(Float64, decode(d, String))
            elseif field_number == 23
                balance_point = parse(Float64, decode(d, String))
            elseif field_number == 24
                status = decode(d, Int64)
            else
                skip(d, wire_type)
            end
        end
        return FilterWarrant(symbol, name, last_done, change_rate, change_val, volume, turnover, expiry_date, strike_price, upper_strike_price, lower_strike_price, outstanding_qty, outstanding_ratio, premium, itm_otm, implied_volatility, delta, call_price, to_call_price, effective_leverage, leverage_ratio, conversion_ratio, balance_point, status)
    end

    struct WarrantFilterListResponse
        warrant_list::Vector{FilterWarrant}
        total_count::Int64
    end
    default_values(::Type{WarrantFilterListResponse}) = (;warrant_list = FilterWarrant[], total_count = zero(Int64))
    field_numbers(::Type{WarrantFilterListResponse}) = (;warrant_list = 1, total_count = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:WarrantFilterListResponse})
        warrant_list = FilterWarrant[]
        total_count = zero(Int64)
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(warrant_list, decode(sub_d, FilterWarrant))
            elseif field_number == 2
                total_count = decode(d, Int64)
            else
                skip(d, wire_type)
            end
        end
        return WarrantFilterListResponse(warrant_list, total_count)
    end

    # 交易时段信息
    struct TradePeriod
        beg_time::Int64
        end_time::Int64
        trade_session::TradeSession.T
    end
    default_values(::Type{TradePeriod}) = (;beg_time = Int64(0), end_time = Int64(0), trade_session = TradeSession.Intraday)
    field_numbers(::Type{TradePeriod}) = (;beg_time = 1, end_time = 2, trade_session = 3)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:TradePeriod})
        beg_time = Int64(0)
        end_time = Int64(0)
        trade_session = TradeSession.Intraday
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                beg_time = decode(d, Int64)
            elseif field_number == 2
                end_time = decode(d, Int64)
            elseif field_number == 3
                trade_session = TradeSession.T(decode(d, Int64))
            else
                skip(d, wire_type)
            end
        end
        return TradePeriod(beg_time, end_time, trade_session)
    end

    # 市场交易时段信息
    struct MarketTradePeriod
        market::String
        trade_session::Vector{TradePeriod}
    end
    MarketTradePeriod() = MarketTradePeriod("", TradePeriod[])
    default_values(::Type{MarketTradePeriod}) = (;market = "", trade_session = TradePeriod[])
    field_numbers(::Type{MarketTradePeriod}) = (;market = 1, trade_session = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:MarketTradePeriod})
        market = ""
        trade_session = TradePeriod[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                market = decode(d, String)
            elseif field_number == 2
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(trade_session, decode(sub_d, TradePeriod))
            else
                skip(d, wire_type)
            end
        end
        return MarketTradePeriod(market, trade_session)
    end

    # 查询各市场的当日交易时段响应
    struct MarketTradePeriodResponse
        market_trade_session::Vector{MarketTradePeriod}
    end
    MarketTradePeriodResponse() = MarketTradePeriodResponse(MarketTradePeriod[])
    default_values(::Type{MarketTradePeriodResponse}) = (;market_trade_session = MarketTradePeriod[])
    field_numbers(::Type{MarketTradePeriodResponse}) = (;market_trade_session = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:MarketTradePeriodResponse})
        market_trade_session = MarketTradePeriod[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(market_trade_session, decode(sub_d, MarketTradePeriod))
            else
                skip(d, wire_type)
            end
        end
        return MarketTradePeriodResponse(market_trade_session)
    end

    struct MarketTradeDayRequest
        market::String
        beg_day::Date
        end_day::Date
    end

    default_values(::Type{MarketTradeDayRequest}) = (;market = "", beg_day = Date(1970,1,1), end_day = Date(1970,1,1))
    field_numbers(::Type{MarketTradeDayRequest}) = (;market = 1, beg_day = 2, end_day = 3)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::MarketTradeDayRequest)
        initpos = position(e.io)
        !isempty(x.market) && encode(e, 1, x.market)
        encode(e, 2, Dates.format(x.beg_day, "yyyymmdd"))
        encode(e, 3, Dates.format(x.end_day, "yyyymmdd"))
        return position(e.io) - initpos
    end

    function _encoded_size(x::MarketTradeDayRequest)
        encoded_size = 0
        !isempty(x.market) && (encoded_size += _encoded_size(x.market, 1))
        encoded_size += _encoded_size(Dates.format(x.beg_day, "yyyymmdd"), 2)
        encoded_size += _encoded_size(Dates.format(x.end_day, "yyyymmdd"), 3)
        return encoded_size
    end

    struct MarketTradeDayResponse
        trade_day::Vector{Date}
        half_trade_day::Vector{Date}
    end
    MarketTradeDayResponse() = MarketTradeDayResponse(Date[], Date[])
    default_values(::Type{MarketTradeDayResponse}) = (;trade_day = Date[], half_trade_day = Date[])
    field_numbers(::Type{MarketTradeDayResponse}) = (;trade_day = 1, half_trade_day = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:MarketTradeDayResponse})
        trade_day = Date[]
        half_trade_day = Date[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                push!(trade_day, Date(decode(d, String), "yyyymmdd"))
            elseif field_number == 2
                push!(half_trade_day, Date(decode(d, String), "yyyymmdd"))
            else
                skip(d, wire_type)
            end
        end
        return MarketTradeDayResponse(trade_day, half_trade_day)
    end

    # --- Capital Flow ---

    # CapitalFlowLine
    struct CapitalFlowLine
        inflow::Float64             # 净流入
        timestamp::Int64            # 分钟开始时间戳
    end
    default_values(::Type{CapitalFlowLine}) = (;inflow = 0.0, timestamp = 0)
    field_numbers(::Type{CapitalFlowLine}) = (;inflow = 1, timestamp = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:CapitalFlowLine})
        inflow = 0.0
        timestamp = 0
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                inflow = parse(Float64, decode(d, String))
            elseif field_number == 2
                timestamp = decode(d, Int64)
            else
                skip(d, wire_type)
            end
        end
        return CapitalFlowLine(inflow, timestamp)
    end

    # CapitalFlowIntradayRequest
    struct CapitalFlowIntradayRequest
        symbol::String
    end
    default_values(::Type{CapitalFlowIntradayRequest}) = (;symbol = "")
    field_numbers(::Type{CapitalFlowIntradayRequest}) = (;symbol = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:CapitalFlowIntradayRequest})
        symbol = ""
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            else
                skip(d, wire_type)
            end
        end
        return CapitalFlowIntradayRequest(symbol)
    end

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::CapitalFlowIntradayRequest)
        initpos = position(e.io)
        !isempty(x.symbol) && encode(e, 1, x.symbol)
        return position(e.io) - initpos
    end

    function _encoded_size(x::CapitalFlowIntradayRequest)
        encoded_size = 0
        !isempty(x.symbol) && (encoded_size += _encoded_size(x.symbol, 1))
        return encoded_size
    end

    # CapitalFlowIntradayResponse
    struct CapitalFlowIntradayResponse
        symbol::String
        capital_flow_lines::Vector{CapitalFlowLine}
    end
    default_values(::Type{CapitalFlowIntradayResponse}) = (;symbol = "", capital_flow_lines = CapitalFlowLine[])
    field_numbers(::Type{CapitalFlowIntradayResponse}) = (;symbol = 1, capital_flow_lines = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:CapitalFlowIntradayResponse})
        symbol = ""
        capital_flow_lines = CapitalFlowLine[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(capital_flow_lines, decode(sub_d, CapitalFlowLine))
            else
                skip(d, wire_type)
            end
        end
        return CapitalFlowIntradayResponse(symbol, capital_flow_lines)
    end

    # CapitalDistribution
    struct CapitalDistribution
        large::Float64
        medium::Float64
        small::Float64
    end
    default_values(::Type{CapitalDistribution}) = (;large = 0.0, medium = 0.0, small = 0.0)
    field_numbers(::Type{CapitalDistribution}) = (;large = 1, medium = 2, small = 3)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:CapitalDistribution})
        large = 0.0
        medium = 0.0
        small = 0.0
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                large = parse(Float64, decode(d, String))
            elseif field_number == 2
                medium = parse(Float64, decode(d, String))
            elseif field_number == 3
                small = parse(Float64, decode(d, String))
            else
                skip(d, wire_type)
            end
        end
        return CapitalDistribution(large, medium, small)
    end

    # CapitalDistributionResponse
    struct CapitalDistributionResponse
        symbol::String
        timestamp::Int64                    # 数据更新时间戳
        capital_in::CapitalDistribution
        capital_out::CapitalDistribution
    end
    default_values(::Type{CapitalDistributionResponse}) = (;symbol = "", timestamp = 0, capital_in = CapitalDistribution(0.0, 0.0, 0.0), capital_out = CapitalDistribution(0.0, 0.0, 0.0))
    field_numbers(::Type{CapitalDistributionResponse}) = (;symbol = 1, timestamp = 2, capital_in = 3, capital_out = 4)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:CapitalDistributionResponse})
        symbol = ""
        timestamp = 0
        capital_in = nothing
        capital_out = nothing
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                timestamp = decode(d, Int64)
            elseif field_number == 3
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                capital_in = decode(sub_d, CapitalDistribution)
            elseif field_number == 4
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                capital_out = decode(sub_d, CapitalDistribution)
            else
                skip(d, wire_type)
            end
        end
        return CapitalDistributionResponse(symbol, timestamp, capital_in, capital_out)
    end

    struct SecurityCalcQuoteRequest
        symbols::Vector{String}
        calc_index::Vector{CalcIndex.T}
    end

    default_values(::Type{SecurityCalcQuoteRequest}) = (;symbols = String[], calc_index = CalcIndex.T[])
    field_numbers(::Type{SecurityCalcQuoteRequest}) = (;symbols = 1, calc_index = 2)

    function encode(e::ProtoBuf.AbstractProtoEncoder, x::SecurityCalcQuoteRequest)
        initpos = position(e.io)
        !isempty(x.symbols) && encode(e, 1, x.symbols)
        !isempty(x.calc_index) && encode(e, 2, x.calc_index)
        return position(e.io) - initpos
    end

    function _encoded_size(x::SecurityCalcQuoteRequest)
        encoded_size = 0
        !isempty(x.symbols) && (encoded_size += _encoded_size(x.symbols, 1))
        !isempty(x.calc_index) && (encoded_size += _encoded_size(x.calc_index, 2))
        return encoded_size
    end

    struct SecurityCalcIndex
        symbol::String
        last_done::Float64
        change_val::Float64
        change_rate::Float64
        volume::Int64
        turnover::Float64
        ytd_change_rate::Float64
        turnover_rate::Float64
        total_market_value::Float64
        capital_flow::Float64
        amplitude::Float64
        volume_ratio::Float64
        pe_ttm_ratio::Float64
        pb_ratio::Float64
        dividend_ratio_ttm::Float64
        five_day_change_rate::Float64
        ten_day_change_rate::Float64
        half_year_change_rate::Float64
        five_minutes_change_rate::Float64
        expiry_date::Date
        strike_price::Float64
        upper_strike_price::Float64
        lower_strike_price::Float64
        outstanding_qty::Int64
        outstanding_ratio::Float64
        premium::Float64
        itm_otm::Float64
        implied_volatility::Float64
        warrant_delta::Float64
        call_price::Float64
        to_call_price::Float64
        effective_leverage::Float64
        leverage_ratio::Float64
        conversion_ratio::Float64
        balance_point::Float64
        open_interest::Int64
        delta::Float64
        gamma::Float64
        theta::Float64
        vega::Float64
        rho::Float64
    end

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityCalcIndex})
        # Initialize fields with default values
        symbol = ""
        last_done = 0.0
        change_val = 0.0
        change_rate = 0.0
        volume = Int64(0)
        turnover = 0.0
        ytd_change_rate = 0.0
        turnover_rate = 0.0
        total_market_value = 0.0
        capital_flow = 0.0
        amplitude = 0.0
        volume_ratio = 0.0
        pe_ttm_ratio = 0.0
        pb_ratio = 0.0
        dividend_ratio_ttm = 0.0
        five_day_change_rate = 0.0
        ten_day_change_rate = 0.0
        half_year_change_rate = 0.0
        five_minutes_change_rate = 0.0
        expiry_date = Date(1970, 1, 1)
        strike_price = 0.0
        upper_strike_price = 0.0
        lower_strike_price = 0.0
        outstanding_qty = Int64(0)
        outstanding_ratio = 0.0
        premium = 0.0
        itm_otm = 0.0
        implied_volatility = 0.0
        warrant_delta = 0.0
        call_price = 0.0
        to_call_price = 0.0
        effective_leverage = 0.0
        leverage_ratio = 0.0
        conversion_ratio = 0.0
        balance_point = 0.0
        open_interest = Int64(0)
        delta = 0.0
        gamma = 0.0
        theta = 0.0
        vega = 0.0
        rho = 0.0

        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                symbol = decode(d, String)
            elseif field_number == 2
                last_done = parse(Float64, decode(d, String))
            elseif field_number == 3
                change_val = parse(Float64, decode(d, String))
            elseif field_number == 4
                change_rate = parse(Float64, decode(d, String))
            elseif field_number == 5
                volume = decode(d, Int64)
            elseif field_number == 6
                turnover = parse(Float64, decode(d, String))
            elseif field_number == 7
                ytd_change_rate = parse(Float64, decode(d, String))
            elseif field_number == 8
                turnover_rate = parse(Float64, decode(d, String))
            elseif field_number == 9
                total_market_value = parse(Float64, decode(d, String))
            elseif field_number == 10
                capital_flow = parse(Float64, decode(d, String))
            elseif field_number == 11
                amplitude = parse(Float64, decode(d, String))
            elseif field_number == 12
                volume_ratio = parse(Float64, decode(d, String))
            elseif field_number == 13
                pe_ttm_ratio = parse(Float64, decode(d, String))
            elseif field_number == 14
                pb_ratio = parse(Float64, decode(d, String))
            elseif field_number == 15
                dividend_ratio_ttm = parse(Float64, decode(d, String))
            elseif field_number == 16
                five_day_change_rate = parse(Float64, decode(d, String))
            elseif field_number == 17
                ten_day_change_rate = parse(Float64, decode(d, String))
            elseif field_number == 18
                half_year_change_rate = parse(Float64, decode(d, String))
            elseif field_number == 19
                five_minutes_change_rate = parse(Float64, decode(d, String))
            elseif field_number == 20
                expiry_date = Date(decode(d, String), "yyyymmdd")
            elseif field_number == 21
                strike_price = parse(Float64, decode(d, String))
            elseif field_number == 22
                upper_strike_price = parse(Float64, decode(d, String))
            elseif field_number == 23
                lower_strike_price = parse(Float64, decode(d, String))
            elseif field_number == 24
                outstanding_qty = decode(d, Int64)
            elseif field_number == 25
                outstanding_ratio = parse(Float64, decode(d, String))
            elseif field_number == 26
                premium = parse(Float64, decode(d, String))
            elseif field_number == 27
                itm_otm = parse(Float64, decode(d, String))
            elseif field_number == 28
                implied_volatility = parse(Float64, decode(d, String))
            elseif field_number == 29
                warrant_delta = parse(Float64, decode(d, String))
            elseif field_number == 30
                call_price = parse(Float64, decode(d, String))
            elseif field_number == 31
                to_call_price = parse(Float64, decode(d, String))
            elseif field_number == 32
                effective_leverage = parse(Float64, decode(d, String))
            elseif field_number == 33
                leverage_ratio = parse(Float64, decode(d, String))
            elseif field_number == 34
                conversion_ratio = parse(Float64, decode(d, String))
            elseif field_number == 35
                balance_point = parse(Float64, decode(d, String))
            elseif field_number == 36
                open_interest = decode(d, Int64)
            elseif field_number == 37
                delta = parse(Float64, decode(d, String))
            elseif field_number == 38
                gamma = parse(Float64, decode(d, String))
            elseif field_number == 39
                theta = parse(Float64, decode(d, String))
            elseif field_number == 40
                vega = parse(Float64, decode(d, String))
            elseif field_number == 41
                rho = parse(Float64, decode(d, String))
            else
                skip(d, wire_type)
            end
        end

        return SecurityCalcIndex(
            symbol, last_done, change_val, change_rate, volume, turnover, ytd_change_rate,
            turnover_rate, total_market_value, capital_flow, amplitude, volume_ratio,
            pe_ttm_ratio, pb_ratio, dividend_ratio_ttm, five_day_change_rate,
            ten_day_change_rate, half_year_change_rate, five_minutes_change_rate,
            expiry_date, strike_price, upper_strike_price, lower_strike_price,
            outstanding_qty, outstanding_ratio, premium, itm_otm, implied_volatility,
            warrant_delta, call_price, to_call_price, effective_leverage,
            leverage_ratio, conversion_ratio, balance_point, open_interest, delta,
            gamma, theta, vega, rho
        )
    end

    struct SecurityCalcQuoteResponse
        security_calc_index::Vector{SecurityCalcIndex}
    end

    default_values(::Type{SecurityCalcQuoteResponse}) = (;security_calc_index = SecurityCalcIndex[])
    field_numbers(::Type{SecurityCalcQuoteResponse}) = (;security_calc_index = 1)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:SecurityCalcQuoteResponse})
        security_calc_index = SecurityCalcIndex[]
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(security_calc_index, decode(sub_d, SecurityCalcIndex))
            else
                skip(d, wire_type)
            end
        end
        return SecurityCalcQuoteResponse(security_calc_index)
    end

    """
    Market Temperature information
    """
    struct MarketTemperatureResponse
        temperature::Union{Int, Nothing}
        description::String
        valuation::Union{Int, Nothing}
        sentiment::Union{Int, Nothing}
        updated_at::DateTime
    end

    default_values(::Type{MarketTemperatureResponse}) = (;temperature = nothing, description = "", valuation = nothing, sentiment = nothing, updated_at = DateTime(1970,1,1))
    field_numbers(::Type{MarketTemperatureResponse}) = (;temperature = 1, description = 2, valuation = 3, sentiment = 4, updated_at = 5)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:MarketTemperatureResponse})
        temperature = nothing
        description = ""
        valuation = nothing
        sentiment = nothing
        updated_at = DateTime(1970,1,1)
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                temperature = decode(d, Int)
            elseif field_number == 2
                description = decode(d, String)
            elseif field_number == 3
                valuation = decode(d, Int)
            elseif field_number == 4
                sentiment = decode(d, Int)
            elseif field_number == 5
                updated_at = unix2datetime(parse(Int, decode(d, String)))
            else
                skip(d, wire_type)
            end
        end
        return MarketTemperatureResponse(temperature, description, valuation, sentiment, updated_at)
    end

    struct MarketTemperature
        timestamp::Int64
        temperature::Int32
        valuation::Int32
        sentiment::Int32
    end

    default_values(::Type{MarketTemperature}) = (;timestamp = 0, temperature = 0, valuation = 0, sentiment = 0)
    field_numbers(::Type{MarketTemperature}) = (;timestamp = 1, temperature = 2, valuation = 3, sentiment = 4)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:MarketTemperature})
        timestamp = 0
        temperature = 0     # 温度值
        valuation = 0       # 估值值
        sentiment = 0       # 情绪值
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                timestamp = decode(d, Int64)
            elseif field_number == 2
                temperature = decode(d, Int32)
            elseif field_number == 3
                valuation = decode(d, Int32)
            elseif field_number == 4
                sentiment = decode(d, Int32)
            else
                skip(d, wire_type)
            end
        end
        return MarketTemperature(timestamp, temperature, valuation, sentiment)
    end

    struct HistoryMarketTemperatureResponse
        list::Vector{MarketTemperature}
        type::String
    end

    default_values(::Type{HistoryMarketTemperatureResponse}) = (;list = MarketTemperature[], type = "")
    field_numbers(::Type{HistoryMarketTemperatureResponse}) = (;list = 1, type = 2)

    function decode(d::ProtoBuf.AbstractProtoDecoder, ::Type{<:HistoryMarketTemperatureResponse})
        list = MarketTemperature[]
        type = ""
        while !message_done(d)
            field_number, wire_type = decode_tag(d)
            if field_number == 1
                len = decode(d, UInt64)
                sub_d = ProtoDecoder(IOBuffer(read(d.io, len)))
                push!(list, decode(sub_d, MarketTemperature))
            elseif field_number == 2
                type = decode(d, String)
            else
                skip(d, wire_type)
            end
        end
        return HistoryMarketTemperatureResponse(list, type)
    end

   
end # module
