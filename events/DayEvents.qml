import QtQuick
import QtQuick.Controls as QC
import qs.Commons
import qs.Ui
import "EventsModel.js" as EM

// 选中日事件区聚合(events/ 模块):头部(日期·计数·添加)+ 事件列表 +
// 添加/编辑表单 + 删除确认(整条 / 仅此天)+ 存储错误条。
// 与 EventStore 单向对话;对外只依赖编排层注入的 store/dateKey/颜色字体。
Item {
  id: root

  property var store: null
  property string dateKey: ""
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dotRed: "#e0744e"
  property color dotGreen: "#7aa2f7"
  property int weekStart: 1
  property string fontFamily: Style.font.family

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color urgentColor: Qt.darker(Color.urgent, 1.15)
  readonly property real gap: Style.space(6)

  readonly property bool panelKeyBlocked:
    formArea.visible || root.pendingDelete != null

  // 当日出现列表(展开+排序;dateKey 或数据变更时重算)
  property var occurrences: []
  property string _renderedKey: ""
  property int _renderedRev: -1

  function refreshDay() {
    if (!root.store || root.dateKey === "") { root.occurrences = []; return }
    root.occurrences = root.store.forDay(root.dateKey)
    root._renderedKey = root.dateKey
    root._renderedRev = root.store.revision
  }

  function headerText() {
    if (root.dateKey === "") return ""
    var p = EM.parseKey(root.dateKey)
    if (!p) return ""
    return (p.month + 1) + "月" + p.day + "日"
  }

  function weekdayText() {
    var p = EM.parseKey(root.dateKey)
    if (!p) return ""
    var weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    var d = new Date(p.year, p.month, p.day)
    return weekdays[d.getDay()]
  }

  // ---- 表单状态 ----
  property bool formOpen: false
  property var formEditing: null

  function openAdd() {
    if (root.formOpen) return
    root.formEditing = null
    form.editingOccurrenceKey = ""
    root.formOpen = true
    Qt.callLater(function() {
      form.beginAdd(root.dateKey)
      form.focusTitle()
    })
  }

  function openEdit(occurrence) {
    if (!occurrence || !occurrence.event) return
    root.formEditing = occurrence
    form.editingOccurrenceKey = occurrence.key || occurrence.event.date || ""
    root.formOpen = true
    Qt.callLater(function() {
      form.beginEdit(occurrence.event)
      form.focusTitle()
    })
  }

  function closeForm() {
    root.formOpen = false
    root.formEditing = null
  }

  function commitForm(fields) {
    if (!root.store) return
    if (fields.detachFrom && fields.detachFrom !== "" && fields.date) {
      // 仅改这一天:原系列跳过该出现日 + 该日新建单日事件
      root.store.skipOccurrence(fields.detachFrom, fields.date)
      var copy = {}
      for (var k in fields) copy[k] = fields[k]
      copy.id = ""
      copy.repeat = "none"
      copy.repeatUntil = null
      root.store.addEvent(copy)
      root.closeForm()
      return
    }
    if (fields.id && fields.id !== "") root.store.updateEvent(fields.id, fields)
    else root.store.addEvent(fields)
    root.closeForm()
  }

  // ---- 删除确认(三种结果:取消 / 仅此天 / 整条)----
  property var pendingDelete: null

  function requestDelete(occurrence) {
    if (!occurrence || !occurrence.event) return
    root.pendingDelete = occurrence
  }

  function confirmDeleteAll() {
    var event = root.pendingDelete ? root.pendingDelete.event : null
    if (event && root.store) root.store.removeEvent(event.id)
    root.pendingDelete = null
  }

  function confirmDeleteOnce() {
    var occ = root.pendingDelete
    if (occ && occ.event && root.store) {
      if (occ.event.repeat && occ.event.repeat !== "none")
        root.store.skipOccurrence(occ.event.id, root.dateKey)
      else
        root.store.removeEvent(occ.event.id)
    }
    root.pendingDelete = null
  }

  // 行首圆点点击:待办→进行中→已完成→待办
  function cycleStatus(occurrence) {
    if (!occurrence || !occurrence.event || !root.store) return
    var order = ["todo", "inprogress", "done"]
    var idx = order.indexOf(occurrence.event.status)
    if (idx === -1) idx = 0
    root.store.updateEvent(occurrence.event.id, { status: order[(idx + 1) % order.length] })
  }

  function dismissError() {
    if (root.store) root.store.lastError = ""
  }

  Connections {
    target: root.store
    function onEventsChanged() { root.refreshDay() }
  }

  onDateKeyChanged: {
    root.refreshDay()
    if (root.formOpen) root.closeForm()
  }
  onStoreChanged: {
    if (root.store) root.refreshDay()
  }
  Component.onCompleted: root.refreshDay()

  // ======================================================== 布局
  // 显式自报测量高度:外层 Column 依赖子项 implicitHeight 布局,
  // 不自报的话事件区会塌成 0 高、画在滚动区外。
  // 手算(而非读 layout.implicitHeight):后者要等渲染帧 polish 才重算,
  // 表单开关/列表切换希望立即让外层 Flickable 得知新高度。
  readonly property real errorBarH:
    root.store && root.store.lastError !== "" ? Style.space(26) : 0
  readonly property real listH:
    root.occurrences.length > 0 ? list.contentHeight : Style.space(24)
  readonly property real formH: root.formOpen ? formArea.height : 0
  readonly property real activeListH: root.formOpen ? 0 : root.listH
  readonly property int _slotCount: 2 + (root.errorBarH > 0 ? 1 : 0)  // 头部 + 列表/表单 + 错误条
  implicitHeight: Style.space(26) + root.activeListH + root.formH + root.errorBarH
    + root.gap * (_slotCount - 1)
  readonly property real measuredHeight: root.implicitHeight

  Column {
    id: layout
    width: parent.width
    spacing: root.gap

    // ---- 头部 ----
    Item {
      width: parent.width
      height: Style.space(26)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.headerText() + "  " + root.weekdayText()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        topPadding: Math.ceil(font.pixelSize * 0.1)
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(90)
        anchors.verticalCenter: parent.verticalCenter
        text: root.occurrences.length > 0
          ? root.occurrences.length + " 项安排"
          : "暂无安排"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelActionButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uDB81\uDC15"          // md-plus
        tooltipText: "添加事件(快捷键 A)"
        foreground: root.foreground
        hoverColor: root.accent
        fontFamily: root.fontFamily
        onClicked: root.openAdd()
      }
    }

    // ---- 列表(或空态) ----
    EventList {
      id: list
      width: parent.width
      visible: !root.formOpen
      occurrences: root.occurrences
      foreground: root.foreground
      accent: root.accent
      dotRed: root.dotRed
      dotGreen: root.dotGreen
      fontFamily: root.fontFamily
      emptyHint: "这天还没有安排 · 点右上角 + 添加"
      height: root.occurrences.length > 0 ? contentHeight : Style.space(24)
      onEditRequested: function(occ) { root.openEdit(occ) }
      onDeleteRequested: function(occ) { root.requestDelete(occ) }
      onStatusCycleRequested: function(occ) { root.cycleStatus(occ) }
    }

    // ---- 添加 / 编辑表单 ----
    Item {
      id: formArea
      width: parent.width
      visible: root.formOpen
      height: visible ? formBox.implicitHeight : 0

      Item {
        id: formBox
        width: parent.width
        implicitHeight: formRootContent.height

        Column {
          id: formRootContent
          width: parent.width

          Text {
            text: root.formEditing ? "编辑事件" : "添加事件"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            topPadding: Style.space(2)
            bottomPadding: Style.space(2)
          }

          EventForm {
            id: form
            width: parent.width
            foreground: root.foreground
            accent: root.accent
            dotRed: root.dotRed
            dotGreen: root.dotGreen
            weekStart: root.weekStart
            fontFamily: root.fontFamily
            onCancel: root.closeForm()
            onSubmit: function(fields) { root.commitForm(fields) }
          }
        }
      }
    }

    // ---- 存储错误条 ----
    Rectangle {
      visible: root.store && root.store.lastError !== ""
      width: parent.width
      height: visible ? Style.space(26) : 0
      radius: Style.cornerRadius
      color: Util.alpha(Color.urgent, 0.10)

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.right: dismissBtn.left
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: "\uEA87  " + (root.store ? root.store.lastError : "")
        color: root.urgentColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelActionButton {
        id: dismissBtn
        anchors.right: parent.right
        anchors.rightMargin: Style.space(2)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uDB80\uDD56"
        tooltipText: "关闭提示"
        foreground: root.urgentColor
        fontFamily: root.fontFamily
        onClicked: root.dismissError()
      }
    }
  }

}
