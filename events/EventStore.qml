import QtQuick
import Quickshell
import Quickshell.Io
import "EventsModel.js" as EM
import "../i18n"

// 事件数据源(events/ 模块核心):事件与提醒去重记录的读/写/缓存/广播。
//
// 磁盘文件与目录约定:
//   ~/.local/share/omarchy-calendar/events.json     事件本体
//   ~/.local/share/omarchy-calendar/notified.json   提醒去重记录
// 写入走 events_sync.py(原子替换),避免半截 JSON;全部为异步 Process,
// 读写各自排队,保证命令按序完成(见 _queue* )。
//
// 只暴露数据 API,不含任何 UI/bar 依赖,便于 Panel/提醒引擎/列表复用。
Item {
  id: root

  property string home: Quickshell.env("HOME") || ""

  // 可由宿主编排层覆盖(如 shell.json 内联设置 eventsDataDir),空则用默认
  property string dataDir: ""
  // 覆盖 events_sync.py 的绝对路径;空则用插件目录内默认位置
  property string helperPath: ""

  readonly property string defaultDataDir: home + "/.local/share/omarchy-calendar"
  readonly property string defaultHelperPath: home
    + "/.config/omarchy/plugins/xechoz.clock/events/events_sync.py"

  property string eventsFile: root.dataDir !== ""
    ? root.dataDir + "/events.json" : root.defaultDataDir + "/events.json"
  property string notifiedFile: root.dataDir !== ""
    ? root.dataDir + "/notified.json" : root.defaultDataDir + "/notified.json"
  property string helper: root.helperPath !== "" ? root.helperPath : root.defaultHelperPath

  // ---- 状态 ----
  property var events: []
  property bool loaded: false
  property string lastError: ""
  property int revision: 0

  // 提醒去重记录 { keys: [ "eventId|yyyy-MM-dd", ... ] },内存态缓存
  property var notifiedKeys: []
  property bool notifiedLoaded: false

  // (events 属性的变更通知即 eventsChanged,勿重复声明同名 signal)

  // ------------------------------------------------------------- 读写排队

  property bool _writeBusy: false
  property var _writePending: null
  property bool _readBusy: false
  property var _readPending: null

  function _queueRead(args, handler) {
    if (root._readBusy) { root._readPending = { args: args, handler: handler }; return }
    root._readBusy = true
    readProc.handler = handler
    readProc.command = args
    readProc.running = true
  }

  function _queueWrite(args) {
    if (root._writeBusy) { root._writePending = args; return }
    root._writeBusy = true
    writeProc.command = args
    writeProc.running = true
  }

  function _releaseRead() {
    root._readBusy = false
    if (root._readPending) {
      var pending = root._readPending
      root._readPending = null
      Qt.callLater(function() { root._queueRead(pending.args, pending.handler) })
    }
  }

  function _releaseWrite() {
    root._writeBusy = false
    if (root._writePending) {
      var pending = root._writePending
      root._writePending = null
      Qt.callLater(function() { root._queueWrite(pending) })
    }
  }

  // ------------------------------------------------------------- events

  function refresh() {
    root.lastError = ""
    root._queueRead(["python3", root.helper, "load-events", root.eventsFile], function(raw) {
      var parsed = null
      try { parsed = JSON.parse(raw || "") } catch (e) { parsed = null }
      if (!parsed || typeof parsed !== "object") {
        root.lastError = I18n.tr("load_error")
        return
      }
      root.events = EM.sanitizeEvents(parsed)
      root.loaded = true
      root.revision++
      root.eventsChanged()
    })
  }

  function _saveEventsNow() {
    root._queueWrite(["python3", root.helper, "save-events", root.eventsFile, JSON.stringify({ version: 1, events: root.events })])
  }

  // 表单字段 → 新增事件;返回新事件或 null
  function addEvent(fields) {
    var event = EM.buildEvent(fields)
    if (!event) { root.lastError = I18n.tr("save_incomplete"); return null }
    root.events = root.events.concat(event)
    root.revision++
    root._saveEventsNow()
    root.eventsChanged()
    return event
  }

  // 编辑:以现有事件为基,合并表单字段后重新规范化
  function updateEvent(id, fields) {
    var target = root.eventById(id)
    if (!target) return null
    var merged = {}
    for (var k in target) merged[k] = target[k]
    var keys = ["title", "flag", "status", "date", "endDate", "time", "repeat", "repeatUntil", "remind", "remindMinutes"]
    for (var i = 0; i < keys.length; i++) {
      if (fields[keys[i]] !== undefined) merged[keys[i]] = fields[keys[i]]
    }
    var normalized = EM.normalizeEvent(merged)
    if (!normalized) { root.lastError = I18n.tr("save_incomplete"); return null }
    root.events = root.events.map(function(e) { return e.id === id ? normalized : e })
    root.revision++
    root._saveEventsNow()
    root.eventsChanged()
    return normalized
  }

  function removeEvent(id) {
    root.events = root.events.filter(function(e) { return e.id !== id })
    root.revision++
    root._saveEventsNow()
    root.eventsChanged()
  }

  // 重复事件:仅跳过某一次出现(写 exceptions)
  function skipOccurrence(id, dateKey) {
    var target = root.eventById(id)
    if (!target || target.repeat === "none") return false
    var exceptions = (target.exceptions || []).concat(dateKey)
    root.events = root.events.map(function(e) {
      if (e.id !== id) return e
      var copy = {}
      for (var k in e) copy[k] = e[k]
      copy.exceptions = exceptions
      return copy
    })
    root.revision++
    root._saveEventsNow()
    root.eventsChanged()
    return true
  }

  function eventById(id) {
    for (var i = 0; i < root.events.length; i++)
      if (root.events[i].id === id) return root.events[i]
    return null
  }

  // ---- 查询(事件量小,直接现算) ----

  // 窗口内按日索引:dateKey → [ {key,endKey,event} ]
  function coverage(fromKey, toKey) {
    return EM.indexByDate(root.events, fromKey, toKey)
  }

  // 某天的事件(排序后:全天在前,再按时间)
  function forDay(dateKey) {
    var map = EM.indexByDate(root.events, dateKey, dateKey)
    return EM.sortOccurrences(map[dateKey] || [])
  }

  function countOn(dateKey) {
    var map = EM.indexByDate(root.events, dateKey, dateKey)
    var list = map[dateKey]
    return list ? list.length : 0
  }

  // 提醒引擎:当天需提醒的出现;全天无时间的事件只在首日提醒
  function remindersDueToday(dateKey) {
    var out = []
    var list = EM.indexByDate(root.events, dateKey, dateKey)[dateKey] || []
    for (var i = 0; i < list.length; i++) {
      var occ = list[i]
      var e = occ.event
      if (!e || !e.remind) continue
      if (!e.time && occ.key !== e.date) continue
      out.push(occ)
    }
    return out
  }

  // ------------------------------------------------------------- notified

  function refreshNotified() {
    root.notifiedLoaded = false
    root._queueRead(["python3", root.helper, "load-notified", root.notifiedFile], function(raw) {
      var parsed = null
      try { parsed = JSON.parse(String(raw || "")) } catch (err) { parsed = null }
      root.notifiedKeys = parsed && Array.isArray(parsed.keys) ? parsed.keys.slice() : []
      root.notifiedLoaded = true
    })
  }

  function notifyHas(key) {
    return root.notifiedKeys.indexOf(String(key)) !== -1
  }

  function notifyAdd(key) {
    key = String(key)
    if (root.notifiedKeys.indexOf(key) !== -1) return
    root.notifiedKeys = root.notifiedKeys.concat(key)
    root._saveNotifiedNow()
  }

  function _saveNotifiedNow() {
    // 只留近 10 天的键,避免文件无限膨胀
    var cutoff = EM.addDays(EM.todayKey(new Date()), -10)
    var kept = root.notifiedKeys.filter(function(k) {
      var m = /(\d{4}-\d{2}-\d{2})$/.exec(String(k || ""))
      if (!m) return false
      return EM.cmpKeys(m[1], cutoff) >= 0
    })
    root._queueWrite(["python3", root.helper, "save-notified", root.notifiedFile, JSON.stringify({ keys: kept })])
  }

  // ------------------------------------------------------------ processes

  Process {
    id: readProc
    running: false
    property var handler: null
    stdout: StdioCollector {
      id: readOut
      waitForEnd: true
      onStreamFinished: {
        if (readProc.handler) readProc.handler(text)
      }
    }
    stderr: StdioCollector {
      id: readErr
      waitForEnd: true
      onStreamFinished: {
        var t = String(readErr.text || "").trim()
        if (t !== "") root.lastError = "events_sync: " + t
      }
    }
    onRunningChanged: {
      if (!readProc.running) root._releaseRead()
    }
  }

  Process {
    id: writeProc
    running: false
    stdout: StdioCollector { id: writeOut; waitForEnd: true }
    stderr: StdioCollector {
      id: writeErr
      waitForEnd: true
      onStreamFinished: {
        var t = String(writeErr.text || "").trim()
        if (t !== "") root.lastError = "events_sync: " + t
      }
    }
    onRunningChanged: {
      if (!writeProc.running) root._releaseWrite()
    }
  }
}
