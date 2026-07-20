"""
LongBridge Julia SDK — P1 Community & Plans Examples

本文件演示 v4.1.0 P1 部分的 4 个 HTTP-only Context：
  • AlertContext     — 价格提醒（CRUD）
  • SharelistContext — 社区自选股列表
  • DCAContext       — 定投计划全生命周期
  • ContentContext   — 社区话题与资讯

运行前请先把 `"your_client_id"` 替换为你自己的 LongBridge Developers 平台 client_id。

⚠️ 本文件中部分调用会**修改账户状态**（创建提醒、定投计划、自选股列表、发布话题等），
   生产前请仔细确认。下面默认把这些写操作注释掉。
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

# ── 创建 4 个 P1 Context ─────────────────────────────────────────────────

ac   = AlertContext(cfg)
slc  = SharelistContext(cfg)
dca  = DCAContext(cfg)
cct  = ContentContext(cfg)

# ════════════════════════════════════════════════════════════════════════
# AlertContext — 价格提醒
# ════════════════════════════════════════════════════════════════════════

# 查询所有提醒（按证券分组）
alerts = list_alerts(ac)
display(alerts)

# 新增提醒（默认注释掉，避免误触发）
#   AlertCondition: PriceRise / PriceFall / PercentRise / PercentFall
#   AlertFrequency: Daily / EveryTime / Once
# add_alert(ac, "700.HK", AlertCondition.PriceRise, "600", AlertFrequency.EveryTime)
# add_alert(ac, "AAPL.US", AlertCondition.PercentFall, "5", AlertFrequency.Once)

# 切换某条提醒的启用状态：先 list 拿到 item，改 enabled 后 update
#   for group in alerts.lists, item in group.indicators
#       new_item = AlertItem(item.id, item.indicator_id, !item.enabled,
#                            item.frequency, item.scope, item.text,
#                            item.state, item.value_map)
#       update_alert(ac, new_item)
#   end

# 删除提醒
# delete_alerts(ac, ["alert-id-1", "alert-id-2"])

# ════════════════════════════════════════════════════════════════════════
# SharelistContext — 社区自选股列表
# ════════════════════════════════════════════════════════════════════════

# 我自己的 + 已订阅的自选股列表
mine = list_sharelists(slc; count=20)
display(mine)

# 热门列表（发现）
popular = popular_sharelists(slc; count=10)
display(popular)

# 某个列表的详情（含成份股）
if !isempty(popular.sharelists)
    detail = sharelist_detail(slc, popular.sharelists[1].id)
    display(detail)
end

# 写操作（默认注释掉）
# new_id = create_sharelist(slc, "我的科技股观察"; description="美股 + 港股核心标的")
# add_sharelist_securities(slc, new_id, ["AAPL.US", "TSLA.US", "700.HK"])
# sort_sharelist_securities(slc, new_id, ["700.HK", "AAPL.US", "TSLA.US"])
# remove_sharelist_securities(slc, new_id, ["TSLA.US"])
# delete_sharelist(slc, new_id)

# ════════════════════════════════════════════════════════════════════════
# DCAContext — 定投计划
# ════════════════════════════════════════════════════════════════════════

# 总览统计（活跃/暂停/已停 计数 + 最近计划 + 累计投入/盈亏）
display(dca_stats(dca))

# 查询所有定投计划，可按状态/标的过滤
display(list_dca(dca))
display(list_dca(dca; status=DCAStatus.Active))
# display(list_dca(dca; symbol="700.HK"))

# 批量检查标的是否支持定投
display(dca_check_support(dca, ["700.HK", "AAPL.US", "TSLA.US"]))

# 给定调度参数下，计算下次交易日
display(dca_calc_date(dca, "700.HK", DCAFrequency.Monthly; day_of_month=15))
display(dca_calc_date(dca, "AAPL.US", DCAFrequency.Weekly; day_of_week="Mon"))

# 写操作（默认注释掉）
# 新建月度定投：每月 15 日投入 1000 港币到 700.HK
# result = create_dca(dca, "700.HK", "1000", DCAFrequency.Monthly; day_of_month=15)
# plan_id = result.plan_id

# 修改计划（只传想改的字段）
# update_dca(dca, plan_id; amount="1500")
# update_dca(dca, plan_id; frequency=DCAFrequency.Fortnightly, day_of_week="Mon")

# 暂停 / 恢复 / 永久停止
# pause_dca(dca, plan_id)
# resume_dca(dca, plan_id)
# stop_dca(dca, plan_id)

# 查询某计划的执行历史
# display(dca_history(dca, plan_id; page=1, limit=20))

# 设置执行前的提醒小时数（必须是 "1"/"6"/"12" 之一）
# dca_set_reminder(dca, "6")

# ════════════════════════════════════════════════════════════════════════
# ContentContext — 社区话题与资讯
# ════════════════════════════════════════════════════════════════════════

# 某证券下的资讯列表
display(news(cct, "AAPL.US"))

# 某证券下的话题列表
display(topics_by_symbol(cct, "700.HK"))

# 我自己发布的话题
display(my_topics(cct; size=20))
display(my_topics(cct; topic_type="article"))

# 写操作（默认注释掉）
# 发布新话题
# new_topic_id = create_topic(cct, "Q1 财报分析", "## 关键数据\n营收同比 +15%, EBIT +22%...";
#                              topic_type="article",
#                              tickers=["700.HK"],
#                              hashtags=["腾讯", "财报"])

# 拿话题详情（如果你已经发过或拿到了某话题 ID）
# display(topic_detail(cct, new_topic_id))

# 拿话题评论
# display(topic_replies(cct, new_topic_id; size=50))

# 回复话题（plain text；提到的 symbol 会自动识别成关联标的）
# reply = create_topic_reply(cct, new_topic_id, "我也持有 700.HK，长期看好")
# 二级回复
# create_topic_reply(cct, new_topic_id, "同感"; reply_to_id=reply.id)

end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main()
