# panmux 重构蓝图（多 Agent / 状态层 / 通知优先）

## 1. 结论先行

当前版本最根本的问题不是某一个 badge、某一个 callback，或者某一处 GTK 绑定写得不够漂亮，而是：

- `panmux` 的业务状态没有独立状态层；
- `Adw.TabPage` 的通用显示字段被拿来充当 panmux store；
- 一个 tab 只能表达一个状态，无法表达“一个 workspace 里同时跑多个 agent”；
- 系统通知和“已读/未读”没有单独模型，只能靠临时 cue 和视觉叠层硬撑；
- sidebar、tab、surface、split focus 之间已经出现了明显的双向耦合。

因此，这次重构的目标不是“继续把现有 sidebar 修顺一点”，而是先把 panmux 从“UI 驱动状态”改成“状态驱动 UI”。

---

## 2. 重构目标

这轮重构只解决对 agent 工作流最关键的问题。

### 2.1 必须达成

1. 一个 workspace/tab 内可以同时表达多个 agent session 的进度，而不是最后一个状态覆盖前一个状态。
2. 系统通知、agent 完成提醒、错误提醒必须成为显式的 attention item，而不是输入一下就消失。
3. 所有 panmux 状态都先进入统一 store，再由 store 派生 sidebar、tab indicator、toast、attention dot。
4. 现有 `panmuxctl`、Unix socket、`PANMUX_*` 环境变量继续保留，不推翻 transport。
5. 重构可以分阶段落地，中间每一期都能保持可运行，而不是一次性大爆炸替换。

### 2.2 明确不做

- 不重写 terminal core；
- 不重写 split/tree 底层数据结构；
- 不做跨进程持久化恢复；
- 不在本轮同时推进 `pi` 集成；
- 不追求 macOS/GTK 同步重构。

---

## 3. 当前实现的已验证问题

下面这些不是抽象担忧，而是当前代码已经存在的结构性问题。

### 3.1 UI 组件字段正在充当业务 store

当前 panmux 状态分散在这些地方：

- `Adw.TabPage.loading`
- `Adw.TabPage.keyword`
- `Adw.TabPage.indicator-tooltip`
- `Adw.TabPage.indicator-icon`
- `Adw.TabPage.needs-attention`
- `Window.private.panmux_sidebar_cues`

这意味着：

- “运行中”是 `loading`
- “完成/错误/告警”是 `keyword`
- “人类可读文案”是 `indicator-tooltip`
- “未读提醒”有时是 `needs-attention`
- “Codex cue” 又是一个独立 map

这不是状态模型，这是把 UI 属性借来拼领域状态。

### 3.2 一个 tab 只有一个状态槽位

`list-tabs` 当前只能返回：

- 一个 `state`
- 一个 `surface_id`
- 一个 `selected`
- 一个 `needs_attention`
- 一个 `loading`

这只适合“一个 tab 就是一条串行任务”的模型，不适合：

- 一个 tab 内多个 split 同时跑 agent；
- 一个 agent 在同一个 workspace 内连续多个 turn；
- 一个 tab 同时有“正在运行的 agent”和“刚完成但待查看的通知”。

### 3.3 通知不是一等公民

当前通知更像“临时视觉 cue”，不是可操作对象：

- 没有 notification id
- 没有 ack 状态
- 没有“是否必须查看”
- 没有“触发来源”
- 没有“点击后应执行什么动作”

结果就是：

- 用户点进 tab、按键、滚动、点击 surface，就可能把 cue 清掉；
- 但这不等于用户真的看过 agent 的输出，也不等于用户完成了确认。

### 3.4 agent 身份靠展示文本推断

现在一些逻辑仍然依赖：

- `title == "Codex"`
- body 恰好是 `"pong"`
- command text 看起来像 `codex`

这在 fallback 阶段可以接受，但不能作为长期结构。

长期上，agent 身份必须来自显式字段，而不是 UI 文案。

### 3.5 sidebar 直接穿透 tab/surface/split

当前 sidebar row 直接绑定：

- `Adw.TabPage.title`
- `GhosttyTab.active-surface`
- `GhosttySurface.pwd`
- `Adw.TabPage.keyword/loading/indicator-tooltip`

这意味着 sidebar 并没有自己的 view model，而是在读 runtime widget graph。

这个结构短期省代码，长期会让：

- tab identity 跟着 focused split 抖动；
- cwd、title、badge、attention 互相污染；
- UI 无法脱离 widget 层做局部重构。

---

## 4. 设计原则

### 4.1 单向数据流

所有 panmux 相关状态更新都必须走：

`Signal / IPC / Hook -> PanmuxEvent -> PanmuxStore -> Selector/Snapshot -> UI`

不能再走：

`Signal -> 直接改 TabPage 字段 -> Sidebar 猜业务语义`

### 4.2 领域状态与 GTK 展示状态分离

- GTK widget 负责显示；
- panmux store 负责语义；
- `Adw.TabPage` 只保留作为 libadwaita tab 容器，不再作为 panmux 真正的业务状态容器。

### 4.3 持久状态与瞬时提醒分离

必须明确区分：

- session lifecycle：`starting/running/completed/failed/exited`
- attention item：`turn complete / error / needs review / system notification`

前者是持续状态，后者是待处理事件。

### 4.4 workspace 聚合与 agent 明细分离

sidebar row 只显示 workspace 级摘要，不承担 agent 全量明细展示。

明细应该放到：

- 选中 workspace 的 activity list
- 或单独 attention/inbox 视图

### 4.5 fallback 可以存在，但不能反向主导模型

Ghostty runtime 的命令探测、`codex` 命令文本识别、进程树 probe 都可以保留，但只能作为 fallback signal source，不能成为主模型的语义中心。

---

## 5. 目标架构

## 5.1 分层

### A. Transport 层

保留并扩展这些入口：

- `panmuxctl`
- Unix socket / JSON-line IPC
- `scripts/panmux_codex_notify.py`
- `scripts/panmux_codex_wrapper.sh`
- Ghostty runtime signal：`start_command` / `stop_command` / `pwd_change` / focus change

### B. Domain 层

新增 panmux 专用状态层：

- `PanmuxStore`
- `PanmuxReducer`
- `PanmuxEvent`
- `WorkspaceState`
- `AgentSessionState`
- `AttentionItem`
- `WorkspaceSnapshot`

### C. Adapter 层

负责把现有 Ghostty GTK runtime 接到 store：

- `ApplicationPanmuxBridge`
- `WindowPanmuxBinding`
- `SurfacePanmuxBinding`
- IPC request -> event adapter

### D. Presentation 层

只消费 snapshot，不直接拼领域状态：

- `Sidebar`
- `SidebarRow`
- `ActivityList`
- `AttentionInbox`
- tab indicator / toast / desktop notification action

---

## 6. 目标数据模型

下面是建议的数据模型。字段不要求一字不差，但语义要保持。

```zig
pub const AgentType = enum {
    codex,
    pi,
    other,
};

pub const SessionPhase = enum {
    starting,
    running,
    waiting_user,
    completed,
    failed,
    exited,
};

pub const Severity = enum {
    none,
    info,
    warning,
    error,
};

pub const AttentionKind = enum {
    turn_complete,
    needs_review,
    system_notification,
    session_failed,
    legacy_notify,
};

pub const WorkspaceState = struct {
    workspace_id: []const u8,
    tab_id: []const u8,
    selected_surface_id: ?[]const u8,
    stable_title: []const u8,
    display_cwd: ?[]const u8,
    selected: bool,
    last_event_at_ms: i64,
};

pub const AgentSessionState = struct {
    session_id: []const u8,
    workspace_id: []const u8,
    tab_id: []const u8,
    surface_id: ?[]const u8,
    agent_type: AgentType,
    agent_label: []const u8,
    phase: SessionPhase,
    severity: Severity,
    turn_id: ?[]const u8,
    last_summary: ?[]const u8,
    started_at_ms: i64,
    updated_at_ms: i64,
};

pub const AttentionItem = struct {
    attention_id: []const u8,
    workspace_id: []const u8,
    session_id: ?[]const u8,
    kind: AttentionKind,
    severity: Severity,
    title: []const u8,
    body: ?[]const u8,
    ack_required: bool,
    acked_at_ms: ?i64,
    created_at_ms: i64,
    action: ?AttentionAction,
};

pub const WorkspaceSnapshot = struct {
    workspace_id: []const u8,
    title: []const u8,
    cwd: ?[]const u8,
    running_count: u16,
    unread_count: u16,
    highest_severity: Severity,
    primary_phase: SessionPhase,
    selected: bool,
};
```

### 6.1 关于 identity 的约束

这一期不做跨进程持久化，因此可以接受：

- `workspace_id` 初期直接等于当前 `tab_id`
- `tab_id`、`surface_id` 继续沿用当前进程内 pointer hex 语义

但必须新增：

- `session_id`
- `attention_id`

因为多 agent 和通知系统离不开这两个 id。

### 6.2 关于 session_id 的来源

建议优先级如下：

1. wrapper 显式生成并注入 `PANMUX_SESSION_ID`
2. notify bridge 透传上游 `thread-id` / `turn-id` 并映射
3. 如果上游没有稳定 session id，则 panmux 本地创建 ephemeral session id

长期上不要再依赖 “tab 上当前最后一个状态” 推断 session。

---

## 7. 事件模型

panmux store 只接收结构化事件。

```zig
pub const PanmuxEvent = union(enum) {
    workspace_opened: struct { workspace_id: []const u8, tab_id: []const u8 },
    workspace_closed: struct { workspace_id: []const u8 },
    workspace_selected: struct { workspace_id: []const u8 },
    surface_focus_changed: struct { workspace_id: []const u8, surface_id: ?[]const u8 },
    surface_pwd_changed: struct { workspace_id: []const u8, surface_id: []const u8, pwd: []const u8 },

    agent_session_started: struct {
        workspace_id: []const u8,
        tab_id: []const u8,
        surface_id: ?[]const u8,
        session_id: []const u8,
        agent_type: AgentType,
        agent_label: []const u8,
    },

    agent_turn_completed: struct {
        workspace_id: []const u8,
        session_id: []const u8,
        turn_id: ?[]const u8,
        severity: Severity,
        summary: ?[]const u8,
        raise_attention: bool,
    },

    agent_session_finished: struct {
        workspace_id: []const u8,
        session_id: []const u8,
        phase: SessionPhase,
        severity: Severity,
        summary: ?[]const u8,
    },

    attention_raised: AttentionItemDraft,
    attention_acked: struct { attention_id: []const u8 },

    legacy_status_set: LegacyStatusPayload,
    legacy_status_cleared: struct { workspace_id: []const u8, surface_id: ?[]const u8 },
};
```

### 7.1 reducer 规则

下面这些规则必须固定下来。

#### A. session lifecycle 不自动清空

- `running` 不应该因为一个 `notify(info)` 就被替换掉；
- `completed/failed/exited` 是 session 终态；
- attention item 是附加在 session 上，而不是覆盖 session。

#### B. 通知必须显式 ack

以下动作都不应该自动 ack attention：

- tab 被选中
- 用户按了一次键
- 用户滚了一下滚轮
- 用户点击了一下 terminal

attention 只能在这些动作中被 ack：

- 用户显式打开该 attention 对应的输出；
- 用户点击“已查看”；
- 用户调用 `panmuxctl ack-attention`；
- 或某个明确的 UI action 触发 ack。

#### C. workspace 摘要只做聚合

`WorkspaceSnapshot` 由 store 派生：

- `running_count` = 当前 running session 数
- `unread_count` = 未 ack attention 数
- `highest_severity` = 当前 session 和未读 attention 的最高级别
- `primary_phase` = 优先显示 running，其次 failed，再其次 completed

sidebar 不再自己判断。

#### D. legacy 入口只做兼容映射

保留现有：

- `notify`
- `set-status`
- `clear-status`

但它们进入 reducer 之前先被转换为 `PanmuxEvent`。

不能再直接改 `TabPage.loading/keyword`。

---

## 8. IPC 与 CLI 重构方案

## 8.1 保留的现有能力

这些命令继续保留，保证已有脚本不立刻失效：

- `panmuxctl notify`
- `panmuxctl set-status`
- `panmuxctl clear-status`
- `panmuxctl focus-tab`
- `panmuxctl list-tabs`

## 8.2 新增的结构化接口

建议新增以下命令：

1. `panmuxctl emit-event`
2. `panmuxctl list-sessions`
3. `panmuxctl list-attention`
4. `panmuxctl ack-attention`
5. `panmuxctl focus-session`

### 8.3 推荐的最小协议方向

比起继续堆 `--title --body --state`，更推荐一条结构化事件入口：

```json
{
  "method": "emit-event",
  "params": {
    "event": {
      "type": "agent_turn_completed",
      "workspace_id": "abc",
      "tab_id": "abc",
      "surface_id": "def",
      "session_id": "codex-123",
      "agent_type": "codex",
      "turn_id": "turn-42",
      "severity": "info",
      "summary": "implemented sidebar reducer",
      "raise_attention": true
    }
  }
}
```

旧接口映射规则：

- `set-status running` -> `agent_session_started` 或 `legacy_status_set`
- `set-status info/error` -> `agent_session_finished`
- `notify` -> `attention_raised`

### 8.4 关于 `PANMUX_INSTANCE_ID`

当前环境已注入 `PANMUX_INSTANCE_ID`，但没有真正进入路由模型。

建议这轮补上它的意义：

- `emit-event` 默认优先写回当前实例；
- 跨窗口操作时先按 instance 过滤，再按 tab/surface 过滤；
- 避免未来多个 panmux 窗口并存时“命中当前活跃窗口”的路由歧义。

---

## 9. 对 Codex 的推荐集成方式

## 9.1 主路径

主路径建议是：

1. wrapper 创建 `session_id`
2. wrapper 注入：
   - `PANMUX_SESSION_ID`
   - `PANMUX_AGENT_TYPE=codex`
   - `PANMUX_AGENT_LABEL=Codex`
3. wrapper 在启动时发送 `agent_session_started`
4. Codex notify bridge 在每个 turn complete 时发送 `agent_turn_completed`
5. wrapper 在进程退出时发送 `agent_session_finished`

这样可以把：

- session lifecycle
- turn-level attention
- process exit

三个层次拆开。

## 9.2 fallback

下面这些保留为 fallback，但不是主语义源：

- semantic prompt 检测命令行是否为 `codex`
- `/proc` 进程树 probe
- `title == "Codex"` 这种展示层判断

它们只在缺少结构化 agent metadata 时兜底。

## 9.3 对 notify bridge 的要求

`scripts/panmux_codex_notify.py` 下一版不应只转：

- `title`
- `body`
- `state`

而应尽量转：

- `agent_type`
- `session_id`
- `turn_id`
- `severity`
- `summary`
- `ack_required`

哪怕其中有部分字段暂时需要本地推断，也比继续只传展示文案更正确。

---

## 10. UI 重构方案

## 10.1 Sidebar 的职责

sidebar row 只显示 workspace 级摘要：

- title
- cwd
- running count
- unread count
- highest severity
- 当前主状态
- 选中态

不再直接承载“最后一条通知正文”。

### 10.2 Sidebar Row 建议表达

建议目标表达：

- 左侧：workspace 标题 + cwd
- 右侧上方：`2 Run` / `1 Err` / `Ready`
- 右侧下方：`Alt+3`
- 角标：未读 attention dot 或 unread count

如果同一 workspace 里：

- 有两个 Codex 在跑；
- 一个已完成但待查看；
- 一个失败；

sidebar 应显示聚合结果，而不是只剩最后一个 `info` 或 `error`。

## 10.3 Activity List

选中 workspace 后，应该有一个 agent activity 明细区。

第一版可以很轻，不必做完整面板，但至少要有一个选中 tab 的 session 列表，展示：

- agent label
- phase
- last summary
- updated time
- unread marker
- `focus` / `ack` 操作

这个区域可以是：

- sidebar 下半区折叠列表；
- 或右侧 drawer；
- 或 tab 内顶部一条轻量 activity strip。

第一版建议选最省改动的方案，不先做花活。

## 10.4 Attention Inbox

系统通知既然是你高度在意的能力，就不该只是一个小点。

建议新增全局 attention inbox，哪怕第一版只是命令接口和极简列表也值得做。

它的职责是：

- 列出所有未读 attention
- 支持按 workspace/session 聚合
- 支持一键 focus 到对应 tab/session
- 支持显式 ack

这部分一旦存在，你就不再依赖“我是不是刚好看到了那个小点”。

---

## 11. 文件与模块边界建议

## 11.1 建议新增文件

- `src/apprt/gtk/panmux_state.zig`
- `src/apprt/gtk/panmux_event.zig`
- `src/apprt/gtk/panmux_reducer.zig`
- `src/apprt/gtk/panmux_snapshot.zig`
- `src/apprt/gtk/class/panmux_sidebar_row.zig`
- `src/apprt/gtk/ui/1.5/panmux-sidebar-row.blp`

如果 activity list 本轮就做，再新增：

- `src/apprt/gtk/class/panmux_activity_list.zig`
- `src/apprt/gtk/ui/1.5/panmux-activity-list.blp`

## 11.2 现有文件的新职责

### `src/apprt/gtk/class/application.zig`

- 持有 panmux store
- 接收 IPC 请求
- 将 request 转换成 `PanmuxEvent`
- 提供 query 接口给 `list-*`

### `src/apprt/gtk/class/window.zig`

- 只负责 window layout、tab selection、snapshot binding
- 不再把 panmux 语义塞进 `Adw.TabPage` 作为主数据源
- 保留少量由 snapshot 派生到 `TabPage` 的兼容显示

### `src/apprt/gtk/class/tab.zig`

- 回到 tab/split container 角色
- 不再承担 panmux 业务状态聚合

### `src/apprt/gtk/class/surface.zig`

- 负责产生 runtime event：
  - pwd change
  - focus change
  - fallback command lifecycle
- 不再直接清理 notification cue

### `src/panmux_ipc.zig`

- 扩展 event payload 和 query response
- 保留旧参数结构做兼容映射

### `scripts/panmux_codex_notify.py`

- 从“标题/正文/状态桥”升级为“结构化 event bridge”

### `scripts/panmux_codex_wrapper.sh`

- 负责 session lifecycle
- 负责生成和透传 `PANMUX_SESSION_ID`

---

## 12. 迁移顺序

必须按下面顺序做，避免 scope 失控。

## Phase 1：引入 store，但不改现有 UI 表达

目标：

- 新建 `PanmuxStore`
- 所有 `notify/set-status/clear-status` 先写 store
- 同时保留现有 `TabPage` 显示逻辑，作为过渡层

验收标准：

- 当前 sidebar 行为不退化
- `list-tabs` 还能正常工作
- store 中能看到与 UI 对齐的 workspace/session/attention 数据

## Phase 2：统一事件入口

目标：

- wrapper、notify bridge、Ghostty fallback 全部先转 `PanmuxEvent`
- 删除 `window.zig` 里直接写业务语义的分散入口

验收标准：

- 同一个 session 的启动、turn complete、退出能串成一条生命周期
- 多个来源不会互相覆盖

## Phase 3：sidebar 脱离 `Adw.TabPage` 直读

目标：

- sidebar 改为绑定 `WorkspaceSnapshot`
- 提出独立 `SidebarRow` widget
- 删除 `window.blp` 里大段 inline 状态模板分支

验收标准：

- sidebar 不再直接依赖 `TabPage.keyword/loading/indicator-tooltip`
- row 状态只由 snapshot 决定

## Phase 4：加入 activity list 与 attention ack

目标：

- 增加 session 明细列表
- 增加 attention 列表与 ack
- 删除“按键/滚动/点击即清 cue”的逻辑

验收标准：

- 系统通知不会因 incidental interaction 丢失
- 用户能明确看到“哪个 agent 刚完成了什么”

## Phase 5：压缩 legacy 兼容层

目标：

- `Adw.TabPage` 只保留最小兼容显示用途
- 老的 `notify/set-status/clear-status` 成为兼容 API，而不是主语义入口

验收标准：

- 新结构稳定
- 旧脚本仍可用
- 新功能不再依赖 UI 属性 hack

---

## 13. 验收标准

重构完成后，至少要满足下面这些真实场景。

### 场景 A：同一 tab 两个 agent 同时运行

预期：

- sidebar 显示 `running_count = 2`
- activity list 里能看到两个 session
- 一个 session 完成不会覆盖另一个 running session

### 场景 B：agent 发出系统通知，但用户先去别的 tab

预期：

- unread attention 保留
- sidebar 有明确聚合提示
- attention inbox 可追溯
- 用户必须显式 ack，通知才算已处理

### 场景 C：一个 session 失败后退出

预期：

- session phase 为 `failed` 或 `exited`
- workspace 最高 severity 升到 `error`
- 未读 attention 清晰可见

### 场景 D：老脚本仍使用 `panmuxctl notify`

预期：

- UI 仍然正常反应
- 但内部已经映射到新 store

---

## 14. 风险与纪律

### 14.1 不要在第一期同时重做 split/tree

`split_tree` 已经够复杂，本轮只把它当 signal source，不把它拖进同一次重构。

### 14.2 不要先追求“完美 agent 抽象”

第一期只需要把 `codex` 跑顺，并把模型设计成未来可扩展到 `pi`。

### 14.3 不要再做“为了快先塞到 TabPage 里”

这条是本轮最重要的纪律。

只要继续把新语义塞进：

- `loading`
- `keyword`
- `indicator-tooltip`

这次重构就等于没做。

### 14.4 attention 不得自动丢失

任何“用户有一点点交互，就当作看过通知了”的逻辑都应该视为错误默认值。

---

## 15. 推荐的第一批落地文件

如果下一步开始实做，我建议第一批就只碰这些文件：

- `src/apprt/gtk/class/application.zig`
- `src/apprt/gtk/class/window.zig`
- `src/apprt/gtk/class/surface.zig`
- `src/panmux_ipc.zig`
- `src/main_panmuxctl.zig`
- `scripts/panmux_codex_notify.py`
- `scripts/panmux_codex_wrapper.sh`
- 新增 `src/apprt/gtk/panmux_state.zig`
- 新增 `src/apprt/gtk/panmux_event.zig`
- 新增 `src/apprt/gtk/panmux_reducer.zig`
- 新增 `src/apprt/gtk/panmux_snapshot.zig`

先不要碰：

- `src/datastruct/split_tree.zig`
- terminal core
- 更广泛的 UI 美化

---

## 16. 一句话版本

panmux 下一阶段的正确主线不是“继续给 sidebar 加状态”，而是：

**先建立 `workspace / session / attention` 三层状态模型，再让 sidebar、tab 和通知都只做这个模型的投影。**
