<p align="center">
  <img src="images/icons/icon_128.png" alt="panmux 图标" width="96" />
</p>

<h1 align="center">panmux</h1>

<p align="center">
  面向 Linux/Wayland 上 coding agent 终端工作流的 Ghostty GTK 分叉。
</p>

<p align="center">
  <a href="./README.md">English</a>
  ·
  <a href="./README.zh-CN.md"><strong>简体中文</strong></a>
</p>

<p align="center">
  <img alt="platform" src="https://img.shields.io/badge/platform-Linux%20%2F%20Wayland-1f6feb" />
  <img alt="ui" src="https://img.shields.io/badge/frontend-GTK-2da44e" />
  <img alt="base" src="https://img.shields.io/badge/base-Ghostty-f59e0b" />
  <img alt="status" src="https://img.shields.io/badge/status-active%20prototype-dc2626" />
  <img alt="license" src="https://img.shields.io/badge/license-MIT-6f42c1" />
</p>

> 保留 Ghostty 的快速终端内核，再补上 agent 密集型终端工作真正缺的那层控制与状态视图。

`panmux` 并不打算完整复刻 `cmux`。它的目标更收敛也更实用：保留 Ghostty 的终端能力，然后围绕 Linux GTK 外壳做增强，让长时间运行的 agent 会话更容易观察、切换和协作。

## 为什么做 panmux

当你长期在终端里使用 coding agent，最棘手的问题往往不是终端模拟本身，而是协同管理：

- 现在到底哪个 tab 在忙？
- 哪个会话已经结束了？
- 这个 tab 对应哪个工作目录？
- 外部工具怎样在不靠屏幕解析的前提下传递状态？

`panmux` 就是为这些问题而生：在 Ghostty 已有终端基础之上，补上一层面向工作流的标签页 UI 和轻量控制平面。

## 当前能力一览

| 领域 | 当前已具备的能力 |
| --- | --- |
| 标签页体验 | 纵向侧边栏、显式快捷键提示、`Alt+1..9` 切换 |
| 上下文感知 | 侧边栏中直接显示当前工作目录 |
| 自动化接口 | 每个窗口一个 Unix socket 控制平面，使用 JSON Line 消息 |
| 状态标记 | 外部工具可把标签页标记为 `running`、`info`、`error`，也可以清空 |
| 通知联动 | Ghostty 桌面通知会回流为侧边栏和标签页状态 |
| 子进程环境 | shell 子进程会收到 `PANMUX_INSTANCE_ID`、`PANMUX_SOCKET_PATH`、`PANMUX_TAB_ID`、`PANMUX_SURFACE_ID` |

## panmux 相对 Ghostty 改了什么

`panmux` **不会** 替换 Ghostty 的渲染器、PTY 模型、终端引擎，也不会推翻它现有的 tab/split 核心。

当前改动刻意保持收敛：

- 重做 Ghostty Linux GTK 前端外层窗口壳
- 引入左侧边栏，作为主要 tab UI
- 复用 Ghostty 已有的 pwd 信号链路展示 cwd
- 增加每窗口 Unix socket 控制平面
- 向 shell 子进程注入 `PANMUX_*` 环境变量
- 把通知事件映射回 tab 和侧边栏状态

一句话总结：**Ghostty 继续负责终端本身，panmux 负责 agent 导向的窗口控制和状态 UX。**

## 当前已验证基线

在 Arch Linux + Hyprland + Wayland 上，当前已经验证通过的基线是：

- 纵向侧边栏可用
- 侧边栏可显示 cwd
- `Alt+1..9` 可以切换 tab
- `panmuxctl notify` 可用
- `panmuxctl set-status` 可用
- `panmuxctl clear-status` 可用
- `panmuxctl focus-tab` 可用
- `panmuxctl list-tabs` 可用

## Codex 集成：当前真实存在的部分

`panmux` **不会** 修改 Codex 源码。当前策略是外部集成，而且是务实的那种：

- `scripts/panmux_codex_notify.py` 用来桥接 Codex 风格的通知 payload
- 裸跑交互式 `codex` 时，现在会通过 shell preexec 检测自动把 tab 标成 `running`
- `scripts/panmux_codex_wrapper.sh` 仍然保留，作为较弱的进程级兜底方案
- 已观察到交互式 Codex 完成时会发出 `OSC 9;pong`
- Ghostty 本来就会把 `OSC 9` 变成桌面通知
- `panmux` 现在会沿着这条路径，把完成信号回写成 `info` 状态

这样可以拿到一个实用的“轮次完成”信号，而不是把普通 shell 退出假装成真正的 agent 完成事件。

## 渲染说明

`panmux` 对 ANSI 和 truecolor 输出的渲染本身是正确的。之前出现过一次“Codex 整体发白、输入框丢灰底”的问题，根因不是渲染，而是父环境里继承了 `NO_COLOR=1`。

本地启动器现在会在启动应用前移除 `NO_COLOR`，让 Codex 以正常彩色模式渲染。

## 本地安装

现阶段更推荐本地前缀安装，而不是发行版打包：

```bash
scripts/install_local_panmux.sh
```

这个脚本会：

- 构建 `ReleaseFast`
- 安装到 `~/.local/opt/panmux/<git-sha>`
- 把 `~/.local/opt/panmux/current` 指到当前版本
- 安装 `~/.local/bin/panmux`
- 安装 `~/.local/bin/panmuxctl`
- 安装 `~/.local/share/applications/panmux.desktop`
- 默认用 `--gtk-single-instance=false` 启动
- 启动前去掉 `NO_COLOR`

## 仓库导览

这个仓库现在就是 `panmux` 的单一事实来源。

- 运行时代码位于 Ghostty GTK 分叉内部
- [`docs/IMPLEMENTATION_BLUEPRINT.md`](./docs/IMPLEMENTATION_BLUEPRINT.md) 说明实现结构
- [`docs/PATCH_MAP.md`](./docs/PATCH_MAP.md) 跟踪 fork 差异
- [`docs/PHASE0_SPIKE_REPORT.md`](./docs/PHASE0_SPIKE_REPORT.md) 记录早期验证结果
- `scripts/` 存放本地安装和 Codex 集成辅助脚本

如果你仍然需要跟踪上游 Ghostty，建议远端布局如下：

- 你自己的 `panmux` GitHub 仓库作为 `origin`
- `ghostty-org/ghostty` 作为 `upstream`

## 范围边界

当前明确不做，或者暂时还没做的事情：

- 不追求完整复刻 `cmux`
- 不做 Electron 或 Tauri 包装层
- 不靠 prompt 解析来猜 cwd
- 不基于通用 shell 生命周期伪造“Codex complete”信号
- 还没有 `pi` 集成
- 现阶段不声称 libghostty 嵌入路线更优
