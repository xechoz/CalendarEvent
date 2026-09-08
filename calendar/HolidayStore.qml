import QtQuick
import Quickshell.Io
import "Holidays.js" as Holidays

// 中国节假日数据仓库(calendar/ 模块):内置 2026 全年 + 联网拉取
// holiday-cn 仓库后续年份 JSON。合并表整体重赋(table = ...)触发
// 变更通知,编排层据此把新表注入 CalendarContent/DayEvents。
//
// 拉取策略:每会话对缺失年份只尝试一次,失败静默(断网/年份未公布
// 时日历照常显示,仅无节假日标记);面板重开时 reset() 允许再试。
Item {
  id: root

  // 合并表:year → { "yyyy-MM-dd": { rest: bool, name: 中文名 } }
  property var table: Holidays.bundledTable()

  // 会话内已失败的年份,不反复打网络
  property var _failed: ({})
  property string _pendingYear: ""

  function reset() { root._failed = ({}) }

  // 缺该年数据且未失败/未在途时拉取
  function ensureYear(year) {
    var y = String(year)
    if (!/^\d{4}$/.test(y)) return
    if (Holidays.hasYear(root.table, y)) return
    if (root._failed[y]) return
    if (fetchProc.running) return
    root._pendingYear = y
    fetchProc.command = ["curl", "-fsS", "--max-time", "10",
      "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/" + y + ".json"]
    fetchProc.running = true
  }

  Process {
    id: fetchProc

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") { root._failed[root._pendingYear] = true; return }
        var parsed = Holidays.parseYearPayload(root._pendingYear, raw)
        // 年份占位(days 为空 = 国务院尚未公布)视同失败:不并入表,
        // 面板重开时重试,公布后即自动出现
        if (!parsed || Object.keys(parsed[root._pendingYear] || {}).length === 0) {
          root._failed[root._pendingYear] = true
          return
        }
        root.table = Holidays.mergeInto(Holidays.bundledTable(), root.table, parsed)
      }
    }
  }
}
