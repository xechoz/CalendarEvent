import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// 迷你月历(events/ 模块):单月网格点选日期,供表单的日期步进器当选择器。
// 不感知业务数据;选中/翻月后把 dateKey 经 picked() 抛给调用方。
Item {
  id: root

  property int year: new Date().getFullYear()
  property int month: new Date().getMonth()
  property string selectedKey: ""
  property string todayKey: Model.keyForDate(new Date())
  property int weekStart: 1
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal picked(string dateKey)

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color selBg: Util.alpha(accent, 0.85)
  readonly property color selFg: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)

  width: Style.space(236)
  implicitHeight: body.implicitHeight

  function moveMonth(delta) {
    var idx = root.year * 12 + root.month + delta
    root.year = Math.floor(idx / 12)
    root.month = ((idx % 12) + 12) % 12
  }

  function monthTitle() {
    return root.year + " 年 " + (root.month + 1) + " 月"
  }

  function short(k) {
    var m = /^\d{4}-(\d{2})-(\d{2})$/.exec(String(k || ""))
    return m ? (parseInt(m[1], 10)) + "/" + (parseInt(m[2], 10)) : ""
  }

  Column {
    id: body
    width: parent.width
    spacing: Style.space(6)

    // ---- 头部:翻月 + 标题 ----
    Item {
      width: parent.width
      height: Style.spacing.controlHeight

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.monthTitle()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "\uDB80\uDC41"      // md-chevron_left
          color: prevM.hovered ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body

          MouseArea {
            id: prevM
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.moveMonth(-1)
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "\uDB80\uDC42"      // md-chevron_right
          color: nextM.hovered ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body

          MouseArea {
            id: nextM
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.moveMonth(1)
          }
        }
      }
    }

    // ---- 星期表头 ----
    Row {
      width: parent.width
      spacing: 0

      Repeater {
        model: 7

        Text {
          required property int index
          width: parent.width / 7
          horizontalAlignment: Text.AlignHCenter
          text: (function() {
            var names = ["日", "一", "二", "三", "四", "五", "六"]
            return names[(root.weekStart + index) % 7]
          })()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ---- 6 行网格 ----
    Repeater {
      model: Model.monthGrid(root.year, root.month, root.weekStart, root.todayKey)

      Row {
        required property var modelData
        width: parent.width
        spacing: 0

        Repeater {
          model: modelData.days

          Rectangle {
            required property var modelData
            width: parent.width / 7
            height: Style.space(26)
            radius: Style.cornerRadius > 0 ? Style.space(3) : 0
            color: modelData.key === root.selectedKey ? root.selBg
              : "transparent"

            Text {
              anchors.centerIn: parent
              text: modelData.day
              color: modelData.key === root.selectedKey ? root.selFg
                : (modelData.today ? root.accent
                  : (modelData.inMonth ? root.foreground
                    : Qt.darker(root.foreground, 1.7)))
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: modelData.today
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.picked(modelData.key)
            }
          }
        }
      }
    }
  }
}
