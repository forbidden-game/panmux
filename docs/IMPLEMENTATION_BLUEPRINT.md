# panmux 实现蓝图（Linux / Ghostty / Codex 优先）

## 1. 项目目标

本项目要在当前机器环境下实现一个类似 `cmux` 的终端应用，但**不是完整复刻**，而是只做对 coding agent 工作流最关键的几个能力。

当前优先级：

1. 左侧竖版 tab（sidebar）
2. 显示每个 tab 当前目录（cwd）
3. `Alt+数字` 切 tab，并显示快捷键提示
4. 接入 `Codex` 完成事件，在 UI 上变更状态并提醒

暂时**不处理 `pi` 集成**。

---

## 2. 当前环境与关键结论

### 2.1 用户环境（已确认）

- OS: `Arch Linux`
- Session: `Wayland`
- WM/DE: `Hyprland`

### 2.2 已核对的上游项目

- `cmux`: <https://github.com/manaflow-ai/cmux>
- `ghostty`: <https://github.com/ghostty-org/ghostty>

### 2.3 当前主线（已完成第一轮 spike）

**当前主线已经确定继续走 `Ghostty` 的 Linux GTK 前端 fork。**

当前结论不是拍脑袋，而是基于第一轮 spike 和真实运行态验收：

- 最小 sidebar widget 已经在 GTK 窗口内工作
- cwd 展示和 `Alt+1..9` 切 tab 已经接上现有 GTK tab/runtime
- app 内控制面已经以 `Unix domain socket + JSON-line` 跑通
- shell 子进程已拿到 `PANMUX_*` 环境变量，可直接回调当前实例
- 现阶段没有证据表明 `libghostty` embed 比继续 fork GTK 更省事

因此：

- 当前**正式主线**是继续做 Ghostty GTK fork
- embed 仍保留为备选路线，但不是当前实施方向

### 2.5 当前已验证实现状态（2026-03-09）

已在当前机器上跑通并验收：

- 左侧 sidebar 已替代顶部 tab bar 成为主导航表达
- sidebar 第二行显示当前 cwd，来源是 Ghostty 现有 pwd 信号链路
- `Alt+1..9` 已切到真实第 1..9 个 tab，sidebar 同步显示快捷键提示
- `panmuxctl notify`、`panmuxctl set-status`、`panmuxctl clear-status`、`panmuxctl focus-tab`、`panmuxctl list-tabs` 已经可用
- shell 环境已注入：`PANMUX_INSTANCE_ID`、`PANMUX_SOCKET_PATH`、`PANMUX_TAB_ID`、`PANMUX_SURFACE_ID`
- `notify` / `set-status` / `clear-status` 都能命中当前 tab，并在 sidebar 中更新状态 pill
- `list-tabs` 能返回当前窗口 tab 快照，包含 index/title/cwd/state/tab_id/surface_id/selected/needs_attention/loading
- 已新增 `scripts/panmux_codex_notify.py` 与 `scripts/panmux_codex_wrapper.sh` 两条 Codex 接入路径
- 其中 wrapper fallback 已用真实 `codex exec` 验收通过；原生 `notify` bridge 已用模拟 `agent-turn-complete` payload 验收通过
- 额外做了 `resize -> focus-tab -> 键盘输入` 验收，当前版本未复现 resize 后终端无法重新拿回输入焦点的问题

这些都属于**已验证事实**，不是仅来自蓝图推断。

### 2.6 颜色渲染补充结论（2026-03-09）

已额外完成一轮针对 `Codex` 颜色缺失的溯源，结论如下：

- `ghostty-panmux` 本身能正确渲染 ANSI / 24-bit 颜色；不是终端渲染器整体失效。
- 本地 Ghostty 配置文件也确实已加载；透明度与主题能对齐不是巧合。
- 真正导致“新开的测试窗里 Codex 只有白字、没有输入框灰底”的根因，是该测试窗的父进程环境带入了 `NO_COLOR=1`。
- 因此，这个问题不是 Ghostty GTK fork 的主题加载 bug，而是**启动链路的环境污染问题**。
- 后续所有 `panmux` 启动包装器，都应该在进程边界移除 `NO_COLOR`；不要把当前 agent 会话的 `NO_COLOR=1` 继续传给 `Codex` TUI。

### 2.4 为什么当前仍默认偏向 Ghostty GTK fork

基于已核对的信息，默认偏向 GTK fork 的原因是：

- Ghostty 已经有完整 Linux app runtime，而不是只有 terminal core
- 当前 tab / split / surface 生命周期、键盘路由、窗口集成已经存在
- `pwd` 和 `command_finished` 都已经打通到 GTK runtime
- 第一阶段要做的主要是 UI 表达层 + 控制面，而不是重新发明终端宿主

但这只是**当前默认**，不是不经 spike 的最终定案。

---

## 3. 上游事实依据

下面这些是已经核对过、可作为实现依据的事实。

### 3.1 `cmux` 已经验证了这套产品方向

`cmux` 不是单纯“换成竖版 tab”，而是已经抽象出了：

- sidebar 工作区行
- 状态 pill
- 进度条
- log entry
- 通知入口
- shell 子进程环境变量注入（`CMUX_*`）

相关参考：

- `Sources/ContentView.swift`
- `Sources/Workspace.swift`
- `Sources/GhosttyTerminalView.swift`
- `docs/notifications.md`

### 3.2 `Ghostty` core 已支持 cwd / pwd 更新

`Ghostty` core 会发出 `pwd_change`，GTK/macOS runtime 都能接住。

关键参考：

- `ghostty/src/Surface.zig`：`pwd_change`
- `ghostty/include/ghostty.h`：`ghostty_action_pwd_s`
- `ghostty/src/apprt/gtk/class/application.zig`：GTK 接收 `pwd`
- `ghostty/src/apprt/gtk/class/surface.zig`：GTK surface 保存 `pwd`

### 3.3 `Ghostty` GTK 端已有命令完成事件

GTK surface 已经处理 `command_finished`，目前主要用于 bell / desktop notification。

关键参考：

- `ghostty/src/apprt/gtk/class/surface.zig`
- `ghostty/src/apprt/gtk/class/application.zig`

这说明：

- 可以复用已有“命令完成”信号链路做泛终端提醒
- 但**不能**把一般 shell command finished 误当作 `Codex` 完成
- `Codex` 完成应该走单独的 app-level IPC / hook / wrapper 集成

### 3.4 `Ghostty` GTK 已有 tab 体系

GTK 前端现在使用：

- `adw.TabView`
- `adw.TabBar`
- `adw.TabOverview`

这意味着 panmux 不需要重建终端 session/tabs 底层，只需要替换或包裹现有 tab UI 表达层。

### 3.5 `Ghostty` embedded / libghostty 确实存在，但稳定性仍要谨慎

已核对到：

- `ghostty/src/apprt/embedded.zig` 确实提供了 surface 初始化 API
- `Ghostty` README 明确写了 `libghostty` 方向存在
- 但 README 同时表明这条线仍在推进中，`Cross-platform libghostty for Embeddable Terminals` 仍然是 `⚠️`
- README 对 `libghostty-vt` 还明确写了 **API 尚未稳定**

因此：

- embed 不是空想路线，值得 spike
- 但也不能被当成“显然更优的成熟路线”

### 3.6 `Codex` 集成点的当前事实边界

本机与官方资料当前已核对到：

- `codex-cli 0.111.0`
- `codex exec` 已明确支持 `--json`
- `codex exec` 已明确支持 `--output-last-message`
- 官方 GitHub repo 已能证实存在 `notify` 配置项，且通知程序会收到 JSON payload；事件类型至少包含 `agent-turn-complete`

同时仍然要明确：

- 这不等于官方已经承诺了一个更宽泛、长期稳定的通用 hook / event API
- 也不能据此把所有交互式 post-turn 集成能力都写成“已稳定”

因此：

- `Codex` 原生 `notify` 已经是一个可用候选点
- 更广义的 hook / 事件流能力仍然需要继续按事实核对，不能补脑

---

## 4. 产品范围定义

## 4.1 第一阶段必须做的功能

### A. 左侧竖版 tab/sidebar

目标：

- 用左侧 sidebar 替代顶部横向 tab bar 的主交互地位
- 每一行对应一个 workspace/tab
- 支持选中态、高亮态、完成提醒态

### B. 显示当前目录

目标：

- 每个 sidebar row 显示该 tab 当前聚焦 surface 的 cwd
- 如果一个 tab 内有多个 split 且 cwd 不同，则显示紧凑摘要
- 优先展示“当前正在操作的目录”，而不是最近执行的命令

### C. `Alt+数字` 切换 tab

目标：

- `Alt+1..9` 切换到第 1..9 个 tab
- sidebar row 右侧显示 `Alt+1` 这类提示
- 如果与 Hyprland 绑定冲突，可配置 fallback

### D. `Codex` 完成态接入

目标：

- `Codex` 一个 session/turn 结束后，能把当前 tab 标为完成或提醒态
- 如果 tab 不在当前焦点中，应产生明显但克制的未读/提醒标记
- 支持来自 CLI/hook/wrapper 的标题、正文、状态字段

## 4.2 暂不做

- `pi` 集成
- 完整复刻 `cmux` 的 browser / log / metadata 全家桶
- 复杂 session restore / workspace persistence
- macOS 专属视觉与交互
- 通用 agent browser 集成

---

## 5. 技术路线比较与当前决策

### 5.1 方案 A：直接 fork `Ghostty` GTK 前端

优点：

- 复用现成 Linux app runtime
- 复用现成 tab/split/window 生命周期
- `pwd` / `command_finished` 已接到 GTK 层
- 最接近“改造现有宿主”而不是“新造宿主”

风险：

- Zig + GTK4/libadwaita 改造成本可能比预期高
- 上游 GTK window/tab 重构会带来 merge/rebase 成本
- 第一版 sidebar 改造可能比文档最初表述得更硬

### 5.2 方案 B：当前 repo 做 meta repo，拉 Ghostty 进来开发

优点：

- 仓库组织更清晰
- panmux 文档、脚本、patch map 可与上游代码分离

缺点：

- 早期开发会增加路径和协作摩擦
- 真正的大量改动仍然会落在 Ghostty 代码里

### 5.3 方案 C：独立 GTK4 app + `libghostty` / embedded API

优点：

- UI 壳完全自主控制
- 长期可能比 fork 更干净
- 若 embed 成熟，upstream 同步负担可能更低

风险：

- 当前是否“成熟到足以作为主路线”尚未证实
- Ghostty README 已显示这条路线仍在演进中
- Phase 0 若验证不顺，会直接拖慢主线

### 5.4 当前决策规则

当前不把 A/C 写死，而采用下面的决策规则：

- **默认起点：A（Ghostty GTK fork）**
- **必须执行的 spike：**
  1. Zig-GTK 自定义 widget spike
  2. `libghostty` embed 可行性 spike
- 如果 A 的 spike 明显可行，而 C 无明显优势，则继续 A
- 如果 A 的 sidebar 改造阻力异常大，而 C 能快速拉起最小 terminal host，则转向 C

### 5.5 当前建议

在没有 spike 结果前，仍然建议新 session 先按 **A 作为默认主线** 推进，但必须把 **C 当作正式备选路线** 写进执行计划，而不是只在脑子里留个可能性。

---

## 6. 维护策略（必须提前定）

### 6.1 Upstream sync 策略

fork Ghostty 之后，必须明确维护纪律：

- **pin 一个明确 upstream commit/tag** 作为开发基线
- 尽量把 panmux 改动集中在少数文件或少数模块边界
- 在必要处使用统一注释前缀，例如：`// panmux:`
- 所有非显而易见的宿主层改动，都要补到文档里
- 建议维护一个 `docs/PATCH_MAP.md`（后续再建），记录：
  - 改了哪些上游文件
  - 为什么改
  - 将来 upstream 若改动，哪里最容易冲突

### 6.2 Rebase 节奏

建议：

- 早期功能开发期：**先 pin，不频繁追新**
- 一旦 sidebar / cwd / IPC 主链稳定，再按固定节奏同步 upstream
- 建议同步节奏：**每月一次** 或在需要安全/兼容修复时提前同步

### 6.3 改动边界原则

优先修改：

- window / tab UI 组装层
- app-level 状态层
- 控制面/IPC 接入层

尽量避免：

- 深挖 terminal core
- 重写 split/tree 基础设施
- 在多个无关层同时打洞

---

## 7. panmux 逻辑分层

### Layer 1: Ghostty 现有能力

- pty / terminal emulation
- split / tab lifecycle
- pwd tracking
- command finished
- keyboard event routing

### Layer 2: panmux app state

新增一个 app-level 状态层，维护每个 tab 的 panmux 元数据：

```text
TabMeta
  id
  title
  focused_cwd
  cwd_summary
  agent_state        // idle | running | waiting | done | error
  unread_flag
  last_notification
  shortcut_hint      // Alt+1 ...
  instance_id
```

### Layer 3: panmux control plane

新增一个本地 IPC + CLI。当前状态分两层：

**已实现：**

- `panmuxctl notify`
- `panmuxctl set-status`
- `panmuxctl clear-status`
- `panmuxctl focus-tab`
- `panmuxctl list-tabs`

这是 `Codex` hook/wrapper 的接入点。

---

## 8. IPC 与多实例设计（从一开始就定清楚）

### 8.1 协议选型

第一版建议：**Unix domain socket + JSON Lines**。

原因：

- Linux/Wayland 下天然适合本地进程通信
- shell 友好
- 调试方便
- 复杂度远低于 gRPC/HTTP server

### 8.2 请求格式

当前最小协议已经是 JSON 行协议，例如：

```json
{"method":"notify","params":{"title":"Codex","body":"Turn complete","state":"done","tab_id":"1a7ec400","surface_id":"1a7f3160"}}
```

其中 `method` 当前已实现：

- `notify`
- `set-status`
- `clear-status`
- `focus-tab`
- `list-tabs`

CLI 负责把 flags 和 `PANMUX_*` 环境变量转成 JSON 请求。

### 8.3 socket 路径

建议：

- 路径根：`$XDG_RUNTIME_DIR/panmux/`
- 每个 app 实例一个 socket：`$XDG_RUNTIME_DIR/panmux/<instance-id>.sock`

`instance-id` 可以是：

- UUID
- 或 `pid + random suffix`

### 8.4 多实例隔离

多实例必须从设计上隔离，不靠“current app”猜测。

所以每个 terminal surface 创建时注入：

- `PANMUX_INSTANCE_ID`
- `PANMUX_SOCKET_PATH`
- `PANMUX_TAB_ID`
- `PANMUX_SURFACE_ID`

这样：

- 当前 shell 里直接执行 `panmuxctl notify` / `set-status` / `clear-status` 就能命中所属实例
- 不同 panmux 窗口不会互串
- 绝大多数脚本无需全局发现“哪个 panmux 是当前 app”

### 8.5 CLI 解析规则

当前实现的解析优先级：

1. 显式 `--socket`
2. 显式 `--tab` / `--tab-id` / `--surface-id`
3. 环境变量 `PANMUX_SOCKET_PATH` / `PANMUX_TAB_ID` / `PANMUX_SURFACE_ID`
4. 若没有目标坐标，则回落到当前活动窗口的当前 tab
5. 若连 socket 都没有，则直接报错，不做危险猜测

---

## 9. `Codex` 集成设计

### 9.1 为什么不能只靠 `command_finished`

因为：

- 普通 shell 命令也会完成
- `Codex` 一次 turn 完成不等于子 shell 退出
- 未来还会有多种 agent，不应把 terminal lifecycle 和 agent lifecycle 混为一谈

所以：

- `command_finished` 只用于泛终端层面的辅助提示
- `Codex` 完成态必须通过 **hook / wrapper / 事件流 -> `panmuxctl`** 明确上报

### 9.2 当前对 `Codex` 的已知事实与未知点

已知（本机核对 + 官方 GitHub repo 资料）：

- `codex-cli 0.111.0`
- `codex exec` 有 `--json`
- `codex exec` 有 `--output-last-message`
- 官方仓库文档/issue 已明确存在 `notify` 配置项；`Codex` 会向外部程序传一段 JSON，事件类型至少包含 `agent-turn-complete`

仍然不能写死为稳定前提的点：

- 除 `notify` 之外，是否还有更通用、稳定、长期承诺的交互式 post-turn hook API
- `notify` payload 是否会继续扩展或调整字段
- 是否存在正式支持的实时事件流，而不是仅面向通知程序的一次性回调

因此：

- 现在可以把“Codex 原生 `notify`”视为**已验证可用的候选集成点**
- 但仍然不应把更宽泛的“稳定 hook/event API”写成既定事实

### 9.3 最小可行接口

当前已经可用的最小 CLI：

```bash
panmuxctl notify \
  --title "Codex" \
  --body "Turn complete" \
  --state done

panmuxctl set-status \
  --state running \
  --title "Codex" \
  --body "Applying patch"

panmuxctl clear-status

panmuxctl focus-tab --tab 2
panmuxctl list-tabs
```

如果命令运行在 panmux/ghostty 子 shell 中，上面五条都可以直接依赖 `PANMUX_*` 环境变量命中当前实例。

### 9.4 `Codex` 集成的三层 fallback

按优先级从高到低：

1. **原生 `notify` 模式**
   - 当前官方 repo 已能证实 `notify` 配置存在
   - 本仓已提供 `scripts/panmux_codex_notify.py` 作为 bridge
   - 但在本机 `codex-cli 0.111.0` 的实际 probe 中，`-c notify=[...]` 还没有成功触发回调，所以这条线目前仍是候选路径，不算本机端到端验收通过

2. **非交互 `exec` / wrapper 模式**
   - 利用 `codex exec --json` / `--output-last-message`
   - 更适合脚本化或批处理任务

3. **wrapper / 进程级模式**
   - 如果没有 turn-level hook，只能先实现“Codex 进程结束”通知
   - 这个语义弱于 turn complete，不能伪装成完全等价能力

### 9.5 结论

产品目标仍然是 **Codex turn complete** 级别提醒。

但工程上必须承认：

- 当前已确认的原生点是 `notify`，不是一个通用事件总线
- 若某些工作流里拿不到 `notify`，第一版仍然需要 wrapper / `codex exec` fallback
- 当前仓库已提供 `scripts/panmux_codex_wrapper.sh`，并且已经用真实 `codex exec` 验收通过
- panmux 侧控制面已经独立成立，不需要修改 Codex 源码


### 9.6 当前推荐接入顺序（2026-03-09）

当前推荐不要直接把产品成败押在原生 `notify` 上，而是分两层使用：

1. **先用 `scripts/panmux_codex_wrapper.sh` 作为已验证 fallback**
   - 这条路径当前已经用真实 `codex exec` 验收通过
   - 语义弱点很明确：它只能表达 Codex 进程退出，不等于每个 turn 完成

2. **并行保留 `scripts/panmux_codex_notify.py`**
   - 当本机 `notify` 真正稳定触发时，直接把 turn-complete 事件桥接进 panmux
   - 这条路径更接近目标产品语义

3. **不修改 Codex 源码**
   - 所有接入都通过外部配置、bridge script 或 wrapper 完成

---

## 10. UI 设计蓝图

### 10.1 主布局

从：

- 顶部 tab bar

变为：

- 左侧固定宽度 sidebar
- 右侧 terminal content

推荐结构：

```text
+--------------------+--------------------------------+
| Sidebar            | Terminal Area                  |
|                    |                                |
| [Tab 1]            |    current terminal/splits     |
|   ~/proj/api       |                                |
|   Alt+1            |                                |
|                    |                                |
| [Tab 2]   ●done    |                                |
|   ~/proj/web       |                                |
|   Alt+2            |                                |
+--------------------+--------------------------------+
```

### 10.2 Sidebar row 信息层级

每个 row 至少显示：

1. tab title
2. cwd
3. shortcut hint（`Alt+数字`）
4. 状态标记（done / unread）

建议优先级：

- 第一行：title + 状态点 + shortcut
- 第二行：cwd

### 10.3 cwd 展示策略

#### 单 pane

显示当前聚焦 pane 的 cwd，例如：

- `~/Work/tries/panmux`

#### 多 split

如果 split 的 cwd 不同：

- `~/proj/api | ~/proj/web`

若空间太小则缩写：

- `~/p/api | ~/p/web`

### 10.4 Codex 状态表现

### 10.5 焦点与 resize 风险

这是实现过程中必须持续关注的风险点，因为此前同类尝试里出现过“窗口 resize 后终端不再稳定拿到输入焦点”的问题。

当前已验证到的事实：

- 在 2026-03-09 的脚本化验收里，实际执行了 `resize -> panmuxctl focus-tab -> 键盘输入` 探针
- 两个 tab 都成功接收到真实键盘输入，并分别在各自 shell 中落盘验证
- 当前版本**未复现** resize 后无法恢复焦点的问题

仍然要保持谨慎：

- 这次验收覆盖的是当前 Arch Linux + Wayland + Hyprland 环境
- 这不是对所有窗口管理器、所有缩放配置、所有多显示器场景的穷尽证明
- 后续每轮涉及 tab 切换、surface focus、window resize 的改动，都应该重复做这组回归检查


建议最小状态集：

- `running`：中性色、无打扰
- `waiting`：轻提示
- `done`：明显但克制的高亮/圆点
- `error`：红色或警告色

非当前 tab 收到 `done` 时：

- row 出现未读圆点
- 可选 toast / desktop notification

当前 tab 收到 `done` 时：

- 不强打扰，只做轻状态变化

### 10.5 Sidebar 折叠/隐藏

这项不必放在第一阶段主功能里，但设计时必须预留：

- 支持临时隐藏 sidebar
- 全屏 coding 时可回到极简 terminal 视图
- 隐藏时仍应保留快捷键切 tab
- 再次展开后，状态与未读标记不能丢失

---

## 11. 键盘交互设计

### 11.1 主目标

- `Alt+1..9`：切换 tab

### 11.2 兼容性问题

Hyprland 可能抢占 `Alt+数字`。

所以实现要求：

1. 默认支持 `Alt+1..9`
2. 支持用户配置 fallback，例如：
   - `Super+1..9`
   - `Ctrl+Alt+1..9`
3. UI 上的 shortcut hint 必须和真实绑定保持一致

### 11.3 首版建议

首版先硬编码：

- 主绑定：`Alt+1..9`
- 如果验证冲突严重，再把它抽配置

---

## 12. 代码改造建议（按 Ghostty GTK fork）

下面是建议优先看的代码区域，不要求文件名未来 100% 不变，但新 session 应从这些入口入手。

### 12.1 GTK window / tab 结构

重点看：

- `ghostty/src/apprt/gtk/class/window.zig`

原因：

- 当前 tab UI 在这里组装
- 有 `adw.TabBar` / `adw.TabView` / `adw.TabOverview`
- 适合切入 sidebar 替代方案

### 12.2 GTK surface 状态

重点看：

- `ghostty/src/apprt/gtk/class/surface.zig`

原因：

- 已有 `pwd` 属性
- 已有 `commandFinished`
- 每个 terminal surface 的局部状态在这里

### 12.3 GTK application action 分发

重点看：

- `ghostty/src/apprt/gtk/class/application.zig`

原因：

- `pwd` / `command_finished` 都在这里往 GTK 层派发
- 未来 panmux 的 control action 也可以借这里接入

### 12.4 子进程环境变量注入

重点看：

- `ghostty/src/apprt/gtk/class/surface.zig`
- `ghostty/src/apprt/gtk/winproto/*.zig`
- `ghostty/src/apprt/embedded.zig`

目标：

- 在创建 surface 时注入 `PANMUX_*` 环境变量

---

## 13. 实施阶段拆分

### Phase 0：技术验证与载体决策

目标：在真正投入功能开发前，消除最大的路线风险。

任务：

- fork `ghostty`
- pin 一个明确 upstream commit/tag
- 跑通本机构建
- 做 **Zig-GTK spike**：在 Ghostty GTK window 中插入一个最小自定义 widget，并验证事件响应
- 做 **embed spike**：验证 `libghostty` / embedded API 是否能在独立 GTK 宿主中跑最小 terminal
- 做 **Codex 集成能力 spike**：确认当前使用方式下，能否拿到稳定的 turn-complete 触发点
- 根据结果在 A（fork）和 C（embed）之间做最终技术路线确认

验收：

- 能回答“继续 fork 还是转 embed”
- 能回答“Codex 是用原生 hook、exec 模式，还是只能做弱 fallback”

### Phase 1：Sidebar 骨架

目标：左侧出现可用的竖版 tab/sidebar。

任务：

- 隐藏或弱化顶部 tab bar
- 加入左侧 sidebar
- sidebar row 能列出当前 tabs
- 点击 row 可切换 tab

验收：

- 可以完全靠 sidebar 切 tab

### Phase 2：cwd 展示

目标：每个 tab row 显示当前目录。

任务：

- 把 surface pwd 汇总到 tab 级状态
- 当前聚焦 pane 的 cwd 实时刷新
- 多 split 时输出 cwd summary

验收：

- `cd` 后 sidebar 行能自动更新

### Phase 3：`Alt+数字`

目标：高效键盘切换 tab。

任务：

- 绑定 `Alt+1..9`
- row 右侧显示快捷键提示
- 校验 Hyprland 冲突场景

验收：

- 键盘与 UI 提示一致

### Phase 4：`panmuxctl` 控制面

目标：建立 agent 集成接口。

任务：

- 建本地 UDS server
- 建 JSON-line 协议
- 建 `panmuxctl` CLI
- 支持 `notify` 最小命令
- 打通多实例环境变量注入

验收：

- 终端内执行 `panmuxctl notify ...` 能更新当前 tab 状态
- 两个 panmux 实例不会互串

### Phase 5：`Codex` 集成

目标：Codex 完成态真实打通。

前提：必须以前面 spike 结论为准，不可凭空假设 hook 存在。

任务：

- 若有稳定 hook：编写 `Codex` hook 脚本/配置
- 若无稳定 hook：先实现明确定义语义的 fallback
- 从 payload/输出中提取简要文本
- 转发到 `panmuxctl notify`
- 非当前 tab 显示未读/完成提醒

验收：

- 一个后台 tab 中的 Codex 完成事件能在 sidebar 中体现
- 若是 fallback 实现，文档必须明确语义边界

---

## 14. 新 session 的具体执行建议

把下面这组任务直接交给新 CodeX session：

### 第一步：先不要直接写功能，先做 3 个 spike

1. 在 Ghostty GTK window 里插入一个最小 sidebar widget
2. 验证 embedded API 能否跑一个最小独立 terminal host
3. 验证当前 Codex 使用方式下是否真有稳定 turn-complete 集成点

### 第二步：根据 spike 结果锁技术路线

- 如果 GTK fork 改造顺手、embed 无明显优势：继续 fork
- 如果 GTK sidebar 改造异常困难、embed 能快速起一个可控宿主：评估转 embed

### 第三步：做最小 sidebar 原型

只做这些：

- 左侧可见 tab 列表
- 点击切换 tab
- 每行显示标题

先不要把 `Codex`、cwd、快捷键一起塞进第一版。

### 第四步：打通 cwd

确认：

- `cd` 后 surface 的 pwd 会刷新
- 选中 tab row 能显示最新 cwd

### 第五步：做 `Alt+数字`

在 UI 上同步展示真实快捷键。

### 第六步：做 `panmuxctl notify`

只实现最小通知命令，不要一开始就做完整 RPC 面。

---

## 15. 需要避免的错误路线

### 错误路线 1：解析 prompt 文本得到 cwd

不应该这样做。

原因：

- 脆弱
- 跟 shell 配置强耦合
- Ghostty 已经有 pwd 机制

### 错误路线 2：把普通命令完成等同于 Codex 完成

不应该这样做。

原因：

- 语义不对
- 很快会误报

### 错误路线 3：为了做 sidebar，重写 tab/split 底层

不应该这样做。

原因：

- 工作量爆炸
- 风险高
- Ghostty 现有底层已经够用

### 错误路线 4：第一版就追求完整 cmux parity

不应该这样做。

原因：

- 会拖慢主线
- 当前真正重要的是 agent 工作流闭环

### 错误路线 5：为了图省事，用 Electron/Tauri 再包一层 Ghostty

不应该这样做。

原因：

- 会把问题从“定制终端宿主”变成“跨进程/跨渲染栈的复杂集成”
- 性能、输入法、快捷键、窗口管理和终端嵌入都会变复杂
- 与当前目标“最小可用、可靠、贴近系统”的方向相反

---

## 16. 第一版完成标准

满足下面几点，就算第一版方向正确：

- 左侧有可点击的竖版 tab/sidebar
- sidebar 每行能显示 tab title 和 cwd
- `Alt+1..9` 可切 tab，且 UI 上有提示
- `panmuxctl notify` 能稳定更新当前实例中的目标 tab 状态
- `Codex` 至少有一个经过 spike 验证的完成态接入方式
- 非当前 tab 的 Codex 完成会有明显提醒

---

## 17. 后续扩展位

第一版之后，再考虑：

- `pi` 集成
- 状态 pill / progress bar / log feed
- 多种 agent 状态统一模型
- session restore
- sidebar 拖拽排序
- richer notification center

---

## 18. 给下一位 CodeX 的一句话任务定义

> 在 Linux/Wayland/Hyprland 上，为 `panmux` 先做技术路线 spike：验证 Ghostty GTK fork 加 sidebar 的改造成本、验证 `libghostty` embed 可行性、验证 Codex 的真实完成态接入点；在 spike 结论基础上，优先实现左侧 sidebar、cwd 展示、`Alt+数字` 切 tab，以及基于 `panmuxctl`（UDS + JSON-line，多实例隔离）的 Codex 状态提醒。不要试图移植 cmux 的 macOS UI 壳，也不要靠解析 shell prompt 或普通 command finished 来模拟 Codex 状态。

## 12. 本地安装与试用

当前阶段先不做发行级打包；推荐使用本地前缀安装，原因是：

- 当前仍在高频试错 UI/交互细节
- 本地试用比 pacman/AUR 打包更快
- 更容易保持系统 Ghostty 与 `panmux` 并存，不互相污染

当前约定：

- 安装脚本：`scripts/install_local_panmux.sh`
- 默认源码目录：当前仓库根目录
- 默认安装前缀：`~/.local/opt/panmux/<git-short-sha>`
- 当前激活版本软链接：`~/.local/opt/panmux/current`
- 命令入口：`~/.local/bin/panmux`
- CLI 入口：`~/.local/bin/panmuxctl`
- 桌面入口：`~/.local/share/applications/panmux.desktop`

安装包装器应满足：

- 启动时显式移除 `NO_COLOR`
- 默认传入 `--gtk-single-instance=false`
- 不覆盖系统 `ghostty`
- 不要求修改 `Codex` 源码

