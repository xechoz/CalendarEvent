# Calendar Event (xechoz.clock)

**English** | [中文](README.zh.md)

A clock, monthly calendar, and **event calendar with to-dos and reminders** bar
widget for [Omarchy Quattro](https://github.com/omacom/omarchy/tree/quattro).

Install from the [Omarchy plugin marketplace](https://plugins.omarchy.org/):

```sh
omarchy plugin add https://github.com/xechoz/CalendarEvent.git --enable --yes
```

<p>
  <img src="preview.png" alt="Calendar Event panel" width="320">
  <img src="screenshot-detail.png" alt="Day events view" width="320">
</p>

## Derived from omarchy.clock

This plugin is **cloned and extended from the built-in `omarchy.clock`** plugin
of the Omarchy desktop — credit is not claimed for the base work.
`BarWidget.qml`, `Panel.qml`, `Model.js` and the overall design originate from
upstream and remain under the upstream MIT license; see the Derived-work notice
in `LICENSE` for the full provenance statement.

- **Kept from upstream (not our contribution)**: clock display with
  right-click format cycling, the calendar grid, timezone selection.
- **Features added by this plugin**:
  - Per-day events: all-day, timed, and multi-day; repeat daily / weekly /
    monthly / yearly (with optional end date and per-occurrence skipping).
  - Todo statuses: todo → in progress → done, cycled with one click on the
    dot in each list row.
  - Desktop reminders: 5/10/15/30/60-minute lead presets, per-event lead
    minutes, never re-notified after a restart.
  - Chinese public holidays: rest days and makeup workdays, 2026 bundled,
    later years fetched online.
  - zh/en localization, event storage and settings persistence, reworked
    event-list and form UI.

## How it differs from other calendar plugins

Existing calendar plugins fall into two camps: **view-only integrations**
(Google Calendar / CalDAV / agenda readers — they display external events but
offer no local creation or reminders) or **lunar-calendar displays** (no
events at all). Calendar Event is the only integrated, fully local one:

- Bar clock + month grid + per-day event management (all-day / timed /
  multi-day / repeating, with per-occurrence skip) — no external account.
- Todo → in-progress → done statuses cycled from the list rows.
- Desktop reminders with per-event lead minutes (5–60) and deduplication.
- Chinese statutory holidays — 2026 bundled, later years fetched
  automatically once published.
- zh/en interface that follows the system language.

All data stays in `~/.local/share/omarchy-calendar`; the plugin works fully
offline.

## Features

- **Clock**: left-click opens the calendar, right-click cycles display formats
  (format/week start are written to shell.json and survive restarts),
  middle-click opens timezone selection.
- **Calendar**: fixed 6-row month grid, today highlighted / selected day
  outlined, event days marked with red/green dots (red = important).
- **Chinese holidays**: statutory holidays shown with red numbers + a "休"
  (rest) corner badge, makeup workdays blue + "班" (work); hover shows the
  holiday name, and the selected day appends it to the header. On by default
  for zh / CN / UTC+8 contexts; disable with the `holidays` setting.
- **Events**: click any day to manage it below — title / start–end date
  (multi-day) / time (empty = all day); repeat daily, weekly, monthly or
  yearly (with an optional end date and per-day skipping of a single
  occurrence).
- **Status**: three states per event — todo (open circle) / in progress (half
  circle) / done (filled circle); one click on the row-leading dot cycles them.
- **Reminders**: desktop notification n minutes before the event (n from
  5/10/15/30/60, default 10). Timed events anchor to the event time, all-day
  events to 09:00 of that day; multi-day events remind on the first day only;
  automatic deduplication — no repeated popups.
- **Shortcuts** (while the panel is open): `A` new event, `Esc` close the
  form, `Del` delete selected, `t` back to today, `w` toggle week start.
- **Language**: interface in Chinese or English, following the system language
  by default; force it with the inline `language` setting (below).

## Language (`language` setting)

UI and reminder strings are translated through the `i18n/I18n.qml` singleton.
Resolution rules:

- Unset / `"auto"` / empty: follow the system `Qt.locale()` (zh* → Chinese,
  anything else → English).
- `"zh"` / `"zh_CN"`: force Chinese; `"en"` / `"en_US"`: force English.

Write the key flat inside the xechoz.clock entry of `shell.json` (a shell
restart applies the change):

```json
{ "id": "xechoz.clock", "language": "en" }
```

## Chinese holidays (`holidays` setting)

Calendar cells mark Chinese statutory holidays (State Council schedule): rest
days show red numbers with a "休" badge, makeup workdays blue numbers with a
"班" badge; hovering shows the holiday name and the selected-day header
appends it.

- Unset / `"auto"`: smart default — on when the system language is Chinese,
  the system locale is a Chinese region, or the timezone is UTC+8 (all of
  mainland China); otherwise off.
- `"on"` / `"off"`: force on / off.

```json
{ "id": "xechoz.clock", "holidays": "off" }
```

Data source: [NateScarlet/holiday-cn](https://github.com/NateScarlet/holiday-cn)
(MIT, based on official gov.cn notices). The full 2026 schedule is bundled in
`calendar/Holidays.js`; for later years the same repository is fetched on
demand (once per missing year per session, silent on failure — offline you
simply get no markers). Once the State Council publishes 2027+ and the
repository picks it up, navigating to that month shows it automatically — no
plugin update needed.

## Install

```sh
omarchy plugin add https://github.com/xechoz/CalendarEvent.git --enable --yes
```

- Without `--yes` just confirm the prompts; you will be asked which bar
  section to place it in — **center** is recommended.
- It appears on the bar right after install; move it with
  `omarchy bar move xechoz.clock --section center`.
- To replace the built-in clock: change `bar.centerAnchor` to
  `"xechoz.clock"` in `~/.config/omarchy/shell.json` and remove the
  `omarchy.clock` layout entry (hot-reloads).

### Manual install

Put the whole folder at `~/.config/omarchy/plugins/xechoz.clock/`, then:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable xechoz.clock
```

## Update / Remove

```bash
omarchy plugin update xechoz.clock   # git-managed plugins update incrementally
omarchy plugin remove xechoz.clock   # removes only the plugin itself
```

To restore the built-in clock after removal, use `omarchy bar` or re-add the
`omarchy.clock` entry to shell.json.

## Dependencies

All ship with Omarchy or its base system — nothing extra to install:

- `python3`: atomic JSON read/write for event data (`events/events_sync.py`).
- `curl`: fetches holiday data for years after 2026; offline, the bundled
  2026 schedule still displays.
- `omarchy-notification-send`: desktop notifications (Omarchy system tool).

## Data

- Events: `~/.local/share/omarchy-calendar/events.json`
- Reminder dedup: `~/.local/share/omarchy-calendar/notified.json`

Data lives outside the plugin, so uninstalling/reinstalling never clears it;
back these two files up.

## Diagnostics

```bash
omarchy-shell xechoz.clock eventsDebug   # data load / counts / layout self-check
omarchy restart shell                    # force a full reload after big changes
```

Plugin code runs inside the `omarchy-shell` process (unsandboxed) — review any
third-party plugin code before installing.

## Development

- Logic/UI layering: `events/EventsModel.js` (pure JS, node-testable) +
  `events/events_sync.py` (atomic JSON backend), everything else QML.
- i18n: `i18n/I18n.qml` (QML singleton dictionary + `tr(key, args)`; bindings
  depend on `I18n.lang`, so switching language takes effect without restart).
- Holidays: `calendar/Holidays.js` (bundled 2026 + parsing, pure JS) +
  `calendar/HolidayStore.qml` (fetches later years).
- Layout: `Panel.qml` orchestrator → `calendar/CalendarContent.qml`
  (calendar) + `events/DayEvents.qml` (day events) +
  `reminders/ReminderEngine.qml` (reminders).
