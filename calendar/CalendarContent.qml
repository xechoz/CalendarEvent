import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "Holidays.js" as Holidays
import "../i18n"

// 月历内容(calendar/ 模块):hero 今日 + 年进度 + 生卒计量 + 月格(点选/圆点) +
// 月份导航。纯展示组件:所有可变状态(今天/视图月/周起始/生卒设置/选中日)由
// 编排层持有并经属性注入,交互经信号上抛;组件内部只保留纯粹的布局几何。
//
// 新增语义(相对内置版):
//   - 格子可点选:点击任一天会 emit dayClicked;编排层负责翻月/选中/联动事件区
//   - 有事件的日子在日期数字下方渲染圆点(dayDots 由编排层注入):每天最多
//     3 个,重要事件橙点、普通事件蓝点(主题色 dotRed/dotGreen 注入)
Item {
  id: root

  // ---- 编排层注入的状态(全部只读展示用) ----
  property date today: new Date()
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  property int weekStart: 1
  property int birthYear: 0
  property int lifeExpectancy: 0
  property bool editingLife: false
  // dateKey → 该日圆点布尔数组(仅当月格窗口内有效;true=重要/橙,
  // false=普通/蓝;长度最多 3,由编排层排序截断)
  property var dayDots: ({})
  property color dotRed: "#e0744e"
  property color dotGreen: "#7aa2f7"

  // ---- 中国节假日(编排层注入;关时格子不显示任何标记) ----
  property bool holidaysOn: false
  // year → { "yyyy-MM-dd": { rest: bool, name } } 合并表
  property var holidayTable: ({})
  // 休=红 / 班(调休上班)=蓝;与事件圆点的橙/蓝错开
  readonly property color holidayRed: "#e5484d"
  readonly property color holidayBlue: "#7aa2f7"

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal todayRequested()
  signal monthStep(int delta)
  signal weekStartToggled()
  signal lifeEditRequested()
  signal lifeClearRequested()
  signal lifeCommit(int bornYear, int lifeSpan)
  signal lifeEditCanceled()
  signal dayClick(string dateKey, bool inMonth)

  // 当前选中日(由编排层维护,驱动格子高亮)
  property string selectedKey: ""

  readonly property string todayKey: Model.keyForDate(root.today)
  readonly property date viewDate: new Date(root.viewYear, root.viewMonth, 1)
  readonly property bool viewingCurrentMonth:
    root.viewYear === root.today.getFullYear() && root.viewMonth === root.today.getMonth()

  readonly property real yearDone: Model.yearProgress(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())

  readonly property int age: Model.ageFromBirthYear(root.birthYear, root.today.getFullYear())
  readonly property real lifeDone: Model.lifeProgress(root.age, root.lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(root.age, root.lifeExpectancy)

  readonly property string nextWeekStartLabel: I18n.weekdayName(Model.toggledWeekStart(root.weekStart))
  readonly property var weekdays: Model.weekdayOrder(root.weekStart)
  readonly property var weeks: Model.monthGrid(root.viewYear, root.viewMonth, root.weekStart, root.todayKey)

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  implicitWidth: Math.max(heroRow.width, gridColumn.width)
  implicitHeight: body.height

  function weekdayLabel(weekday) {
    return String(I18n.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  // 某日圆点布尔数组(超出 3 再兜底截一次,防脏数据)
  function dotsFor(key) {
    var map = root.dayDots || {}
    var arr = Array.isArray(map[key]) ? map[key] : []
    return arr.length > 3 ? arr.slice(0, 3) : arr
  }

  // 某日节假日条目(未开启/无数据返回 null)
  function holidayFor(key) {
    if (!root.holidaysOn || !root.holidayTable || key === "") return null
    for (var year in root.holidayTable) {
      var t = root.holidayTable[year]
      if (t && t[key]) return t[key]
    }
    return null
  }

  // 编排层把 editingLife 置 true 后调用本函数聚焦编辑字段
  function beginLifeEditing() {
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function commitLifeFields() {
    var born = Model.parseBirthYear(bornField.text, root.today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      root.lifeCommit(born, span)
    else
      root.lifeCommit(-1, -1)   // 无变化,仅退出编辑
  }

  Column {
    id: body
    width: parent.width
    spacing: Style.space(8)

    // ---- Hero: 今日,居中 ----
    Item {
      width: parent.width
      height: heroRow.height

      Row {
        id: heroRow
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(22)

        Text {
          anchors.baseline: heroDate.baseline
          text: "󰃭"
          color: heroMouse.containsMouse
            ? Style.hoverStateColor(root.foreground, Color.accent)
            : root.foreground
          font.family: root.fontFamily
          font.pixelSize: 48
        }

        Text {
          id: heroDate
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: I18n.formatDate(root.today, "MMMM d")
          color: heroMouse.containsMouse
            ? Style.hoverStateColor(root.foreground, Color.accent)
            : root.foreground
          font.family: root.fontFamily
          font.pixelSize: 52
          font.bold: true
        }
      }

      MouseArea {
        id: heroMouse
        x: heroRow.x
        y: heroRow.y
        width: heroRow.width
        height: heroRow.height
        enabled: !root.viewingCurrentMonth
        hoverEnabled: enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.todayRequested()

        PanelToolTip {
          visible: heroMouse.containsMouse
          text: I18n.tr("back_to_today")
          fontFamily: root.fontFamily
        }
      }
    }

    // ---- 年进度(兼作 hero 下的分隔线) ----
    Item {
      width: parent.width
      height: yearBlock.y + yearBlock.height

      Item {
        id: yearBlock
        y: Style.space(6)
        anchors.horizontalCenter: parent.horizontalCenter
        width: gridColumn.width
        height: Math.max(yearLabel.implicitHeight, Style.space(10))

        TapHandler {
          enabled: !root.editingLife
          onDoubleTapped: root.lifeEditRequested()
        }

        Row {
          visible: root.editingLife
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("born")
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          TextField {
            id: bornField
            width: Style.space(70)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: I18n.tr("year")
            foreground: root.foreground
            font.family: root.fontFamily
            inputMethodHints: Qt.ImhDigitsOnly

            Keys.onPressed: function(event) { handleLifeKey(event, true) }
            Keys.onEscapePressed: root.lifeEditCancel()
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.space(6)
            text: I18n.tr("live_to")
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
          }

          TextField {
            id: expectancyField
            width: Style.space(60)
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "90"
            foreground: root.foreground
            font.family: root.fontFamily
            inputMethodHints: Qt.ImhDigitsOnly

            Keys.onPressed: function(event) { handleLifeKey(event, false) }
            Keys.onEscapePressed: root.lifeEditCancel()
          }
        }

        Text {
          id: yearLabel
          textFormat: Text.PlainText
          visible: !root.editingLife
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.today.getFullYear()
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Text {
          id: yearPercent
          textFormat: Text.PlainText
          visible: !root.editingLife
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.yearDonePercent + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          id: yearTrack
          visible: !root.editingLife
          anchors.left: yearLabel.right
          anchors.right: yearPercent.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(6)
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            width: Math.round(parent.width * root.yearDone)
            height: parent.height
            radius: parent.radius
            color: Style.selectedStateColor(root.foreground, Color.accent)

            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }
      }
    }

    // ---- 生卒计量 ----
    Item {
      visible: root.birthYear > 0
      width: parent.width
      height: visible ? lifeBlock.height : 0

      Item {
        id: lifeBlock
        anchors.horizontalCenter: parent.horizontalCenter
        width: gridColumn.width
        height: Math.max(lifeLabel.implicitHeight, Style.space(10))

        Text {
          id: lifeLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: I18n.tr("life")
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: 1
        }

        Text {
          id: lifePercent
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.lifeDonePercent + "%"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Rectangle {
          anchors.left: lifeLabel.right
          anchors.right: lifePercent.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(6)
          radius: Style.cornerRadius > 0 ? height / 2 : 0
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            width: Math.round(parent.width * root.lifeDone)
            height: parent.height
            radius: parent.radius
            color: Style.selectedStateColor(root.foreground, Color.accent)

            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
          }
        }

        TapHandler {
          onDoubleTapped: root.lifeClearRequested()
        }

        MouseArea {
          id: lifeMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton

          PanelToolTip {
            visible: lifeMouse.containsMouse
            text: "Memento Mori"
            fontFamily: root.fontFamily
          }
        }
      }
    }

    // ---- 月格 ----
    Item {
      width: parent.width
      height: gridColumn.y + gridColumn.height

      WheelHandler {
        onWheel: function(event) {
          if (event.angleDelta.y === 0) return
          root.monthStep(event.angleDelta.y > 0 ? -1 : 1)
        }
      }

      Column {
        id: gridColumn
        y: Style.space(18)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(3)

        Row {
          id: headerRow
          spacing: root.cellSpacing

          Rectangle {
            width: root.weekColumnWidth
            height: Style.space(16)
            radius: Style.cornerRadius
            color: weekStartMouse.containsMouse
              ? Style.hoverFillFor(root.foreground, Color.accent)
              : "transparent"

            Text {
              anchors.centerIn: parent
              text: "W"
              color: weekStartMouse.containsMouse
                ? Style.hoverStateColor(root.foreground, Color.accent)
                : Qt.darker(root.foreground, 1.9)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            MouseArea {
              id: weekStartMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.weekStartToggled()
            }

            PanelToolTip {
              visible: weekStartMouse.containsMouse
              text: I18n.tr("start_weeks_on", [root.nextWeekStartLabel])
              fontFamily: root.fontFamily
            }
          }

          Item {
            width: root.gutterWidth
            height: Style.space(16)
          }

          Repeater {
            model: root.weekdays

            Text {
              textFormat: Text.PlainText
              required property var modelData
              width: root.cellWidth
              height: Style.space(16)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: root.weekdayLabel(modelData)
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }
          }
        }

        Repeater {
          model: root.weeks

          Row {
            required property var modelData
            spacing: root.cellSpacing

            Text {
              textFormat: Text.PlainText
              width: root.weekColumnWidth
              height: root.cellHeight
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: modelData.week
              color: Qt.darker(root.foreground, 1.9)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Item {
              width: root.gutterWidth
              height: root.cellHeight
            }

            Repeater {
              model: modelData.days

              DayCell {
                cellData: modelData
                cellWidth: root.cellWidth
                cellHeight: root.cellHeight
                fg: root.foreground
                accent: Color.accent
                fam: root.fontFamily
                selected: root.selectedKey === modelData.key
                dots: root.dotsFor(modelData.key)
                dotRed: root.dotRed
                dotGreen: root.dotGreen
                holiday: root.holidayFor(modelData.key)
                holidayRed: root.holidayRed
                holidayBlue: root.holidayBlue
                onClicked: function(key, inMonth) { root.dayClick(key, inMonth) }
              }
            }
          }
        }
      }

      // 周数槽沟的竖分隔线(仅日行高度)
      Rectangle {
        x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
        y: gridColumn.y + headerRow.height + gridColumn.spacing
        width: Style.spacing.hairline
        height: gridColumn.height - headerRow.height - gridColumn.spacing
        color: root.foreground
        opacity: 0.1
      }
    }

    // ---- 月份导航 ----
    Item {
      width: parent.width
      height: monthNav.height

      Item {
        id: monthNav
        anchors.horizontalCenter: parent.horizontalCenter
        width: gridColumn.width
        height: monthLabel.implicitHeight + Style.space(10)

        Text {
          id: monthLabel
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(130)
          horizontalAlignment: Text.AlignHCenter
          text: I18n.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.letterSpacing: 1
        }

        PanelActionButton {
          anchors.left: parent.left
          anchors.leftMargin: -Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰅁"
          tooltipText: I18n.tr("prev_month")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.monthStep(-1)
        }

        PanelActionButton {
          anchors.right: parent.right
          anchors.rightMargin: -Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰅂"
          tooltipText: I18n.tr("next_month")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.monthStep(1)
        }
      }
    }
  }

  function lifeEditCancel() {
    if (root.editingLife) root.lifeEditCanceled()
  }

  function handleLifeKey(event, bornFirst) {
    if (event.key === Qt.Key_Escape) {
      root.lifeEditCancel()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLifeFields()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      var other = bornFirst ? expectancyField : bornField
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // ---- 单元格(含点选与事件圆点) ----
  component DayCell: Item {
    id: cell

    property var cellData: null
    property bool selected: false
    property color fg: Color.foreground
    property color accent: Color.accent
    property string fam: Style.font.family
    property real cellWidth: 0
    property real cellHeight: 0
    // 该日圆点布尔数组(true=重要,false=普通);颜色见 dotRed/dotGreen
    property var dots: []
    property color dotRed: "#e0744e"
    property color dotGreen: "#7aa2f7"
    // 该日节假日条目 {rest,name} 或 null
    property var holiday: null
    property color holidayRed: "#e5484d"
    property color holidayBlue: "#7aa2f7"

    signal clicked(string key, bool inMonth)

    readonly property bool isToday: cellData ? cellData.today === true : false
    readonly property bool hovered: cellMouse.containsMouse
    readonly property int dotCount: cell.dots && Array.isArray(cell.dots) ? cell.dots.length : 0
    readonly property bool holidayVisible: cell.holiday !== null && cell.holiday !== undefined

    width: cell.cellWidth
    height: cell.cellHeight

    Rectangle {
      id: cellSurface
      anchors.fill: parent
      radius: Style.cornerRadius
      color: cell.hovered
        ? Style.hoverFillFor(cell.fg, cell.accent)
        : (cell.selected ? Util.alpha(cell.accent, 0.10) : "transparent")
      border.width: (cell.isToday || cell.selected)
        ? Style.spacing.hairline * 2
        : 0
      border.color: (cell.isToday || cell.selected)
        ? cell.accent
        : "transparent"

      Behavior on color { ColorAnimation { duration: 80 } }
    }

    MouseArea {
      id: cellMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: cell.clicked(cellData.key, cellData.inMonth)
    }

    Text {
      id: dayText
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: cell.dotCount > 0 ? -Style.space(4) : 0
      text: cellData.day
      color: cell.holidayVisible
        ? (cell.holiday.rest ? cell.holidayRed : cell.holidayBlue)
        : (!cellData.inMonth
          ? Qt.darker(cell.fg, 2.2)
          : (cellData.weekend ? Qt.darker(cell.fg, 1.45) : cell.fg))
      font.family: cell.fam
      font.pixelSize: Style.font.body
      font.bold: cell.isToday || cell.selected
    }

    // 节假日角标(休/班,固定汉字记号;比日期数字小一圈,外月格子半透明)
    Text {
      visible: cell.holidayVisible
      anchors.right: parent.right
      anchors.rightMargin: Style.space(3)
      anchors.top: parent.top
      anchors.topMargin: Style.space(1)
      text: cell.holidayVisible ? (cell.holiday.rest ? "休" : "班") : ""
      color: cell.holidayVisible
        ? (cell.holiday.rest ? cell.holidayRed : cell.holidayBlue)
        : "transparent"
      opacity: cellData.inMonth ? 0.9 : 0.45
      font.family: cell.fam
      // 固定小字号:约日期数字(body)的 2/3,不随 caption 缩放喧宾夺主
      font.pixelSize: Math.round(Style.font.body * 0.66)
      font.bold: false
    }

    PanelToolTip {
      visible: cell.holidayVisible && cell.hovered
      text: cell.holidayVisible
        ? Holidays.labelFor(cell.holiday, I18n.lang) + " · "
          + (cell.holiday.rest ? I18n.tr("holiday_rest") : I18n.tr("holiday_work"))
        : ""
      fontFamily: cell.fam
    }

    Row {
      id: dotRow
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(3)
      spacing: Style.space(2)
      visible: cell.dotCount > 0

      Repeater {
        model: cell.dots

        Rectangle {
          required property bool modelData
          width: Style.space(3)
          height: Style.space(3)
          // 圆点永远是圆:不跟主题 cornerRadius(为 0 时会变方形)
          radius: height / 2
          color: modelData ? cell.dotRed : cell.dotGreen
          opacity: cellData.inMonth ? 1 : 0.45
        }
      }
    }
  }
}
