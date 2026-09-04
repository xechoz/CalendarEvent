import QtQuick
import qs.Commons
import qs.Ui
import "EventsModel.js" as EM

// 添加/编辑事件表单(events/ 模块,纯 UI)。
// 不直接碰存储:提交时把字段对象经 submit(fields) 抛出,由聚合层写 EventStore;
// 取消经 cancel()。字段:标题 / 起止日期(多日)/ 时间(空=全天)/
// 重复 + 截止 / 到点提醒 / 备注。规则:多日与重复互斥(见 EventsModel)。
Item {
  id: root

  property string startDateKey: EM.todayKey(new Date())
  property var editing: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dotRed: "#e0744e"
  property color dotGreen: "#7aa2f7"
  property string fontFamily: Style.font.family

  signal submit(var fields)
  signal cancel()

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property bool repeatLocked: root._repeat !== "none"

  // ---- 内部字段(含脏校验反馈) ----
  property string _title: ""
  property string _startKey: ""
  property string _endKey: ""
  property string _time: ""
  property string _flag: "normal"
  property string _status: "todo"
  property string _repeat: "none"
  property string _repeatUntil: ""
  property bool _hasUntil: false
  property bool _remind: true
  property string _note: ""
  property string fieldError: ""

  readonly property bool timeBad: root._time !== "" && EM.normalizeTime(root._time) === null

  property var repeatOptions: [
    { value: "none", label: "不重复" },
    { value: "daily", label: "每天" },
    { value: "weekly", label: "每周" },
    { value: "monthly", label: "每月" },
    { value: "yearly", label: "每年" }
  ]

  function beginAdd(dateKey) {
    root.editing = null
    root._startKey = EM.normalizeDate(dateKey) || EM.todayKey(new Date())
    root._endKey = ""
    root._title = ""
    root._flag = "normal"
    root._status = "todo"
    root._time = ""
    root._repeat = "none"
    root._repeatUntil = ""
    root._hasUntil = false
    root._remind = true
    root._note = ""
    root.fieldError = ""
  }

  function beginEdit(event) {
    if (!event) return
    root.editing = event
    root._startKey = event.date
    root._endKey = event.endDate || ""
    root._title = event.title
    root._flag = event.flag === "important" ? "important" : "normal"
    root._status = EM.STATUSES.indexOf(event.status) !== -1 ? event.status : "todo"
    root._time = event.time || ""
    root._repeat = event.repeat || "none"
    root._repeatUntil = event.repeatUntil || ""
    root._hasUntil = !!event.repeatUntil
    root._remind = event.remind !== false
    root._note = event.note || ""
    root.fieldError = ""
  }

  function focusTitle() {
    Qt.callLater(function() {
      titleField.forceActiveFocus()
      titleField.selectAll()
    })
  }

  function commit() {
    var title = EM.normalizeTitle(root._title)
    if (title === "") {
      root.fieldError = "标题不能为空"
      titleField.forceActiveFocus()
      return
    }
    if (root.timeBad) {
      root.fieldError = "时间格式应为 HH:MM(如 14:30)"
      timeField.forceActiveFocus()
      return
    }
    var startKey = EM.normalizeDate(root._startKey) || EM.todayKey(new Date())
    var endKey = null
    if (root._endKey !== "" && root._endKey !== root._startKey)
      endKey = EM.normalizeDate(root._endKey)
    if (endKey && EM.cmpKeys(endKey, startKey) < 0) endKey = null
    var repeat = root._repeat
    if (endKey) repeat = "none"
    var untilKey = null
    if (repeat !== "none" && root._hasUntil)
      untilKey = EM.normalizeDate(root._repeatUntil)
    root.submit({
      id: root.editing ? String(root.editing.id) : "",
      title: title,
      flag: root._flag,
      status: root._status,
      date: startKey,
      endDate: endKey,
      time: EM.normalizeTime(root._time),
      note: EM.normalizeNote(root._note),
      repeat: repeat,
      repeatUntil: untilKey,
      remind: root._remind
    })
  }

  // 双栏行的栏宽:成对 Row 的 spacing 是 8(不是 body 的 6),
  // 少算会把右栏挤宽 2px、被面板滚动区裁掉右边,见各双栏 Row。
  function halfWidth() {
    return Math.floor((body.width - Style.space(8)) / 2)
  }

  // 自报测量高度:宿主(聚合层/外层 Column)靠 implicitHeight 决定表单是否占位,
  // Item 默认 implicitHeight 为 0,不声明的话字段整块会塌成 0 高。
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: parent.width
    spacing: Style.space(6)
    topPadding: Style.space(2)

    // ---- 标题 ----
    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        text: "标题"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      TextField {
        id: titleField
        width: parent.width
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        placeholderText: "给这天记点什么…(必填)"
        text: root._title
        verticalPadding: Style.space(5)
        onTextChanged: {
          root._title = text
          if (root.fieldError !== "") root.fieldError = ""
        }
        onAccepted: root.commit()
        Keys.onEscapePressed: root.cancel()
      }
    }

    // ---- 日期起止 / 时间·重复 ----
    Row {
      width: parent.width
      spacing: Style.space(8)

      DateStepper {
        id: startStepper
        labelText: "开始"
        key: root._startKey
        width: root.halfWidth()
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onStepped: {
          root._startKey = startStepper.key
          if (root._endKey !== "" && EM.cmpKeys(root._endKey, startStepper.key) < 0)
            root._endKey = startStepper.key
        }
      }

      DateStepper {
        id: endStepper
        labelText: "结束"
        key: root._endKey !== "" ? root._endKey : root._startKey
        minKey: root._startKey
        locked: root.repeatLocked
        width: root.halfWidth()
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onStepped: {
          root._endKey = endStepper.key === root._startKey ? "" : endStepper.key
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      Column {
        width: root.halfWidth()
        spacing: Style.space(3)

        Text {
          text: "时间(留空 = 全天)"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          id: timeField
          width: parent.width
          foreground: root.foreground
          accent: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          placeholderText: "HH:MM"
          text: root._time
          verticalPadding: Style.space(5)
          onTextChanged: {
            root._time = text
            if (root.fieldError !== "") root.fieldError = ""
          }
          onAccepted: root.commit()
          Keys.onEscapePressed: root.cancel()
        }
      }

      Column {
        width: root.halfWidth()
        spacing: Style.space(3)

        Text {
          text: "重复"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Row {
          width: parent.width
          height: Style.spacing.controlHeight
          spacing: Style.space(6)

          Dropdown {
            id: repeatDropdown
            anchors.verticalCenter: parent.verticalCenter
            width: (repeatToggleHost.visible ? parent.width * 0.6 : parent.width) - 0
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            options: root.repeatOptions
            value: root._repeat
            showLabel: false
            onChanged: function(v) {
              root._repeat = v
              if (v !== "none" && root._endKey !== "" && root._endKey !== root._startKey)
                root._endKey = ""
              if (root._repeat === "none") root._hasUntil = false
            }
          }

          Item {
            id: repeatToggleHost
            visible: root._repeat !== "none"
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.4 - parent.spacing
            height: Style.spacing.controlHeight

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: "transparent"
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(4)
              spacing: Style.space(4)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "限"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              ToggleSwitch {
                id: untilToggle
                anchors.verticalCenter: parent.verticalCenter
                checked: root._hasUntil
                foreground: root.foreground
                accent: root.accent
                onToggled: function() {
                  root._hasUntil = !root._hasUntil
                  if (root._hasUntil && !root._repeatUntil)
                    root._repeatUntil = EM.addDays(root._startKey, 30)
                }
              }
            }
          }
        }
      }
    }

    // ---- 重复截止 ----
    Row {
      visible: root._repeat !== "none" && root._hasUntil
      width: parent.width
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "重复到"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      DateStepper {
        id: untilStepper
        key: root._repeatUntil !== "" ? root._repeatUntil : root._startKey
        minKey: root._startKey
        width: Style.space(168)
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onStepped: { root._repeatUntil = untilStepper.key }
      }

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uDB80\uDD56"   // md-close
        tooltipText: "去掉重复截止"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root._hasUntil = false
      }
    }

    // ---- 标签(普通=蓝点 / 重要=橙点,决定日期圆点颜色) ----
    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "标签"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        FlagChip {
          value: "normal"
          labelText: "普通"
          dotColor: root.dotGreen
          active: root._flag === "normal"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onChosen: root._flag = "normal"
        }

        FlagChip {
          value: "important"
          labelText: "重要"
          dotColor: root.dotRed
          active: root._flag === "important"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onChosen: root._flag = "important"
        }
      }
    }

    // ---- 状态(待办=空心圆 / 进行中=半圆 / 已完成=实心圆,均为蓝) ----
    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "状态"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        StatusChip {
          value: "todo"
          labelText: "待办"
          glyphText: "\uDB82\uDE9E"     // md circle-slice-1(1% 进度)
          active: root._status === "todo"
          accentColor: root._flag === "important" ? root.dotRed : root.dotGreen
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChosen: root._status = "todo"
        }

        StatusChip {
          value: "inprogress"
          labelText: "进行中"
          glyphText: "\uDB84\uDF96"     // md circle-half-full
          active: root._status === "inprogress"
          accentColor: root._flag === "important" ? root.dotRed : root.dotGreen
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChosen: root._status = "inprogress"
        }

        StatusChip {
          value: "done"
          labelText: "已完成"
          glyphText: "\uDB81\uDDE0"     // md check-circle(实心+钩)
          active: root._status === "done"
          accentColor: root._flag === "important" ? root.dotRed : root.dotGreen
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChosen: root._status = "done"
        }
      }
    }

    // ---- 提醒 / 备注 ----
    Row {
      width: parent.width
      spacing: Style.space(8)

      Column {
        width: root.halfWidth()
        spacing: Style.space(3)

        Text {
          text: "提醒"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Item {
          width: parent.width
          height: Style.spacing.controlHeight

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            ToggleSwitch {
              id: remindSwitch
              anchors.verticalCenter: parent.verticalCenter
              checked: root._remind
              foreground: root.foreground
              accent: root.accent
              onToggled: function() { root._remind = !root._remind }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root._time === "" ? "全天 09:00 提醒" : "提前 10 分钟提醒"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Column {
        width: root.halfWidth()
        spacing: Style.space(3)

        Text {
          text: "备注"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        TextField {
          id: noteField
          width: parent.width
          foreground: root.foreground
          accent: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          placeholderText: "可选,一行"
          text: root._note
          verticalPadding: Style.space(5)
          onTextChanged: { root._note = text }
          onAccepted: root.commit()
          Keys.onEscapePressed: root.cancel()
        }
      }
    }

    // ---- 操作行 ----
    Item {
      width: parent.width
      height: Math.max(addBtn.implicitHeight, Style.spacing.controlHeight)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: actionsRow.left
        anchors.rightMargin: Style.spacing.md
        visible: root.timeBad || root.fieldError !== ""
        elide: Text.ElideRight
        text: root.timeBad ? "时间应为 HH:MM(如 14:30)" : root.fieldError
        color: Qt.darker(Color.urgent, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        id: actionsRow
        anchors.right: parent.right
        spacing: Style.spacing.xs

        Button {
          id: cancelBtn
          text: "取消"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          bordered: true
          onClicked: root.cancel()
        }

        Button {
          id: addBtn
          text: root.editing ? "保存修改" : "添加"
          iconText: "\uDB81\uDC15"   // md-plus
          accent: root.accent
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.commit()
        }
      }
    }
  }

  // 状态选择块:蓝色圆形图标(空心/半圆/实心)+ 文字,点击选中
  component StatusChip: Item {
    id: chip

    property string value: ""
    property string labelText: ""
    property string glyphText: ""
    property color accentColor: "#7aa2f7"
    property bool active: false
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family

    signal chosen(string value)

    readonly property bool hovered: chipMouse.containsMouse

    width: contentRow.implicitWidth + Style.space(22)
    height: Style.spacing.controlHeight

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: chip.active
        ? Util.alpha(chip.accentColor, 0.12)
        : (chip.hovered ? Util.alpha(chip.foreground, 0.06) : "transparent")
      border.width: chip.active ? Style.spacing.hairline * 2 : 0
      border.color: chip.active ? Util.alpha(chip.accentColor, 0.9) : "transparent"

      Behavior on color { ColorAnimation { duration: 80 } }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.chosen(chip.value)
    }

    Row {
      id: contentRow
      x: Style.space(11)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.glyphText
        color: chip.active ? chip.accentColor : Qt.darker(chip.foreground, 1.6)
        font.family: chip.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.labelText
        color: chip.active ? chip.foreground : Qt.darker(chip.foreground, 1.4)
        font.family: chip.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: chip.active
      }
    }
  }

  // 标签选择块:圆点色标 + 文字,点击选中;active 高亮描边
  component FlagChip: Item {
    id: chip

    property string value: ""
    property string labelText: ""
    property color dotColor: "#888888"
    property bool active: false
    property color foreground: Color.foreground
    property color accent: Color.accent
    property string fontFamily: Style.font.family

    signal chosen(string value)

    readonly property bool hovered: chipMouse.containsMouse

    width: contentRow.implicitWidth + Style.space(24)
    height: Style.spacing.controlHeight

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      // 选中高亮用该标签自己的颜色(普通=蓝 / 重要=橙),不用通用 accent
      color: chip.active
        ? Util.alpha(chip.dotColor, 0.12)
        : (chip.hovered ? Util.alpha(chip.foreground, 0.06) : "transparent")
      border.width: chip.active ? Style.spacing.hairline * 2 : 0
      border.color: chip.active ? chip.dotColor : "transparent"

      Behavior on color { ColorAnimation { duration: 80 } }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.chosen(chip.value)
    }

    Row {
      id: contentRow
      x: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(3)
        height: Style.space(3)
        // 圆点永远是圆:不跟主题 cornerRadius(为 0 时会变方形)
        radius: height / 2
        color: chip.dotColor
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.labelText
        color: chip.active ? chip.foreground : Qt.darker(chip.foreground, 1.4)
        font.family: chip.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: chip.active
      }
    }
  }

  // 日期步进器:纯键盘/点击步进,避免自由文本日期的输入错误面
  component DateStepper: Item {
    id: stepper

    property string labelText: ""
    property string key: ""
    property string minKey: ""
    property bool locked: false
    property color foreground: Color.foreground
    property color accent: Color.accent
    property string fontFamily: Style.font.family
    signal stepped()

    height: Style.spacing.controlHeight

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(5)
      anchors.rightMargin: Style.space(5)
      spacing: Style.space(3)

      Text {
        visible: stepper.labelText !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: stepper.labelText
        color: Qt.darker(stepper.foreground, 1.5)
        font.family: stepper.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelActionButton {
        id: prevBtn
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uDB80\uDF74"   // md-minus
        tooltipText: "前一天"
        foreground: stepper.foreground
        fontFamily: stepper.fontFamily
        enabled: !stepper.locked
        onClicked: stepper.step(-1)
      }

      Text {
        id: keyText
        anchors.verticalCenter: parent.verticalCenter
        text: stepper.key
        elide: Text.ElideRight
        color: stepper.locked ? Qt.darker(stepper.foreground, 1.8) : stepper.foreground
        font.family: stepper.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
      }

      PanelActionButton {
        id: nextBtn
        anchors.verticalCenter: parent.verticalCenter
        iconText: "\uDB81\uDC15"   // md-plus
        tooltipText: "后一天"
        foreground: stepper.foreground
        fontFamily: stepper.fontFamily
        enabled: !stepper.locked
        onClicked: stepper.step(1)
      }
    }

    function step(delta) {
      var current = stepper.key
      if (current === "") current = EM.todayKey(new Date())
      var next = EM.addDays(current, delta)
      if (next === "") return
      if (stepper.minKey !== "" && EM.cmpKeys(next, stepper.minKey) < 0) return
      stepper.key = next
      stepper.stepped()
    }
  }
}
