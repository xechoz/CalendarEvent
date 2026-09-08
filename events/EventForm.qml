import QtQuick
import qs.Commons
import qs.Ui
import "EventsModel.js" as EM
import "../i18n"

// 添加/编辑事件表单(events/ 模块,纯 UI)。
// 不直接碰存储:提交时把字段对象经 submit(fields) 抛出,由聚合层写 EventStore;
// 取消经 cancel()。字段:标题 / 时间(空=全天)/ 标签 / 状态 / 到点提醒
// (开关 + n 分钟前提前量,全天事件锚定当天 09:00)。
// 日期不在表单里改:新建固定在打开表单时聚合层传入的选中日(beginAdd 的
// dateKey);编辑沿用原事件日期。旧数据的重复/多日结构编辑时原样透传(整条修改)。
Item {
  id: root

  property var editing: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dotRed: "#e0744e"
  property color dotGreen: "#7aa2f7"
  property string fontFamily: Style.font.family

  signal submit(var fields)
  signal cancel()

  readonly property color dim: Qt.darker(foreground, 1.5)

  // ---- 内部字段(含脏校验反馈) ----
  // _date/_endKey/_repeat/_repeatUntil 由 begin* 从外部快照,表单不改动;
  // 编辑旧重复/多日事件时保持原结构,新建则永远是选中日上的单日事件。
  property string _date: ""
  property string _endKey: ""
  property string _repeat: "none"
  property string _repeatUntil: ""
  property string _title: ""
  property string _time: ""
  property string _flag: "normal"
  property string _status: "todo"
  property bool _remind: true
  property int _remindMinutes: 10
  property string fieldError: ""
  property string _errField: ""     // "title" | "time" | "" —— 错误归属字段

  // 提前量档位(分钟);默认 10,与提醒引擎缺省一致
  readonly property var remindPresets: [5, 10, 15, 30, 60]
  readonly property int defaultRemindMinutes: 10

  readonly property bool timeBad: root._time !== "" && EM.normalizeTime(root._time) === null

  function beginAdd(dateKey) {
    root.editing = null
    root._date = EM.normalizeDate(dateKey) || EM.todayKey(new Date())
    root._endKey = ""
    root._repeat = "none"
    root._repeatUntil = ""
    root._title = ""
    root._flag = "normal"
    root._status = "todo"
    root._time = ""
    root._remind = true
    root._remindMinutes = root.defaultRemindMinutes
    root.fieldError = ""
  }

  function beginEdit(event) {
    if (!event) return
    root.editing = event
    root._date = event.date
    root._endKey = event.endDate || ""
    root._repeat = event.repeat || "none"
    root._repeatUntil = event.repeatUntil || ""
    root._title = event.title
    root._flag = event.flag === "important" ? "important" : "normal"
    root._status = EM.STATUSES.indexOf(event.status) !== -1 ? event.status : "todo"
    root._time = event.time || ""
    root._remind = event.remind !== false
    root._remindMinutes = root.normalizeRemindValue(event.remindMinutes)
    root.fieldError = ""
  }

  function toggleRemind() { root._remind = !root._remind }

  // 事件旧数据无提前量字段时回默认;非法值或不在档位内的吸附回默认
  function normalizeRemindValue(v) {
    var n = Number(v)
    if (!isFinite(n) || Math.floor(n) !== n || n < 0) return root.defaultRemindMinutes
    if (root.remindPresets.indexOf(n) === -1) return root.defaultRemindMinutes
    return n
  }

  // 步进提前量:在档位间循环(delta=±1)
  function stepRemind(delta) {
    var idx = root.remindPresets.indexOf(root._remindMinutes)
    var len = root.remindPresets.length
    if (idx === -1) idx = root.remindPresets.indexOf(root.defaultRemindMinutes)
    idx = (idx + delta) % len
    if (idx < 0) idx += len
    root._remindMinutes = root.remindPresets[idx]
  }

  // 状态选择统一入口:切到“已完成”时自动关提醒
  function chooseStatus(v) {
    if (v === "done" && root._status !== "done" && root._remind) root._remind = false
    root._status = v
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
      root.fieldError = I18n.tr("title_required")
      root._errField = "title"
      titleField.forceActiveFocus()
      return
    }
    if (root.timeBad) {
      root.fieldError = I18n.tr("time_format_error")
      root._errField = "time"
      timeField.forceActiveFocus()
      return
    }
    root._errField = ""
    var startKey = EM.normalizeDate(root._date) || EM.todayKey(new Date())
    var endKey = null
    if (root._endKey !== "" && root._endKey !== root._date)
      endKey = EM.normalizeDate(root._endKey)
    if (endKey && EM.cmpKeys(endKey, startKey) < 0) endKey = null
    var repeat = root._repeat
    var untilKey = null
    if (repeat !== "none" && root._repeatUntil !== "")
      untilKey = EM.normalizeDate(root._repeatUntil)
    var payload = {
      id: root.editing ? String(root.editing.id) : "",
      title: title,
      flag: root._flag,
      status: root._status,
      date: startKey,
      endDate: endKey,
      time: EM.normalizeTime(root._time),
      repeat: repeat,
      repeatUntil: untilKey,
      remind: root._remind,
      remindMinutes: root._remindMinutes
    }
    root.submit(payload)
  }

  // ---- 提醒描述 ----
  // 锚点:带时间的事件用事件时刻;全天事件用当天 09:00(不再有独立文案,
  // 与提醒引擎同一规则);提醒时刻 = 锚点 - 提前量,不足则钳到 00:00。
  function anchorMin() {
    var t = EM.normalizeTime(root._time)
    if (t) return parseInt(t.slice(0, 2), 10) * 60 + parseInt(t.slice(3, 5), 10)
    return 9 * 60
  }

  function formatMin(min) {
    if (min < 0) min = 0
    var hh = Math.floor(min / 60)
    var mm = min % 60
    return (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm
  }

  // 提醒描述位文案(步进值之后的一段)
  function remindDesc() {
    if (root._status === "done" && !root._remind)
      return I18n.tr("done_remind_off")
    if (!root._remind) return ""
    if (root.timeBad) return I18n.tr("time_bad_remind")
    return I18n.tr("remind_desc", [root.formatMin(root.anchorMin() - root._remindMinutes)])
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

      TextField {
        id: titleField
        width: parent.width
        foreground: root.foreground
        accent: root.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        placeholderText: I18n.tr("title_placeholder")
        text: root._title
        verticalPadding: Style.space(5)
        onTextChanged: {
          root._title = text
          if (root.fieldError !== "") { root.fieldError = ""; root._errField = "" }
        }
        onAccepted: root.commit()
        Keys.onEscapePressed: root.cancel()
      }

      // 校验错误红框(就近反馈)
      Rectangle {
        visible: root._errField === "title" && root.fieldError !== ""
        anchors.fill: titleField
        radius: Style.cornerRadius
        color: "transparent"
        border.width: Style.spacing.hairline * 2
        border.color: Color.urgent
      }

      Text {
        visible: root._errField === "title" && root.fieldError !== ""
        width: parent.width
        text: root.fieldError
        color: Qt.darker(Color.urgent, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        topPadding: Style.space(2)
      }
    }

    // ---- 时间 ----
    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        text: I18n.tr("time_label")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Row {
        id: timeRow
        width: parent.width
        spacing: Style.space(4)

        TextField {
          id: timeField
          width: clearTimeBtn.visible
            ? parent.width - clearTimeBtn.width - parent.spacing : parent.width
          foreground: root.foreground
          accent: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          placeholderText: "HH:MM"
          text: root._time
          verticalPadding: Style.space(5)
          onTextChanged: {
            root._time = text
            if (root.fieldError !== "") { root.fieldError = ""; root._errField = "" }
          }
          onAccepted: root.commit()
          Keys.onEscapePressed: root.cancel()
        }

        PanelActionButton {
          id: clearTimeBtn
          anchors.verticalCenter: parent.verticalCenter
          visible: root._time !== ""
          iconText: "\uDB80\uDD56"      // md-close
          tooltipText: I18n.tr("clear_time_tooltip")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root._time = ""
        }
      }

      Rectangle {
        visible: root._errField === "time" && root.fieldError !== ""
        anchors.fill: timeRow
        radius: Style.cornerRadius
        color: "transparent"
        border.width: Style.spacing.hairline * 2
        border.color: Color.urgent
      }
    }

    // ---- 标签(普通=蓝点 / 重要=橙点,决定日期圆点颜色) ----
    Row {
      width: parent.width
      spacing: Style.space(6)

      FieldLabel {
        text: I18n.tr("flag")
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        FlagChip {
          value: "normal"
          labelText: I18n.tr("flag_normal")
          dotColor: root.dotGreen
          active: root._flag === "normal"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onChosen: root._flag = "normal"
        }

        FlagChip {
          value: "important"
          labelText: I18n.tr("flag_important")
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

      FieldLabel {
        text: I18n.tr("status")
      }

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        StatusChip {
          value: "todo"
          labelText: I18n.tr("status_todo")
          glyphText: "\uDB82\uDE9E"     // md circle-slice-1(1% 进度)
          active: root._status === "todo"
          accentColor: root._flag === "important" ? root.dotRed : root.dotGreen
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChosen: root.chooseStatus("todo")
        }

        StatusChip {
          value: "inprogress"
          labelText: I18n.tr("status_inprogress")
          glyphText: "\uDB84\uDF96"     // md circle-half-full
          active: root._status === "inprogress"
          accentColor: root._flag === "important" ? root.dotRed : root.dotGreen
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChosen: root.chooseStatus("inprogress")
        }

        StatusChip {
          value: "done"
          labelText: I18n.tr("status_done")
          glyphText: "\uDB81\uDDE0"     // md check-circle(实心+钩)
          active: root._status === "done"
          accentColor: root._flag === "important" ? root.dotRed : root.dotGreen
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChosen: root.chooseStatus("done")
        }
      }
    }

    // ---- 提醒(单行:标题 + 开关 + 提前量步进 + 提醒时刻描述) ----
    Item {
      id: remindWrap
      width: parent.width
      height: Style.spacing.controlHeight

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: "transparent"
        border.width: remindRow.activeFocus ? Style.spacing.hairline : 0
        border.color: remindRow.activeFocus ? Util.alpha(root.accent, 0.7) : "transparent"
      }

      Row {
        id: remindRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        activeFocusOnTab: true
        Keys.onSpacePressed: { root.toggleRemind(); event.accepted = true }
        Keys.onReturnPressed: { root.toggleRemind(); event.accepted = true }
        Keys.onEscapePressed: { root.cancel(); event.accepted = true }
        Keys.onLeftPressed: { if (root._remind && !root.timeBad) root.stepRemind(-1); event.accepted = true }
        Keys.onRightPressed: { if (root._remind && !root.timeBad) root.stepRemind(1); event.accepted = true }

        FieldLabel {
          text: I18n.tr("remind")
        }

        ToggleSwitch {
          id: remindSwitch
          anchors.verticalCenter: parent.verticalCenter
          checked: root._remind
          foreground: root.foreground
          accent: root.accent
          onToggled: function() { root.toggleRemind() }
        }

        // 提前量步进器(档位循环);开启且时间合法时出现
        Row {
          id: stepRow
          visible: root._remind && !root.timeBad
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          StepperBtn {
            anchors.verticalCenter: parent.verticalCenter
            text: "-"
            foreground: root.foreground
            dimColor: root.dim
            fontFamily: root.fontFamily
            onClicked: root.stepRemind(-1)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(22)
            horizontalAlignment: Text.AlignHCenter
            text: String(root._remindMinutes)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          StepperBtn {
            anchors.verticalCenter: parent.verticalCenter
            text: "+"
            foreground: root.foreground
            dimColor: root.dim
            fontFamily: root.fontFamily
            onClicked: root.stepRemind(1)
          }
        }

        Text {
          id: remindDescText
          visible: root.remindDesc() !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: root.remindDesc()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
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
        visible: root.fieldError !== "" && root._errField === ""
        elide: Text.ElideRight
        text: root.fieldError
        color: Qt.darker(Color.urgent, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        id: actionsRow
        anchors.right: parent.right
        spacing: Style.spacing.xs

        // 取消:次要操作,低调(无边框幽灵态)
        Button {
          id: cancelBtn
          text: I18n.tr("cancel")
          foreground: root.dim
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.cancel()
        }

        // 添加/保存:主操作,accent 实底;悬停/按下透明度 50%
        PrimaryBtn {
          id: addBtn
          text: root.editing ? I18n.tr("save_changes") : I18n.tr("add")
          iconText: "\uDB81\uDC15"   // md-plus
          accent: root.accent
          foreground: Color.background
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.commit()
        }
      }
    }
  }

  // 固定宽度行标签:让 标签/状态/提醒 三行的内容列左对齐
  component FieldLabel: Text {
    width: Style.space(48)
    anchors.verticalCenter: parent.verticalCenter
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  // 主按钮(添加/保存):accent 实底。
  // 反馈语言:悬停 → 叠 10% 白蒙层微提亮(引导可点);按下 → 整体透明度 70%
  // (按下去);键盘 Tab 有焦点环,Space/Enter 触发。
  component PrimaryBtn: Item {
    id: pb

    property string text: ""
    property string iconText: ""
    property color accent: Color.accent
    property color foreground: Color.background
    property string fontFamily: Style.font.family
    property int fontSize: Style.font.bodySmall

    signal clicked()

    readonly property bool hot: pbMouse.containsMouse
    readonly property bool down: pbMouse.pressed

    implicitWidth: content.implicitWidth + Style.space(24)
    implicitHeight: Style.spacing.controlHeight
    activeFocusOnTab: true

    opacity: pb.down ? 0.7 : 1
    Behavior on opacity { NumberAnimation { duration: 90 } }

    Keys.onSpacePressed: { pb.clicked(); event.accepted = true }
    Keys.onReturnPressed: { pb.clicked(); event.accepted = true }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: pb.accent
    }

    // 悬停提亮蒙层(按下时不叠加,避免和透明度混淆)
    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: "#ffffff"
      opacity: pb.hot && !pb.down ? 0.1 : 0
      Behavior on opacity { NumberAnimation { duration: 90 } }
    }

    // 键盘焦点环
    Rectangle {
      anchors.fill: parent
      anchors.margins: -Style.space(2)
      radius: Style.cornerRadius + Style.space(2)
      color: "transparent"
      border.width: pb.activeFocus ? Style.spacing.hairline * 2 : 0
      border.color: pb.activeFocus ? Util.alpha(pb.accent, 0.9) : "transparent"
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)

      Text {
        visible: pb.iconText !== ""
        text: pb.iconText
        color: pb.foreground
        font.family: pb.fontFamily
        font.pixelSize: pb.fontSize
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: pb.text
        color: pb.foreground
        font.family: pb.fontFamily
        font.pixelSize: pb.fontSize
        font.bold: true
      }
    }

    MouseArea {
      id: pbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pb.clicked()
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
    activeFocusOnTab: true

    Keys.onSpacePressed: { chip.chosen(chip.value); event.accepted = true }
    Keys.onReturnPressed: { chip.chosen(chip.value); event.accepted = true }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: chip.active
        ? Util.alpha(chip.accentColor, 0.12)
        : (chip.hovered ? Util.alpha(chip.foreground, 0.06) : "transparent")
      border.width: chip.active || chip.activeFocus ? Style.spacing.hairline * 2 : 0
      border.color: chip.active ? Util.alpha(chip.accentColor, 0.9)
        : (chip.activeFocus ? Util.alpha(chip.foreground, 0.8) : "transparent")

      Behavior on color { ColorAnimation { duration: 80 } }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { chip.forceActiveFocus(); chip.chosen(chip.value) }
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
    activeFocusOnTab: true

    Keys.onSpacePressed: { chip.chosen(chip.value); event.accepted = true }
    Keys.onReturnPressed: { chip.chosen(chip.value); event.accepted = true }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      // 选中高亮用该标签自己的颜色(普通=蓝 / 重要=橙),不用通用 accent
      color: chip.active
        ? Util.alpha(chip.dotColor, 0.12)
        : (chip.hovered ? Util.alpha(chip.foreground, 0.06) : "transparent")
      border.width: chip.active || chip.activeFocus ? Style.spacing.hairline * 2 : 0
      border.color: chip.active ? chip.dotColor
        : (chip.activeFocus ? Util.alpha(chip.accent, 0.8) : "transparent")

      Behavior on color { ColorAnimation { duration: 80 } }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { chip.forceActiveFocus(); chip.chosen(chip.value) }
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

  // 提醒提前量步进器按钮:纯文字 −/+ 小圆角块(不依赖图标字体)。
  // 悬停叠浅底、按下加深,和 chips 反馈语言一致;键盘由行级 左/右 方向键负责。
  component StepperBtn: Item {
    id: sb

    property string text: ""
    property color foreground: Color.foreground
    property color dimColor: Qt.darker(foreground, 1.5)
    property string fontFamily: Style.font.family

    signal clicked()

    readonly property bool hot: sbMouse.containsMouse
    readonly property bool down: sbMouse.pressed

    width: Style.space(18)
    height: Style.spacing.controlHeight

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: sb.down
        ? Util.alpha(sb.foreground, 0.14)
        : (sb.hot ? Util.alpha(sb.foreground, 0.07) : "transparent")
    }

    Text {
      anchors.centerIn: parent
      text: sb.text
      color: sb.hot ? sb.foreground : sb.dimColor
      font.family: sb.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    MouseArea {
      id: sbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sb.clicked()
    }
  }
}
