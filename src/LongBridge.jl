module LongBridge

using TOML, Dates
using PrecompileTools: @setup_workload, @compile_workload

# Version
include_dependency(joinpath(@__DIR__, "..", "Project.toml"))
const VERSION = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))["version"]

# Forward declaration for multi-dispatch across modules
function disconnect! end

"""
    to_market_time(timestamp, timezone)

Convert a UTC `DateTime` or Unix timestamp to a timezone-aware market time.
Install and load the optional TimeZones.jl package to enable this conversion.
The `timezone` argument should be an IANA name such as `"America/New_York"`.
"""
function to_market_time(args...)
    throw(
        ArgumentError(
            "to_market_time requires TimeZones.jl; install it and load it with `using TimeZones`",
        ),
    )
end

# Core Modules
include("Core/Constant.jl")
include("Core/Errors.jl")
include("Core/Utils.jl")
include("Core/USProtocol.jl")
include("Core/Cache.jl")
include("Core/Commands.jl")
include("Core/HttpClient.jl")
include("Core/ControlProtocol.jl")
include("Core/QuoteProtocol.jl")
include("Core/TradeProtocol.jl")
include("Core/CalendarProtocol.jl")
include("Core/PortfolioProtocol.jl")
include("Core/MarketProtocol.jl")
include("Core/FundamentalProtocol.jl")
include("Core/AlertProtocol.jl")
include("Core/SharelistProtocol.jl")
include("Core/DCAProtocol.jl")
include("Core/ContentProtocol.jl")
include("Core/AssetProtocol.jl")
include("Core/ScreenerProtocol.jl")
include("OAuth.jl")
include("Config.jl")
include("Client.jl")

include("Quote/QuotePush.jl")
include("Quote/Quote.jl")
include("Trade/TradePush.jl")
include("Trade/Trade.jl")
include("Calendar/Calendar.jl")
include("Portfolio/Portfolio.jl")
include("MarketCtx/MarketCtx.jl")
include("Fundamental/Fundamental.jl")
include("Alert/Alert.jl")
include("Sharelist/Sharelist.jl")
include("DCA/DCA.jl")
include("Content/Content.jl")
include("Asset/Asset.jl")
include("Screener/Screener.jl")

using .Constant: Market, Currency
using .ControlProtocol
using .QuoteProtocol
using .TradeProtocol
using .USProtocol
using .CalendarProtocol
using .PortfolioProtocol
using .MarketProtocol
using .FundamentalProtocol
using .AlertProtocol
using .SharelistProtocol
using .DCAProtocol
using .ContentProtocol
using .AssetProtocol
using .ScreenerProtocol
using .Commands
using .Cache
using .OAuth
using .Config
using .Errors
using .Client
using .TradePush
using .Trade
using .QuotePush
using .Quote
using .Calendar
using .Portfolio
using .MarketCtx
using .Fundamental
using .Alert
using .Sharelist
using .DCA
using .Content
using .Asset
using .Screener
using .Utils: utc_iso8601

#= ==================== Exports ==================== =#

# --- Module & Core ---
export Quote,
    Trade,
    Config,
    disconnect!,                                     # 断开连接
    to_market_time,
    utc_iso8601,
    VERSION

export LongBridgeError, UnexpectedHttpResponse, ApiResponse

# --- Config ---
export Settings, config, from_oauth                        # 配置加载（config 是 Settings 的兼容别名）
export enable_papertrading!, dc_region

# --- OAuth ---
export OAuthBuilder, OAuthHandle, OAuthToken, build

# --- Constant (Enums) ---
export Market, Currency

# --- QuoteProtocol (行情协议) ---
# Push 结构体
export PushQuote, PushDepth, PushBrokers, PushTrade
# 枚举类型
export SubType,
    CandlePeriod,
    AdjustType,
    Direction,
    TradeSession,
    Granularity,
    WarrantSortBy,
    SortOrderType,
    SecuritiesUpdateMode,
    SecurityListCategory

# --- Quote (行情模块) ---
# Context
export QuoteContext
# 订阅管理
export subscribe,
    unsubscribe,
    subscriptions,
    set_on_quote,
    set_on_depth,
    set_on_brokers,
    set_on_trades,
    set_on_candlestick
# 实时行情
export realtime_quote, quote_snapshot, static_info, depth, brokers, trades, intraday
# 实时数据访问 (从本地缓存)
export realtime_depth, realtime_brokers, realtime_trades, realtime_candlesticks
# K线数据
export candlesticks, history_candlesticks_by_offset, history_candlesticks_by_date
# K线订阅
export subscribe_candlesticks, unsubscribe_candlesticks
# 期权
export option_quote, option_chain_expiry_date_list, option_chain_info_by_date
# 窝轮
export warrant_quote, warrant_list, warrant_issuers, warrant_filter
# 市场信息
export trading_session,
    trading_days,
    participants,
    member_id,
    quote_level,
    subscribe_limit,
    history_candlestick_limit,
    quote_package_details,
    filings,
    security_list
export symbol_to_counter_ids, resolve_counter_ids
# 资金流
export capital_flow, capital_distribution, calc_indexes
# 市场温度
export market_temperature, history_market_temperature
# 自选股
export watchlist, create_watchlist_group, delete_watchlist_group, update_watchlist_group
# v4.1.0 新增
export short_positions, option_volume, option_volume_daily, update_pinned
# v4.2.0 新增
export short_trades
export ShortPositionsItem,
    ShortPositionsResponse,
    ShortTradesItem,
    ShortTradesResponse,
    OptionVolumeStats,
    OptionVolumeDailyStat,
    OptionVolumeDaily,
    PinnedMode,
    FilingItem,
    QuotePackageDetail

# --- TradeProtocol (交易协议) ---
# Options 结构体
export GetHistoryExecutionsOptions,
    GetTodayExecutionsOptions,
    GetAllExecutionsOptions,
    GetUSHistoryOrders,
    QueryUSOrdersOptions,
    EstimateMaxPurchaseQuantityOptions,
    GetHistoryOrdersOptions,
    ReplaceOrderOptions,
    SubmitOrderOptions,
    GetTodayOrdersOptions
# 枚举类型
export OrderType,
    OrderSide,
    OrderStatus,
    OrderTag,
    TimeInForceType,
    OutsideRTH,
    TopicType

# --- Trade (交易模块) ---
# Context
export TradeContext
# 订单操作
export submit_order, replace_order, cancel_order, order_detail
# 订单查询
export today_orders, history_orders, today_executions, history_executions
# 账户信息
export account_balance,
    cash_flow, stock_positions, fund_positions, margin_ratio, estimate_max_purchase_quantity
# 推送
export set_on_order_changed

# --- v4.4.0 US-region APIs ---
export us_company_overview,
    us_valuation_overview,
    us_financial_overview,
    us_financial_statement,
    us_key_financial_metrics,
    us_analyst_consensus,
    us_etf_dividend_info,
    us_company_dividends,
    us_etf_files,
    us_crypto_overview,
    us_asset_overview,
    us_realized_pl,
    us_query_orders,
    us_order_detail

export USRankTag,
    USSharelistItem,
    USAIChatData,
    USCompanyOverview,
    USValuationMetric,
    USValuationOverview,
    USReportPeriod,
    USFinancialISItem,
    USFinancialBSItem,
    USFinancialCFItem,
    USFinancialOverview,
    USFinancialStatementField,
    USFinancialStatementPeriod,
    USFinancialStatement,
    USKeyMetricItem,
    USKeyFinancialMetrics,
    USConsensusEstimate,
    USConsensusItem,
    USAnalystConsensus,
    USFiscalYearDividend,
    USETFDividendInfo,
    USRecentDividend,
    USDividendHistoryItem,
    USDividendPayoutRecord,
    USCompanyDividends,
    USETFFile,
    USETFFilesResponse,
    USCryptoOverview,
    GetUSHistoryOrders,
    QueryUSOrdersOptions,
    QueryUSOrdersResponse,
    USOrderHistory,
    USButtonControl,
    USChargeItem,
    USChargeDetail,
    USAttachedOrder,
    USOrderDetail,
    USOrderDetailResponse,
    USCashEntry,
    USCryptoEntry,
    USStockEntry,
    USAssetOverview,
    USRealizedPLMetric,
    USRealizedPLEntry,
    USRealizedPL,
    GetAllExecutionsOptions,
    AllExecutionsResponse

# --- Calendar (财务日历) ---
export CalendarContext, finance_calendar
export CalendarCategory
export CalendarDataKv, CalendarEventInfo, CalendarDateGroup, CalendarEventsResponse

# --- Portfolio (组合分析) ---
export PortfolioContext,
    exchange_rate,
    profit_analysis,
    profit_analysis_by_market,
    profit_analysis_detail,
    profit_analysis_flows
export FlowDirection, AssetType
export ExchangeRate,
    ExchangeRates,
    ProfitSummaryInfo,
    ProfitSummaryBreakdown,
    ProfitAnalysisSummary,
    ProfitAnalysisItem,
    ProfitAnalysisSublist,
    ProfitAnalysis,
    ProfitAnalysisByMarketItem,
    ProfitAnalysisByMarket,
    ProfitDetailEntry,
    ProfitDetails,
    ProfitAnalysisDetail,
    FlowItem,
    ProfitAnalysisFlows

# --- Market (市场数据) ---
export MarketContext,
    market_status,
    broker_holding,
    broker_holding_detail,
    broker_holding_daily,
    ah_premium,
    ah_premium_intraday,
    trade_stats,
    anomaly,
    constituent,
    top_movers,
    rank_categories,
    rank_list
export BrokerHoldingPeriod, AhPremiumPeriod, MarketTradeStatus
export MarketTimeItem,
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
    RankListResponse

# --- Fundamental (基本面) ---
export FundamentalContext,
    financial_report,
    institution_rating,
    institution_rating_detail,
    dividend,
    dividend_detail,
    forecast_eps,
    consensus,
    valuation,
    valuation_history,
    industry_valuation,
    industry_valuation_dist,
    company,
    executive,
    shareholder,
    fund_holder,
    corp_action,
    invest_relation,
    operating,
    buyback,
    ratings,
    business_segments,
    business_segments_history,
    institution_rating_views,
    industry_rank,
    industry_peers,
    financial_report_snapshot,
    shareholder_top,
    shareholder_detail,
    valuation_comparison,
    etf_asset_allocation,
    macroeconomic_indicators,
    macroeconomic
export FinancialReportKind,
    FinancialReportPeriod,
    InstitutionRecommend,
    ElementType,
    MacroeconomicCountry,
    MacroeconomicImportance
export FinancialReports,
    RatingEvaluate,
    RatingTarget,
    RatingSummaryEvaluate,
    InstitutionRatingLatest,
    InstitutionRatingSummary,
    InstitutionRating,
    InstitutionRatingDetailEvaluateItem,
    InstitutionRatingDetailEvaluate,
    InstitutionRatingDetailTargetItem,
    InstitutionRatingDetailTarget,
    InstitutionRatingDetail,
    DividendItem,
    DividendList,
    ForecastEpsItem,
    ForecastEps,
    ConsensusDetail,
    ConsensusReport,
    FinancialConsensus,
    ValuationPoint,
    ValuationMetricData,
    ValuationMetricsData,
    ValuationData,
    ValuationHistoryMetric,
    ValuationHistoryMetrics,
    ValuationHistoryData,
    ValuationHistoryResponse,
    IndustryValuationHistory,
    IndustryValuationItem,
    IndustryValuationList,
    ValuationDist,
    IndustryValuationDist,
    CompanyOverview,
    Professional,
    ExecutiveGroup,
    ExecutiveList,
    ShareholderStock,
    Shareholder,
    ShareholderList,
    FundHolder,
    FundHolders,
    CorpActionLive,
    CorpActionItem,
    CorpActions,
    InvestSecurity,
    InvestRelations,
    OperatingIndicator,
    OperatingFinancial,
    OperatingItem,
    OperatingList,
    RecentBuybacks,
    BuybackHistoryItem,
    BuybackRatios,
    BuybackData,
    RatingLeafIndicator,
    RatingIndicator,
    RatingSubIndicatorGroup,
    RatingCategory,
    StockRatings,
    BusinessSegmentItem,
    BusinessSegments,
    BusinessSegmentHistoryItem,
    BusinessSegmentsHistoricalItem,
    BusinessSegmentsHistory,
    InstitutionRatingViewItem,
    InstitutionRatingViews,
    IndustryRankItem,
    IndustryRankGroup,
    IndustryRankResponse,
    IndustryPeersTop,
    IndustryPeerNode,
    IndustryPeersResponse,
    SnapshotForecastMetric,
    SnapshotReportedMetric,
    FinancialReportSnapshot,
    ShareholderTopResponse,
    ShareholderDetailResponse,
    ValuationHistoryPoint,
    ValuationComparisonItem,
    ValuationComparisonResponse,
    HoldingDetail,
    AssetAllocationItem,
    AssetAllocationGroup,
    AssetAllocationResponse,
    MacroeconomicIndicator,
    MacroeconomicIndicatorListResponse,
    Macroeconomic,
    MacroeconomicResponse

# --- Alert (价格提醒) ---
export AlertContext, list_alerts, add_alert, update_alert, delete_alerts
export AlertCondition, AlertFrequency
export AlertItem, AlertSymbolGroup, AlertList

# --- Sharelist (社区自选股) ---
export SharelistContext,
    list_sharelists,
    sharelist_detail,
    popular_sharelists,
    create_sharelist,
    delete_sharelist,
    add_sharelist_securities,
    remove_sharelist_securities,
    sort_sharelist_securities
export SharelistStock, SharelistInfo, SharelistList, SharelistScopes, SharelistDetail

# --- DCA (定投计划) ---
export DCAContext,
    list_dca,
    create_dca,
    update_dca,
    pause_dca,
    resume_dca,
    stop_dca,
    dca_history,
    dca_stats,
    dca_check_support,
    dca_calc_date,
    dca_set_reminder
export DCAFrequency, DCAStatus
export DcaPlan,
    DcaList,
    DcaStats,
    DcaSupportInfo,
    DcaSupportList,
    DcaHistoryRecord,
    DcaHistoryResponse,
    DcaCreateResult,
    DcaCalcDateResult

# --- Content (社区话题与资讯) ---
export ContentContext,
    my_topics,
    create_topic,
    topics_by_symbol,
    topic_detail,
    topic_replies,
    create_topic_reply,
    news
export TopicAuthor,
    TopicImage,
    OwnedTopic,
    TopicItem,
    TopicReply,
    NewsItem,
    MyTopicsOptions,
    CreateTopicOptions,
    ListTopicRepliesOptions,
    CreateReplyOptions

# --- Asset (账户结算单) ---
export AssetContext, statements, statement_download_url
export StatementType
export StatementItem, GetStatementListResponse, GetStatementResponse

# --- Screener (选股器) ---
export ScreenerContext,
    screener_recommend_strategies,
    screener_user_strategies,
    screener_strategy,
    screener_search,
    screener_indicators
export ScreenerCondition,
    ScreenerRecommendStrategiesResponse,
    ScreenerUserStrategiesResponse,
    ScreenerStrategyResponse,
    ScreenerSearchResponse,
    ScreenerIndicatorsResponse

# ==================== Precompile workload ====================
# Force compilation of the most-used construction paths so a fresh REPL
# session can hit the network within the first second instead of paying
# several seconds of inference on the first call.
@setup_workload begin
    @compile_workload begin
        # Config: both auth modes — exercises the constructor + alias.
        cfg = Config.Settings(
            "k",
            "s",
            "t",
            DateTime(2099, 1, 1);
            http_url = "https://example.test",
            quote_ws_url = "wss://example.test",
            trade_ws_url = "wss://example.test",
        )
        cfg.auth_mode = :apikey

        # OAuth: build a handle without doing real auth.
        tok = OAuth.OAuthToken("k", "a", nothing, UInt64(0))
        OAuth.is_expired(tok)
        OAuth.expires_soon(tok)

        # Errors path
        try
            throw(Errors.LongBridgeError(0, "warm"))
        catch
        end

        # HTTP-only Context constructors — these only store cfg and
        # spawn nothing, so they're safe to invoke at precompile time.
        # Forces method specialization for the constructor chain and
        # any default-arg paths each context uses.
        AssetContext(cfg)
        CalendarContext(cfg)
        FundamentalContext(cfg)
        MarketContext(cfg)
        PortfolioContext(cfg)
        AlertContext(cfg)
        SharelistContext(cfg)
        DCAContext(cfg)
        ContentContext(cfg)
        ScreenerContext(cfg)

        # Warm small helpers commonly hit on first user call.
        Utils.symbol_to_counter_id("SPY.US")
        Utils.counter_id_to_symbol("ST/HK/700")
    end
end

end # module LongBridge
