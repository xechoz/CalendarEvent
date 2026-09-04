import QtQuick
import Quickshell.Io
import "../events/EventsModel.js" as EM

// 到点提醒引擎(reminders/ 模块):低频扫描 + 桌面通知 + 去重。
//
// 规则:
//   - 带时间的事件 → 当天该时刻提醒
//   - 全天事件 → 当天 09:00 提醒(多日全天事件只在首日)
//   - 通知以 "eventId|yyyy-MM-dd" 为键去重,重启不重复弹
//   - 唤醒/恢复后错过 >5 分钟的不再补弹
Item {
  id: root

  // 由编排层注入:EventStore 实例;为空则不启动
  property var store: null
  property int intervalMs: 30000

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
    var now = new Date()
    var dateKey = EM.todayKey(now)
    var nowMin = now.getHours() * 60 + now.getMinutes()
    var due = root.store.remindersDueToday(dateKey)
    for (var i = 0; i < due.length; i++) {
      var occ = due[i]
      var e = occ.event
      var at = e.time || "09:00"
      var atMin = parseInt(at.slice(0, 2), 10) * 60 + parseInt(at.slice(3, 5), 10)
      if (nowMin < atMin) continue
      if (nowMin - atMin > 5) continue
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
    if (event.note) parts.push(String(event.note))
    var body = parts.join(" · ")
    notifyProc.command = ["omarchy-notification-send", "-g", "󰃭", event.title, body]
    notifyProc.running = true
  }

  Process {
    id: notifyProc
    running: false
  }
}
