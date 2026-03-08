# panmux

`panmux` 是一个面向 Linux/Wayland 的、受 `cmux` 启发的 Ghostty GTK fork。

当前目标不是完整复刻 `cmux`，而是在 **Arch Linux + Hyprland + Wayland** 环境下，优先实现几项与 coding agent 工作流高度相关的能力：

- 左侧竖版 tab / workspace sidebar
- 每个 tab 显示当前目录（cwd）
- `Alt+数字` 快速切换 tab，并在 UI 上显示快捷键提示
- 接收 `Codex` 结束事件，并在 sidebar 中显示状态/提醒

详细实现蓝图见：`docs/IMPLEMENTATION_BLUEPRINT.md`。

## 仓库定位

这个仓库现在就是 `panmux` 的**单一主仓**：

- 运行时代码直接基于 Ghostty Linux GTK 前端 fork
- `panmux` 自身的文档、安装脚本、Codex 集成脚本也都已并入本仓
- 后续开源发布建议以本仓为准，不再拆成“文档仓 + 代码仓”双仓结构

如果后续要持续跟进上游 Ghostty，推荐保留：

- 你的 GitHub 仓库作为 `origin`
- `https://github.com/ghostty-org/ghostty` 作为 `upstream`

## 当前已验证状态（2026-03-09）

- 主线已确定继续走 `Ghostty GTK fork`，当前不转向 embed。
- 已完成的最小闭环：左侧 sidebar、cwd 展示、`Alt+1..9` 切 tab、`panmuxctl notify`、`panmuxctl set-status`、`panmuxctl clear-status`、`panmuxctl focus-tab`、`panmuxctl list-tabs`。
- app 内控制面已采用 `Unix domain socket + JSON-line`，并且 shell 子进程已注入 `PANMUX_INSTANCE_ID`、`PANMUX_SOCKET_PATH`、`PANMUX_TAB_ID`、`PANMUX_SURFACE_ID`。
- `panmuxctl` 在 shell 内可直接依赖 `PANMUX_*` 环境变量，无需显式 `--socket`。
- `Codex` 集成边界已明确：只消费外部 `notify` / hook / wrapper 事件，不修改 `Codex` 源码。
- 2026-03-09 验收中额外做了 `resize -> focus-tab -> 键盘输入` 探针；当前版本未复现窗口 resize 后终端失焦、无法继续输入的问题。该结论来自脚本化验收，不代表已经覆盖所有 Wayland/Hyprland 边角场景。

## Codex 集成现状（2026-03-09）

- 已新增 `scripts/panmux_codex_notify.py`：用于承接 Codex 原生 `notify` payload，并在收到 `agent-turn-complete` 时转发到 `panmuxctl notify`。
- 已新增 `scripts/panmux_codex_wrapper.sh`：这是当前**已完成真实验收**的弱语义 fallback，会在启动 Codex 前设置 `running`，在 Codex 进程退出后发 `done`/`error`。
- 当前本机实测：`codex exec` 通过 wrapper fallback 已经能把真实完成态打回 panmux。
- 当前本机实测：官方文档/issue 显示存在 `notify` 配置，但在本机 `codex-cli 0.111.0` 下，使用 `-c notify=[...]` 做的 probe 尚未触发回调，因此原生 `notify` 在这台机器上仍然属于**脚本已准备好、但未端到端验证**的候选路径。

## 颜色渲染注意事项（2026-03-09）

- 已验证：`panmux`/Ghostty fork 本身可以正确渲染 ANSI / truecolor，`Codex` 在其中也可以正常显示主题色与输入框灰底。
- 本机出现过一次“新开的测试窗口里 Codex 只有白字、没有灰底”的现象；最终已追到根因：**启动该窗口的父进程环境里带有 `NO_COLOR=1`**。
- 这不是 Ghostty 配置文件未加载，也不是 `panmux` sidebar 改动导致的渲染回归。
- 因此，后续所有 `panmux` 启动入口都应在进程边界显式去掉 `NO_COLOR`，至少不能把它原样继承进测试窗口。

## 本地安装（当前推荐方式）

当前先不做 pacman/AUR 打包；第一版采用**本地前缀安装**，用于你在这台机器上直接长期试用：

- 安装脚本：`scripts/install_local_panmux.sh`
- 默认源码目录：当前仓库根目录
- 默认安装位置：`~/.local/opt/panmux/current`
- 默认命令入口：`~/.local/bin/panmux`
- 控制面 CLI：`~/.local/bin/panmuxctl`
- 桌面入口：`~/.local/share/applications/panmux.desktop`

该安装方式会：

- 使用 `ReleaseFast` 构建当前 fork
- 安装完整 Ghostty 资源到本地前缀
- 生成名为 `panmux` 的启动包装器
- 在启动时自动 `unset NO_COLOR`
- 默认使用 `--gtk-single-instance=false`，避免与系统 Ghostty 混成同一实例
