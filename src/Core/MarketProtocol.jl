module MarketProtocol

using EnumX, JSON, Dates
using ..Utils: Dec64, JSONObject, counter_id_to_symbol, to_china_time
using ..Constant: Market
import ..Utils: _parse_optional_decimal, construct

export BrokerHoldingPeriod,
    AhPremiumPeriod,
    MarketTradeStatus,
    MarketTimeItem,
    MarketStatusResponse,
    BrokerHoldingEntry,
    BrokerHoldingTop,
    BrokerHoldingChanges,
    BrokerHoldingDetailItem,
    BrokerHoldingDetail,
    BrokerHoldingDailyItem,
    BrokerHoldingDailyHistory,
    AhPremiumKline,
    AhPremiumKlines,
    AhPremiumIntraday,
    TradeStatistics,
    TradePriceLevel,
    TradeStatsResponse,
    AnomalyItem,
    AnomalyResponse,
    ConstituentStock,
    IndexConstituents,
    TopMoversStock,
    TopMoversEvent,
    TopMoversResponse,
    RankCategoriesResponse,
    RankListItem,
    RankListResponse,
    _broker_holding_period_str,
    _ah_premium_period_line_type,
    _market_from_str,
    _market_trade_status_from_int,
    _market_trade_status_code,
    _market_trade_status_name,
    _market_trade_status_label,
    _market_trade_status_normalize,
    _market_trade_status_is_us_market,
    _market_trade_status_is_us_pre_post,
    _market_trade_status_is_us_night,
    _market_trade_status_is_us_closing,
    _market_trade_status_is_closing,
    _market_trade_status_is_us_prev,
    _market_trade_status_is_us_after,
    _market_trade_status_is_trading,
    _market_trade_status_is_dark,
    _market_trade_status_allow_trading,
    _market_trade_status_is_special

@enumx BrokerHoldingPeriod begin
    Rct1 = 1   # 1 日变化
    Rct5 = 5   # 5 日变化
    Rct20 = 20  # 20 日变化
    Rct60 = 60  # 60 日变化
end

@enumx AhPremiumPeriod begin
    Min1 = 1
    Min5 = 5
    Min15 = 15
    Min30 = 30
    Min60 = 60
    Day = 1000
    Week = 2000
    Month = 3000
    Year = 4000
end

function _broker_holding_period_str(p::BrokerHoldingPeriod.T)
    p === BrokerHoldingPeriod.Rct1 ? "rct_1" :
    p === BrokerHoldingPeriod.Rct5 ? "rct_5" :
    p === BrokerHoldingPeriod.Rct20 ? "rct_20" :
    p === BrokerHoldingPeriod.Rct60 ? "rct_60" : error("unknown BrokerHoldingPeriod: $p")
end

function _ah_premium_period_line_type(p::AhPremiumPeriod.T)
    p === AhPremiumPeriod.Min1 ? "1" :
    p === AhPremiumPeriod.Min5 ? "5" :
    p === AhPremiumPeriod.Min15 ? "15" :
    p === AhPremiumPeriod.Min30 ? "30" :
    p === AhPremiumPeriod.Min60 ? "60" :
    p === AhPremiumPeriod.Day ? "1000" :
    p === AhPremiumPeriod.Week ? "2000" :
    p === AhPremiumPeriod.Month ? "3000" :
    p === AhPremiumPeriod.Year ? "4000" : error("unknown AhPremiumPeriod: $p")
end

function _market_from_str(s::AbstractString)
    s == "US" ? Market.US :
    s == "HK" ? Market.HK : s == "CN" ? Market.CN : s == "SG" ? Market.SG : Market.Unknown
end

const RawJSON = Union{JSON.Object{String,Any},Dict{String,Any},Vector{Any},Nothing}

# ── market_status ──────────────────────────────────────────────────

@enumx TradeStatus begin
    UNKNOWN = -1
    NO_REGISTER_QUOTE = 0
    CLEAN = 101
    OPEN_BID = 102
    MORNING_CLOSING = 103
    TRADING = 105
    NOON_CLOSING = 106
    CLOSE_BID = 107
    CLOSING = 108
    DARK_WAIT = 110
    DARK_TRADING = 111
    DARK_CLOSING = 112
    AFTER_FIX = 120
    HALF_CLOSING = 121
    NOT_OPENED = 122
    REALTIME_QUOTE = 123
    US_PREV = 201
    US_TRADING = 202
    US_AFTER = 203
    US_CLOSING = 204
    US_STOP = 205
    US_CLEAN = 206
    US_NIGHT = 207
    US_PREV_MARKET_CLEAN = 209
    US_AFTER_MARKET_CLEAN = 210
    REFRESH = 1000
    DELIST = 1001
    PREPARE = 1002
    CODE_CHANGE = 1003
    STOP = 1004
    WILL_OPEN = 1005
    COMMON_SUSPEND = 1006
    EXPIRE = 1007
    NO_QUOTE = 1008
    UNITED = 1009
    TRADING_HALT = 1010
    WAIT_LISTING = 1011
    FUSE = 2001
end

const MarketTradeStatus = TradeStatus

function _market_trade_status_from_int(n::Integer)::TradeStatus.T
    n == -1 ? TradeStatus.UNKNOWN :
    n == 0 ? TradeStatus.NO_REGISTER_QUOTE :
    n == 101 ? TradeStatus.CLEAN :
    n == 102 ? TradeStatus.OPEN_BID :
    n == 103 ? TradeStatus.MORNING_CLOSING :
    n == 105 ? TradeStatus.TRADING :
    n == 106 ? TradeStatus.NOON_CLOSING :
    n == 107 ? TradeStatus.CLOSE_BID :
    n == 108 ? TradeStatus.CLOSING :
    n == 110 ? TradeStatus.DARK_WAIT :
    n == 111 ? TradeStatus.DARK_TRADING :
    n == 112 ? TradeStatus.DARK_CLOSING :
    n == 120 ? TradeStatus.AFTER_FIX :
    n == 121 ? TradeStatus.HALF_CLOSING :
    n == 122 ? TradeStatus.NOT_OPENED :
    n == 123 ? TradeStatus.REALTIME_QUOTE :
    n == 201 ? TradeStatus.US_PREV :
    n == 202 ? TradeStatus.US_TRADING :
    n == 203 ? TradeStatus.US_AFTER :
    n == 204 ? TradeStatus.US_CLOSING :
    n == 205 ? TradeStatus.US_STOP :
    n == 206 ? TradeStatus.US_CLEAN :
    n == 207 ? TradeStatus.US_NIGHT :
    n == 209 ? TradeStatus.US_PREV_MARKET_CLEAN :
    n == 210 ? TradeStatus.US_AFTER_MARKET_CLEAN :
    n == 1000 ? TradeStatus.REFRESH :
    n == 1001 ? TradeStatus.DELIST :
    n == 1002 ? TradeStatus.PREPARE :
    n == 1003 ? TradeStatus.CODE_CHANGE :
    n == 1004 ? TradeStatus.STOP :
    n == 1005 ? TradeStatus.WILL_OPEN :
    n == 1006 ? TradeStatus.COMMON_SUSPEND :
    n == 1007 ? TradeStatus.EXPIRE :
    n == 1008 ? TradeStatus.NO_QUOTE :
    n == 1009 ? TradeStatus.UNITED :
    n == 1010 ? TradeStatus.TRADING_HALT :
    n == 1011 ? TradeStatus.WAIT_LISTING :
    n == 2001 ? TradeStatus.FUSE : TradeStatus.UNKNOWN
end

_market_trade_status_from_value(v::TradeStatus.T) = v
function _market_trade_status_from_value(v)::TradeStatus.T
    isnothing(v) && return TradeStatus.UNKNOWN
    if v isa AbstractString
        n = tryparse(Int, String(v))
        isnothing(n) && return TradeStatus.UNKNOWN
        return _market_trade_status_from_int(n)
    end
    v isa Number && return _market_trade_status_from_int(Int(v))
    TradeStatus.UNKNOWN
end

_market_trade_status_code(status::TradeStatus.T)::Int = Int(status)

function _market_trade_status_normalize(status::TradeStatus.T)::TradeStatus.T
    status === TradeStatus.CLEAN ? TradeStatus.CLOSING :
    status === TradeStatus.US_PREV_MARKET_CLEAN ? TradeStatus.US_CLOSING :
    status === TradeStatus.US_CLEAN ? TradeStatus.US_PREV :
    status === TradeStatus.US_AFTER_MARKET_CLEAN ? TradeStatus.US_TRADING : status
end

function _market_trade_status_name(status::TradeStatus.T)::String
    normalized = _market_trade_status_normalize(status)
    normalized === TradeStatus.UNKNOWN || normalized === TradeStatus.NO_REGISTER_QUOTE ? "Unknown" :
    normalized === TradeStatus.OPEN_BID ? "Open Bid" :
    normalized === TradeStatus.MORNING_CLOSING ? "Morning Break" :
    normalized === TradeStatus.TRADING || normalized === TradeStatus.US_TRADING ? "Trading" :
    normalized === TradeStatus.NOON_CLOSING ? "Mid-Day Break" :
    normalized === TradeStatus.CLOSE_BID ? "Close Bid" :
    normalized === TradeStatus.CLOSING ||
        normalized === TradeStatus.HALF_CLOSING ||
        normalized === TradeStatus.US_CLOSING ? "Closed" :
    normalized === TradeStatus.DARK_WAIT ? "Dark Wait" :
    normalized === TradeStatus.DARK_TRADING ? "Dark Trading" :
    normalized === TradeStatus.DARK_CLOSING ? "Closing" :
    normalized === TradeStatus.AFTER_FIX ? "After Fix" :
    normalized === TradeStatus.NOT_OPENED ? "Not Open" :
    normalized === TradeStatus.REALTIME_QUOTE ? "Temporary Break" :
    normalized === TradeStatus.US_PREV ? "Pre-Market" :
    normalized === TradeStatus.US_AFTER ? "Post-Market" :
    normalized === TradeStatus.US_STOP || normalized === TradeStatus.STOP ? "Stop" :
    normalized === TradeStatus.US_NIGHT ? "Overnight" :
    normalized === TradeStatus.REFRESH ? "Refresh" :
    normalized === TradeStatus.DELIST ? "Delist" :
    normalized === TradeStatus.PREPARE ? "Prepare" :
    normalized === TradeStatus.CODE_CHANGE ? "Code Change" :
    normalized === TradeStatus.WILL_OPEN ? "Will Open" :
    normalized === TradeStatus.COMMON_SUSPEND ? "Common Suspend" :
    normalized === TradeStatus.EXPIRE ? "Expire" :
    normalized === TradeStatus.NO_QUOTE ? "No Quote" :
    normalized === TradeStatus.UNITED ? "Not Listed" :
    normalized === TradeStatus.TRADING_HALT ? "Terminated" :
    normalized === TradeStatus.WAIT_LISTING ? "Wait Listing" :
    normalized === TradeStatus.FUSE ? "Fuse" : "Unknown"
end

function _market_trade_status_label(status::TradeStatus.T)::String
    normalized = _market_trade_status_normalize(status)
    if normalized === TradeStatus.US_PREV ||
        normalized === TradeStatus.US_TRADING ||
        normalized === TradeStatus.US_AFTER ||
        normalized === TradeStatus.US_NIGHT ||
        normalized === TradeStatus.US_CLOSING ||
        normalized === TradeStatus.TRADING ||
        normalized === TradeStatus.CLOSING
        return _market_trade_status_name(normalized)
    end
    ""
end

_market_trade_status_is_us_market(status::TradeStatus.T)::Bool =
    200 <= _market_trade_status_code(status) < 300
_market_trade_status_is_us_prev(status::TradeStatus.T)::Bool =
    status === TradeStatus.US_PREV || status === TradeStatus.US_CLEAN
_market_trade_status_is_us_after(status::TradeStatus.T)::Bool =
    status === TradeStatus.US_AFTER
_market_trade_status_is_us_pre_post(status::TradeStatus.T)::Bool =
    _market_trade_status_is_us_prev(status) || _market_trade_status_is_us_after(status)
_market_trade_status_is_us_night(status::TradeStatus.T)::Bool =
    status === TradeStatus.US_NIGHT
_market_trade_status_is_us_closing(status::TradeStatus.T)::Bool =
    status === TradeStatus.US_CLOSING || status === TradeStatus.US_PREV_MARKET_CLEAN
_market_trade_status_is_closing(status::TradeStatus.T)::Bool =
    status === TradeStatus.US_CLOSING ||
    status === TradeStatus.US_PREV_MARKET_CLEAN ||
    status === TradeStatus.CLOSING ||
    status === TradeStatus.HALF_CLOSING
_market_trade_status_is_trading(status::TradeStatus.T)::Bool =
    status === TradeStatus.TRADING ||
    status === TradeStatus.US_TRADING ||
    status === TradeStatus.US_AFTER_MARKET_CLEAN
_market_trade_status_is_dark(status::TradeStatus.T)::Bool =
    status === TradeStatus.DARK_WAIT ||
    status === TradeStatus.DARK_TRADING ||
    status === TradeStatus.DARK_CLOSING
_market_trade_status_allow_trading(status::TradeStatus.T)::Bool =
    status === TradeStatus.OPEN_BID ||
    status === TradeStatus.TRADING ||
    status === TradeStatus.CLOSE_BID ||
    status === TradeStatus.NOT_OPENED ||
    status === TradeStatus.NOON_CLOSING ||
    status === TradeStatus.US_TRADING ||
    status === TradeStatus.US_AFTER_MARKET_CLEAN
_market_trade_status_is_special(status::TradeStatus.T)::Bool =
    _market_trade_status_code(status) < 100 ||
    status === TradeStatus.US_STOP ||
    _market_trade_status_code(status) >= 1000

struct MarketTimeItem
    market::Market.T
    trade_status::TradeStatus.T
    timestamp::String
    delay_trade_status::TradeStatus.T
    delay_timestamp::String
    sub_status::Int
    delay_sub_status::Int
end
function construct(::Type{MarketTimeItem}, obj::JSONObject)
    MarketTimeItem(
        _market_from_str(String(get(obj, :market, ""))),
        _market_trade_status_from_value(get(obj, :trade_status, -1)),
        String(get(obj, :timestamp, "")),
        _market_trade_status_from_value(get(obj, :delay_trade_status, -1)),
        String(get(obj, :delay_timestamp, "")),
        Int(get(obj, :sub_status, 0)),
        Int(get(obj, :delay_sub_status, 0)),
    )
end

struct MarketStatusResponse
    market_time::Vector{MarketTimeItem}
end
function construct(::Type{MarketStatusResponse}, obj::JSONObject)
    items = if haskey(obj, :market_time) && !isnothing(obj.market_time)
        [construct(MarketTimeItem, x) for x in obj.market_time]
    else
        MarketTimeItem[]
    end
    MarketStatusResponse(items)
end

# ── broker_holding (top) ───────────────────────────────────────────

struct BrokerHoldingEntry
    name::String
    parti_number::String
    chg::Union{Dec64,Nothing}
    strong::Bool
end
function construct(::Type{BrokerHoldingEntry}, obj::JSONObject)
    BrokerHoldingEntry(
        String(get(obj, :name, "")),
        String(get(obj, :parti_number, "")),
        _parse_optional_decimal(get(obj, :chg, nothing)),
        Bool(get(obj, :strong, false)),
    )
end

struct BrokerHoldingTop
    buy::Vector{BrokerHoldingEntry}
    sell::Vector{BrokerHoldingEntry}
    updated_at::String
end
function construct(::Type{BrokerHoldingTop}, obj::JSONObject)
    _list(key) =
        if haskey(obj, key) && !isnothing(obj[key])
            [construct(BrokerHoldingEntry, x) for x in obj[key]]
        else
            BrokerHoldingEntry[]
        end
    BrokerHoldingTop(_list(:buy), _list(:sell), String(get(obj, :updated_at, "")))
end

# ── broker_holding (detail) ────────────────────────────────────────

struct BrokerHoldingChanges
    value::Union{Dec64,Nothing}
    chg_1::Union{Dec64,Nothing}
    chg_5::Union{Dec64,Nothing}
    chg_20::Union{Dec64,Nothing}
    chg_60::Union{Dec64,Nothing}
end
function construct(::Type{BrokerHoldingChanges}, obj::JSONObject)
    BrokerHoldingChanges(
        _parse_optional_decimal(get(obj, :value, nothing)),
        _parse_optional_decimal(get(obj, :chg_1, nothing)),
        _parse_optional_decimal(get(obj, :chg_5, nothing)),
        _parse_optional_decimal(get(obj, :chg_20, nothing)),
        _parse_optional_decimal(get(obj, :chg_60, nothing)),
    )
end

struct BrokerHoldingDetailItem
    name::String
    parti_number::String
    ratio::BrokerHoldingChanges
    shares::BrokerHoldingChanges
    strong::Bool
end
function construct(::Type{BrokerHoldingDetailItem}, obj::JSONObject)
    BrokerHoldingDetailItem(
        String(get(obj, :name, "")),
        String(get(obj, :parti_number, "")),
        construct(BrokerHoldingChanges, obj.ratio),
        construct(BrokerHoldingChanges, obj.shares),
        Bool(get(obj, :strong, false)),
    )
end

struct BrokerHoldingDetail
    list::Vector{BrokerHoldingDetailItem}
    updated_at::String
end
function construct(::Type{BrokerHoldingDetail}, obj::JSONObject)
    items = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(BrokerHoldingDetailItem, x) for x in obj.list]
    else
        BrokerHoldingDetailItem[]
    end
    BrokerHoldingDetail(items, String(get(obj, :updated_at, "")))
end

# ── broker_holding (daily) ─────────────────────────────────────────

struct BrokerHoldingDailyItem
    date::String
    holding::Union{Dec64,Nothing}
    ratio::Union{Dec64,Nothing}
    chg::Union{Dec64,Nothing}
end
function construct(::Type{BrokerHoldingDailyItem}, obj::JSONObject)
    BrokerHoldingDailyItem(
        String(get(obj, :date, "")),
        _parse_optional_decimal(get(obj, :holding, nothing)),
        _parse_optional_decimal(get(obj, :ratio, nothing)),
        _parse_optional_decimal(get(obj, :chg, nothing)),
    )
end

struct BrokerHoldingDailyHistory
    list::Vector{BrokerHoldingDailyItem}
end
function construct(::Type{BrokerHoldingDailyHistory}, obj::JSONObject)
    items = if haskey(obj, :list) && !isnothing(obj.list)
        [construct(BrokerHoldingDailyItem, x) for x in obj.list]
    else
        BrokerHoldingDailyItem[]
    end
    BrokerHoldingDailyHistory(items)
end

# ── ah_premium ─────────────────────────────────────────────────────

"""
`ah_premium` / `ah_premium_intraday` 中价格类字段在 API 缺失时返回空串。
上游用 `decimal_empty_is_0`：空串视为 0。非数字占位符（如 `"--"`）一并视作 0。
"""
function _decimal_empty_is_zero(v)
    (isnothing(v) || (v isa AbstractString && isempty(v))) && return Dec64(0)
    v isa Number && return Dec64(v)
    try
        return parse(Dec64, String(v))
    catch
        return Dec64(0)
    end
end

struct AhPremiumKline
    aprice::Dec64
    apreclose::Dec64
    hprice::Dec64
    hpreclose::Dec64
    currency_rate::Dec64
    ahpremium_rate::Dec64
    price_spread::Dec64
    timestamp::DateTime           # 转换为 UTC+8 时间
end
function construct(::Type{AhPremiumKline}, obj::JSONObject)
    AhPremiumKline(
        _decimal_empty_is_zero(get(obj, :aprice, "")),
        _decimal_empty_is_zero(get(obj, :apreclose, "")),
        _decimal_empty_is_zero(get(obj, :hprice, "")),
        _decimal_empty_is_zero(get(obj, :hpreclose, "")),
        _decimal_empty_is_zero(get(obj, :currency_rate, "")),
        _decimal_empty_is_zero(get(obj, :ahpremium_rate, "")),
        _decimal_empty_is_zero(get(obj, :price_spread, "")),
        to_china_time(
            obj.timestamp isa Number ? Int64(obj.timestamp) : String(obj.timestamp),
        ),
    )
end

struct AhPremiumKlines
    klines::Vector{AhPremiumKline}
end
function construct(::Type{AhPremiumKlines}, obj::JSONObject)
    items = if haskey(obj, :klines) && !isnothing(obj.klines)
        [construct(AhPremiumKline, x) for x in obj.klines]
    else
        AhPremiumKline[]
    end
    AhPremiumKlines(items)
end

# 上游 AhPremiumIntraday 的 JSON 字段名也叫 `klines`
struct AhPremiumIntraday
    klines::Vector{AhPremiumKline}
end
function construct(::Type{AhPremiumIntraday}, obj::JSONObject)
    items = if haskey(obj, :klines) && !isnothing(obj.klines)
        [construct(AhPremiumKline, x) for x in obj.klines]
    else
        AhPremiumKline[]
    end
    AhPremiumIntraday(items)
end

# ── trade_stats ────────────────────────────────────────────────────

struct TradeStatistics
    avgprice::Dec64
    buy::Dec64
    neutral::Dec64
    preclose::Dec64
    sell::Dec64
    timestamp::String
    total_amount::Dec64
    trade_date::Vector{String}
    trades_count::String
end
function construct(::Type{TradeStatistics}, obj::JSONObject)
    dates = if haskey(obj, :trade_date) && !isnothing(obj.trade_date)
        String[String(d) for d in obj.trade_date]
    else
        String[]
    end
    TradeStatistics(
        _decimal_empty_is_zero(get(obj, :avgprice, "")),
        _decimal_empty_is_zero(get(obj, :buy, "")),
        _decimal_empty_is_zero(get(obj, :neutral, "")),
        _decimal_empty_is_zero(get(obj, :preclose, "")),
        _decimal_empty_is_zero(get(obj, :sell, "")),
        String(get(obj, :timestamp, "")),
        _decimal_empty_is_zero(get(obj, :total_amount, "")),
        dates,
        String(get(obj, :trades_count, "")),
    )
end

struct TradePriceLevel
    buy_amount::Dec64
    neutral_amount::Dec64
    price::Dec64
    sell_amount::Dec64
end
function construct(::Type{TradePriceLevel}, obj::JSONObject)
    TradePriceLevel(
        _decimal_empty_is_zero(get(obj, :buy_amount, "")),
        _decimal_empty_is_zero(get(obj, :neutral_amount, "")),
        _decimal_empty_is_zero(get(obj, :price, "")),
        _decimal_empty_is_zero(get(obj, :sell_amount, "")),
    )
end

struct TradeStatsResponse
    statistics::TradeStatistics
    trades::Vector{TradePriceLevel}
end
function construct(::Type{TradeStatsResponse}, obj::JSONObject)
    trades = if haskey(obj, :trades) && !isnothing(obj.trades)
        [construct(TradePriceLevel, x) for x in obj.trades]
    else
        TradePriceLevel[]
    end
    TradeStatsResponse(construct(TradeStatistics, obj.statistics), trades)
end

# ── anomaly ────────────────────────────────────────────────────────

struct AnomalyItem
    symbol::String                     # 由 counter_id 转换
    name::String
    alert_name::String
    alert_time::Int64                  # 毫秒时间戳
    change_values::Vector{String}
    emotion::Int                       # 1=正向 2=负向
end
function construct(::Type{AnomalyItem}, obj::JSONObject)
    vals = if haskey(obj, :change_values) && !isnothing(obj.change_values)
        String[String(v) for v in obj.change_values]
    else
        String[]
    end
    AnomalyItem(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :name, "")),
        String(get(obj, :alert_name, "")),
        Int64(get(obj, :alert_time, 0)),
        vals,
        Int(get(obj, :emotion, 0)),
    )
end

struct AnomalyResponse
    all_off::Bool
    changes::Vector{AnomalyItem}
end
function construct(::Type{AnomalyResponse}, obj::JSONObject)
    items = if haskey(obj, :changes) && !isnothing(obj.changes)
        [construct(AnomalyItem, x) for x in obj.changes]
    else
        AnomalyItem[]
    end
    AnomalyResponse(Bool(get(obj, :all_off, false)), items)
end

# ── constituent ────────────────────────────────────────────────────

struct ConstituentStock
    symbol::String
    name::String
    last_done::Union{Dec64,Nothing}
    prev_close::Union{Dec64,Nothing}
    inflow::Union{Dec64,Nothing}
    balance::Union{Dec64,Nothing}
    amount::Union{Dec64,Nothing}
    total_shares::Union{Dec64,Nothing}
    tags::Vector{String}
    intro::String
    market::String
    circulating_shares::Union{Dec64,Nothing}
    delay::Bool
    chg::Union{Dec64,Nothing}
    trade_status::Int
end
function construct(::Type{ConstituentStock}, obj::JSONObject)
    tags = if haskey(obj, :tags) && !isnothing(obj.tags)
        String[String(t) for t in obj.tags]
    else
        String[]
    end
    ConstituentStock(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :name, "")),
        _parse_optional_decimal(get(obj, :last_done, nothing)),
        _parse_optional_decimal(get(obj, :prev_close, nothing)),
        _parse_optional_decimal(get(obj, :inflow, nothing)),
        _parse_optional_decimal(get(obj, :balance, nothing)),
        _parse_optional_decimal(get(obj, :amount, nothing)),
        _parse_optional_decimal(get(obj, :total_shares, nothing)),
        tags,
        String(get(obj, :intro, "")),
        String(get(obj, :market, "")),
        _parse_optional_decimal(get(obj, :circulating_shares, nothing)),
        Bool(get(obj, :delay, false)),
        _parse_optional_decimal(get(obj, :chg, nothing)),
        Int(get(obj, :trade_status, 0)),
    )
end

struct IndexConstituents
    fall_num::Int
    flat_num::Int
    rise_num::Int
    stocks::Vector{ConstituentStock}
end
function construct(::Type{IndexConstituents}, obj::JSONObject)
    items = if haskey(obj, :stocks) && !isnothing(obj.stocks)
        [construct(ConstituentStock, x) for x in obj.stocks]
    else
        ConstituentStock[]
    end
    IndexConstituents(
        Int(get(obj, :fall_num, 0)),
        Int(get(obj, :flat_num, 0)),
        Int(get(obj, :rise_num, 0)),
        items,
    )
end

# ── top_movers ─────────────────────────────────────────────────────

"""
`top_movers` 事件中的证券信息。`symbol` 由 `counter_id` 转换。
"""
struct TopMoversStock
    symbol::String
    code::String
    name::String
    full_name::String
    change::String
    last_done::String
    market::String
    labels::Vector{String}
    logo::String
end
function construct(::Type{TopMoversStock}, obj::JSONObject)
    labels = if haskey(obj, :labels) && !isnothing(obj.labels)
        String[String(l) for l in obj.labels]
    else
        String[]
    end
    TopMoversStock(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :code, "")),
        String(get(obj, :name, "")),
        String(get(obj, :full_name, "")),
        String(get(obj, :change, "")),
        String(get(obj, :last_done, "")),
        String(get(obj, :market, "")),
        labels,
        String(get(obj, :logo, "")),
    )
end

"""
`top_movers` 事件单条记录。`timestamp` 从 unix 秒转 `DateTime` (UTC)。
"""
struct TopMoversEvent
    timestamp::DateTime
    alert_reason::String
    alert_type::Int64
    stock::TopMoversStock
    post::RawJSON
end
function construct(::Type{TopMoversEvent}, obj::JSONObject)
    ts_raw = get(obj, :timestamp, 0)
    ts_int = ts_raw isa AbstractString ? parse(Int64, ts_raw) : Int64(ts_raw)
    stock_obj = get(obj, :stock, nothing)
    stock =
        stock_obj === nothing ? TopMoversStock("", "", "", "", "", "", "", String[], "") :
        construct(TopMoversStock, stock_obj)
    TopMoversEvent(
        unix2datetime(ts_int),
        String(get(obj, :alert_reason, "")),
        Int64(get(obj, :alert_type, 0)),
        stock,
        get(obj, :post, nothing),
    )
end

struct TopMoversResponse
    events::Vector{TopMoversEvent}
    next_params::RawJSON
end
function construct(::Type{TopMoversResponse}, obj::JSONObject)
    events = if haskey(obj, :events) && !isnothing(obj.events)
        [construct(TopMoversEvent, x) for x in obj.events]
    else
        TopMoversEvent[]
    end
    TopMoversResponse(events, get(obj, :next_params, nothing))
end

# ── rank_categories ────────────────────────────────────────────────

"""
排行榜分类元数据。结构因 API 演进而变，原样保留 JSON。
"""
struct RankCategoriesResponse
    data::RawJSON
end
construct(::Type{RankCategoriesResponse}, obj) = RankCategoriesResponse(obj)

# ── rank_list ──────────────────────────────────────────────────────

"""
排行榜单条记录。`symbol` 由 `counter_id` 转换；数值字段保留 API 原字符串。
"""
struct RankListItem
    symbol::String
    code::String
    name::String
    last_done::String
    chg::String
    change::String
    inflow::String
    market_cap::String
    industry::String
    pre_post_price::String
    pre_post_chg::String
    amplitude::String
    five_day_chg::String
    turnover_rate::String
    volume_rate::String
    pb_ttm::String
end
function construct(::Type{RankListItem}, obj::JSONObject)
    RankListItem(
        counter_id_to_symbol(String(get(obj, :counter_id, ""))),
        String(get(obj, :code, "")),
        String(get(obj, :name, "")),
        String(get(obj, :last_done, "")),
        String(get(obj, :chg, "")),
        String(get(obj, :change, "")),
        String(get(obj, :inflow, "")),
        String(get(obj, :market_cap, "")),
        String(get(obj, :industry, "")),
        String(get(obj, :pre_post_price, "")),
        String(get(obj, :pre_post_chg, "")),
        String(get(obj, :amplitude, "")),
        String(get(obj, :five_day_chg, "")),
        String(get(obj, :turnover_rate, "")),
        String(get(obj, :volume_rate, "")),
        String(get(obj, :pb_ttm, "")),
    )
end

struct RankListResponse
    bmp::Bool
    lists::Vector{RankListItem}
end
function construct(::Type{RankListResponse}, obj::JSONObject)
    items = if haskey(obj, :lists) && !isnothing(obj.lists)
        [construct(RankListItem, x) for x in obj.lists]
    else
        RankListItem[]
    end
    RankListResponse(Bool(get(obj, :bmp, false)), items)
end

end # module MarketProtocol
