// 中国法定节假日数据(内置 + 联网年份的解析/合并,纯 JS 无 Qt 依赖)。
//
// 数据源:NateScarlet/holiday-cn(https://github.com/NateScarlet/holiday-cn),
// 年份 JSON 形如 [{"name":"国庆节","date":"2026-10-01","isOffDay":true}, ...],
// isOffDay=false 即调休上班日。内置 2026 全年(含 gov.cn 红头文件依据);
// 之后的年份由 HolidayStore 联网拉取同一仓库,成功后合并进表。
//
// 表结构:year → { "yyyy-MM-dd": { rest: bool, name: 中文名 } }

// 内置年份:2026(国务院《关于2026年部分节假日安排的通知》,
// https://www.gov.cn/zhengce/zhengceku/202511/content_7047091.htm)
var BUNDLED = {
  "2026": {
    // 元旦:1/1–1/3 休;1/4(周日)上班
    "2026-01-01": { rest: true, name: "元旦" },
    "2026-01-02": { rest: true, name: "元旦" },
    "2026-01-03": { rest: true, name: "元旦" },
    "2026-01-04": { rest: false, name: "元旦" },
    // 春节:2/15–2/23 休;2/14(周六)、2/28(周六)上班
    "2026-02-14": { rest: false, name: "春节" },
    "2026-02-15": { rest: true, name: "春节" },
    "2026-02-16": { rest: true, name: "春节" },
    "2026-02-17": { rest: true, name: "春节" },
    "2026-02-18": { rest: true, name: "春节" },
    "2026-02-19": { rest: true, name: "春节" },
    "2026-02-20": { rest: true, name: "春节" },
    "2026-02-21": { rest: true, name: "春节" },
    "2026-02-22": { rest: true, name: "春节" },
    "2026-02-23": { rest: true, name: "春节" },
    "2026-02-28": { rest: false, name: "春节" },
    // 清明节:4/4–4/6 休
    "2026-04-04": { rest: true, name: "清明节" },
    "2026-04-05": { rest: true, name: "清明节" },
    "2026-04-06": { rest: true, name: "清明节" },
    // 劳动节:5/1–5/5 休;5/9(周六)上班
    "2026-05-01": { rest: true, name: "劳动节" },
    "2026-05-02": { rest: true, name: "劳动节" },
    "2026-05-03": { rest: true, name: "劳动节" },
    "2026-05-04": { rest: true, name: "劳动节" },
    "2026-05-05": { rest: true, name: "劳动节" },
    "2026-05-09": { rest: false, name: "劳动节" },
    // 端午节:6/19–6/21 休
    "2026-06-19": { rest: true, name: "端午节" },
    "2026-06-20": { rest: true, name: "端午节" },
    "2026-06-21": { rest: true, name: "端午节" },
    // 中秋节:9/25–9/27 休
    "2026-09-25": { rest: true, name: "中秋节" },
    "2026-09-26": { rest: true, name: "中秋节" },
    "2026-09-27": { rest: true, name: "中秋节" },
    // 国庆节:10/1–10/7 休;9/20(周日)、10/10(周六)上班
    "2026-09-20": { rest: false, name: "国庆节" },
    "2026-10-01": { rest: true, name: "国庆节" },
    "2026-10-02": { rest: true, name: "国庆节" },
    "2026-10-03": { rest: true, name: "国庆节" },
    "2026-10-04": { rest: true, name: "国庆节" },
    "2026-10-05": { rest: true, name: "国庆节" },
    "2026-10-06": { rest: true, name: "国庆节" },
    "2026-10-07": { rest: true, name: "国庆节" },
    "2026-10-10": { rest: false, name: "国庆节" }
  }
}

// 七大节日英文名(兜底:未收录的沿用中文名)
var EN_NAMES = {
  "元旦": "New Year's Day",
  "春节": "Spring Festival",
  "清明节": "Qingming Festival",
  "劳动节": "Labor Day",
  "端午节": "Dragon Boat Festival",
  "中秋节": "Mid-Autumn Festival",
  "国庆节": "National Day"
}

// 内置表深拷贝(合并时不被外部改写)
function bundledTable() {
  return mergeInto({}, BUNDLED)
}

// 把 holiday-cn 年份 payload 解析成 year → dateKey → {rest,name} 表
function parseYearPayload(year, text) {
  var table = {}
  var arr = null
  try {
    arr = JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
  if (arr && typeof arr === "object" && Array.isArray(arr.days)) arr = arr.days
  if (!Array.isArray(arr)) return null
  var y = String(year)
  for (var i = 0; i < arr.length; i++) {
    var d = arr[i]
    if (!d || typeof d !== "object") continue
    var date = String(d.date || "")
    var name = String(d.name || "").replace(/^\s+|\s+$/g, "")
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || name === "") continue
    table[date] = { rest: d.isOffDay !== false, name: name }
  }
  var out = {}
  out[y] = table
  return out
}

// 把多张 year→表 浅合并进 target 并返回(target 会被就地修改)
function mergeInto(target, tables) {
  var src = arguments.length > 2 ? [].slice.call(arguments, 1) : (tables !== undefined ? [tables] : [])
  for (var i = 0; i < src.length; i++) {
    var t = src[i]
    if (!t || typeof t !== "object") continue
    for (var year in t) {
      if (!t[year] || typeof t[year] !== "object") continue
      target[year] = t[year]
    }
  }
  return target
}

// 某年是否已有数据
function hasYear(table, year) {
  return table && table[String(year)] && typeof table[String(year)] === "object"
}

// 日期条目 → 展示名(按语言)
function labelFor(entry, lang) {
  if (!entry || typeof entry !== "object") return ""
  if (lang === "en") return EN_NAMES[entry.name] || entry.name
  return entry.name
}

if (typeof module !== "undefined") {
  module.exports = {
    BUNDLED: BUNDLED,
    EN_NAMES: EN_NAMES,
    bundledTable: bundledTable,
    parseYearPayload: parseYearPayload,
    mergeInto: mergeInto,
    hasYear: hasYear,
    labelFor: labelFor
  }
}
