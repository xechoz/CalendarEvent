import QtQuick
import QtQuick.Controls as QC
import qs.Commons
import qs.Ui
import "EventsModel.js" as EM

// 添加/编辑事件表单(events/ 模块,纯 UI)。
// 不直接碰存储:提交时把字段对象经 submit(fields) 抛出,由聚合层写 EventStore;
// 取消经 cancel()。字段:标题 / 起止日期(多日)/ 时间(空=全天)/
// 重复 + 截止 / 到点提醒。规则:多日与重复互斥(见 EventsModel)。
Item {
  id: root

  property string startDateKey: EM.todayKey(new Date())
  property var editing: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color dotRed: "#e0744e"
  property color dotGreen: "#7aa2f7"
  property int weekStart: 1
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
  property string fieldError: ""
  property string _errField: ""     // "title" | "time" | "" —— 错误归属字段
  // 重复事件「仅改这一天」:进入编辑时由聚合层带上本次出现的日期
  property string editingOccurrenceKey: ""
  property bool _detach: false
  readonly property bool detachFirstOccurrence: !!root.editing
    && root.editingOccurrenceKey !== ""
    && root.editingOccurrenceKey === String(root.editing.date || "")
  readonly property bool detachAllowed: !!root.editing
    && root.editing.repeat && root.editing.repeat !== "none"
    && root.editingOccurrenceKey !== ""
    && !root.detachFirstOccurrence
  // 在多日基础上改选重复时,被自动忽略的原结束日期(提示用)
  property string _endIgnored: ""

  readonly property bool timeBad: root._time !== "" && EM.normalizeTime(root._time) === null

  property var repeatOptions: [
    { value: "none", label: "不重复" },
    { value: "daily", label: "每天" },
    { value: "weekly", label: "每周" },
    { value: "monthly", label: "每月" },
    { value: "yearly", label: "每年" }
  ]

  function toggleDetach() {
    if (!root.detachAllowed || !root.editing) return
    root._detach = !root._detach
    if (root._detach) {
      // 本次编辑针对所选出现日;原系列将在保存时跳过这天
      root._startKey = root.editingOccurrenceKey
      root._endKey = ""
      root._endIgnored = ""
    }
  }

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
    root._endIgnored = ""
    root.fieldError = ""
  }

  function beginEdit(event) {
    if (!event) return
    root.editing = event
    root._detach = false
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
    root._endIgnored = ""
    root.fieldError = ""
  }

  function toggleRemind() { root._remind = !root._remind }

  function toggleUntil() {
    root._hasUntil = !root._hasUntil
    if (root._hasUntil && !root._repeatUntil)
      root._repeatUntil = EM.addDays(root._startKey, 30)
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
      root.fieldError = "标题不能为空"
      root._errField = "title"
      titleField.forceActiveFocus()
      return
    }
    if (root.timeBad) {
      root.fieldError = "时间格式应为 HH:MM(如 14:30)"
      root._errField = "time"
      timeField.forceActiveFocus()
      return
    }
    root._errField = ""
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
      remind: root._remind
    }
    if (root._detach && root.editing)
      payload.detachFrom = String(root.editing.id)
    root.submit(payload)
  }

  // 双栏行的栏宽:成对 Row 的 spacing 是 8(不是 body 的 6),
  // 少算会把右栏挤宽 2px、被面板滚动区裁掉右边,见各双栏 Row。
  function halfWidth() {
    return Math.floor((body.width - Style.space(8)) / 2)
  }

  // ---- 重复预览文案(所见即所得:把展开规则翻成人话) ----
  function shortKey(key) {
    var p = EM.parseKey(key)
    if (!p) return key
    return (p.month + 1) + "/" + p.day
  }

  function repeatSummary() {
    if (root._repeat === "none") return ""
    var p = EM.parseKey(root._startKey)
    if (!p) return ""
    var d = new Date(p.year, p.month, p.day)
    var weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    var base = ""
    if (root._repeat === "daily") base = "每天"
    else if (root._repeat === "weekly") base = "每周" + weekdays[d.getDay()]
    else if (root._repeat === "monthly") base = "每月 " + p.day + " 日(该月没有这天则跳过)"
    else if (root._repeat === "yearly") base = "每年 " + (p.month + 1) + "/" + p.day
      + (p.month === 1 && p.day === 29 ? "(闰年才有)" : "")
    else base = "不重复"
    var f = EM.repeatForecast({
      date: root._startKey,
      repeat: root._repeat,
      repeatUntil: root._hasUntil ? root._repeatUntil : "",
      today: EM.todayKey(new Date())
    })
    var parts = [base]
    if (f.next.length === 0) {
      parts.push(root._hasUntil ? "已到截止日,不再出现" : "暂无后续出现")
    } else {
      parts.push("下次 " + f.next.map(root.shortKey).join("、"))
    }
    if (f.untilTotal !== null) parts.push("共 " + f.untilTotal + " 次")
    else if (f.yearCount !== null
        && root._repeat !== "daily" && root._repeat !== "yearly" && f.yearCount > 0)
      parts.push("约 " + f.yearCount + " 次/年")
    return parts.join(" · ")
  }

  // 提醒时刻说明:带时间 → 提前 10 分钟(实时计算);全天 → 09:00
  function remindText() {
    if (root._time === "") return "全天 09:00 提醒"
    var t = EM.normalizeTime(root._time)
    if (!t) return "填好时间后这里会显示提醒时刻"
    var min = parseInt(t.slice(0, 2), 10) * 60 + parseInt(t.slice(3, 5), 10) - 10
    if (min < 0) min = 0
    var hh = Math.floor(min / 60)
    var mm = min % 60
    return "提前 10 分钟 · 将于 " + (hh < 10 ? "0" : "") + hh + ":"
      + (mm < 10 ? "0" : "") + mm + " 提醒"
  }

  // 自报测量高度:宿主(聚合层/外层 Column)靠 implicitHeight 决定表单是否占位,
  // Item 默认 implicitHeight 为 0,不声明的话字段整块会塌成 0 高。
  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: parent.width
    spacing: Style.space(6)
    topPadding: Style.space(2)

    // ---- 编辑重复出现时的「仅改这一天」切换 ----
    Column {
      width: parent.width
      visible: root.editing && root.editing.repeat && root.editing.repeat !== "none"
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "本次编辑"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Button {
          id: detachBtn
          text: root._detach ? "整条同步改" : "仅改这一天"
          foreground: root._detach ? Color.background : root.foreground
          background: root._detach ? root.accent : "transparent"
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          enabled: !!root.editing
            && !root.detachFirstOccurrence
          tooltipText: root.detachFirstOccurrence
            ? "首次出现日不能单独改,请整条修改"
            : (root._detach ? "恢复为修改整条重复事件" : "把这次出现复制成单日事件再改,原系列跳过这一天")
          onClicked: root.toggleDetach()
        }
      }

      Text {
        visible: root._detach
        width: parent.width
        wrapMode: Text.Wrap
        text: "将把本次出现(" + root.shortKey(root.editingOccurrenceKey)
          + ")存为单日事件,原重复系列会跳过这一天;状态/标签/时间等以当前填写为准。"
        color: Util.alpha(root.foreground, 0.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

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
        placeholderText: "接下来要做些什么呢…"
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

    // ---- 日期起止 / 时间·重复 ----
    Row {
      width: parent.width
      spacing: Style.space(8)

      DateStepper {
        id: startStepper
        labelText: "开始"
        key: root._startKey
        width: root.halfWidth()
        showToday: true
        weekStart: root.weekStart
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onEscapeKey: root.cancel()
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
        weekStart: root.weekStart
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onEscapeKey: root.cancel()
        onStepped: {
          root._endKey = endStepper.key === root._startKey ? "" : endStepper.key
          root._endIgnored = ""
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
            tooltipText: "清空时间(变为全天)"
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
              var dropped = root._endKey !== "" && root._endKey !== root._startKey
                ? root._endKey : ""
              root._repeat = v
              if (v !== "none" && dropped !== "") {
                root._endIgnored = dropped
                root._endKey = ""
              }
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
              border.width: untilRow.activeFocus ? Style.spacing.hairline : 0
              border.color: untilRow.activeFocus ? Util.alpha(root.accent, 0.7) : "transparent"
            }

            Row {
              id: untilRow
              anchors.fill: parent
              anchors.leftMargin: Style.space(4)
              spacing: Style.space(4)
              activeFocusOnTab: true
              Keys.onSpacePressed: { root.toggleUntil(); event.accepted = true }
              Keys.onReturnPressed: { root.toggleUntil(); event.accepted = true }

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
                onToggled: function() { root.toggleUntil() }
              }
            }
          }
        }
      }
    }

    // ---- 重复说明(预览 + 冲突提示) ----
    Text {
      visible: root._repeat !== "none"
      width: parent.width
      wrapMode: Text.Wrap
      text: root._endIgnored !== ""
        ? "已按单日重复,忽略原结束日期 " + root.shortKey(root._endIgnored)
          + "(想限制到某天请在“限”里设置)"
        : root.repeatSummary()
      color: root._endIgnored !== ""
        ? Qt.darker(Color.urgent, 1.2)
        : Util.alpha(root.foreground, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
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
        weekStart: root.weekStart
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        onEscapeKey: root.cancel()
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
          onChosen: root.chooseStatus("todo")
        }

        StatusChip {
          value: "inprogress"
          labelText: "进行中"
          glyphText: "\uDB84\uDF96"     // md circle-half-full
          active: root._status === "inprogress"
          accentColor: root._flag === "important" ? root.dotRed : root.dotGreen
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChosen: root.chooseStatus("inprogress")
        }

        StatusChip {
          value: "done"
          labelText: "已完成"
          glyphText: "\uDB81\uDDE0"     // md check-circle(实心+钩)
          active: root._status === "done"
          accentColor: root._flag === "important" ? root.dotRed : root.dotGreen
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChosen: root.chooseStatus("done")
        }
      }
    }

    // ---- 提醒 ----
    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        text: "提醒"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

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

          ToggleSwitch {
            id: remindSwitch
            anchors.verticalCenter: parent.verticalCenter
            checked: root._remind
            foreground: root.foreground
            accent: root.accent
            onToggled: function() { root.toggleRemind() }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.remindText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // 已完成时提醒被自动关闭的说明
      Text {
        visible: root._status === "done" && !root._remind
        text: "已完成事件默认不再提醒;如需提醒请重新打开开关"
        color: Util.alpha(root.foreground, 0.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
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
          text: "取消"
          foreground: root.dim
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: root.cancel()
        }

        // 添加/保存:主操作,accent 实底;悬停/按下透明度 50%
        PrimaryBtn {
          id: addBtn
          text: root.editing ? (root._detach ? "仅此天保存" : "保存修改") : "添加"
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

  // 步进图标钮:单击步进一次,长按 420ms 后每 90ms 连发
  component StepIconBtn: Item {
    id: b

    property string glyphText: ""
    property string textLabel: ""
    property string tipText: ""
    property bool enabled: true
    property color foreground: Color.foreground
    property string fontFamily: Style.font.family
    property var onStep: null      // function(): 触发一次步进

    readonly property bool hovered: holdMouse.containsMouse
    readonly property bool down: holdMouse.pressed
    property bool _held: false
    property int _pressStart: 0

    width: Style.space(24)
    height: Style.spacing.controlHeight

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: b.down ? Util.alpha(b.foreground, 0.14)
        : (b.hovered ? Util.alpha(b.foreground, 0.07) : "transparent")
      Behavior on color { ColorAnimation { duration: 70 } }
    }

    Text {
      anchors.centerIn: parent
      visible: b.textLabel === ""
      text: b.glyphText
      color: b.enabled
        ? (b.hovered || b.down ? b.foreground : Qt.darker(b.foreground, 1.4))
        : Qt.darker(b.foreground, 1.9)
      font.family: b.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.centerIn: parent
      visible: b.textLabel !== ""
      text: b.textLabel
      color: b.enabled
        ? (b.hovered || b.down ? b.foreground : Qt.darker(b.foreground, 1.2))
        : Qt.darker(b.foreground, 1.9)
      font.family: b.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: b.hovered || b.down
    }

    MouseArea {
      id: holdMouse
      anchors.fill: parent
      enabled: b.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onPressed: {
        b._held = false
        b._pressStart = Date.now()
        holdTimer.interval = 420
        holdTimer.repeat = false
        holdTimer.running = true
      }
      onReleased: {
        var wasHeld = b._held
        holdTimer.running = false
        if (!wasHeld && b.onStep) b.onStep()
      }
      onCanceled: { holdTimer.running = false }
    }

    Timer {
      id: holdTimer
      repeat: false
      onTriggered: {
        b._held = true
        if (b.onStep) b.onStep()
        holdTimer.interval = 90
        holdTimer.repeat = true
        holdTimer.running = true
      }
    }

    PanelToolTip {
      visible: !!holdMouse.hovered && b.tipText !== ""
      text: b.tipText
      fontFamily: b.fontFamily
    }
  }

  // 日期步进器:点击/长按连发 ± 天、键盘步进、双击 = ±1 周、
  // 焦点后 ↑↓ ←→ / PgUp PgDn、可选「今天」快捷钮。
  component DateStepper: Item {
    id: stepper

    property string labelText: ""
    property string key: ""
    property string minKey: ""
    property bool locked: false
    property bool showToday: false
    property int pickerYear: 0
    property int pickerMonth: 0
    property int weekStart: 1
    property color foreground: Color.foreground
    property color accent: Color.accent
    property string fontFamily: Style.font.family
    signal stepped()
    signal escapeKey()

    height: Style.spacing.controlHeight
    activeFocusOnTab: true

    function step(delta) {
      if (stepper.locked) return
      var current = stepper.key
      if (current === "") current = EM.todayKey(new Date())
      var next = EM.addDays(current, delta)
      if (next === "") return
      if (stepper.minKey !== "" && EM.cmpKeys(next, stepper.minKey) < 0) return
      stepper.key = next
      stepper.forceActiveFocus()
      stepper.stepped()
    }

    function jumpToday() {
      if (stepper.locked) return
      var current = stepper.key || EM.todayKey(new Date())
      var today = EM.todayKey(new Date())
      var d = EM.diffDays(current, today)
      stepper.step(d)
    }

    Keys.onLeftPressed: { stepper.step(-1); event.accepted = true }
    Keys.onRightPressed: { stepper.step(1); event.accepted = true }
    Keys.onUpPressed: { stepper.step(7); event.accepted = true }
    Keys.onDownPressed: { stepper.step(-7); event.accepted = true }
    Keys.onEscapePressed: { stepper.escapeKey(); event.accepted = true }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: "transparent"
      border.width: stepper.activeFocus ? Style.spacing.hairline : 0
      border.color: stepper.activeFocus
        ? Util.alpha(stepper.accent, 0.55) : "transparent"
    }

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

      StepIconBtn {
        id: prevBtn
        anchors.verticalCenter: parent.verticalCenter
        glyphText: "\uDB80\uDF74"     // md-minus
        tipText: "前一天(按住连续)"
        enabled: !stepper.locked
        foreground: stepper.foreground
        fontFamily: stepper.fontFamily
        onStep: function() { stepper.step(-1) }
      }

      // 日期文本:单击打开迷你月历;双击 = ±1 周
      Item {
        id: keyHost
        width: keyText.implicitWidth
        height: parent.height

        Text {
          id: keyText
          anchors.centerIn: parent
          text: stepper.key
          elide: Text.ElideRight
          color: stepper.locked ? Qt.darker(stepper.foreground, 1.8) : stepper.foreground
          font.family: stepper.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
          id: keyArea
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (stepper.locked) return
            if (clickGate.running) {          // 第二次点击构成双击
              clickGate.stop()
              stepper.step(7)
              return
            }
            clickGate.running = true           // 等待双可判
          }
        }

        PanelToolTip {
          visible: keyArea.containsMouse && !stepper.locked
          text: "点开日历选择 · 双击跳一周"
          fontFamily: stepper.fontFamily
        }

        Timer {
          id: clickGate
          interval: 240
          onTriggered: {
            stepper.pickerYear = EM.parseKey(stepper.key).year
            stepper.pickerMonth = EM.parseKey(stepper.key).month
            pickerPopup.open()
          }
        }
      }

      StepIconBtn {
        id: nextBtn
        anchors.verticalCenter: parent.verticalCenter
        glyphText: "\uDB81\uDC15"     // md-plus
        tipText: "后一天(按住连续)"
        enabled: !stepper.locked
        foreground: stepper.foreground
        fontFamily: stepper.fontFamily
        onStep: function() { stepper.step(1) }
      }

      StepIconBtn {
        id: todayBtn
        visible: stepper.showToday && !stepper.locked
          && stepper.key !== EM.todayKey(new Date())
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(44)
        textLabel: "今天"
        tipText: "回到今天"
        foreground: stepper.foreground
        fontFamily: stepper.fontFamily
        onStep: function() { stepper.jumpToday() }
      }
    }

    // ---- 迷你月历弹层 ----
    QC.Popup {
      id: pickerPopup
      parent: stepper
      x: 0
      y: stepper.height + Style.space(3)
      width: Math.min(Style.space(236), stepper.width)
      padding: Style.spacing.hairline * 2
      closePolicy: QC.Popup.CloseOnEscape | QC.Popup.CloseOnPressOutside
      focus: true

      background: Rectangle {
        color: Color.background
        radius: Style.cornerRadius
        border.width: Style.spacing.hairline
        border.color: Util.alpha(stepper.accent, 0.35)
      }

      contentItem: MiniCalendar {
        width: pickerPopup.width
        year: stepper.pickerYear > 0 ? stepper.pickerYear : EM.parseKey(stepper.key || EM.todayKey(new Date())).year
        month: stepper.pickerMonth > 0 ? stepper.pickerMonth : EM.parseKey(stepper.key || EM.todayKey(new Date())).month
        selectedKey: stepper.key
        todayKey: EM.todayKey(new Date())
        weekStart: stepper.weekStart
        foreground: stepper.foreground
        accent: stepper.accent
        fontFamily: stepper.fontFamily
        onPicked: function(k) {
          if (stepper.locked) { pickerPopup.close(); return }
          if (stepper.minKey !== "" && EM.cmpKeys(k, stepper.minKey) < 0)
            k = stepper.minKey
          stepper.key = k
          stepper.forceActiveFocus()
          stepper.stepped()
          pickerPopup.close()
        }
      }
    }
  }
}
