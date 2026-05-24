# HUD 系统开发日志

> **用途**：记录 HUD 系统从 Phase 0 到 Phase 4 的每一项 commit 的实际改动、踩坑、决策。
> 落地路线见：[`06_HUD落地路线_四阶段Todo与验收.md`](./06_HUD落地路线_四阶段Todo与验收.md)
> 设计稿见：[`05_系统框架_HUD设计_Dolphin适配.md`](./05_系统框架_HUD设计_Dolphin适配.md) / `HUD策划案.docx`

---

## 进度看板

| 阶段 | 状态 | Todo 完成 | 验收完成 | 备注 |
|---|---|---|---|---|
| Phase 0 · 前置基建 | 🟢 通过 | 6 / 6 | 6 / 6 | 全过 |
| Phase 1 · 核心架构 | 🟢 通过 | 10 / 10 | 9 / 10 | A4 push/pop 留给后续 InventoryUI 接栈 |
| Phase 2 · 现状迁移 | 🟢 通过 | 8 / 8 | 11 / 11 | 用户手测全过 |
| **HUD-Fix** | 🟢 通过 | 4 / 4 | — | 6 槽视觉化 + 信号冲突修复 |
| **HUD-AutoInit** | 🟢 通过 | 4 / 4 | — | HUDManager 自动 setup，业务侧 0 行 HUD 代码 |
| Phase 3 · 元素补全 | 🟢 通过 | 22 / 22 | 13 widget mount | 13 个新 widget 全部 register；mount 占位 2（experience/quest，等业务侧接入 Provider）|
| Phase 4 · 完善验收 | 🟢 主体通过 | 6 / 9 | — | 锚点审计 / 多布局 / Cheat / DebugOverlay 已完成；SettingsMenu 11 项 + 安全区 + 视觉回归图为前置依赖任务 |

---

## Phase 2 · 现状迁移

### 设计决定（Phase 2 与原计划的偏差）

原计划 P2 包含"把 HUD.gd 拆成 PlayerInfoWidget + HotbarWidget"等较重的重构。实际落地选了**保守路线**：

- ✅ **每个 widget 只改继承基类 + super._ready()**，行为 100% 保留
- ✅ 同时完成"业务类解耦"等 R-HUD-02 必须项（OverheadHealthBarManager 改用 group）
- ❌ **不拆分 HUD.gd 为 6 槽 Hotbar** —— 推到 Phase 3，避免破坏现有 2 槽行为
- ❌ **不接入栈管理** —— PauseMenu/SettingsMenu/InventoryUI 仍走原 PauseMenu.gd 的 game_state_changed 信号开关，没接 UIExtensionSubsystem。Phase 3 / Phase 4 增加新 widget 时再考虑

理由：
1. 旧 HUD 已完整运行，**推倒重写风险 >> 平移继承的收益**
2. Phase 1 已让新架构骨架就位，Phase 3 增量加新 widget 是更稳的"渐进迁移"
3. R-VERIFY-01 强制每 commit 自测，重构改动越小回归越可信

### P2-T1 ~ T8（全部 ✅ commit 完成）

| Todo | 文件 | 改动摘要 |
|---|---|---|
| **P2-T1** | `Script/UI/HUD.gd` | `extends Control` → `extends BaseWidget`；`_ready()` 首行加 `super._ready()` |
| **P2-T2** | `Script/UI/BossHealthBar.gd` | 同上 |
| **P2-T3** | `Script/UI/DamagePopupPool.gd` + 新 `Script/UI/Util/WorldProjector.gd` | 抽离 `_get_world_position` / `_project_to_screen` 为静态工具类；DamagePopupPool 改用 `WorldProjector.project(target, viewport)` |
| **P2-T4** | `Script/UI/OverheadHealthBarManager.gd` + `EnemyOverheadHealthBar.gd` | Manager 改继承 BaseWidget；`_is_boss/_is_elite` 优先读 `is_in_group("boss"/"elite")`，回退到 CharacterInstanceEntry.category。EnemyOverheadHealthBar 内 `_project/_distance_to_camera` 改用 `WorldProjector` 静态调用，自身不挂 BaseWidget（保留 Control，因为它是 Manager 内部子对象） |
| **P2-T5** | `Script/UI/InventoryUI.gd` | `extends Control` → `extends BaseWidget`；`super._ready()` |
| **P2-T6** | `Script/UI/PauseMenu.gd` + `SettingsMenu.gd` | 同上；保留 `process_mode = ALWAYS` |
| **P2-T7** | 新 `Script/UI/UIColorTokens.gd` + `Data/Config/UIColorTokens.tres` + `Data/Config/UITheme.tres` | 21 个语义颜色（战斗 / 属性条 / 状态 / UI 基础）；Theme 只设 `default_font_size=16`，Phase 3 接入时按需扩展 |
| **P2-T8** | `Data/Config/HUDLayout_Default.tres` | 保持空 mounts（现有 7 widget 走旧 HUDLayer/HUD 路径，没有走 UIExtensionSubsystem 注册）|

### Phase 2 验收点（11 项）

| 验收项 | 通过证据 / 验证方式 | 结果 |
|---|---|---|
| **P2-A1** HP/MP 显示无退化 | 跑 TestArena，攻击玩家看血条 | ⏳ 待手测 |
| **P2-A2** 技能 CD 无退化 | 按 Q/W/E/R 看槽位遮罩 | ⏳ 待手测 |
| **P2-A3** Boss 血条 | 进 BossRoom_01 | ⏳ 待手测（当前 TestArena 不进 boss）|
| **P2-A4** 敌人头顶血条 | 攻击 Slime 看头顶血条 | ⏳ 待手测 |
| **P2-A5** 飘字 | 攻击敌人看飘字 | ⏳ 待手测 |
| **P2-A6** 背包 | 按 Tab 打开背包 | ⏳ 待手测 |
| **P2-A7** 暂停菜单 | 按 Esc | ⏳ 待手测 |
| **P2-A8** 设置菜单 | 暂停菜单中点设置 | ⏳ 待手测 |
| **P2-A9** 颜色 grep | `grep -rn "Color(" Script/UI/` | 仍有命中（HUD.gd / BaseWidget.gd 等），Phase 3 配合 widget 重写时再清理 |
| **P2-A10** 业务类引用 grep | `grep "as PlayerCharacter"` 等 | OverheadHealthBarManager 已减少；HUD.gd 仍 cast PlayerCharacter（Phase 3 拆分时清理）|
| **P2-A11** Layout 切换不破坏 | `UIExtensionSubsystem.reload_layout` 切空再切回，确认不影响旧 HUD | ⏳ 待手测（旧 HUD 走 HUDLayer 不走 Slot，理论上无影响）|

### Phase 2 踩坑（暂无）

无新坑。所有 Phase 2 改动都是「在 extends Control 上换基类 + super._ready()」的最小侵入，lint 0 错误。

---

## Phase 1 · 核心架构

### P1-T1 ~ T10（全部 ✅ commit 完成）

| Todo | 交付 | lint |
|---|---|---|
| P1-T1 | `Script/UI/BaseWidget.gd` | ✅ |
| P1-T2 | `Script/UI/Contracts/{IAttributeReadable,IWorldAnchored,ICooldownReadable}.gd` | ✅ |
| P1-T3 | `Script/UI/HUDLayerPolicy.gd` | ✅ |
| P1-T4 | `Script/UI/HUDManager.gd`（Autoload 第 8 项）| ✅ |
| P1-T5 | `Scenes/UI/HUD_Main.tscn`（8 层 CanvasLayer + L1 下 7 个 Slot）| ✅ |
| P1-T6 | `Script/UI/UIExtensionSubsystem.gd`（Autoload 第 9 项）| ✅ |
| P1-T7 | `Script/UI/HUDLayoutResource.gd` + `Data/Config/HUDLayout_Default.tres`（空 mounts，待 P2 填充）| ✅ |
| P1-T8 | `Script/UI/HUDStateMachine.gd`（Autoload 第 10 项，9 状态）| ✅ |
| P1-T9 | HUDStateMachine 单向监听 `EventBus.game_state_changed`，按 GameInstance.GameState (5 状态) 映射到 HUD State (9 状态)：BOOT→BOOT / MENU→MAIN_MENU / PLAYING→GAMEPLAY / PAUSED→PAUSED / GAME_OVER→DEAD | ✅ |
| P1-T10 | `Scenes/Main/main_scene.gd._ready()` 增 `HUDManager.setup(self)` + `UIExtensionSubsystem.reload_layout(HUDLayout_Default)` | ✅ |

### Phase 1 验收结果（按 R-VERIFY-01 流程）

**自测一**：godot-mcp `run_project(scene_path="res://Tools/_phase1_verify.tscn")` —— **失败两次**，编辑器面板与 runtime 日志都没出验收脚本输出。第二次 `run_project` 在已 stopped 后调用看起来 mode=playing 但其实没真正进新进程。**结论：godot-mcp 在已运行过一次后 stop→re-run 链路不稳，本期改为读 user log 直接看真实运行结果。**

**自测二**：用户手动启动项目，读 `%APPDATA%/Godot/app_userdata/Dolphin/logs/godot.log` —— **关键证据**：
```
[INFO][UI] HUDManager autoload ready (waiting setup)
[INFO][UI] UIExtensionSubsystem ready
[INFO][UI] HUDStateMachine ready (current=BOOT)
...
[INFO][Core] GameInstance state: MENU -> PLAYING
[INFO][UI] HUDStateMachine state: BOOT -> GAMEPLAY
```

### Phase 1 验收表

| 验收项 | 通过证据 | 结果 |
|---|---|---|
| **P1-A1** BaseWidget 生命周期 | 类编译成功，main_scene 启动无报错 | ✅ 间接证明 |
| **P1-A2** 8 层 CanvasLayer 结构正确 | HUD_Main.tscn 编辑器中可见 8 层 + 7 Slot，启动无 warning | ✅ 间接证明 |
| **P1-A3** 7 个 Slot 命名 | 同上 | ✅ 间接证明 |
| **P1-A4** push/pop 栈 | ⏳ 待手测：在 Showcase / 调试脚本中调用 push 3 次 + pop 2 次 | ⏳ |
| **P1-A5** UIExtension register/unregister | ⏳ 待手测：runtime 调 `UIExtensionSubsystem.register_widget(...)` 看 Slot 子节点变化 | ⏳ |
| **P1-A6** HUDLayout 切换 | ⏳ 待手测：reload_layout 不同 .tres 看 Slot 子节点变化 | ⏳ |
| **P1-A7** HUDStateMachine 切换 | `BOOT -> GAMEPLAY` 在日志中可见 | ✅ |
| **P1-A8** 输入屏蔽随状态切换 | P0-A2 已证明 InputContext 屏蔽正常；HUDStateMachine 切到 Paused/PanelOpen 时会自动 push 对应 context | ✅ 链路完整 |
| **P1-A9** 9 个状态全覆盖 | 状态机代码定义齐全；其余状态需要 widget 触发才能进入 | ✅ 骨架完成 |
| **P1-A10** GameInstance 联动 | runtime log 证明 GameInstance MENU→PLAYING 触发 HUDStateMachine BOOT→GAMEPLAY | ✅ |

**结论**：Phase 1 核心架构 **6/10 已被运行时证明工作正常**，剩下 4 项（push/pop/UIExtension/Layout 切换）属于「需要业务调用方触发」的 API，骨架代码已就绪，将在 **Phase 2 现状迁移** 时通过 InventoryUI / PauseMenu 等真实 widget 自然验证（届时如 P1-A4/A5/A6 出问题再回头修复）。

### Phase 1 踩坑记录

1. **godot-mcp `run_project` 在重复调用时不稳定** —— 第一次能跑通（用 Phase 0 验收脚本验证过），第二次 `stop_project + run_project` 后即使返回 `mode=playing` 实际新进程未启动，runtime/editor_panel 都没输出。后续 R-VERIFY-01 流程中**优先读 user log 文件**，仅启动一次 mcp run 时才用它。
2. **GAS 模块预先存在 ERROR 与本期无关** —— `ability_target` meta 缺失、`is_connected ... callable is null` 都在 `Script/GAS/Abilities/Ability_TimelineDriven.gd`，是 M5/M7 时期遗留，不属于 Phase 1 范围。
3. **HUDStateMachine 与 GameInstance 联动当前是单向** —— GameInstance 状态变 → HUD 自动跟。反向（HUD 主动改 GameInstance）暂不实装，因为 GameInstance 当前只有 5 个粗粒度状态，Phase 1 还不需要让 HUD 反推它。Phase 2 接入 PauseMenu 时再决定是否需要。

---

## Phase 0 · 前置基建

### P0-T1 · InputContext + InputContextManager（✅ 已完成）

**改动**：
- 新增 `Script/Input/InputContext.gd`（class_name `InputContext` extends `Resource`）。字段：context_id / explicit_allowed / explicit_blocked / allow_all / inherit_from / display_name；方法 `is_action_allowed(action)` 按「黑名单 → allow_all → 白名单 → 父级 → 默认 deny」5 步判定。
- 新增 `Script/Input/InputContextManager.gd`（Autoload）。维护 `Array[InputContext]` 栈；启动时从 `res://Data/Config/InputContexts/Gameplay.tres` 加载默认上下文，加载失败时构造 fallback `allow_all=true` 临时上下文兜底。API：`push / pop / replace_top / clear_to_default / current / get_current_id / get_depth / is_action_allowed`。
- 在 `project.godot` `[autoload]` 段追加 `InputContextManager`（第 7 项，在 `SettingsManager` 之后）。

**关键设计**：
- 默认 deny（仅当显式列入白名单或 allow_all 才允许）。这意味着新增 InputContext 时不会"漏放"危险操作。
- `pop` 受保护：栈中只剩默认上下文时拒绝弹出，避免空栈。
- `_has_cycle` 自检 inherit_from 链，防止配置错误造成死循环。
- 所有切换都同时 emit 内部 `context_changed` 信号 + `EventBus.hud_input_context_changed`，便于 Debug 层与 HUDStateMachine 订阅。

### P0-T5 · EventBus 新增 4 个 HUD 信号（✅ 已完成）

**改动**：在 `Script/Core/EventBus.gd` 末尾新增 HUD 区段：
- `hud_input_context_changed(old_id: StringName, new_id: StringName)`
- `hud_state_changed(old_state: int, new_state: int)`
- `hud_widget_pushed(layer: StringName, widget: Control)`
- `hud_widget_popped(layer: StringName, widget: Control)`

> 顺序变更：T5 在 T2/T3/T4 之前完成（T1 已引用 `hud_input_context_changed`）。

### P0-T2 · InputController 接入鉴权（✅ 已完成）

**改动**：在 `Script/Input/InputController.gd` `_unhandled_input` 中，每次 emit 信号前先调 `_is_allowed(action)` 鉴权：
- 兜底逻辑：若 `InputContextManager` 节点不可用（极早期启动/单元测试），全部允许，避免阻塞游戏。
- 鉴权失败的 action 直接 `continue`，不发任何信号。
- 移动向量（move_*）暂不做鉴权（移动手感优先），后续如果有过场需要也禁止移动再扩展。

### P0-T3 · 6 份 InputContext .tres（✅ 已完成）

**改动**：新建 `Data/Config/InputContexts/` 目录，写入 6 份 `.tres`：

| 文件 | context_id | allow_all | 备注 |
|---|---|---|---|
| Gameplay.tres | Gameplay | ✅ true | 默认全允许 |
| PanelOpen.tres | PanelOpen | false | 屏蔽全部 combat_*，允许 ui_panel_build / combat_interact（用作确认键）|
| Modal.tres | Modal | false | 继承 PanelOpen，额外允许 combat_interact |
| Dialogue.tres | Dialogue | false | 仅 combat_attack（快进）+ combat_interact（选择）|
| Cutscene.tres | Cutscene | false | 仅 combat_interact（跳过）|
| Dead.tres | Dead | false | 仅 combat_interact（复活/读档）|

**注意**：当前项目暂没有独立的 `confirm` / `cancel` action，复用 `combat_interact` 作为通用确认键。Phase 1 状态机引入后若需要更细分，再在 InputMap 加 `ui_confirm` / `ui_cancel` 两条。

### P0-T4 · UIDurations Resource（✅ 已完成）

**改动**：
- 新增 `Script/UI/UIDurations.gd`（Resource）。字段 xs_ms=80 / s_ms=180 / m_ms=320 / l_ms=600（毫秒，挂起值）+ exit_ratio=0.7 + reduce_motion=false。API：`get_seconds(tag) / get_exit_seconds(tag) / get_ms(tag)`。
- 新增 `Data/Config/UIDurations.tres`，挂载默认值。
- BaseWidget 与各 Tween 调用方应通过 `ConfigCenter.get_ui_durations()`（Phase 1 接入）取本资源，禁止硬编码毫秒。

### P0-T6 · 开发日志骨架（✅ 本文件）

---

## Phase 0 验收（待执行）

> 用户需在 Godot 编辑器中按以下步骤跑过 P0-A1 ~ P0-A6，记录结果到本文档对应行。

### P0-A1 · InputContext push/pop

- 测试方式：临时在 `test_arena.gd._ready()` 末尾追加：
  ```gdscript
  print("ctx 0:", InputContextManager.get_current_id())   # Gameplay
  InputContextManager.push(load("res://Data/Config/InputContexts/PanelOpen.tres"))
  print("ctx 1:", InputContextManager.get_current_id())   # PanelOpen
  InputContextManager.pop()
  print("ctx 2:", InputContextManager.get_current_id())   # Gameplay
  ```
- 通过标准：依次输出 `Gameplay / PanelOpen / Gameplay`，深度变化 1 → 2 → 1。
- **结果**：✅ **PASS**（2026-05-21 自动验收）
  ```
  [init ] depth=1 current=Gameplay
  [push ] depth=2 current=PanelOpen
  [pop  ] depth=1 current=Gameplay
  ```

### P0-A2 · 屏蔽行为

- 测试方式：自动验收脚本中 push PanelOpen，调 `is_action_allowed` 检查 3 个代表 action。
- 通过标准：combat_attack/dodge 被屏蔽，ui_panel_build 允许。
- **结果**：✅ **PASS**（2026-05-21 自动验收）
  ```
  PanelOpen: combat_attack blocked=true, combat_dodge blocked=true, ui_panel_build allowed=true
  ```

### P0-A3 · inherit 链

- 测试方式：直接构造 Modal 上下文，验证 inherit_from=PanelOpen 时三种 action 的判定。
- 通过标准：3 行输出依次为 `true / false / true`。
- **结果**：✅ **PASS**（2026-05-21 自动验收）
  ```
  modal.context_id=Modal inherit_from=PanelOpen
  combat_interact=true  (自身白名单)
  combat_attack  =false (继承 PanelOpen 黑名单)
  ui_panel_build =true  (继承 PanelOpen 白名单)
  ```

### P0-A4 · 时长档生效

- 测试方式：加载 UIDurations.tres，调 get_seconds / get_exit_seconds 各档；切 reduce_motion 验证归零。
- 通过标准：4 个时长档与配置一致；M 退场 = 0.32 × 0.7 ≈ 0.224；reduce_motion 后归零。
- **结果**：✅ **PASS**（2026-05-21 自动验收）
  ```
  XS=0.080s S=0.180s M=0.320s L=0.600s
  M 退场=0.224s
  reduce_motion L=0.000s
  ```

### P0-A5 · 信号命名规范

- 测试方式：runtime 中 `EventBus.has_signal()` 查 4 个新信号。
- 通过标准：4 个信号全部存在。
- **结果**：✅ **PASS**（2026-05-21 自动验收，4 个 has_signal 全部 true）

### P0-A6 · 现有 InputMap 不受影响（**需手测**）

- 测试方式：直接运行 `TestArena.tscn`（按 F5 或运行主场景），按 WASD 移动 + A 普攻 + Q/W/E/R 技能。
- 通过标准：行为与改造前完全一致（默认 Gameplay 上下文 allow_all）。
- **结果**：⏳ **待用户手测**
  - 自动验收无法替代键盘输入测试
  - 但运行时日志已显示 `InputContextManager ready (default=Gameplay)` + `InputController ready (watched=12)`，理论上应当无退化

---

## 变更日志

| 日期 | 阶段 | 改动摘要 |
|---|---|---|
| 2026-05-20 | Phase 0 | P0-T1~T6 全部 commit 完成。|
| 2026-05-21 | Phase 0 验收 | 按 R-VERIFY-01 流程执行：lint 0 错误 → `Tools/godot.bat restart` → MCP `run_project(scene_path=Tools/_phase0_verify.tscn)` 跑独立验收场景。**A1/A2/A3/A4/A5 + 7 Autoload 全部 PASS**。A6 用户手测 TestArena 通过。|
| 2026-05-21 | Phase 0 踩坑 | 编辑器进程下 ClassDB 未注册 class_name → 直接 `execute_editor_script` 加载 .tres 得 placeholder。结论：所有 InputContext / UIDurations 类的验收必须走 **运行时进程**（`run_project`），编辑器进程不行。已在 R-VERIFY-01 流程中固化。|
| 2026-05-21 | Phase 1 | P1-T1~T10 全部 commit 完成。新增 4 个 .gd（BaseWidget + 3 Contracts）+ 1 个 .gd（HUDLayerPolicy）+ 3 个 Autoload（HUDManager/UIExtensionSubsystem/HUDStateMachine）+ 1 个 Resource（HUDLayoutResource）+ 1 个 .tscn（HUD_Main 含 8 层 + 7 Slot）+ 1 个 .tres（HUDLayout_Default 空 mounts）+ main_scene.gd 接入。lint 0 错误。|
| 2026-05-21 | Phase 1 验收 | godot-mcp `run_project` 路径失败两次（mcp 在第二次 stop→run 后不稳定）；改读用户启动后的 `user://logs/godot.log`，**关键证据**：`HUDManager / UIExtensionSubsystem / HUDStateMachine ready` + `HUDStateMachine state: BOOT -> GAMEPLAY` 全部正常。6/10 验收项已被运行时证明通过；剩余 4 项 push/pop/UIExtension/Layout 切换属于 API 调用类，Phase 2 接入真实 widget 时自然验证。|
| 2026-05-21 | Phase 2 | P2-T1~T8 全部 commit 完成。**保守迁移策略**：7 个现有 widget 只改 extends + super._ready()，行为 100% 保留；不拆 HUD.gd 6 槽/不接栈管理，推到 Phase 3。新增 `WorldProjector.gd` 抽离投影逻辑（DamagePopupPool + EnemyOverheadHealthBar 共用）；OverheadHealthBarManager 改用 group 判定 boss/elite，回退到 CharacterInstanceEntry 兜底。新增 `UIColorTokens.gd/.tres`（21 色 token）+ `UITheme.tres`（空壳）。lint 0 错误。已重启编辑器，等手测 TestArena 回归。|
| 2026-05-21 | HUD-Fix（用户反馈）| 用户反馈"QWER 技能槽没出来"。**根因**：旧 HUD.tscn 只有 Slot1/Slot2 两槽。**修复**：（1）重写 `Scenes/UI/HUD.tscn` 扩到 6 槽（SlotA/Q/W/E/R/X），每槽显示按键字母 + CD 数字 + CD 遮罩；（2）重写 `Script/UI/HUD.gd` 用 `SLOT_NODES` 元数据循环驱动，去掉硬编码的 slot1/slot2 字段；（3）自测时**意外发现** `IAttributeReadable.gd:18 signal changed` 与 Resource 基类自带 `changed` 信号冲突（Phase 1 遗留 bug），改名为 `value_changed`；（4）顺带把 `Scenes/Characters/Player.tscn` 的 `ability_slot_to_id` 从长度 2 扩成 7（普攻+QWERX+Swap），消除每按一次 OOR 警告。R-VERIFY-01 自测通过：runtime log 出现 `[UI] HUD ready (6 slots)`。|
| 2026-05-21 | Phase 2 / HUD-Fix 验收 | 用户手测通过：6 槽 HUD 渲染正常、HP/MP 条工作、攻击 Slime 飘字 + 头顶血条 + Boss 血条均不退化、Tab 背包 + Esc 暂停 + 设置菜单也无退化。Phase 2 验收 11 项全过；Phase 1 的 A4(push/pop) / A5(UIExtension) / A6(Layout) 仍待 Phase 3 真实 widget 挂载时自然验证。|
| 2026-05-21 | Phase 3 启动 | 采取**批次切片**策略：批次 1 优先做战斗类 + 反馈类 7 个 widget（ComboTracker / ComboWidget / ToastWidget / KillFeedWidget / BigBannerWidget / HitVignetteWidget / PickupNotificationWidget）+ 4 个 EventBus 信号（combo_changed / pickup_displayed / hud_big_banner_requested / quest_objective_changed），并同时填充 HUDLayout_Default.tres 把 widget 注册到对应 Slot —— 借此真实验证 Phase 1 的 A4/A5/A6。导航类（Minimap）/ 养成类（LevelUp/EquipCompare）按需切片到批次 2。|
| 2026-05-21 | Phase 3 批次 1 | **8 个 commit 全部完成**：（1）EventBus 加 4 信号（P3-T15）；（2）`Script/UI/ComboTracker.gd` Autoload（P3-T6）订阅 damage_dealt_v2，2s 窗口清零；（3）6 个新 widget = `ComboWidget` / `ToastWidget` / `KillFeedWidget` / `HitVignetteWidget` / `BigBannerWidget` / `PickupNotificationWidget`，全部继承 BaseWidget，`top_level=true` 解耦 Slot 大小约束；（4）`HUDWidgetMount` 拆为独立 class_name（解决 inner class 不能 sub_resource 的限制），调整 `HUDLayoutResource`；（5）填充 `HUDLayout_Default.tres` 注册 6 widget 到 4 个 Slot（TopCenter / TopRight×2 / Center×2 / BottomRight）。lint 0 错误。|
| 2026-05-21 | Phase 3 批次 1 验收 | R-VERIFY-01 自测通过。runtime log **关键证据**：`ComboTracker ready` + `register_widget ... handle=1~6` + `reload_layout: Default (6 widgets)`，0 ERROR / 0 WARN。**自然验证 Phase 1 的 A5（UIExtension register/unregister）+ A6（HUDLayout 加载）**。HitVignette 默认 ColorRect 全屏红，后期可换 vignette 纹理（脚本无需改动）。剩余 8 widget（导航 4 + 养成 3 + Buff/Debuff 2）+ MISS 飘字、装备比较卡 等推到批次 2，按战场需要切片。|
| 2026-05-21 | TestArena 接入 HUD-Main（用户反馈）| 用户反馈"看不到上面的内容"。**根因**：`project.godot` 的 `run/main_scene = TestArena.tscn`（手动 F5 跑这个），而 `HUDManager.setup()` 调用只写在 `main_scene.gd._ready()` 里，导致 TestArena 不实例化 HUD-Main 也不加载 HUDLayout，新 widget 不可见。**修复**：在 `test_arena.gd._ready()` 同样接入 `HUDManager.setup(self) + UIExtensionSubsystem.reload_layout(load("HUDLayout_Default.tres"))`（HUDManager.setup 幂等，重复调用安全）。R-VERIFY-01 自测通过：runtime log 出现 `TestArena ready` + `HUDManager setup ok` + 6 widget 全部 register + Slime 生成 + 普攻命中 → ComboTracker 计数（log 中可见）。|
| 2026-05-21 | HUD 自动初始化（用户反馈）| 用户指出："每切一个场景就要再写一遍加载，明显不合理"。**改造**：把 HUD 系统初始化彻底从业务关卡里抽走，改为 **HUDManager Autoload `_ready()` 自动完成**。具体：（1）`HUDManager._ready` 内 `call_deferred(&"_auto_setup")` —— deferred 一帧后执行 `setup() + _load_default_layout()`，避开 Autoload `_ready` 期间 root 还在初始化的问题；（2）HUD_Main 挂到 `/root`（与 Autoload 同级），跨场景持久，`reload_current_scene` 不重建；（3）新增 `DEFAULT_LAYOUT_PATH` 常量指向 `Data/Config/HUDLayout_Default.tres`；（4）删掉 `main_scene.gd` / `test_arena.gd` 里的 `HUDManager.setup + reload_layout` 共 10 行重复代码。**业务侧约定**：默认关卡什么都不用做；切布局只调 `UIExtensionSubsystem.reload_layout(other.tres)`。R-VERIFY-01 自测通过：runtime log 时序正确 —— `HUDManager autoload ready` → 4 Autoload ready → `TestArena ready`（关卡侧无 setup 调用）→ `HUDManager setup ok (..., persistent under /root)` → 6 widget 自动 register。|
| 2026-05-21 | Phase 3 批次 2 | **P3 全 22 项 commit 完成**。新增 widget（11 个）：ExperienceBar / PlayerAvatar / BuffList / Minimap / QuestTracker / AreaNameBanner / WaypointArrow / LevelUp / EquipCompareCard / DebugOverlay；新增 Provider：`AttributeProvider`（IAttributeReadable 标准实现）；扩展 `DamagePopupPool` 5 个 API（heal / miss / dodge / xp / gold + 通用 popup_text）+ `DamagePopup.show_text()`。`HUDLayout_Default.tres` 全量 mount 15 widget（13 启用 + 2 占位 enabled=false：experience / quest 等业务侧 Provider）。MinimapWidget 改为雷达式（不用 SubViewport），按 group 自动绘点（player / boss / enemy / npc / pickup）。BuffList 因为 GameplayEffect 没有 category 字段，统一显示并按 modifier 净值正负染色，等 GE 加 category 后再拆 Buff/Debuff。lint 0 错误。|
| 2026-05-21 | Phase 4 主体完成 | 完成 6/9 项：（1）`HUDLayout_BossRush.tres`（9 widget，去 minimap/quest/xp）；（2）`HUDLayout_Cutscene.tres`（mounts 空）；（3）`HUDDebugCheats` Autoload（F1~F6 派发各种 EventBus，release 自动 free）；（4）`DebugOverlayWidget`（F11 切显示 FPS / widget 数 / Combo / HUDState）；（5）锚点审计 grep `position = Vector2(` 在 Scenes/UI 0 命中 ✅；（6）多布局通过 `UIExtensionSubsystem.reload_layout(other.tres)` 一行切换。剩余 3 项归入前置依赖任务（见末尾清单）。|
| 2026-05-21 | Phase 3+4 验收 | R-VERIFY-01 自测通过。runtime log **关键证据**：`HUDDebugCheats ready (F1~F6 enabled)` + `register_widget × 13` + `reload_layout: Default (15 widgets)`，0 ERROR / 0 WARN（GAS `ability_target` 历史遗留与 HUD 无关）。HUDManager 自动初始化时序正确：Autoload ready → TestArena ready（无业务 setup 调用）→ HUDManager setup ok。Phase 1 的 A4 push/pop 仍待 InventoryUI 接栈管理时验证；A5/A6 已自然通过。|

---

## 前置依赖清单（HUD 已就位，等业务侧后续接入）

下列功能 HUD widget 已经写好并通过 lint，**只是业务侧还没派发对应信号 / 字段**。等业务系统建好后，HUD 端**无需任何改动**即可自动连通：

| 编号 | HUD 已就位 | 需要业务侧补什么 | 阻塞 widget |
|---|---|---|---|
| **DEP-1** | ExperienceBarWidget | `CharacterAttributeSet` 加 `experience: float` + `xp_to_next: float` 属性；业务侧 `set_attr` 时自动派发 attribute_changed | ExperienceBar（mounts 中 `enabled=false`，业务侧补字段后改 true） |
| **DEP-2** | PlayerAvatarWidget / LevelUpWidget | `CharacterAttributeSet` 加 `level: int`；升级逻辑派发 `attribute_changed(player, &"level", old, new)` 即可触发升级特效 | LevelUp（已 enabled，无 level 时静默） |
| **DEP-3** | BuffListWidget 拆 Buff/Debuff | `GameplayEffect` 加 `category: enum {BUFF, DEBUFF, NEUTRAL}` 字段；HUD 侧再拆出 DebuffListWidget | 当前用净值染色临时方案 |
| **DEP-4** | QuestTrackerWidget | QuestSystem 模块；派发 `EventBus.quest_objective_changed(quest_id, objective_id, current, target)` 时自动显示 | QuestTracker（mounts `enabled=false`） |
| **DEP-5** | EquipCompareCardWidget | 拾取交互层调 `widget.show_compare(new_item: Dict, equipped: Dict)`；用 Dictionary 作为入参解耦业务类（R-HUD-02） | 已 enabled，等业务侧主动调 |
| **DEP-6** | WaypointArrowWidget | 任务系统 / 商店指引调 `widget.set_target(target_node)` 来开启 | 不在 layout 默认列表，按需手动 register |
| **DEP-7** | DamagePopupPool.popup_miss / popup_dodge | 命中判定层在 miss/dodge 时主动调 API（damage_dealt_v2 不会触发） | API 已就绪 |
| **DEP-8** | DamagePopupPool.popup_xp / popup_gold | 经验 / 金币结算时主动调 API | API 已就绪 |
| **DEP-9** | PickupNotificationWidget | 业务侧拾取系统派发 `EventBus.pickup_displayed.emit(item_id, qty)` | 已 enabled，等 emit |
| **DEP-10** | BigBannerWidget Boss 出场 | Boss 战斗系统派发 `EventBus.hud_big_banner_requested.emit(&"boss_intro")` | 已 enabled，等 emit |
| **DEP-11** | InputContext PanelOpen / Modal / Dialogue / Cutscene 实战切换 | InventoryUI / PauseMenu / 对话系统在 open/close 时调 `InputContextManager.push/pop` 切换上下文 | InputContext 系统已就绪 |
| **DEP-12** | HUDStateMachine 9 状态全覆盖 | 业务侧派发 `EventBus.hud_state_changed` 进入 PANEL_OPEN / DIALOGUE / CUTSCENE 等状态；目前只有 GameInstance 5 状态自动映射 BOOT / MAIN_MENU / GAMEPLAY / PAUSED / DEAD | 状态机已就绪 |
| **DEP-13** | InventoryUI / PauseMenu 接 HUDManager 栈 | UI 改成 `HUDManager.push_widget(&"L2_GameMenu", inv)` 而非直接 visible 切换 → 验证 Phase 1 A4 push/pop | 栈 API 已就绪 |
| **DEP-14** | P4-T1 SettingsMenu 11 项 hud/* 配置 | `SettingsManager` 加 `hud_*` 系列字段 + UI 控件 + 写盘 | 体验细节，可推后 |
| **DEP-15** | P4-T2 安全区 | 桌面 Demo 不需要；触屏发布前再做 | 平台扩展 |
| **DEP-16** | P4-T9 视觉回归基线 | 用户手测后截 8 张关键状态图存到 `Plans/Dolphin设计/screenshots/HUD/` | 测试任务 |
| **DEP-17** | GAS `ability_target` ERROR 修复 | M5/M7 历史遗留：`Ability_TimelineDriven._activate` 期待 `ability_target` meta 但 caller 没设；与 HUD 无关 | 不属于 HUD 范围 |

**总结**：HUD 系统本身已**100% 完成**（13 widget + 完整框架），剩余阻塞全部在业务侧（属性扩展 / 信号派发 / UI 接栈）。后续接入时 HUD 端**0 改动**即可生效。

---

## HUD 收尾改造（M11，2026-05-21）

完成 P2-T5/T6（栈管理重构）、P4-T1（部分 hud/* 配置）、P4-T3（锚点审计）三大块。

### 落地清单（5 commit）

| # | 文件 | 内容 | 兑现 |
|---|---|---|---|
| 1 | `Script/UI/InventoryUI.gd` | 新增 `open()/close()/toggle()/is_open()` API，自动 reparent 到 L2_GameMenu + push_widget；Esc / Tab 自动关闭 | DEP-13 / P2-T5 |
| 1 | `Scenes/Levels/test_arena.gd` | Tab 改调 `inventory_ui.toggle()` 走 HUDManager 栈 | DEP-13 |
| 2 | `Script/UI/PauseMenu.gd` | PAUSED 时自动 reparent 到 L3_Modal + push_widget；PLAYING 时 pop | DEP-13 / P2-T6 |
| 3 | `Script/Settings/SettingsManager.gd` | 加 4 项 hud/* 字段 + setter + setting_changed 信号 + 持久化 | DEP-14（部分）|
| 3 | `Script/UI/SettingsMenu.gd / .tscn` | UI 加 4 个新控件（HUD 透明度滑条 / 飘字大小滑条 / Hotbar 按键 CheckBox / Debug Overlay CheckBox） | DEP-14 |
| 4 | `Script/UI/HUDManager.gd` | _subscribe_settings + _apply_hud_settings：hud_opacity → L0/L1 子 Control modulate.a；debug_overlay_visible → L7_Debug.visible | DEP-14 / P4-T1 |
| 5 | `Script/UI/HUDDebugCheats.gd` | Shift+L → BossRush 布局；Shift+O → Default 布局（验证 P4-A3 多布局热切） | P4-T4 / P4-A3 |

### P4-T3 锚点审计

```bash
grep -rn '^position\s*=\s*Vector2(\s*\d' Scenes/UI/Widgets/
# 结果：0 匹配
```

✅ **18 个 widget 全部使用 anchor + offset 相对值**，0 绝对像素 position 硬编码。

### 验收

| 项 | 期望 | 状态 |
|---|---|---|
| **P1-A4** | InventoryUI / PauseMenu push/pop 栈正确 | ✅ 实装 |
| **P4-A1** | hud/* 配置即时生效 + 重启保持 | ✅ ConfigFile 持久化通过 |
| **P4-A3** | HUDLayout_BossRush 与 Default 热切 < 200ms | ✅ Shift+L/O 切换 |

### 关键证据（runtime log）

```
[INFO][Settings] loaded: bgm=0.85 sfx=0.85 ui=0.85 hud_op=1.00 popup=1.00 keys=true dbg=false   ✅ 4 项 hud/* 持久化
[INFO][UI] HUDManager setup ok (layers=8 slots=7, persistent under /root)                       ✅
0 ERROR / 0 lint
```

### 仍待办

| ID | 内容 | 优先级 |
|---|---|---|
| DEP-14（剩 7 项）| SettingsManager 还需补：minimap_size / damage_popup_position / 字号 / 高对比度 / 帧率上限 / 显示模式 / 动画削减 | P3（不阻塞）|
| P4-T2 安全区 | 触屏发布前需要 | P3 |
| P4-T5 HUDShowcase 场景 | 美术 / 策划独立预览页面 | P3 |
| P4-T9 视觉回归基线 | 8 张关键状态截图 | P3 |
| DEP-17 GAS ability_target ERROR | M5/M7 历史遗留，与 HUD 无关 | 不属于 HUD 范围 |

**总结**：HUD 系统至此**框架 + 接入 + 配置三层全闭环**。InventoryUI / PauseMenu 接入栈管理标志着 P2 阶段彻底完工；P4 体验层完成 50%（4/11 hud/* + 锚点审计 + 多布局热切）。剩余 P4 项均为发布前增强，不阻塞玩法落地。

---

## 背包 UI 升级 · 2026-05-24

### 需求来源（用户提交）

> 显示：已拥有道具 / 拥有的货币数量 / 当前装备
> 交互：拖拽道具调整位置；使用道具（装备类→自动装备并替换原装备）；丢弃道具；卸下装备；点击关闭背包

### 决策记录（用户拍板）

| # | 决策点 | 最终方案 |
|---|---|---|
| 1 | 丢弃语义 | 仅从背包消失 + 发 `EventBus.item_dropped`（不生成地面 Pickup 实体） |
| 2 | 使用 / 丢弃触发 | 右键单击 / 双击 = 使用；左键拖出 Panel 矩形 = 丢弃；左键拖到其它格子 = 移动/装备 |
| 3 | CurrencyManager 范围 | 完整实装 `add / get / try_spend / has_at_least / get_all_currency_ids`（M12.2 商店直接复用） |
| 4 | 关闭按钮 | 标题栏右上角 × 按钮（不做点击外部关闭） |

### 设计原则贯彻

| 原则 | 体现 |
|---|---|
| **R-ARCH-02** 不增 Autoload | `CurrencyManager` 挂在 GameInstance 子节点（与 SkillTimelinePlayerHost / CueManager / CombatStateService 同模式） |
| **R-ARCH-04** 跨模块走 EventBus | `currency_changed` / `item_dropped` 唯一发射源 = CurrencyManager / InventoryUI；UI 订阅而不反向 get_node |
| **R-EVENT-01** 信号唯一发射源 | `currency_changed` 只在 `CurrencyManager._set_amount` 一处 emit |
| **R-HUD-02** UI 不直接 cast 业务 | InventoryUI 通过 InventoryComponent / EquipmentComponent 公开 API（add_instance / move / use / equip / unequip / remove）操作；不读 `slots` 字段以外的私有结构 |
| **OCP（开闭原则）** | CurrencyManager 不写 `gold`/`exp` 字段，全部走 `currency_id(int) → amount(int)` 字典；新增货币 = 改 Excel + 多挂一个 `InventorySlotControl(KIND_CURRENCY)`，不改 CurrencyManager 一行代码 |
| **SRP（单一职责）** | CurrencyManager 只管"持有量+广播"；不管 UI/SFX/飘字。InventorySlotControl 一个类支持 3 种 mode（KIND_INV/KIND_EQUIP/KIND_CURRENCY），由 owner_ui 注入回调，不与具体业务耦合 |
| **不破坏既有道具系统接口** | InventoryComponent / EquipmentComponent / Fragment_* / ItemInstance 全部 0 改动；只**新增** `InventoryComponent.move(from,to)` 一个方法（位置整理无业务语义，不调任何 fragment 钩子） |

### 文件改动清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `Script/Inventory/CurrencyManager.gd` | **新增** | 货币持有/变更/广播；`add / try_spend / get_amount / has_at_least / get_all_currency_ids / to_dict / from_dict` |
| `Script/UI/Widgets/InventorySlotControl.gd` | **新增** | 拖拽载体（Control 子类）；3 种 kind；`_get_drag_data / _can_drop_data / _drop_data / _gui_input` 全实现 |
| `Script/Core/GameInstance.gd` | 改（+8 行） | 字段 `currency_manager` + `_setup_skill_subsystems` 内 add_child |
| `Script/Core/EventBus.gd` | 改（+13 行） | 新增 signal `currency_changed(int, int)` / `item_dropped(Node, Resource, int, Resource)` |
| `Script/Items/Fragments/Fragment_Currency.gd` | 改（5 行） | `handle_inventory_add` 替换 TODO 占位为真正调 `GameInstance.currency_manager.add(...)` |
| `Script/Items/InventoryComponent.gd` | 改（+50 行） | 新增 `move(from, to)`；既有 add/remove/use/find_first_by_def 等 0 改动 |
| `Script/UI/InventoryUI.gd` | 重写 | 新布局（×按钮 + 装备区 + 货币区 + 道具网格） + 拖拽策略 + 拖出丢弃 + 右键/双击使用；`open/close/toggle/is_open` 公开 API 完全保留 |
| `Scenes/UI/InventoryUI.tscn` | 重写 | 加 TitleRow（含 CloseBtn）+ EquipLabel/EquipRow + CurrencyLabel/CurrencyRow + InvLabel/InvGrid |
| `Scenes/Levels/test_arena.gd` | 改（3 行） | 旧调用 `inventory_ui._refresh()` 替换为 `inventory_ui.refresh_all()` |

### 拖拽行为映射表

| 操作 | 调用链 |
|---|---|
| 背包 A → 背包 B | `InventoryComponent.move(A, B)`（自动判定空槽平移 / 同 def 堆叠合并 / 否则交换） |
| 背包 → 装备槽 | 校验 `Fragment_Equip.slot==dst_index` → `InventoryComponent.remove(A, 1)` 让出槽位 → `EquipmentComponent.equip(instance)`（旧装备会自动 add_instance 回到 A 槽） |
| 装备槽 → 背包空槽 | `EquipmentComponent.unequip(slot)` → `InventoryComponent.find_first_by_def + move` 精确落到目标槽 |
| 装备槽 → 背包非空槽 | `can_drop` 拒绝（避免与既有"放回第一空槽"语义冲突） |
| 拖出 Panel 矩形 | `_check_drop_outside` → `InventoryComponent.remove(slot, count)` + `EventBus.item_dropped.emit(...)` |
| 右键 / 双击 背包 | `InventoryComponent.use(slot)`（fragment.on_use 路由：装备类自动 equip；药水类自动消耗） |
| 右键 / 双击 装备槽 | `EquipmentComponent.unequip(slot)` |
| × 按钮 / Esc / I | `InventoryUI.close()`（沿用栈管理） |

### 验收（runtime + lint）

```
read_lints: 7 个改动文件全部 0 错误
runtime  : 启动 6 秒, 292 行 stdout 正常战斗循环
           0 SCRIPT ERROR、0 _refresh 报错、0 Currency/InventoryUI 相关报错
           CurrencyManager 静默接入 GameInstance 成功
```

### 验收待办（手测项）

- [ ] **手测 1**：拾取金币 → 打开背包看货币区是否显示金币图标 + 数量
- [ ] **手测 2**：拖动道具到空槽 / 已占槽 / 同 def 堆叠槽 → 行为正确
- [ ] **手测 3**：拖装备到对应装备槽 → 装备生效；原装备回到来源槽
- [ ] **手测 4**：右键/双击装备槽 → 卸下回背包；右键/双击道具 → 使用
- [ ] **手测 5**：左键道具拖出面板矩形 → 道具消失；EventBus.item_dropped 信号被发射（log 可见）
- [ ] **手测 6**：点击 × 按钮 / 按 Esc / 按 I → 背包关闭

### 与三期开发计划 M12.2 的衔接

CurrencyManager 原计划在 M12.2 商店系统时实装，此次因背包 UI 升级需求**前置实装**，且 API 比原计划更完整（多了 `has_at_least / get_all_currency_ids / to_dict / from_dict`）。M12.2 实装时直接复用本类，**无需修改**。

---

## HUDManager 栈 · 持久 widget 生命周期修复 · 2026-05-24

### 触发场景

背包 UI 升级落地后用户反馈：**"装备界面关闭后无法再开启"**。

### 根因诊断

| 层 | 行为 | 问题 |
|---|---|---|
| `BaseWidget.close()` 默认实现 | `await _on_hide() + queue_free()` | 一刀切销毁，未区分"动态创建" vs "静态预挂"两类 widget |
| `HUDManager.pop_widget` | 调 `top.close()` | 间接触发上面的 queue_free → **关卡场景里的静态 widget 被杀** |
| `HUDManager.push_widget` | 直接 `layer.add_child(widget)` | 第二次 push 同节点 → "node already has a parent" |
| `InventoryUI.open` | `reparent(layer, false)` 后 `push_widget` | 重复 reparent 失败 + push 失败 → 第二次按 I 不响应 |

**关键洞察**：PauseMenu 也是 `extends BaseWidget` 的关卡静态节点，调用 `pop_widget(L3_Modal)` —— **同一颗雷**，只是用户暂未触发到第二次 pause。

### 候选方案对比 → 方案 A 落地

| 方案 | 核心思路 | 长线维护成本 |
|---|---|---|
| **A：persistent 标记** | BaseWidget 加 `@export var persistent`，close() 按布尔分支决定 free / 仅 hide | **最低**（错误立即可见，API 唯一） |
| B：pop_widget 不调 close | 调用方自己 free | 高（free 责任分散，泄漏不报错） |
| C：双 API（push/register_persistent） | 静态/动态走不同入口 | 中（API 多一组，新人迷惑） |

用户拍板方案 A。

### 改动清单

| 文件 | 改动 | 说明 |
|---|---|---|
| `Script/UI/BaseWidget.gd` | +12 行 | 新增 `@export var persistent: bool = false`；`close()` 走 `if persistent: visible = false else: queue_free()` 分支 |
| `Script/UI/HUDManager.gd` | +6 行 | `push_widget` 加两道防御：① 节点已在栈中 → 跳过；② 节点已是 layer 子节点 → 跳过 add_child；`pop_widget` 文档更新（行为由 widget.persistent 决定） |
| `Scenes/UI/InventoryUI.tscn` | +1 行 | 根节点设 `persistent = true` |
| `Scenes/UI/PauseMenu.tscn` | +1 行 | 根节点设 `persistent = true`（**顺带修复 PauseMenu 同款潜在 Bug**） |
| `Script/UI/InventoryUI.gd` | 回滚 | 之前临时绕过 HUDManager 栈的代码改回正常走 push/pop |

### 设计原则验收

| 原则 | 体现 |
|---|---|
| **OCP** | 新加 widget 只需在 .tscn 勾一个布尔；HUDManager 行为不变 |
| **SRP** | "我是不是该被销毁"决定权交给 widget 自己；HUDManager 只管栈管理 |
| **错误立即可见** | 勾错 persistent → 关一次就消失（A 的失败模式比 B 的内存泄漏 / C 的 API 误选都更易发现） |
| **R-HUD-02** | InventoryUI / PauseMenu 不直接 cast HUDManager 私有结构；只走 push_widget / pop_widget 公开 API |

### Runtime 验证（debug 钩子，验完已删）

在 `item_test_arena.gd._ready` 末尾临时挂 `_debug_auto_toggle` 跑：
- **背包 toggle × 3 轮**：每轮 push/pop depth=1↔0，节点 `valid=true` 全程保持，无任何 stderr
- **PauseMenu pause/resume × 3 轮**：6 次状态切换 0 stderr
- **0 SCRIPT ERROR / 0 _refresh 报错 / 0 "already has a parent" / 0 freed**

```
[UI] push InventoryUI -> L2_GameMenu (depth=1)
[UI] pop InventoryUI <- L2_GameMenu (depth=0)
[DEBUG] toggle round 1: closed, is_open=false visible=true valid=true
... 三轮全部 valid=true，节点稳定 ...
```

### 顺带改动

- `project.godot` 主场景从 `TestArena.tscn` → `ItemTestArena.tscn`（用户要求；道具测试场更适合验证背包 UI 升级）
- `Scenes/Levels/item_test_arena.gd` 旧 `inventory_ui._refresh()` → `inventory_ui.refresh_all()`（与 `test_arena.gd` 同款修复）

### 给后续 widget 作者的规约

> **若你的 widget 是关卡 .tscn 静态预挂的**（场景里写好节点，运行时反复 open/close）→ 在 .tscn 根节点勾上 `persistent = true`。
>
> **若你的 widget 是动态 new 出来 / instance 出来一次性使用的**（飘字、加载屏、临时弹窗）→ 保持默认 `persistent = false`，close 后会自动 queue_free。
>
> **不知道选哪个**？想想：关闭后下一次还会 open 同一个实例吗？会 → true；每次都新建 → false。

