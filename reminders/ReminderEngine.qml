import QtQuick
import Quickshell.Io
import "../events/EventsModel.js" as EM
import "../i18n"

// 到点提醒引擎(reminders/ 模块):低频扫描 + 桌面通知 + 去重。
//
// 规则:
//   - 提醒时刻 = 锚点 - 提前量:带时间事件锚点=事件时刻;全天事件锚点=当天 09:00
//   - 提前量取事件 remindMinutes(表单可选 5/10/15/30/60),旧数据缺失时回退
//     leadMinutes(10) 兜底
//   - 提前后不足 0 分的钳制到当天 00:00,不提前到昨天;提醒时刻已过窗口
//     (提前点起 5 分钟内)的不再补弹
//   - 通知以 "eventId|yyyy-MM-dd" 为键去重,重启不重复弹
//   - 全天事件只提醒当天一次(多日事件只在首日,由 remindersDueToday 保证)
Item {
  id: root

  // 由编排层注入:EventStore 实例;为空则不启动
  property var store: null
  property int intervalMs: 30000
  // 兜底提前量(分钟):事件没写 remindMinutes(旧数据)时使用;全天/定时同样适用
  property int leadMinutes: 10

  // 测试/调优钩子:注入 nowOverride(ms/Date)与 notifyHook 可在离线环境验证
  // 窗口计算,不注入时按真实时钟扫描、走系统桌面通知。
  property var nowOverride: null
  property var notifyHook: null

  Timer {
    id: scanTimer
    interval: root.intervalMs
    running: false
    repeat: true
    onTriggered: root.scan()
  }

  Connections {
    target: root.store
    function onEventsChanged() { root.arm() }
    function onLoadedChanged() { root.arm() }
  }

  function arm() {
    if (!root.store || !root.store.loaded) { scanTimer.stop(); return }
    if (!root.store.notifiedLoaded) root.store.refreshNotified()
    scanTimer.start()
    root.scan()
  }

  function scan() {
    if (!root.store || !root.store.loaded) return
    var now = root.nowOverride ? new Date(root.nowOverride) : new Date()
    var dateKey = EM.todayKey(now)
    var nowMin = now.getHours() * 60 + now.getMinutes()
    var due = root.store.remindersDueToday(dateKey)
    for (var i = 0; i < due.length; i++) {
      var occ = due[i]
      var e = occ.event
      // 锚点时刻:带时间的事件 = 事件时刻;全天事件 = 当天 09:00(表单同规则)
      var at = e.time || "09:00"
      var atMin = parseInt(at.slice(0, 2), 10) * 60 + parseInt(at.slice(3, 5), 10)
      // 提前量:每事件 remindMinutes(0 及以上);缺失/非法(旧数据)回退全局默认
      var lead = root.leadMinutes
      if (e.remindMinutes !== null && e.remindMinutes !== undefined)
        lead = e.remindMinutes
      var remindAt = atMin - lead
      if (remindAt < 0) remindAt = 0
      if (nowMin < remindAt) continue
      if (nowMin - remindAt > 5) continue
      var key = e.id + "|" + dateKey
      if (root.store.notifyHas(key)) continue
      root.notify(e, at, dateKey)
      root.store.notifyAdd(key)
    }
  }

  function notify(event, at, dateKey) {
    var parts = []
    if (event.time) parts.push(I18n.tr("notify_time", [at]))
    else parts.push(I18n.tr("notify_all_day"))
    if (event.endDate && event.endDate !== event.date)
      parts.push(I18n.tr("notify_day_n", [EM.diffDays(event.date, dateKey) + 1]))
    var body = parts.join(" · ")
    if (root.notifyHook) { root.notifyHook(event, at, dateKey); return }
    notifyProc.command = ["omarchy-notification-send", "-g", "󰃭", event.title, body]
    notifyProc.running = true
  }

  Process {
    id: notifyProc
    running: false
  }
}
