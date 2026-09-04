# Xechoz Calendar(xechoz.clock)

Omarchy bar 时钟 + 月历 + **事件日历**(带待办/提醒)插件。

克隆自 Omarchy 内置 `omarchy.clock`,扩展为可管理事件的日历:每个日期下可记录
全天/多日/定时/重复事件,附带 待办→进行中→已完成 状态与到点桌面提醒。

> Derived from the built-in `omarchy.clock` plugin of the Omarchy desktop
> (https://omarchy.org/). See LICENSE for provenance. MIT licensed.

## 功能

- **时钟**:左键弹出日历,右键切换显示格式(格式/周起始写入 shell.json,重启保留),中键打开时区选择
- **月历**:6 行月网格、今天高亮/选中日描边、有事件的日子显示红/绿圆点(重要=红)
- **事件**:点击任意一天,下方管理当日安排 —— 标题 / 起止日期(多日)/ 时间(留空=全天);支持 每天/每周/每月/每年 重复(可设截止日期、可按天跳过某次出现)
- **状态**:每个事件三态 待办(空心圆)/ 进行中(半圆)/ 已完成(实心圆,蓝);列表行首圆点一键切换
- **提醒**:定时事件提前 10 分钟桌面通知,全天事件默认 09:00(多日只在首日);自动去重,不会重复弹
- **快捷键**:面板内 `A` 新建事件、`Esc` 关闭表单、`Del` 删除选中、`t` 回到今天、`w` 切换周起始

## 安装

```bash
omarchy plugin add https://github.com/<your-name>/<repo>.git --enable --yes
```

- 无 `--yes` 时按提示确认即可;会询问放入 bar 哪个区,建议选 **center**
- 安装后自动出现在 bar 上;可用 `omarchy bar move xechoz.clock --section center` 调整
- 若想替换原内置时钟:在 `~/.config/omarchy/shell.json` 把 `bar.centerAnchor`
  改为 `"xechoz.clock"`,并把原 `omarchy.clock` 布局条目移除(文件热重载)

### 手动安装

把整个目录放到 `~/.config/omarchy/plugins/xechoz.clock/`,然后:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable xechoz.clock
```

## 更新 / 卸载

```bash
omarchy plugin update xechoz.clock    # git 管理的插件可增量更新
omarchy plugin remove xechoz.clock    # 只移除插件本体
```

卸载后如需恢复内置时钟:用 `omarchy bar` 或直接在 shell.json 里加回 `omarchy.clock` 条目。

## 数据

- 事件:`~/.local/share/omarchy-calendar/events.json`
- 提醒去重:`~/.local/share/omarchy-calendar/notified.json`

数据独立于插件本体,卸载/重装不会清空;备份时带上这两个文件即可。

## 诊断

```bash
omarchy-shell xechoz.clock eventsDebug   # 数据加载/计数/布局自检
omarchy restart shell                    # 大改后强制重载
```

插件代码运行在 `omarchy-shell` 进程内(非沙箱),安装第三方插件前请自行审阅代码。

## 开发

- 逻辑与 UI 分层:`events/EventsModel.js`(纯 JS,可 node 单测)、`events/events_sync.py`
  (原子 JSON 读写后端),其余为 QML
- 布局结构:`Panel.qml` 协调层 → `calendar/CalendarContent.qml`(月历)+
  `events/DayEvents.qml`(当日事件区)+ `reminders/ReminderEngine.qml`(提醒)
