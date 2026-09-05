import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls as QC
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "events/EventsModel.js" as EM
import "calendar"
import "events"
import "reminders"

// xechoz.clock 协调层(瘦身版)。
//
// 职责边界:
//   - 唯一状态持有者:today / 视图年月 / 周起始 / 生卒 / 选中日 / 面板开合
//   - 事件数据:持有 EventStore(唯一数据源)与 ReminderEngine 实例
//   - 展示:CalendarContent(月历本体)与 DayEvents(选中日事件区)只拿
//     props 并上抛信号;本文件负责接线/计算索引(圆点 dayCounts)
//   - 所有持久化(格式循环在 BarWidget、周起始/生卒/事件目录配置)走
//     真实布局条目 id(resolveEnabledId),克隆后仍能写回 shell.json
//
// BarWidget.qml 负责栏上标签与弹出契约;本面板是其 popup 内容宿主。
Panel {
  id: root
  moduleName: "xechoz.clock"
  ipcTarget: "xechoz.clock"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock 跨午夜保持诚实,无需重开面板即可滚动高亮。
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // ---- 屏幕上显示的月(只此一处可改)
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth:
    viewYear === today.getFullYear() && viewMonth === today.getMonth()

  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  property bool editingLife: false

  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)

  // ---- 选中日(事件区联动)
  property string selectedKey: ""

  // ---- 事件数据源与提醒引擎
  property bool eventsConfigured: false

  // 运行时自检(IPC eventsDebug 调用;便于排查克隆后的持久化/数据问题)
  function debugInfo() {
    return "loaded=" + store.loaded + " events=" + store.events.length
      + " err=" + JSON.stringify(store.lastError)
      + " notified=" + store.notifiedLoaded + " notifiedKeys=" + store.notifiedKeys.length
      + " sel=" + root.selectedKey + " today=" + root.todayKey
      + " cc=" + Math.round(calendarContent.width) + "x" + Math.round(calendarContent.height)
      + " deH=" + Math.round(dayEvents.implicitHeight)
      + " colI=" + Math.round(contentColumn.implicitHeight)
      + " occ=" + dayEvents.occurrences.length
      + " dots=" + JSON.stringify(root.dayDots)
  }

  // ---- 当月格事件索引(dateKey → 该日圆点数组,仅当月格窗口;圆点用)。
  // 每个元素是布尔:true=重要(橙点)/ false=普通(蓝点);每日最多 3 个,
  // 重要事件排在前面,保证橙点不会被普通事件挤掉。
  property var dayDots: ({})

  // ---- 圆点配色:重要=固定 #e0744e(暖橘);普通取当前主题 colors.toml 的 blue
  // (窗口/弹窗边框的 Omarchy 蓝,主题换色时 FileView 会重读;缺省 #7aa2f7)。
  property var themeBlueToken: ""
  readonly property color dotRed: "#e0744e"
  readonly property color dotGreen: root.hexColor(root.themeBlueToken, "#7aa2f7")

  function hexColor(token, fallback) {
    return typeof token === "string" && /^#[0-9A-Fa-f]{6}$/.test(token) ? token : fallback
  }

  function loadThemeColors(text) {
    var blue = ""
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = /^\s*blue\s*=\s*["']?(#[0-9A-Fa-f]{6})/.exec(lines[i])
      if (m) blue = m[1]
    }
    root.themeBlueToken = blue
  }

  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // 周起始/生卒配置等经 shell.json 内联条目写入;条目 id 可能因克隆/改名
  // 与 moduleName 不同,必须按“实际生效条目”解析而不是硬编码。
  function entryId() {
    var shell = root.bar ? root.bar.shell : null
    var registry = shell ? shell.pluginRegistry : null
    if (registry && typeof registry.resolveEnabledId === "function")
      return registry.resolveEnabledId(root.moduleName)
    return root.moduleName
  }

  // 事件文件目录可由内联设置覆盖(留空用默认)
  function applyEventsConfig() {
    var dir = String(root.setting("eventsDataDir", "") || "").trim()
    store.dataDir = dir
    store.helperPath = ""
    if (!root.eventsConfigured) {
      root.eventsConfigured = true
      Qt.callLater(function() {
        store.refresh()
        store.refreshNotified()
      })
    } else {
      store.refresh()
    }
  }

  // 重算当月格圆点索引(窗口 = 首行首日 ~ 末行末日)。
  // 每日取 出现列表按时间排序后,重要(flag=important)在前、普通在后,
  // 截前 3 个作为该日圆点(布尔数组)。
  function updateDayCounts() {
    var all = store && store.loaded ? store.events : []
    var grid = Model.monthGrid(root.viewYear, root.viewMonth, root.weekStart, root.todayKey)
    var first = grid.length > 0 && grid[0].days.length > 0 ? grid[0].days[0].key : ""
    var last = grid.length > 0 ? grid[5].days[6].key : ""
    if (first === "" || last === "") { root.dayDots = ({}); return }
    var map = store.coverage(first, last)
    var dots = {}
    for (var key in map) {
      var list = EM.sortOccurrences(map[key] || [])
      if (list.length === 0) continue
      var important = []
      var normal = []
      for (var i = 0; i < list.length; i++) {
        var ev = list[i].event
        if (ev && ev.flag === "important") important.push(true)
        else normal.push(false)
      }
      var merged = important.concat(normal)
      if (merged.length > 3) merged = merged.slice(0, 3)
      dots[key] = merged
    }
    root.dayDots = dots
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
    store.refresh()
  }

  // ------------------------------------------------------------ 选日

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  function open() {
    refresh()
    themeColorsView.reload()
    if (root.selectedKey === "") root.selectedKey = root.todayKey
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLife) root.cancelEditingLife()
    if (dayEvents) dayEvents.closeForm()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // 本地先生效再写 shell.json(由 bar 回写同值);克隆后经 entryId() 命中真实条目
  function persistSettings(values) {
    var entry = { id: root.entryId() }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.entryId(), entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // ---- 生卒(视图字段在 CalendarContent,状态与本文件持久化) ----
  function startEditingLife() {
    root.editingLife = true
    calendarContent.beginLifeEditing()
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function commitLife(born, span) {
    if (born >= 0 || span >= 0)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }



  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  // ============================================================ 事件与提醒
  EventStore {
    id: store
  }

  ReminderEngine {
    id: reminder
    store: store
  }

  // 当前主题 colors.toml 的 blue(普通事件圆点配色用);换主题后自动重读。
  // 文件由 omarchy 在切换主题时替换,FileView 换文件也会触发 reload。
  FileView {
    id: themeColorsView
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeColors(text())
    onFileChanged: reload()
    onLoadFailed: root.loadThemeColors("")
  }

  Connections {
    target: store
    function onEventsChanged() { root.updateDayCounts() }
  }

  onViewYearChanged: root.updateDayCounts()
  onViewMonthChanged: root.updateDayCounts()
  onWeekStartChanged: root.updateDayCounts()

  onSettingsChanged: {
    root.applyEventsConfig()
    // 生卒/周起始回写会改 settings;数值型只读属性自动跟随
  }

  Component.onCompleted: {
    root.applyEventsConfig()
    Qt.callLater(function() {
      if (store && store.loaded) root.updateDayCounts()
    })
  }

component DangerBtn: Item {
  id: db

  property string text: ""
  property string iconText: ""
  property color fill: Qt.darker(Color.urgent, 1.15)
  property color foreground: Color.background
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.bodySmall

  signal clicked()

  readonly property bool hot: dbMouse.containsMouse
  readonly property bool down: dbMouse.pressed

  implicitWidth: content.implicitWidth + Style.space(24)
  implicitHeight: Style.spacing.controlHeight
  activeFocusOnTab: true

  opacity: db.down ? 0.7 : 1
  Behavior on opacity { NumberAnimation { duration: 90 } }

  Keys.onSpacePressed: { db.clicked(); event.accepted = true }
  Keys.onReturnPressed: { db.clicked(); event.accepted = true }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: db.fill
  }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: "#ffffff"
    opacity: db.hot && !db.down ? 0.1 : 0
    Behavior on opacity { NumberAnimation { duration: 90 } }
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -Style.space(2)
    radius: Style.cornerRadius + Style.space(2)
    color: "transparent"
    border.width: db.activeFocus ? Style.spacing.hairline * 2 : 0
    border.color: db.activeFocus ? Color.urgent : "transparent"
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      visible: db.iconText !== ""
      text: db.iconText
      color: db.foreground
      font.family: db.fontFamily
      font.pixelSize: db.fontSize
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: db.text
      color: db.foreground
      font.family: db.fontFamily
      font.pixelSize: db.fontSize
      font.bold: true
    }
  }

  MouseArea {
    id: dbMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: db.clicked()
  }
}

  // ============================================================ 面板布局
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife || (dayEvents && dayEvents.panelKeyBlocked)
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
        else if (t === "a" || t === "A") {
          if (dayEvents && !dayEvents.panelKeyBlocked) dayEvents.openAdd()
        }
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: contentColumn.width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: contentColumn
          // 不窄于月格,保证七列完整;弹层宽度上限由屏幕决定,超宽才滚动
          width: Math.max(calendarScroll.width, calendarContent.implicitWidth)
          spacing: Style.space(10)

          CalendarContent {
            id: calendarContent
            width: contentColumn.width
            today: root.today
            viewYear: root.viewYear
            viewMonth: root.viewMonth
            weekStart: root.weekStart
            birthYear: root.birthYear
            lifeExpectancy: root.lifeExpectancy
            editingLife: root.editingLife
            selectedKey: root.selectedKey
            dayDots: root.dayDots
            dotRed: root.dotRed
            dotGreen: root.dotGreen
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily

            onTodayRequested: root.goToToday()
            onMonthStep: function(delta) { root.moveMonth(delta) }
            onWeekStartToggled: root.toggleWeekStart()
            onLifeEditRequested: root.startEditingLife()
            onLifeClearRequested: root.clearLife()
            onLifeCommit: function(born, span) { root.commitLife(born, span) }
            onLifeEditCanceled: root.cancelEditingLife()
            onDayClick: function(dateKey, inMonth) {
              root.viewYear = parseInt(dateKey.slice(0, 4), 10)
              root.viewMonth = parseInt(dateKey.slice(5, 7), 10) - 1
              root.selectedKey = dateKey
            }
          }

          PanelSeparator {
            width: contentColumn.width
            foreground: root.contentForeground
          }

          DayEvents {
            id: dayEvents
            width: contentColumn.width
            store: store
            dateKey: root.selectedKey
            dotRed: root.dotRed
            dotGreen: root.dotGreen
            weekStart: root.weekStart
            foreground: root.contentForeground
            accent: Color.accent
            fontFamily: root.contentFontFamily

            onFormOpenChanged: {
              if (!dayEvents.formOpen && !root.editingLife)
                Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
            }
          }
        }
      }
    // ============================================================ 删除确认浮层
    // 覆盖整块弹层而非事件区:事件少时弹层高度小,若浮层只盖事件区,
    // 确认卡片会被压缩、底部按钮需滚动才能点。这里整体居中且有足够高度。
    Item {
      id: delLayer
      anchors.fill: parent
      visible: dayEvents && dayEvents.pendingDelete != null

      readonly property var pending: dayEvents ? dayEvents.pendingDelete : null
      readonly property bool multi: pending
        ? (!!pending.event.repeat && pending.event.repeat !== "none")
        : false
      readonly property string message: pending
        ? "删除「" + pending.event.title + "」?" : ""

      function close(): void {
        if (dayEvents) dayEvents.pendingDelete = null
        Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
      }

      Rectangle {
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.72)

        MouseArea {
          anchors.fill: parent
          onClicked: delLayer.close()
        }
      }

      BorderSurface {
        id: delCard
        width: Math.min(parent.width - Style.space(16), Style.space(360))
        // 内容超高才在卡内滚动;整层高度充足时正常情况不需要滚动
        height: Math.min(Math.max(delScrollContent.implicitHeight, Style.space(170)) + Style.space(32),
          Math.max(Style.space(60), parent.height - Style.space(24)))
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        color: Color.background
        borderSpec: Border.flat(Qt.darker(Color.urgent, 1.05), Style.normalBorderWidth)
        radius: Style.cornerRadius
        padding: Style.space(16)

        Flickable {
          id: delScroll
          anchors.fill: parent
          clip: true
          contentWidth: width
          contentHeight: delScrollContent.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          QC.ScrollBar.vertical: QC.ScrollBar { policy: delScrollContent.implicitHeight > delScroll.height
              ? QC.ScrollBar.AsNeeded : QC.ScrollBar.AlwaysOff }

          Column {
            id: delScrollContent
            width: parent.width
            spacing: Style.space(8)

            // ---- 标题区:红底删除图标 + 加粗标题 + 说明 ----
            Column {
              width: parent.width
              spacing: Style.space(8)

              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(40)
                height: Style.space(40)
                radius: Style.space(20)
                color: Util.alpha(Color.urgent, 0.14)

                Text {
                  anchors.centerIn: parent
                  text: "\uDB80\uDDB4"               // md-delete
                  color: Color.urgent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.subtitle + 4
                }
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: delLayer.message
                wrapMode: Text.Wrap
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: delLayer.multi
                wrapMode: Text.Wrap
                text: "这是重复出现的事件,可以只去掉这一天,或整条删除。"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // ---- 操作区:删除红实底;取消/仅此天为描边 ----
            Column {
              width: parent.width
              spacing: Style.space(8)
              topPadding: Style.space(4)

              DangerBtn {
                width: parent.width
                visible: delLayer.multi
                text: "整条删除(含以后所有出现)"
                iconText: "\uDB80\uDDB4"
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                onClicked: dayEvents.confirmDeleteAll()
              }

              Row {
                id: actRow
                width: parent.width
                spacing: Style.space(8)

                Button {
                  width: (actRow.width - Style.space(8)) / 2
                  text: delLayer.multi ? "仅去掉这一天" : "取消"
                  foreground: delLayer.multi ? root.contentForeground : Qt.darker(root.contentForeground, 1.5)
                  accent: Color.accent
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  bordered: true
                  onClicked: delLayer.multi ? dayEvents.confirmDeleteOnce() : delLayer.close()
                }

                DangerBtn {
                  width: (actRow.width - Style.space(8)) / 2
                  visible: !delLayer.multi
                  text: "删除"
                  iconText: "\uDB80\uDDB4"
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: dayEvents.confirmDeleteAll()
                }

                Button {
                  id: cancelBtn
                  width: (actRow.width - Style.space(8)) / 2
                  visible: delLayer.multi
                  text: "取消"
                  foreground: Qt.darker(root.contentForeground, 1.5)
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  bordered: true
                  onClicked: delLayer.close()
                }
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "此操作不可恢复"
                color: Util.alpha(Qt.darker(root.contentForeground, 2.2), 0.8)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
    }
  }
}
