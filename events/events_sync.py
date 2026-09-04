#!/usr/bin/env python3
"""日历事件的数据同步脚本(xechoz.clock 插件事件模块的数据后端)。

纯本地文件 I/O,不产生任何副作用:
  load-events [file]       打印 events.json 内容(不存在时输出空库)
  save-events <file> <json> 原子写入 events.json
  load-notified [file]     打印 notified.json 内容(不存在时输出空记录)
  save-notified <file> <json> 原子写入 notified.json

file 缺省时用 ~/.local/share/omarchy-calendar/ 下的默认路径。
原子性:先写临时文件再 os.replace,避免写入中途崩溃留下半截 JSON。
"""

import json
import os
import sys

DATA_DIR = os.path.expanduser("~/.local/share/omarchy-calendar")
DEFAULT_EVENTS_FILE = os.path.join(DATA_DIR, "events.json")
DEFAULT_NOTIFIED_FILE = os.path.join(DATA_DIR, "notified.json")

EMPTY_EVENTS = {"version": 1, "events": []}
EMPTY_NOTIFIED = {"keys": []}


def load_json(path, fallback):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            value = json.load(fh)
        if isinstance(value, dict):
            return value
    except (OSError, ValueError):
        pass
    return fallback


def save_json(path, value):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    payload = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(payload)
    os.replace(tmp, path)


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: events_sync.py load-events [file] | save-events <file> <json> | load-notified [file] | save-notified <file> <json>\n")
        return 2
    command = argv[1]
    if command == "load-events":
        path = argv[2] if len(argv) > 2 else DEFAULT_EVENTS_FILE
        print(json.dumps(load_json(path, EMPTY_EVENTS), ensure_ascii=False))
    elif command == "save-events":
        if len(argv) < 4:
            return 2
        payload = json.loads(argv[3])
        if not isinstance(payload, dict):
            return 2
        save_json(argv[2], payload)
    elif command == "load-notified":
        path = argv[2] if len(argv) > 2 else DEFAULT_NOTIFIED_FILE
        print(json.dumps(load_json(path, EMPTY_NOTIFIED), ensure_ascii=False))
    elif command == "save-notified":
        if len(argv) < 4:
            return 2
        payload = json.loads(argv[3])
        if not isinstance(payload, dict):
            return 2
        save_json(argv[2], payload)
    else:
        sys.stderr.write("unknown command: %s\n" % command)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
