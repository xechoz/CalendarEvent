import QtQuick
import Quickshell.Io
import "../events/EventsModel.js" as EM

// 到点提醒引擎(reminders/ 模块):低频扫描 + 桌面通知 + 去重。
//
// 规则:
//   - 带时间的事件 → 提前 leadMinutes(10)分钟提醒,如 15:30 的事件 15:20 弹
//   - 全天事件 → 当天 09:00 提醒,不受提前量影响(多日全天事件只在首日)
//   - 通知以 "eventId|yyyy-MM-dd" 为键去重,重启不重复弹
//   - 唤醒/恢复后错过提醒窗口(提前点起 5 分钟内)的不再补弹
//   - 跨天边界:凌晨事件提前后不足 0 分的,钳制到当天 00:00,不提前到昨天
Item {
  id: root

  // 由编排层注入:EventStore 实例;为空则不启动
  property var store: null
  property int intervalMs: 30000
  // 带时间事件的提前量(分钟);全天事件不受影响(仍按事件时刻 09:00)
  property int leadMinutes: 10

  // 测试/调优钩子:注入 nowOverride(ms/Date)与 notifyHook 可在离线环境验证
  // 窗口计算,不注入时行为与旧版一致。
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
      var at = e.time || "09:00"
      var atMin = parseInt(at.slice(0, 2), 10) * 60 + parseInt(at.slice(3, 5), 10)
      // 提前量只作用于带时间的事件;全天(无 time)保持在 at 时刻(09:00)
      var remindAt = e.time ? atMin - root.leadMinutes : atMin
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
    if (event.time) parts.push("时间 " + at)
    else parts.push("全天事件")
    if (event.endDate && event.endDate !== event.date)
      parts.push("第 " + (EM.diffDays(event.date, dateKey) + 1) + " 天")
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
