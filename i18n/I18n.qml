pragma Singleton
import QtQml

// xechoz.clock 多语言(zh / en)单例。
//
// 语言解析:
//   - language 为 "" / "auto" → 跟随系统 Qt.locale().name(zh* → zh,其余 → en)
//   - 显式 "zh" / "zh_CN" / "en" / "en_US" 等 → 强制指定语言
// 由 Panel 注入 language(读内联设置 setting("language","")),
// 设置变更时所有 `I18n.tr(...)` / 日期格式化依赖绑定自动重算。
//
// tr(key, args):字典查找 + "{0}" 占位符替换;缺 key 回退英文,再回退 key 本身。
QtObject {
  id: root

  property string language: ""

  readonly property string lang: {
    var want = String(root.language || "").trim().toLowerCase()
    if (want !== "" && want !== "auto") {
      var norm = want.split(/[-_]/)[0]
      if (norm === "zh" || norm === "en") return norm
      return norm
    }
    var sys = String(Qt.locale().name).toLowerCase()
    return sys.indexOf("zh") === 0 ? "zh" : "en"
  }

  // 与 lang 对应的展示 locale 名:日期/星期名称按所选语言渲染。
  // 注意:QLocale 存在 property var 里再传给 C++ 函数会被 Qt6 拒绝,
  // 所有格式化都经下方辅助函数每次现场 Qt.locale(localeName) 构造。
  readonly property string localeName: root.lang === "zh" ? "zh_CN" : "en_US"

  readonly property var dict: ({
    zh: {
      // ---- Panel.qml 删除确认 ----
      delete_title: "删除「{0}」?",
      delete_all: "整条删除(含以后所有出现)",
      delete_this_only: "仅去掉这一天",
      delete: "删除",
      cancel: "取消",

      // ---- CalendarContent ----
      back_to_today: "回到今天",
      born: "BORN",
      year: "年份",
      live_to: "LIVE TO",
      life: "LIFE",
      start_weeks_on: "以 {0} 为一周起点",
      prev_month: "上个月",
      next_month: "下个月",

      // ---- DayEvents ----
      no_events: "暂无安排",
      events_count: "{0} 项安排",
      add_tooltip: "添加事件(快捷键 A)",
      empty_hint: "这天还没有安排 · 点右上角 + 添加",
      edit_event: "编辑事件",
      add_event: "添加事件",
      dismiss_error: "关闭提示",

      // ---- EventForm ----
      title_required: "标题不能为空",
      time_format_error: "时间格式应为 HH:MM(如 14:30)",
      done_remind_off: "已完成事件自动关闭提醒",
      time_bad_remind: "时间格式不正确,无法计算提醒时刻",
      remind_desc: "分钟前 · 将于 {0} 提醒",
      title_placeholder: "要记点什么呢…",
      time_label: "时间(留空 = 全天)",
      clear_time_tooltip: "清空时间(变为全天)",
      flag: "标签",
      flag_normal: "普通",
      flag_important: "重要",
      status: "状态",
      status_todo: "待办",
      status_inprogress: "进行中",
      status_done: "已完成",
      remind: "提醒",
      save_changes: "保存修改",
      add: "添加",

      // ---- EventList ----
      status_tooltip: "状态:{0}(点击切换)",
      all_day: "全天",
      delete_row_tooltip: "删除(点击行本身可编辑)",
      repeat_daily: "每天",
      repeat_weekly: "每周",
      repeat_monthly: "每月",
      repeat_yearly: "每年",

      // ---- EventStore ----
      load_error: "事件数据读取失败(文件损坏?)",
      save_incomplete: "事件信息不完整,无法保存",

      // ---- ReminderEngine ----
      notify_time: "时间 {0}",
      notify_all_day: "全天事件",
      notify_day_n: "第 {0} 天",

      // ---- 中国节假日 ----
      holiday_rest: "休",
      holiday_work: "班"
    },
    en: {
      delete_title: "Delete \"{0}\"?",
      delete_all: "Delete all (incl. future occurrences)",
      delete_this_only: "Only this day",
      delete: "Delete",
      cancel: "Cancel",

      back_to_today: "Back to today",
      born: "BORN",
      year: "year",
      live_to: "LIVE TO",
      life: "LIFE",
      start_weeks_on: "Start weeks on {0}",
      prev_month: "Previous month",
      next_month: "Next month",

      no_events: "No events",
      events_count: "{0} event(s)",
      add_tooltip: "Add event (A)",
      empty_hint: "Nothing here yet · tap + to add",
      edit_event: "Edit event",
      add_event: "Add event",
      dismiss_error: "Dismiss",

      title_required: "Title is required",
      time_format_error: "Time must be HH:MM (e.g. 14:30)",
      done_remind_off: "Reminders are off for done events",
      time_bad_remind: "Invalid time, cannot compute reminder",
      remind_desc: "min before · at {0}",
      title_placeholder: "What to note…",
      time_label: "Time (empty = all day)",
      clear_time_tooltip: "Clear time (all-day)",
      flag: "Flag",
      flag_normal: "Normal",
      flag_important: "Important",
      status: "Status",
      status_todo: "Todo",
      status_inprogress: "In progress",
      status_done: "Done",
      remind: "Remind",
      save_changes: "Save",
      add: "Add",

      status_tooltip: "Status: {0} (click to change)",
      all_day: "All day",
      delete_row_tooltip: "Delete (click the row itself to edit)",
      repeat_daily: "Daily",
      repeat_weekly: "Weekly",
      repeat_monthly: "Monthly",
      repeat_yearly: "Yearly",

      load_error: "Failed to read events (corrupt file?)",
      save_incomplete: "Incomplete event, cannot save",

      notify_time: "Time {0}",
      notify_all_day: "All-day event",
      notify_day_n: "Day {0}",

      holiday_rest: "rest",
      holiday_work: "work"
    }
  })

  function tr(key, args) {
    var table = root.dict[root.lang] || root.dict.en
    var text = table[key]
    if (text === undefined) text = root.dict.en[key]
    if (text === undefined) return String(key)
    return root.subst(text, args)
  }

  function subst(text, args) {
    var out = String(text)
    if (!args) return out
    if (Array.isArray(args)) {
      for (var i = 0; i < args.length; i++)
        out = out.replace(new RegExp("\\{" + i + "\\}", "g"), String(args[i]))
    } else {
      for (var k in args)
        out = out.split("{" + k + "}").join(String(args[k]))
    }
    return out
  }

  // 选中日头部:zh "3月5日" / en "March 5"
  function dayHeader(year, month, day) {
    var fmt = root.lang === "zh" ? "M月d日" : "MMMM d"
    return Qt.locale(root.localeName).toString(new Date(year, month, day), fmt)
  }

  // 星期名称(0=周日):zh 短格式 "周日" / en 长格式 "Sunday"
  function weekdayName(weekday) {
    var fmt = root.lang === "zh" ? Locale.ShortFormat : Locale.LongFormat
    return Qt.locale(root.localeName).dayName(weekday, fmt)
  }

  // 通用星期名(调用方指定格式)
  function dayName(weekday, fmt) {
    return Qt.locale(root.localeName).dayName(weekday, fmt)
  }

  // 带所选语言 locale 的日期格式化(替代 Qt.formatDate 的两参版本)
  function formatDate(date, fmt) {
    return Qt.locale(root.localeName).toString(date, fmt)
  }

  function formatDateTime(date, fmt) {
    return Qt.locale(root.localeName).toString(date, fmt)
  }

  // 是否“中国语境”:显式/跟随语言为中文,或系统 locale 为中国区,
  // 或时区为 UTC+8(中国全域无夏令时)。节假日功能据此默认开启。
  function isChinaContext() {
    if (root.lang === "zh") return true
    var name = String(Qt.locale().name).toLowerCase()
    if (name.indexOf("zh") === 0) return true
    if (/_cn$/.test(name)) return true
    return new Date().getTimezoneOffset() === -480
  }
}
