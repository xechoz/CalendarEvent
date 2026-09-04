import QtQuick
import qs.Commons
import qs.Ui

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
  property color statusBlue: "#7aa2f7"
  property string fontFamily: Style.font.family
  property real rowHeight: Style.space(38)
  property real rowGap: Style.space(4)
  property string emptyHint: "这天还没有安排,点右上角“添加”记一笔"

  signal editRequested(var occurrence)
  signal deleteRequested(var occurrence)
  // 点击行首状态圆点:请求把该次出现的事件切到下一状态
  signal statusCycleRequested(var occurrence)

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property real contentHeight: Math.max(0,
    root.occurrences.length * (root.rowHeight + root.rowGap) - root.rowGap)

  function metaLine(event, occurrence) {
    var parts = []
    if (event.flag === "important") parts.push("重要")
    if (event.status === "done") parts.push("已完成")
    else if (event.status === "inprogress") parts.push("进行中")
    if (event.time) parts.push("时间 " + event.time)
    else if (event.endDate && event.endDate !== event.date)
      parts.push("全天 · " + event.date + " ~ " + event.endDate)
    else parts.push("全天")
    if (event.repeat && event.repeat !== "none") parts.push(root.repeatLabel(event.repeat))
    if (event.note) parts.push(String(event.note))
    return parts.join("  ·  ")
  }

  function statusGlyph(status) {
    if (status === "done") return "\uDB81\uDDE0"        // 实心圆+钩(md check-circle)
    if (status === "inprogress") return "\uDB84\uDF96"  // 半圆
    return "\uDB82\uDE9E"                               // 1% 进度弧(md circle-slice-1)
  }

  function statusLabel(status) {
    if (status === "done") return "已完成"
    if (status === "inprogress") return "进行中"
    return "待办"
  }

  function nextStatus(status) {
    if (status === "done") return "todo"
    if (status === "inprogress") return "done"
    return "inprogress"
  }

  function repeatLabel(repeat) {
    if (repeat === "daily") return "每天"
    if (repeat === "weekly") return "每周"
    if (repeat === "monthly") return "每月"
    if (repeat === "yearly") return "每年"
    return ""
  }

  function repeatShort(repeat) {
    var label = root.repeatLabel(repeat)
    return label !== "" ? " · 重复·" + label : ""
  }

  component EventRow: Rectangle {
    id: row

    property var occurrence: null

    width: root.width
    height: root.rowHeight
    radius: Style.cornerRadius
    color: mouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
    Behavior on color { ColorAnimation { duration: 80 } }

    readonly property var ev: occurrence && occurrence.event ? occurrence.event : null
    readonly property bool timed: !!ev && !!ev.time
    // 已完成:标题删除线,整行置灰(见下方各绑定)
    readonly property bool done: !!ev && ev.status === "done"

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.editRequested(row.occurrence)
    }

    // 状态圆点(点击循环 待办→进行中→已完成→待办;颜色蓝)
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
        color: root.statusBlue
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
          ? "状态:" + root.statusLabel(row.ev.status) + "(点击切换)"
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
        text: row.timed ? row.ev.time : "全天"
        color: row.done
          ? Util.alpha(root.foreground, 0.3)
          : (row.timed ? root.accent : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: row.timed
      }
    }

    // 标签色点:重要=红 / 普通=绿
    Rectangle {
      id: flagDot
      anchors.left: chip.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(3)
      height: Style.space(3)
      // 圆点永远是圆:不跟主题 cornerRadius(为 0 时会变方形)
      radius: height / 2
      color: row.done
        ? Util.alpha(root.foreground, 0.32)
        : (row.ev && row.ev.flag === "important" ? root.dotRed : root.dotGreen)
    }

    Text {
      id: titleText
      anchors.left: flagDot.right
      anchors.leftMargin: Style.space(8)
      anchors.right: mouse.containsMouse ? deleteBtn.left : parent.right
      anchors.rightMargin: mouse.containsMouse ? Style.space(4) : Style.space(8)
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
      anchors.right: mouse.containsMouse ? deleteBtn.left : parent.right
      anchors.rightMargin: mouse.containsMouse ? Style.space(4) : Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      clip: true

      Text {
        visible: row.ev && row.ev.flag === "important"
        text: "重要"
        color: row.done ? Util.alpha(root.foreground, 0.3) : root.dotRed
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

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
      visible: mouse.containsMouse
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      iconText: "\uDB80\uDD56"            // md-close
      tooltipText: "删除(点击行本身可编辑)"
      foreground: root.foreground
      hoverColor: Qt.darker(Color.urgent, 1.2)
      fontFamily: root.fontFamily
      onClicked: root.deleteRequested(row.occurrence)
    }

    PanelToolTip {
      visible: mouse.containsMouse
      text: row.ev ? root.metaLine(row.ev, row.occurrence) : ""
      fontFamily: root.fontFamily
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
