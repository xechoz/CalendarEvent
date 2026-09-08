# AGENTS.md

## 验证流程(必做)

每次修改完代码(任何文件),都必须重启 Omarchy shell 才能验证效果:

```bash
omarchy restart shell
```

插件代码运行在 omarchy-shell 进程内,没有单插件热重载;不重启则改动不会生效、
也无法确认结果。重启后可再自检:

```bash
omarchy-shell shell ping                      # shell 正常
omarchy-shell xechoz.clock eventsDebug        # 插件加载/数据/布局自检(loaded=true 且 err="" 即无 QML 报错)
```

注意:QML 语法错误只在 shell 重启加载时暴露(eventsDebug 的 err 字段 / shell 日志)。
