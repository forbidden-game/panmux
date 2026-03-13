# panmux reply-state 执行方案

## 1. 结论

最新的 `PANMUX_REPLY_STATE.md` 方向是成立的，核心判断也是对的：

- `seen` 和 `running` 必须分离
- reply-state 必须是 session-scoped，而不是 workspace-scoped 假确认
- `session_id` / `surface_id` 路由优先级必须高于“当前激活 split”

但它如果直接进入实现，还差三件事才能真正闭环：

1. completion notify 必须把 `phase` 从 `running` 拉到 `waiting_user` 或 `failed`
2. view 事件必须明确命中“当前选中的 workspace + 当前选中的 surface 绑定 session”
3. UI 上不能再存在“批量清空 needs input”这种绕过 `seen -> running` 约束的入口，除非整套 reply-state 都在同一 feature flag 后一起上线

这份执行方案的目标，就是把这三件事和实现/UI 绑定关系一起钉死。

## 2. 当前实现和新文档的主要冲突

当前代码里已经存在一版 `panmux_state`，但它的语义中心还是旧模型：

- [`src/apprt/gtk/panmux_state.zig`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/panmux_state.zig) 仍以 `severity + attention ack` 为主，而不是 `reply_attention + draft_started`
- [`src/apprt/gtk/class/window.zig`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/class/window.zig) 会在缺少 `surface_id` 时把当前 active surface 注入状态更新，这和新文档的“保留旧绑定”相冲突
- [`src/apprt/gtk/class/window.zig`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/class/window.zig) 的 tab 选择、输入事件、ack button 仍然在做“整页消费 needs input”的旧行为
- [`src/apprt/gtk/ui/1.5/window.blp`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/ui/1.5/window.blp) 的 sidebar 主要还是绑定 `Adw.TabPage.loading/keyword/indicator-tooltip`，store 不是唯一真源

所以这次不能是“在旧 store 上补两个字段”，而要明确分层：

`Signal / IPC / UI interaction -> PanmuxEvent -> PanmuxReducer -> Snapshot -> UI render`

## 3. 目标状态模型

`reply_attention` 才是 Codex reply-state 的主语义。

建议把 Codex session 状态扩成下面这组字段：

```zig
pub const ReplyAttention = enum {
    none,
    unseen,
    seen,
};

pub const AgentSessionState = struct {
    session_id: []const u8,
    workspace_id: []const u8,
    tab_id: []const u8,
    surface_id: ?[]const u8,
    agent_type: AgentType,
    agent_label: []const u8,
    phase: SessionPhase,
    reply_attention: ReplyAttention,
    draft_started: bool,
    turn_id: ?[]const u8,
    last_summary: ?[]const u8,
    last_attention_id: ?[]const u8,
    started_at_ms: i64,
    updated_at_ms: i64,
};
```

同时保留 `AttentionItem`，但角色要收缩：

- `AgentSessionState.reply_attention` 是 tab/sidebar/inspector 的主判断依据
- `AttentionItem` 只负责存储“最近一条待看的 reply 文本 / 失败摘要 / legacy attention”
- unread 计数按 session 聚合，不按 attention item 条数聚合

`WorkspaceState.selected_surface_id` 不能继续是死字段，必须真的接入 split focus。

另外要把 predicate 明确拆开，不能继续只有一个模糊的 `isSessionActive`：

```zig
pub fn isProcessRunning(phase: SessionPhase) bool {
    return switch (phase) {
        .starting, .running => true,
        .waiting_user, .failed, .completed, .exited => false,
    };
}

pub fn isReplyRelevant(session: *const AgentSessionState) bool {
    if (session.reply_attention != .none) return true;
    return switch (session.phase) {
        .starting, .running, .waiting_user, .failed => true,
        .completed, .exited => false,
    };
}
```

约束要写死：

- workspace snapshot / queue / detail selector 用 `isReplyRelevant`
- running badge / spinner / running_count 用 `isProcessRunning`
- `failed` 不能因为“进程已经不在跑”就从 reply-state UI 里消失

## 4. 事件模型

实现里需要把“外部事件”和“本地 UI 事件”都变成结构化 event。

### 4.1 外部事件

| 来源 | 事件 | reducer 结果 |
| --- | --- | --- |
| `panmuxctl set-status --state running` | `session_running` | `phase = running`, `reply_attention = none`, `draft_started = false` |
| `panmuxctl notify` 成功完成 | `session_waiting_user` | `phase = waiting_user`, `reply_attention = unseen`, `draft_started = false` |
| `panmuxctl notify` 失败 | `session_failed` | `phase = failed`, `reply_attention = unseen`, `draft_started = false` |
| `panmuxctl clear-status` | `session_cleared` | 按 `session_id` 清理；无 `surface_id` 时不得注入 active surface |
| surface 命令探测 / wrapper 启动 | `session_running` | 与显式 `set-status running` 同义 |

如果保留零参数 `panmuxctl clear-status` 兼容入口，它只表示 legacy current-target clear，不属于 reply-state 主语义路径。

Codex completion attention 的 refresh 规则也必须固定：

- `turn_id` 存在时，用 `session_id + turn_id` 作为 logical attention key
- `turn_id` 缺失时，用 `session_id` 作为 fallback key
- 命中同一个 logical key 时，更新现有 item，而不是 append 第二条 unread
- refresh 默认保留原 `attention_id`；新的 logical reply 才创建新的 `attention_id`

### 4.2 本地 UI 事件

| 来源 | 事件 | reducer 结果 |
| --- | --- | --- |
| tab 切换 / window 激活 / split focus 切换 | `session_viewed` | 仅目标 session: `unseen -> seen` |
| 可归因为 reply draft 的输入 | `reply_draft_started` | 仅目标 session: `draft_started = true` |
| 同 surface 上的提交动作 | `reply_submitted` | 仅当 `draft_started = true` 时：`reply_attention = none`, `draft_started = false`, `phase = running` |

这三个本地事件是这次方案最关键的新增点。没有它们，新文档的状态机落不到 UI 上。

### 4.3 输入接线前置条件

这里不能只写“Window 接本地事件”。

当前真实旧链路是：

`普通按键 / paste -> Surface.panmuxInputActivity() -> Window.panmuxConsumeNeedsInputSurface() -> workspace 内所有 codex session ack`

所以在接入新状态机之前，必须先做两个前置动作：

1. 在 [`src/apprt/gtk/class/surface.zig`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/class/surface.zig) 新增 surface-level input signal 或 callback，至少能区分：
   - draft-like text input
   - paste text
   - submit intent
2. 把旧的 `panmuxInputActivity -> panmuxConsumeNeedsInputSurface -> ackSessionAttention` 链路从 Codex reply-state 主路径移除

否则结果一定会变成：

- 一边新增 `reply_draft_started / reply_submitted`
- 一边保留旧的 workspace-wide ack
- 最终新旧状态机并存，UI 行为继续漂移

## 5. 路由和绑定规则

### 5.1 session 绑定

Reducer 侧统一遵守：

1. `session_id` 命中已有 session 时，优先按 session 更新
2. 只有事件带了显式 `surface_id` 时，才允许重绑到新 split
3. 只有没有 `session_id` 时，才允许走 legacy `surface_id -> session` fallback

实现上这意味着：

- [`src/apprt/gtk/class/window.zig`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/class/window.zig) 的 `applyPanmuxStatus` 不能再把“page 当前 active surface”当成默认写回值
- [`src/apprt/gtk/class/window.zig`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/class/window.zig) 的 `clearPanmuxStatus` 不能在 `session_id` 已存在时额外套上 `surface_id orelse active_surface`

### 5.2 selected surface 绑定

`WorkspaceState.selected_surface_id` 必须来自真实 UI 焦点，而不是临时现算：

- page selected 改变时更新当前 workspace 的 `selected = true`
- tab 内 active surface 改变时更新当前 workspace 的 `selected_surface_id`
- window re-activate 时，按 selected page + selected surface 重新分发 `session_viewed`

这部分建议直接在 [`src/apprt/gtk/class/window.zig`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/class/window.zig) 监听：

- `Adw.TabView::notify::selected-page`
- `GhosttyTab::notify::active-surface`
- `Gtk.Window::notify::is-active`

## 6. draft / submit 的本地判定

这是 UI 和状态最容易再次脱节的地方，必须单独定规则。

### 6.1 draft_started 只在“真的像回复”时设置

默认只接受这几类输入作为 draft：

- 可打印文本输入
- IM commit 文本
- paste 非空文本

明确不算 draft：

- 单纯切 tab / 切 split / 鼠标点击
- 方向键、PageUp/PageDown、滚轮
- 只有 modifier 的按键
- 纯命令快捷键

### 6.2 reply_submitted 的默认启发式

在没有 Codex 明确“已接收输入”信号之前，使用保守版本：

- 同一 `surface_id`
- session 当前 `reply_attention in { unseen, seen }`
- `draft_started = true`
- 无 modifier 的 `Enter/Return`

只有四个条件同时满足，才允许本地转到 `phase = running`。

这条规则不证明 Codex 语义上真的接受了回复，但它满足新文档的 non-goal：只做本地 UI 状态闭环，不伪装成协议确认。

## 7. UI 绑定合同

### 7.1 总原则

`Adw.TabPage` 以后只做 render target，不再做语义真源。

短期可以继续把 snapshot 渲染到：

- `page.loading`
- `page.keyword`
- `page.indicator-tooltip`

但所有读取逻辑都必须回到 store selector，不能再反向从这些字段猜 reply-state。

### 7.2 sidebar row

sidebar 只消费 `WorkspaceReplySnapshot`：

```zig
pub const WorkspaceReplySnapshot = struct {
    workspace_id: []const u8,
    badge: enum { none, running, unseen, seen },
    running_count: u32,
    unseen_count: u32,
    seen_count: u32,
    primary_session_id: ?[]const u8,
    tooltip: ?[]const u8,
    overlay: OverlayKind,
};
```

绑定关系要固定成下面这样：

- 标题：workspace title
- cwd：selected surface cwd
- running badge：`badge == running`
- unseen badge：`badge == unseen`
- seen badge：`badge == seen`
- unread 圆点数字：`unseen_count`
- overlay：只给 legacy info/warning/error，不表达 Codex reply-state

重点是：

- `seen` 必须有独立视觉态，不能继续和 `running` 或“已清空”混用
- `unseen_count` 显示的是“多少个 session 还没看”，不是 attention item 数量

### 7.3 tab indicator

tab indicator 只表达 workspace 聚合态：

- `running` -> spinner
- `unseen` -> 强提示图标
- `seen` -> 弱提示图标
- `none` -> 不显示 Codex badge

`Adw.TabPage.needs-attention` 不再承载 Codex reply-state。它只保留给真正无结构的 legacy 提醒。

### 7.4 inspector / detail panel

当前 detail panel 可以保留，但语义必须改：

- 它显示“当前 window 内哪些 workspace 正在等你”
- 数据源来自 window-level selector，不来自 `ackSessionAttention`
- “Clear Needs Input” 这个按钮不应该继续存在于 Codex reply-state 路径

建议改成两步：

1. 先移除/隐藏 Codex 的 bulk ack 行为
2. detail panel 只做导航和摘要，不做状态跳变

如果未来要支持显式 dismiss，也必须是新的独立动作，不能借旧 ack 语义偷渡。

## 8. 建议的 selector

最少需要三类 selector：

### 8.1 workspace selector

- `workspaceReplySnapshot(workspace_id)`
- 给 sidebar / tab indicator 用

它必须只基于 reducer/store 状态，不允许回读 `Adw.TabPage` 展示字段。

### 8.2 workspace detail selector

- `workspaceSessionRows(workspace_id)`
- 给当前 tab 的 detail panel / future activity list 用

每个 row 至少要有：

- `session_id`
- `surface_id`
- `phase`
- `reply_attention`
- `draft_started`
- `summary`
- `is_selected_surface`

### 8.3 window queue selector

- `windowReplyQueue(window_workspaces)`
- 给“哪些 tab 正在等你”面板用

排序规则建议固定：

1. `unseen` 优先
2. `seen` 次之
3. 最近 `updated_at_ms` 靠前

这三个 selector 都必须包含 `failed + unseen/seen` 的可见路径，不能因为 helper 只表达“进程仍在跑”就把失败回复过滤掉。

## 9. 分阶段落地顺序

### Phase 0: 先拆旧输入链路

- 在 [`src/apprt/gtk/class/surface.zig`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/class/surface.zig) 增加 panmux reply input signal / callback
- 停掉旧的 `panmuxInputActivity -> panmuxConsumeNeedsInputSurface -> ackSessionAttention` 对 Codex reply-state 的直接清理
- 保证普通按键和 paste 不会再做 workspace-wide ack
- 同时移除、隐藏或 feature-gate 掉 detail panel 里的 Codex bulk-clear 入口

验收标准：

- 仓库里不存在“任意普通输入即可把整个 workspace needs input 清掉”的路径
- 仓库里不存在一个仍可点击的 Codex bulk-clear UI 绕过路径，除非整套 reply-state 仍在同一 feature flag 后
- 后续 Phase 3 只是在消费新 signal，不是和旧逻辑叠加

### Phase 1: 先修 domain，不碰复杂 UI

- 在 [`src/apprt/gtk/panmux_state.zig`](/home/pxz/Work/tries/ghostty-panmux/src/apprt/gtk/panmux_state.zig) 引入 `reply_attention` / `draft_started`
- 新增 reducer 规则、`isProcessRunning` / `isReplyRelevant` 两套 predicate 和 selector
- 定义 Codex completion attention 的 logical refresh key
- 把当前 `ackSessionAttention` 从 Codex reply-state 主路径摘掉

验收标准：

- store 里可以稳定表达 `running / unseen / seen`
- `failed` session 在 reply-state selector 中仍然可见
- `seen` 不会直接掉回 `running`

### Phase 2: 修路由和 split 绑定

- 让 `selected_surface_id` 真正工作起来
- 修正“缺少 `surface_id` 时 preserve binding”的逻辑
- 修正 `clear-status(session_id)` 只按 session 清理

验收标准：

- tab 内两个 split 分别绑定两个 session 时，不会因为切焦点而串状态

### Phase 3: 接本地 view / draft / submit 事件

- tab select
- window activate
- split focus change
- 消费 Phase 0 暴露出的文本输入 / IM commit / paste / submit signal
- Enter submit

验收标准：

- `unseen -> seen` 只在目标 session 上发生
- `seen -> running` 只在同 surface 提交后发生

### Phase 4: UI 迁移

- sidebar 改为读 snapshot
- tab indicator 改为读 snapshot
- detail panel 改为 window queue selector
- 确认 Codex bulk-clear UI 在新界面里仍然不存在

验收标准：

- UI 所有 badge 都能从 store 单独推导出来
- 不再需要“看一下 `page.keyword` 当前是什么再决定业务逻辑”

### Phase 5: 调试面和 IPC 可观测性

- [`src/panmux_ipc.zig`](/home/pxz/Work/tries/ghostty-panmux/src/panmux_ipc.zig) 的 `SessionInfo` 暴露 `reply_attention` 和 `draft_started`
- `list-tabs` 增加 `seen_count` / `unseen_count`
- 保证脚本和测试能直接观察状态，不用靠 UI 猜

## 10. 测试矩阵

除了原文档已有测试，还建议补这几类：

- completion notify 后 `phase` 必为 `waiting_user` 或 `failed`，不能残留 `running`
- `failed` session 在 workspace snapshot / window queue / detail selector 里仍可见
- `session_id` 命中时，缺失 `surface_id` 不会把绑定改到当前 active surface
- tab select 只把 selected surface 对应 session 从 `unseen` 变 `seen`
- split focus 从 A 切到 B 时，只影响 B 的 session
- `draft_started = true` 但没有 Enter，不允许 `seen -> running`
- Enter 发生在别的 surface，不允许清当前 waiting session
- 相同 `session_id + turn_id` 的重复 notify 只 refresh 一个 logical attention item
- inspector/detail panel 不存在 bulk clear Codex reply-state 的路径

## 11. 这次实现要刻意避免的回退

下面这些如果再次出现，基本就意味着又走回旧路了：

- 从 `Adw.TabPage.keyword/loading/needs-attention` 反推 reply-state
- 把“当前 page 的 active surface”偷偷塞进无 `surface_id` 的 session 更新
- 在 workspace 级做统一 ack，然后假装用户已经处理过 reply
- 用一个 tab 级布尔值表达多个 split/session 的 reply-state

如果实现过程中要做兼容层，也只能是“store -> UI 字段的单向镜像”，不能是 UI 字段反向主导 store。
