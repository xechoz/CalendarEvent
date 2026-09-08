import QtQuick
import qs.Commons
import qs.Ui
import "../i18n"

// 选中日的事件列表(events/ 模块,纯展示)。
// 数据由宿主编排层展开注入(occurrences = [{key,endKey,event}, ...]),
// 行内不感知存储;编辑/删除经信号向上抛,由聚合层决定动作与确认。
Item {
  id: root

  property var occurrences: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dotRed: "#e0744e"
  property color dotGreen: "#7aa2f7"
  property string fontFamily: Style.font.family
  property real rowHeight: Style.space(38)
  property real rowGap: Style.space(4)
  property string emptyHint: I18n.tr("empty_hint")

  signal editRequested(var occurrence)
  signal deleteRequested(var occurrence)
  // 点击行首状态圆点:请求把该次出现的事件切到下一状态
  signal statusCycleRequested(var occurrence)

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property real contentHeight: Math.max(0,
    root.occurrences.length * (root.rowHeight + root.rowGap) - root.rowGap)

  function statusGlyph(status) {
    if (status === "done") return "\uDB81\uDDE0"        // 实心圆+钩(md check-circle)
    if (status === "inprogress") return "\uDB84\uDF96"  // 半圆
    return "\uDB82\uDE9E"                               // 1% 进度弧(md circle-slice-1)
  }

  function statusLabel(status) {
    if (status === "done") return I18n.tr("status_done")
    if (status === "inprogress") return I18n.tr("status_inprogress")
    return I18n.tr("status_todo")
  }

  function nextStatus(status) {
    if (status === "done") return "todo"
    if (status === "inprogress") return "done"
    return "inprogress"
  }

  function repeatLabel(repeat) {
    if (repeat === "daily") return I18n.tr("repeat_daily")
    if (repeat === "weekly") return I18n.tr("repeat_weekly")
    if (repeat === "monthly") return I18n.tr("repeat_monthly")
    if (repeat === "yearly") return I18n.tr("repeat_yearly")
    return ""
  }

  component EventRow: Rectangle {
    id: row

    property var occurrence: null

    width: root.width
    height: root.rowHeight
    radius: Style.cornerRadius
    color: row.active ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
    Behavior on color { ColorAnimation { duration: 80 } }

    readonly property var ev: occurrence && occurrence.event ? occurrence.event : null
    readonly property bool timed: !!ev && !!ev.time
    // 已完成:标题删除线,整行置灰(见下方各绑定)
    readonly property bool done: !!ev && ev.status === "done"
    // 重要/普通 不再用单独小圆点表达,直接体现在状态圆点的颜色上
    readonly property color importanceColor: ev && ev.flag === "important"
      ? root.dotRed : root.dotGreen
    // 行被“选中/悬停”时才显示 ✕。行悬停与按钮悬停合并(指针在按钮上时
    // 行本身不再算 hovered),并用 150ms 宽限定时器收尾,避免状态残留导致
    // ✕ 看起来常驻。
    property bool xHovered: false
    readonly property bool active: mouse.containsMouse || xHovered

    function startHideTimer() { if (!row.xHovered) hideTimer.restart() }

    Timer {
      id: hideTimer
      interval: 150
      onTriggered: row.xHovered = false
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onExited: row.startHideTimer()
      onClicked: root.editRequested(row.occurrence)
    }

    // 状态圆点(形状=进度,颜色=重要/普通;点击循环 待办→进行中→已完成→待办)
    Item {
      id: statusHost
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(18)
      height: Style.space(18)

      Text {
        anchors.centerIn: parent
        text: root.statusGlyph(row.ev ? row.ev.status : "todo")
        color: row.importanceColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        id: statusMouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
          if (row.ev) root.statusCycleRequested(row.occurrence)
        }
      }

      PanelToolTip {
        visible: statusMouse.containsMouse
        text: row.ev
          ? I18n.tr("status_tooltip", [root.statusLabel(row.ev.status)])
          : ""
        fontFamily: root.fontFamily
      }
    }

    // 时间徽章 / “全天”小标
    Rectangle {
      id: chip
      anchors.left: statusHost.right
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: chipText.implicitWidth + Style.space(10)
      height: Style.space(19)
      radius: Style.cornerRadius > 0 ? Math.round(height / 2) : 0
      color: row.done
        ? Util.alpha(root.foreground, 0.045)
        : (row.timed ? Util.alpha(root.accent, 0.16) : Util.alpha(root.foreground, 0.07))

      Text {
        id: chipText
        anchors.centerIn: parent
        text: row.timed ? row.ev.time : I18n.tr("all_day")
        color: row.done
          ? Util.alpha(root.foreground, 0.3)
          : (row.timed ? root.accent : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: row.timed
      }
    }

    Text {
      id: titleText
      anchors.left: chip.right
      anchors.leftMargin: Style.space(8)
      anchors.right: row.active ? deleteBtn.left : parent.right
      anchors.rightMargin: row.active ? Style.space(4) : Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: row.ev ? row.ev.title : ""
      elide: Text.ElideRight
      color: row.done ? Util.alpha(root.foreground, 0.38) : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.strikeout: row.done
    }

    Row {
      id: tagsRow
      anchors.left: titleText.right
      anchors.leftMargin: Style.space(6)
      anchors.right: row.active ? deleteBtn.left : parent.right
      anchors.rightMargin: row.active ? Style.space(4) : Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      clip: true

      Text {
        visible: row.ev && row.ev.repeat && row.ev.repeat !== "none"
        text: root.repeatLabel(row.ev.repeat)
        color: row.done ? Util.alpha(root.foreground, 0.3) : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.italic: true
      }
    }

    PanelActionButton {
      id: deleteBtn
      visible: row.active
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      size: Style.space(30)
      iconText: "\uDB80\uDD56"            // md-close
      tooltipText: I18n.tr("delete_row_tooltip")
      foreground: root.foreground
      hoverColor: Qt.darker(Color.urgent, 1.2)
      fontFamily: root.fontFamily
      onHovered: function(h) {
        hideTimer.stop()
        row.xHovered = h
      }
      onClicked: root.deleteRequested(row.occurrence)
    }
  }

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: root.rowGap

    Repeater {
      model: root.occurrences

      EventRow { occurrence: modelData }
    }
  }

  Text {
    visible: root.occurrences.length === 0
    width: parent.width
    text: root.emptyHint
    color: Qt.darker(root.foreground, 1.9)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignHCenter
    topPadding: Style.space(4)
  }
}
