// 事件纯逻辑:校验/规范化/重复展开/按日索引/序列化。
// 与 clock/Model.js 的约定一致:零 Qt/locale 依赖,可被 node 单测,
// QML 只负责展示与 I/O 时机。

var MS_PER_DAY = 86400000

// ---- 日期键工具("yyyy-MM-dd",全部本地时区,与 Model.js dateKey 同源) ----

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function dateKeyOf(year, month, day) {
  return year + "-" + pad2(month + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKeyOf(date.getFullYear(), date.getMonth(), date.getDate())
}

function parseKey(key) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ""))
  if (!m) return null
  var year = parseInt(m[1], 10)
  var month = parseInt(m[2], 10) - 1
  var day = parseInt(m[3], 10)
  if (year < 1900 || year > 9999 || month < 0 || month > 11 || day < 1 || day > 31) return null
  var probe = new Date(year, month, day)
  if (probe.getFullYear() !== year || probe.getMonth() !== month || probe.getDate() !== day) return null
  return { year: year, month: month, day: day }
}

// 以 UTC 参考做纯代数运算,避免 DST 干扰跨日加减
function toUtcMs(key) {
  var p = parseKey(key)
  if (!p) return NaN
  return Date.UTC(p.year, p.month, p.day)
}

function addDays(key, amount) {
  var ms = toUtcMs(key)
  if (!isFinite(ms)) return ""
  var d = new Date(ms + Number(amount) * MS_PER_DAY)
  return dateKeyOf(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())
}

function diffDays(fromKey, toKey) {
  var a = toUtcMs(fromKey)
  var b = toUtcMs(toKey)
  if (!isFinite(a) || !isFinite(b)) return NaN
  return Math.round((b - a) / MS_PER_DAY)
}

function cmpKeys(a, b) {
  if (a === b) return 0
  return a < b ? -1 : 1
}

function daysInMonth(year, month) {
  return new Date(year, month + 1, 0).getDate()
}

function isLeapYear(year) {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0
}

function todayKey(now) {
  return keyForDate(now || new Date())
}

// ---- 字段规范化 ----

var REPEATS = ["none", "daily", "weekly", "monthly", "yearly"]

// 标签:important=重要(红点)/ normal=普通(绿点);缺省按普通
var FLAGS = ["normal", "important"]

// 状态:todo=待办(空心圆)/ inprogress=进行中(半圆)/ done=已完成(实心圆)
var STATUSES = ["todo", "inprogress", "done"]

function normalizeFlag(value) {
  var v = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return FLAGS.indexOf(v) !== -1 ? v : "normal"
}

function normalizeStatus(value) {
  var v = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return STATUSES.indexOf(v) !== -1 ? v : "todo"
}

function normalizeRepeat(value) {
  var v = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return REPEATS.indexOf(v) !== -1 ? v : "none"
}

// 只接受 HH:MM;返回两位格式或 null
function normalizeTime(value) {
  var t = String(value === undefined || value === null ? "" : value).trim()
  if (t === "") return null
  var m = /^([01]?\d|2[0-3]):([0-5]\d)$/.exec(t)
  if (!m) return null
  return pad2(m[1]) + ":" + m[2]
}

function normalizeTitle(value) {
  var t = String(value === undefined || value === null ? "" : value)
  t = t.replace(/^\s+|\s+$/g, "")
  return t.length > 120 ? t.slice(0, 120) : t
}

function normalizeNote(value) {
  var t = String(value === undefined || value === null ? "" : value)
  t = t.replace(/^\s+|\s+$/g, "")
  return t.length > 300 ? t.slice(0, 300) : t
}

function normalizeDate(value) {
  if (value === undefined || value === null) return null
  var p = parseKey(String(value).trim())
  return p ? String(value).trim() : null
}

// 多日与重复互斥:endDate 一旦大于 date,repeat 强制 none
function normalizeEvent(raw) {
  if (!raw || typeof raw !== "object") return null
  var date = normalizeDate(raw.date)
  if (!date) return null
  var title = normalizeTitle(raw.title)
  if (title === "") return null
  var endDate = normalizeDate(raw.endDate)
  if (endDate && cmpKeys(endDate, date) < 0) endDate = null
  var time = normalizeTime(raw.time)
  var repeat = normalizeRepeat(raw.repeat)
  var repeatUntil = normalizeDate(raw.repeatUntil)
  if (endDate && endDate !== date) repeat = "none"
  if (repeat === "none") repeatUntil = null
  var exceptions = []
  if (Array.isArray(raw.exceptions)) {
    for (var i = 0; i < raw.exceptions.length; i++) {
      var k = normalizeDate(raw.exceptions[i])
      if (k && k !== date && exceptions.indexOf(k) === -1) exceptions.push(k)
    }
    exceptions.sort()
  }
  return {
    id: String(raw.id === undefined || raw.id === null ? "" : raw.id),
    title: title,
    flag: normalizeFlag(raw.flag),
    status: normalizeStatus(raw.status),
    date: date,
    endDate: endDate,
    time: time,
    note: normalizeNote(raw.note),
    repeat: repeat,
    repeatUntil: repeatUntil,
    remind: raw.remind !== false,
    exceptions: exceptions
  }
}

// 库级清洗:丢掉畸形条目,补全缺失 id
function sanitizeEvents(raw) {
  var list = []
  if (raw && typeof raw === "object" && Array.isArray(raw.events)) {
    for (var i = 0; i < raw.events.length; i++) {
      var e = normalizeEvent(raw.events[i])
      if (!e) continue
      if (e.id === "") e.id = makeId(e.date)
      list.push(e)
    }
  }
  return list
}

function makeId(dateKey) {
  var stamp = Date.now().toString(36)
  var rand = Math.floor(Math.random() * 0xffffff).toString(36)
  var p = parseKey(dateKey)
  var suffix = p ? "" + p.year + pad2(p.month + 1) + pad2(p.day) : ""
  return "evt-" + suffix + "-" + stamp + rand
}

// 表单字段 → 事件对象;带 id 则保留(编辑,exceptions 由调用方并回)
function buildEvent(fields) {
  var f = fields || {}
  var e = normalizeEvent({
    id: f.id,
    title: f.title,
    flag: f.flag,
    status: f.status,
    date: f.date,
    endDate: f.endDate,
    time: f.time,
    note: f.note,
    repeat: f.repeat,
    repeatUntil: f.repeatUntil,
    remind: f.remind,
    exceptions: f.exceptions
  })
  if (!e) return null
  if (e.id === "") e.id = makeId(e.date)
  return e
}

// ---- 出现展开 ----

// 事件是否覆盖 dateKey(多日段内任一天都算;重复事件总是单日段)
function eventCoversKey(event, key) {
  var end = event.endDate && event.endDate !== event.date ? event.endDate : event.date
  return cmpKeys(event.date, key) <= 0 && cmpKeys(key, end) <= 0
}

function isException(event, key) {
  return event.exceptions && event.exceptions.indexOf(String(key)) !== -1
}

// 单条事件的开始日键序列,取与 [from,to] 相交的部分。
// 规则:daily 每天 / weekly 同星期几 / monthly 每月同“日”(该月无此日则跳过)
//      / yearly 每年同月日(闰 2/29 非闰年跳过);repeatUntil 截断;exceptions 排除。
function occurrenceStartKeys(event, fromKey, toKey, cap) {
  var max = Number(cap) > 0 ? Number(cap) : 2000
  var start = event.date
  var until = event.repeatUntil && cmpKeys(event.repeatUntil, toKey) < 0 ? event.repeatUntil : toKey
  var from = cmpKeys(fromKey, start) >= 0 ? fromKey : start
  if (cmpKeys(from, until) > 0 || cmpKeys(start, toKey) > 0) return []
  var out = []

  function pushIf(key) {
    if (key === "" || isException(event, key)) return
    if (cmpKeys(key, from) < 0 || cmpKeys(key, until) > 0) return
    if (out.length >= max) return
    out.push(key)
  }

  var pStart = parseKey(start)
  if (event.repeat === "daily") {
    var days = diffDays(from, until)
    for (var i = 0; i <= days && out.length < max; i++) pushIf(addDays(from, i))
  } else if (event.repeat === "weekly") {
    var gap = Math.max(0, diffDays(start, from))
    var weeks = Math.floor(gap / 7)
    for (var w = 0; w <= 2000 && out.length < max; w++) {
      var wk = addDays(start, (weeks + w) * 7)
      if (wk === "" || cmpKeys(wk, until) > 0) break
      if (cmpKeys(wk, from) >= 0) pushIf(wk)
    }
  } else if (event.repeat === "monthly") {
    var mFrom = parseKey(from)
    var stepStart = (mFrom.year * 12 + mFrom.month) - (pStart.year * 12 + pStart.month)
    for (var step = stepStart; step < 2400 && out.length < max; step++) {
      var idx = pStart.year * 12 + pStart.month + step
      var y = Math.floor(idx / 12)
      var mo = idx % 12
      if (mo < 0) { mo += 12; y -= 1 }
      if (pStart.day > daysInMonth(y, mo)) continue
      var mk = dateKeyOf(y, mo, pStart.day)
      if (cmpKeys(mk, until) > 0) break
      pushIf(mk)
    }
  } else if (event.repeat === "yearly") {
    var yFrom = parseKey(from)
    var firstYear = yFrom.year - pStart.year
    for (var ys = firstYear; ys < 3000 && out.length < max; ys++) {
      var yy = pStart.year + ys
      if (pStart.month === 1 && pStart.day === 29 && !isLeapYear(yy)) continue
      var yk = dateKeyOf(yy, pStart.month, pStart.day)
      if (cmpKeys(yk, until) > 0) break
      pushIf(yk)
    }
  } else {
    if (cmpKeys(start, until) <= 0) pushIf(start)
  }
  return out
}

// 展示用出现条目:{ key, endKey, event }
function occurrenceForEvent(event, key) {
  if (!eventCoversKey(event, key)) return null
  return {
    key: key,
    endKey: event.endDate && event.endDate !== event.date ? event.endDate : key,
    event: event
  }
}

// 视图查询:dateKey → [ {key,endKey,event} ](仅窗口内;重复段展开到整天)
function indexByDate(events, fromKey, toKey, cap) {
  var map = {}
  if (!fromKey || !toKey || cmpKeys(fromKey, toKey) > 0) return map
  var list = Array.isArray(events) ? events : []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (!e || !e.date) continue
    if (normalizeRepeat(e.repeat) !== "none") {
      // 重复出现:每个开始日都是合法覆盖日(单日段),不再经过
      // eventCoversKey 的“base date 段”判定(那会把 k > date 判成不覆盖)
      var starts = occurrenceStartKeys(e, fromKey, toKey, cap)
      for (var s = 0; s < starts.length; s++) {
        var k = starts[s]
        if (!k) continue
        if (!map[k]) map[k] = []
        map[k].push({ key: k, endKey: k, event: e })
      }
    } else {
      // 单次事件(可多日):与窗口相交的每一天都登记
      if (!eventCoversKey(e, fromKey) && !eventCoversKey(e, toKey)
          && (cmpKeys(e.date, fromKey) < 0 || cmpKeys(e.date, toKey) > 0)) {
        if (!(e.endDate && e.endDate !== e.date)) continue
      }
      var lo = cmpKeys(e.date, fromKey) >= 0 ? e.date : fromKey
      var hi = e.endDate && e.endDate !== e.date ? e.endDate : e.date
      if (cmpKeys(hi, toKey) > 0) hi = toKey
      if (cmpKeys(lo, hi) > 0) continue
      var span = diffDays(lo, hi)
      for (var d = 0; d <= span; d++) {
        var covered = addDays(lo, d)
        if (!map[covered]) map[covered] = []
        map[covered].push(occurrenceForEvent(e, covered))
      }
    }
  }
  return map
}

// 排序:全天(无时间)在前,再按时间升序,同时间按标题
function timeRank(o) {
  var t = o && o.event && o.event.time
  if (!t) return -1
  return parseInt(t.slice(0, 2), 10) * 60 + parseInt(t.slice(3, 5), 10)
}

function sortOccurrences(arr) {
  if (!arr) return arr
  return arr.slice().sort(function(a, b) {
    var ta = timeRank(a)
    var tb = timeRank(b)
    if (ta !== tb) return ta - tb
    var taTitle = String(a.event.title)
    var tbTitle = String(b.event.title)
    if (taTitle === tbTitle) return 0
    return taTitle < tbTitle ? -1 : 1
  })
}

function hasAnyOn(map, key) {
  return map && Array.isArray(map[key]) && map[key].length > 0
}

// 某日首个事件(列表已按 sortOccurrences 排过),用作格内小点上限之外的提示?
// 保留占位以扩展 —— 当前无额外语义。
function describeRange(event) {
  if (event.endDate && event.endDate !== event.date)
    return event.date + " ~ " + event.endDate
  return event.date
}

if (typeof module !== "undefined") {
  module.exports = {
    pad2: pad2,
    dateKeyOf: dateKeyOf,
    keyForDate: keyForDate,
    parseKey: parseKey,
    addDays: addDays,
    diffDays: diffDays,
    cmpKeys: cmpKeys,
    daysInMonth: daysInMonth,
    isLeapYear: isLeapYear,
    todayKey: todayKey,
    REPEATS: REPEATS,
    FLAGS: FLAGS,
    STATUSES: STATUSES,
    normalizeFlag: normalizeFlag,
    normalizeStatus: normalizeStatus,
    normalizeRepeat: normalizeRepeat,
    normalizeTime: normalizeTime,
    normalizeTitle: normalizeTitle,
    normalizeNote: normalizeNote,
    normalizeDate: normalizeDate,
    normalizeEvent: normalizeEvent,
    sanitizeEvents: sanitizeEvents,
    makeId: makeId,
    buildEvent: buildEvent,
    eventCoversKey: eventCoversKey,
    isException: isException,
    occurrenceStartKeys: occurrenceStartKeys,
    occurrenceForEvent: occurrenceForEvent,
    indexByDate: indexByDate,
    sortOccurrences: sortOccurrences,
    hasAnyOn: hasAnyOn,
    describeRange: describeRange
  }
}
