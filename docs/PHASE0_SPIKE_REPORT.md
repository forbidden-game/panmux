# Phase 0 Spike Report

## 路线结论

- 结论：继续走 `Ghostty GTK fork`，不转 `embedded/libghostty` 主线。
- 原因不是“GTK 一定更优”，而是当前已验证事实显示：Linux 上做 sidebar 的最短路径在 GTK 窗口装配层；而 `libghostty` 当前公开 surface 平台仍是 Apple 导向，不能把它当成 Linux 上现成成熟宿主。

## 已验证事实

### 仓库与本机状态

- 当前 `panmux` 仓库还是文档仓，只有 `README.md` 和 `docs/IMPLEMENTATION_BLUEPRINT.md`。
- 本机可用：`ghostty 1.2.3-arch3`、`codex-cli 0.111.0`、`zig 0.15.2`、`GTK 4.20.3`、`libadwaita 1.8.4`。
- 本机已补齐 `blueprint-compiler 0.18.0`，满足 Ghostty `HACKING.md` 要求的 `0.16.0+`。
- `codex exec --help` 已明确支持 `--json`、`--output-last-message`、`--output-schema`。

### Spike 1：Ghostty GTK 自定义 widget 可行性

- 在本机现有 Ghostty 源码镜像里，最小 sidebar 插入点已明确存在于 `src/apprt/gtk/ui/1.5/window.blp`。
- 当前窗口结构是在同一个 `Gtk.Box` 里放置：左侧 `Gtk.ListView sidebar`、中间 `Gtk.Separator`、右侧 `Adw.ToastOverlay`/`Adw.TabView`。这说明 sidebar 是窗口装配层 sibling，不是去改 terminal core。
- sidebar 的点击切换链路已明确：`src/apprt/gtk/class/window.zig` 中的 `sidebarActivate` 通过 `tab_view.getNthPage(...)` 与 `tab_view.setSelectedPage(...)` 切 tab。
- sidebar 行数据绑定链路已明确：row model 绑定 `tab_view.pages`，cwd 文本通过 `Adw.TabPage -> GhosttyTab.active-surface -> GhosttySurface.pwd` 取值。
- 本机已有一份局部原型提交 `34517451b0e9392d993f3e775cb272fcba3a1481`，证明源代码层面已经能把 sidebar、点击回调、cwd 展示、attention 样式接到 GTK window/tab 结构里。
- 之前阻塞构建的根因已经确认：不是 Ghostty 原型坏了，而是本机缺 `blueprint-compiler`。补装后，`/tmp/panmux-ghostty-proto` 上的 `zig build -Doptimize=Debug` 已通过。
- 我已在当前 Hyprland/Wayland 会话里直接启动 patched `ghostty`，并通过 `hyprctl clients -j` 观察到新窗口 `class = com.mitchellh.ghostty-debug` 成功映射；这说明当前 sidebar 原型至少已经通过“本机构建 + 本机拉起窗口”这一级验证。
- 仍未验证：本轮还没有做人工点击和截图验收，所以“窗口已拉起”是事实；“sidebar 视觉细节与交互细节都已验收”仍未完成。

### Spike 2：Ghostty embedded / libghostty 可行性

- `zig build -Dapp-runtime=none -Demit-exe=false -Doptimize=Debug` 可在本机成功产出 `libghostty.so`、`libghostty.a`、`ghostty.h`。这证明库可构建。
- `include/ghostty.h` 当前公开的 surface platform 只包含 `macOS`/`iOS` 视图句柄；没有 GTK/X11/Wayland/Linux host surface 平台声明。
- `src/apprt/embedded.zig` 当前 `PlatformTag` 只有 `macos = 1`、`ios = 2`。这不是推断，是源码事实。
- 我用一个最小 C probe 成功走到 `ghostty_init -> ghostty_config_new/finalize -> ghostty_app_new`，但在 Linux 上 `ghostty_surface_new` 失败。结合头文件与 `embedded.zig`，失败的根因是：当前公开 embedded surface 平台并不包含 Linux GTK/Wayland 宿主入口。
- upstream README 仍把 `Cross-platform libghostty for Embeddable Terminals` 标为进行中；`libghostty-vt` 更成熟，但那不是完整 terminal host。
- 结论不是“embed 不存在”，而是“当前 Linux 第一阶段不比 GTK fork 更省事”。

### Spike 3：Codex 集成能力探针

- 本机 help 已验证：`codex exec` 支持 `--json` 和 `--output-last-message`。
- 官方 `openai/codex` 仓库文档已明确声明 `notify` 与 `notify_mode` 配置项，并把它定义为每次 completed turn 后执行的外部命令；hooks 文档也明确有 `after_agent` 事件。
- 本机安装的 `codex 0.111.0` 原生二进制字符串中存在：`thread/started notification`、`turn/started notification`、`turn/completed notification`、`maybe_notify` 等符号。
- 我已在本机实测：`codex exec -c 'notify=[...]' -c 'notify_mode="always"'` 会调用外部脚本，并传入 JSON payload。
- 当前 0.111.0 本机实测得到的 payload 形状为：
  - `type: "agent-turn-complete"`
  - `thread-id`
  - `turn-id`
  - `cwd`
  - `input-messages`
  - `last-assistant-message`
- 因此，现在不能再把“Codex 原生 hook/notify 不存在”写成假设；在本机上，这条路已经被文档 + 二进制 + 实测三重验证。

## 未验证项

- 未验证：GTK sidebar 原型在真实窗口中的人工点击/视觉验收。
- 未验证：交互式 TUI 模式下每轮 notify 与 `codex exec` 是否存在额外 payload 差异；当前只实测了 `exec`。
- 未验证：Ghostty 官方 upstream 当前最新 commit 是否已与本机本地镜像完全一致。

## 方案判断

### 为什么继续走 GTK fork

- sidebar 的最短切入点已经明确落在 `window.blp + window.zig`，不是深挖 core。
- cwd 展示链路已经能直接复用 `GhosttySurface.pwd`，符合“不解析 prompt 推断 cwd”的纪律。
- `Adw.TabView`/`Adw.TabPage`/`GhosttyTab.active-surface` 这些现成结构，足以支撑第一阶段 sidebar + cwd + `Alt+数字`。
- `Alt+数字` 这一条不需要新造底层 tab 切换机制：Ghostty 现有 `goto_tab` action 与 GTK runtime 已经能处理；本轮只是把 Linux 默认从 `Alt+1..8 + Alt+9=last_tab` 修正为 `Alt+1..9=tab 1..9`，并让 sidebar hint 从真实 trigger 反查生成。
- `embedded/libghostty` 在 Linux 上目前缺少对等成熟宿主 surface 平台，第一阶段会把精力耗在宿主补洞而不是 panmux 需求本身。

### 为什么现在不转 embed

- 现成公开 surface 平台不包含 Linux host，这个阻塞比“加 sidebar widget”更硬。
- `libghostty-vt` 是另一个可能的未来方向，但那会把 panmux 第一阶段从“改现有宿主 UI”转成“自建 terminal host”，不符合当前最小路径。

## Ghostty GTK fork 的第一批准确切入点

### 最小 sidebar 原型

- `src/apprt/gtk/ui/1.5/window.blp`
  - 在 window 主布局里定义 sidebar widget
  - 绑定 row factory、row model、row activate
- `src/apprt/gtk/class/window.zig`
  - `bindTemplateChildPrivate("sidebar", ...)`
  - `bindTemplateCallback("sidebar_activate", ...)`
  - 增加 row 绑定 helper，例如 cwd/shortcut 的 closure

### 第一批扩展文件

- `src/apprt/gtk/css/style.css`
  - sidebar 样式、selected/attention 状态
- `src/apprt/gtk/class/tab.zig`
  - tab 层 attention / active-surface 相关联动
- `src/apprt/gtk/class/surface.zig`
  - cwd、command finished、后续 `PANMUX_*` 环境变量注入的主要落点
- `src/apprt/gtk/class/application.zig`
  - GTK action 分发、pwd/command_finished 上行接入、未来控制面桥接点

## 最小实现顺序

1. `window.blp`：左侧 sidebar 先出现，并能列出 tabs。
2. `window.zig`：sidebar 点击切 tab，保证 terminal area 不被替换。
3. `style.css`：只补最小可读样式，不先做复杂状态色。
4. `surface.zig` + `tab.zig`：把 `pwd` 汇总到 sidebar 第二行。
5. `window.zig`：加入 `Alt+1..9` 绑定与 UI hint。
6. `application.zig` + 新控制面模块：再接 `panmuxctl notify`。

## Codex 集成结论

- 原生 hook / notify：存在，且现在已经被官方仓库文档与本机实测共同证实。
- 第一版推荐优先接 `notify`，不要先走 wrapper 降级。
- 当前本机已确认可用的最小策略是：
  - `notify = ["/path/to/panmux-codex-hook"]`
  - `notify_mode = "always"`
- fallback 1：`codex exec --json`
  - 语义弱化点：只能覆盖非交互执行，不是长期交互 TUI 的每轮回调。
- fallback 2：`codex exec --output-last-message`
  - 语义弱化点：只能拿到最终消息文本，失去更细事件语义。
- fallback 3：wrapper 包一层 `codex`
  - 语义弱化点：若包的是交互 `codex`，只能得到进程结束，不等于 turn complete。

## 本轮建议

- 进入实现阶段时，先从 `Ghostty GTK fork` 做最小 sidebar 原型。
- 不要先做完整 IPC；先把 sidebar/click/title 跑通。
- cwd 继续明确走 `pwd` 信号链，不走 shell prompt 解析。
- Codex 第一版直接走 `notify`，并把当前 payload 映射到 `panmuxctl notify`。

## 本轮验证命令

- `pacman -Sy --needed --noconfirm blueprint-compiler`
- `blueprint-compiler --version`
- `codex --version`
- `codex --help`
- `codex exec --help`
- `zig build -Doptimize=Debug`（`/tmp/panmux-ghostty-proto`，已通过）
- `zig build -Dapp-runtime=none -Demit-exe=false -Doptimize=Debug`
- `codex exec --skip-git-repo-check -c 'notify=[...]' -c 'notify_mode="always"' 'Reply with exactly OK.'`
