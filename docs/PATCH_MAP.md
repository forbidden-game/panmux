# PATCH_MAP

## 当前主线

- 主线：`Ghostty GTK fork`
- 当前阶段：`Phase 1 sidebar skeleton` + `Phase 2 state refactor design`
- 暂不走：`embedded/libghostty` Linux 宿主主线

## 当前优先文档

- 实现主线：`docs/IMPLEMENTATION_BLUEPRINT.md`
- 当前结构重整：`docs/REFACTOR_BLUEPRINT.md`

## 第一批目标文件

### `src/apprt/gtk/ui/1.5/window.blp`

- 角色：窗口主布局与 sidebar widget 装配点
- 第一批改动：sidebar row 列表、row activate、separator、右侧保留 `Adw.TabView`
- 风险：Blueprint 构建依赖 `blueprint-compiler`

### `src/apprt/gtk/class/window.zig`

- 角色：window template child/callback 绑定与 tab 选择联动
- 第一批改动：sidebar child 绑定、activate callback、cwd/shortcut helper
- 风险：focus/selected-page 联动容易出现“点击 sidebar 后 terminal 未重新 grab focus”问题

### `src/apprt/gtk/css/style.css`

- 角色：sidebar 样式与 selected/attention 状态视觉
- 第一批改动：最小可读样式
- 风险：低

### `src/apprt/gtk/class/tab.zig`

- 角色：tab 级 active surface/attention 语义
- 第一批改动：让 sidebar 能稳定读取当前 tab 的 active surface 状态
- 风险：中，容易把“tab 表达层状态”与“terminal lifecycle”缠在一起

### `src/apprt/gtk/class/surface.zig`

- 角色：surface 的 `pwd`、`command_finished`、后续 env 注入
- 第一批改动：pwd 到 sidebar 的最短链路；后续再加 `PANMUX_*`
- 风险：不要把普通 `command_finished` 误写成 Codex 完成

### `src/apprt/gtk/class/application.zig`

- 角色：GTK app action 分发与未来控制面入口
- 第一批改动：Phase 1 可只读少改；Phase 4 再接 control plane
- 风险：高于前几项，先别过早扩 scope

### `src/config/Config.zig`

- 角色：默认 keybind 定义
- 第一批改动：把 Linux 默认 tab 数字键从 `Alt+1..8 + Alt+9=last` 调整为 `Alt+1..9=tab 1..9`
- 风险：这是 fork 行为差异，后续需要记入 patch map，避免 upstream sync 时被覆盖

## 近期不碰的区域

- terminal core
- split/tree 底层重写
- prompt 解析式 cwd
- 普通 shell 生命周期冒充 Codex turn 完成
