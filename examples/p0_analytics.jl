"""
LongBridge Julia SDK — P0 Analytics Examples

本文件演示 v4.1.0 移植过来的 4 个 HTTP-only Context 的用法，外加 QuoteContext 的 4 个新方法。
所有调用都是同步阻塞的 REST 请求；institution_rating 和 profit_analysis 内部用受监督的异步任务并发 fan-out。

运行前请先设置 OAuth client_id（替换下面的占位符）。
"""

using LongBridge, Dates

function main()

# ── OAuth 初始化（跨平台浏览器回调） ─────────────────────────────────────

function open_browser(url)
    cmd = if Sys.islinux()
        `xdg-open $url`
    elseif Sys.isapple()
        `open $url`
    elseif Sys.iswindows()
        `cmd /c start $url`
    else
        error("Unsupported platform for browser auto-open; visit URL manually: $url")
    end
    run(cmd)
end

oauth = OAuthBuilder("your_client_id") |> build(open_browser)
cfg   = Config.from_oauth(oauth)

# ── 创建 4 个新 Context ──────────────────────────────────────────────────

fc = FundamentalContext(cfg)
mc = MarketContext(cfg)
cc = CalendarContext(cfg)
pc = PortfolioContext(cfg)

# 注意：这些 Context 都是 HTTP-only，无 WebSocket 连接，
# 因此**不需要** disconnect!（也不存在该方法）。可以随时创建、随时丢弃。

# ════════════════════════════════════════════════════════════════════════
# FundamentalContext — 财报、估值、评级、公司信息
# ════════════════════════════════════════════════════════════════════════

# 分红历史
display(dividend(fc, "700.HK"))

# 分红详情（最近 + 历史方案）
display(dividend_detail(fc, "700.HK"))

# 机构评级（并行 fan-out：latest + summary 两个端点）
display(institution_rating(fc, "AAPL.US"))

# 评级历史明细（按周快照 + 目标价时间序列）
display(institution_rating_detail(fc, "AAPL.US"))

# P/E、P/B、P/S、股息率快照（含历史 high/low/median）
display(valuation(fc, "TSLA.US"))

# 估值历史时间序列（PE/PB/PS/股息率）
display(valuation_history(fc, "TSLA.US"))

# 行业可比公司估值对比
display(industry_valuation(fc, "TSLA.US"))

# 行业估值分布（行业内分位数）
display(industry_valuation_dist(fc, "TSLA.US"))

# 公司概况（董事长、网站、员工数、IPO 价等）
display(company(fc, "AAPL.US"))

# 管理层与董事会
display(executive(fc, "AAPL.US"))

# 主要股东（含变动追踪）
display(shareholder(fc, "AAPL.US"))

# 持有该证券的基金/ETF
display(fund_holder(fc, "AAPL.US"))

# 公司行动（分红、拆股、回购）
display(corp_action(fc, "AAPL.US"))

# 对外投资关系（被投公司列表）
display(invest_relation(fc, "AAPL.US"))

# 经营报告与关键指标
display(operating(fc, "AAPL.US"))

# 营收/利润/EPS 一致预期 vs 实际
display(consensus(fc, "AAPL.US"))

# 分析师 EPS 预测
display(forecast_eps(fc, "AAPL.US"))

# 回购数据（TTM + 历史 + 比率）
display(buyback(fc, "AAPL.US"))

# 多维度评级（成长、盈利、估值等子指标）
display(ratings(fc, "AAPL.US"))

# 完整财报（嵌套结构因 kind 而异，list 字段为原始 JSON）
display(financial_report(fc, "AAPL.US"; kind=FinancialReportKind.IncomeStatement))
display(financial_report(fc, "700.HK"; kind=FinancialReportKind.All, period=FinancialReportPeriod.Annual))

# ════════════════════════════════════════════════════════════════════════
# MarketContext — 市场状态、券商持仓、A/H 溢价、异动
# ════════════════════════════════════════════════════════════════════════

# 各市场的开收市状态
display(market_status(mc))

# 净买/净卖前十名券商（按指定回看期）
display(broker_holding(mc, "700.HK", BrokerHoldingPeriod.Rct1))   # 1日
display(broker_holding(mc, "700.HK", BrokerHoldingPeriod.Rct60))  # 60日

# 全部券商持仓明细（每个券商的 1/5/20/60 日变化）
display(broker_holding_detail(mc, "700.HK"))

# 指定券商对某证券的每日持仓历史
# broker_holding_daily(mc, "700.HK", "6727")  # 6727 = 瑞银 parti_number

# A/H 溢价 K 线（30 天日线）
display(ah_premium(mc, "700.HK", AhPremiumPeriod.Day, 30))
display(ah_premium(mc, "700.HK", AhPremiumPeriod.Min5, 60))   # 60 根 5 分钟

# A/H 溢价当日分时
display(ah_premium_intraday(mc, "700.HK"))

# 买/卖/中性方向成交统计
display(trade_stats(mc, "700.HK"))

# 市场异动（大宗交易、融资买入等）
display(anomaly(mc, "HK"))

# 指数成份股（注意：传递指数 symbol，如 HSI.HK）
display(constituent(mc, "HSI.HK"))

# ════════════════════════════════════════════════════════════════════════
# CalendarContext — 财务日历
# ════════════════════════════════════════════════════════════════════════

# 本周财报
display(finance_calendar(cc, CalendarCategory.Report, Date(2026,5,15), Date(2026,5,22)))

# 本月分红
display(finance_calendar(cc, CalendarCategory.Dividend, Date(2026,5,1), Date(2026,5,31)))

# 即将上市的 IPO（限定香港市场）
display(finance_calendar(cc, CalendarCategory.Ipo, Date(2026,5,1), Date(2026,6,30); market="HK"))

# 宏观数据发布
display(finance_calendar(cc, CalendarCategory.MacroData, Date(2026,5,15), Date(2026,5,22)))

# 休市日
display(finance_calendar(cc, CalendarCategory.Closed, Date(2026,5,1), Date(2026,12,31); market="US"))

# ════════════════════════════════════════════════════════════════════════
# PortfolioContext — 汇率、盈亏分析
# ════════════════════════════════════════════════════════════════════════

# 所有支持币种的汇率快照
display(exchange_rate(pc))

# 账户总盈亏分析（并行 fan-out：summary + sublist）
display(profit_analysis(pc))

# 限定时间窗口的盈亏
display(profit_analysis(pc; start=Date(2026,1,1), end_=Date(2026,5,15)))

# 按市场分页查询
display(profit_analysis_by_market(pc; page=1, size=20, market="US"))

# 单只证券盈亏明细（正股 / 衍生品分解）
# display(profit_analysis_detail(pc, "AAPL.US"))

# 单只证券交易流水
# display(profit_analysis_flows(pc, "AAPL.US"; page=1, size=50, derivative=false))

# ════════════════════════════════════════════════════════════════════════
# QuoteContext v4.1.0 新增方法（这些走原有 QuoteContext，但内部直接调 HTTP）
# ════════════════════════════════════════════════════════════════════════

qctx = QuoteContext(cfg)
try
    # 美股做空数据（FINRA 双月公布；v0.8.0 起 HK 端点也走同一函数）
    display(short_positions(qctx, "TSLA.US"; count=20))
    # 港股做空（自动选 /v1/quote/short-positions/hk）
    # display(short_positions(qctx, "700.HK"; count=20))

    # v0.8.0 新增：做空成交记录
    # display(short_trades(qctx, "AAPL.US"; count=20))

    # 实时认购/认沽成交量
    display(option_volume(qctx, "AAPL.US"))

    # 历史日度期权成交统计（最近 30 天）
    ts_now = Int64(round(datetime2unix(now())))
    display(option_volume_daily(qctx, "AAPL.US", ts_now, 30))

    # 把自选股置顶（取消置顶用 PinnedMode.Remove）
    # update_pinned(qctx, PinnedMode.Add, ["700.HK", "AAPL.US"])

    # ────────────────────────────────────────────────────────────────────
    # v0.7.0 新增：UserProfile / filings / quote_snapshot vs realtime_quote
    # ────────────────────────────────────────────────────────────────────

    # 行情账号信息（连接后由 QueryUserQuoteProfile 自动拉取）
    @info "user profile" member_id=member_id(qctx) quote_level=quote_level(qctx)
    for pkg in quote_package_details(qctx)
        @info "package" pkg.key pkg.name pkg.start_at pkg.end_at
    end

    # 公司公告（REST /v1/quote/filings）
    for f in filings(qctx, "AAPL.US")
        @info "filing" f.title f.published_at f.file_urls
    end

    # 一次性服务器查询（旧 realtime_quote 的行为）
    display(quote_snapshot(qctx, ["AAPL.US", "TSLA.US"]))

    # 本地缓存读取：先订阅，再读
    subscribe(qctx, ["AAPL.US"], [SubType.QUOTE]; is_first_push=true)
    sleep(1)                            # 等一条推送进来
    q = realtime_quote(qctx, "AAPL.US")
    isnothing(q) ? @info("尚无推送到达") : @info("cached quote", last_done=q.last_done, ts=q.timestamp)
    unsubscribe(qctx, ["AAPL.US"], [SubType.QUOTE])
finally
    disconnect!(qctx)
end

# ════════════════════════════════════════════════════════════════════════
# AssetContext v0.7.0 — 账户结算单
# ════════════════════════════════════════════════════════════════════════

ac = AssetContext(cfg)

# 月度结算单（第 1 页，每页 20 条）
sl = statements(ac, StatementType.Monthly; page=1, page_size=20)
for item in sl.list
    @info "statement" date=item.dt file_key=item.file_key
end

# 用第一条记录的 file_key 换下载链接
if !isempty(sl.list)
    url = statement_download_url(ac, sl.list[1].file_key)
    @info "下载链接（短期有效）" url=url.url
end

# ════════════════════════════════════════════════════════════════════════
# v0.8.0 新增 —— 上游 LongPort SDK v4.2.0 对齐
# ════════════════════════════════════════════════════════════════════════

# Fundamental：9 个新方法
fc = FundamentalContext(cfg)
display(business_segments(fc, "AAPL.US"))                  # 最新业务分部构成
# display(business_segments_history(fc, "AAPL.US"))        # 历史业务+地区分部
# display(institution_rating_views(fc, "AAPL.US"))         # 评级分布时间序列
# display(industry_rank(fc, "US", "pe", "asc", 20))        # 行业排名
# display(industry_peers(fc, "AAPL.US", "US"))             # 同业链
# display(financial_report_snapshot(fc, "AAPL.US"))        # 财报快照
# display(shareholder_top(fc, "AAPL.US"))                  # 主要股东排行
# display(valuation_comparison(fc, "AAPL.US", "USD"; comparison_symbols=["MSFT.US","GOOGL.US"]))

# Market：3 个新方法
mc = MarketContext(cfg)
display(top_movers(mc, ["US"], 1, 20))                     # 异动榜（POST）
# display(rank_categories(mc))                             # 排行榜分类
# display(rank_list(mc, "us_top_gain"))                    # 用上面拿到的 key 查具体榜

# Screener：5 个新方法（全部返回原始 JSON，可用 .data 索引取字段）
sc = ScreenerContext(cfg)
display(screener_indicators(sc))                           # 可用指标列表
# display(screener_recommend_strategies(sc, "US"))         # 推荐策略（v0.8.1 起需要 market）
# display(screener_user_strategies(sc, "US"))              # 我的策略
# display(screener_strategy(sc, 12345))                    # 单个策略详情
# display(screener_search(sc, "US"; strategy_id=12345, page=0, size=20))     # Mode A
# Mode B：自定义条件
# conds = [ScreenerCondition("pettm"; min="0", max="20"),
#          ScreenerCondition("roe";   min="0.1")]
# display(screener_search(sc, "US"; conditions=conds, page=0, size=20))

# ════════════════════════════════════════════════════════════════════════
# v0.8.5 新增 —— 宏观经济数据（上游 macrodata v2 对齐）
# ════════════════════════════════════════════════════════════════════════

fc = FundamentalContext(cfg)

# 1) 宏观经济指标列表（不带过滤，默认前 100 条；count 为总数）
indicators = macroeconomic_indicators(fc)
@info "宏观指标总数" count=indicators.count
for ind in indicators.data[1:min(5, end)]
    @info "indicator" ind.indicator_code ind.country ind.name ind.periodicity
end

# 2) 按国家过滤 + 关键字模糊过滤 + 分页（country 用 MacroeconomicCountry 枚举）
us = macroeconomic_indicators(fc; country=MacroeconomicCountry.UnitedStates, keyword="CPI", offset=0, limit=20)
display(us)
# 其他可选：HongKong / China / EuroZone / Japan / Singapore
# display(macroeconomic_indicators(fc; country=MacroeconomicCountry.China))

# importance 是原始整数（1=低 2=中 3=高），可转枚举
for ind in us.data
    imp = LongBridge.FundamentalProtocol._macroeconomic_importance_from_int(ind.importance)
    imp == MacroeconomicImportance.High && @info "高重要性指标" ind.indicator_code ind.name
end

# 3) 用列表里拿到的 indicator_code 查历史数据
if !isempty(us.data)
    code = us.data[1].indicator_code
    hist = macroeconomic(fc, code)
    @info "历史数据" code total=hist.count info_name=hist.info.name
    for pt in hist.data[1:min(5, end)]
        @info "data point" pt.period pt.actual_value pt.forecast_value pt.release_at pt.unit
    end
end

# 4) 限定日期窗口（接受 "YYYY-MM-DD" 字符串或 Date）+ 分页
# display(macroeconomic(fc, "US_CPI_YOY"; start_date="2023-01-01", end_date="2024-12-31"))
# display(macroeconomic(fc, "US_CPI_YOY"; start_date=Date(2023,1,1), end_date=Date(2024,12,31), offset=0, limit=50))

end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main()
