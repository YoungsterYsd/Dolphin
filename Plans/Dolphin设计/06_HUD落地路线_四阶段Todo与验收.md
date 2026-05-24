# 06 · HUD 落地路线 / 四阶段 Todo 与验收清单

> **文档定位**：把 `05_系统框架_HUD设计_Dolphin适配.md` / `HUD策划案.docx` 的设计内容，拆成可交付的 commit 级 Todo，并给出每一项的验收内容与验收表。
> **状态**：路线锁定；具体毫秒值 / 颜色 / 像素挂起。
> **生成日期**：2026-05-20
> **建议节奏**：Phase 0 → 1 → 2 必须打包完成，Phase 3 可按战场需要切片，Phase 4 收尾。

---

## 0. 路线总览

| 阶段 | 名称 | 工作量 | 必做 | 输出 |
|---|---|---|---|---|
| **Phase 0** | 前置基建 | 2~3d | ✅ 必做 | InputContext 系统 + 时长档定义 |
| **Phase 1** | 核心架构 | 6~8d | ✅ 必做 | BaseWidget / HUDManager / HUDStateMachine / UIExtensionSubsystem |
| **Phase 2** | 现状迁移 | 3~4d | ✅ 必做 | 7 个现有 widget 接入新架构，行为不退化 |
| **Phase 3** | 元素补全 | 5~7d | ⭕ 可切片 | 战斗 / 反馈 / 导航 / 养成 类元素 |
| **Phase 4** | 完善与验收 | 1~3d | ⭕ 收尾 | 设置 / 适配 / Showcase / 验收清单跑通 |

> **里程碑约束**：Phase 0+1+2 共 ≈ 10~13d 必须打包完成；中间态（一半新一半旧）维护成本高于纯旧版。

---

## Phase 0 · 前置基建（2~3d）

> **存在原因**：`05` 策划案的状态机 + 输入屏蔽 + 动画时长档，依赖两个项目当前没有的基础设施。Phase 0 不写 HUD 业务，只补地基。

### 0.1 Todo 清单（commit 级）

| # | Todo | 类型 | 工作量 | 交付 |
|---|---|---|---|---|
| **P0-T1** | 新增 `Script/Input/InputContext.gd`（Resource）+ `Script/Input/InputContextManager.gd`（Autoload）。InputContext 携带：context_id / allowed_actions: StringName[] / blocked_actions: StringName[] / inherit_from: InputContext。Manager 维护 InputContext 栈，对 `InputController` 暴露 `is_action_allowed(action)` 查询。 | 新增 | 1d | 2 个 .gd + Autoload 注册 |
| **P0-T2** | 改造 `Script/Input/InputController.gd`（如果还没有则在派发 `EventBus.player_input_action_pressed/released` 时先调用 `InputContextManager.is_action_allowed`，被屏蔽的 action 直接 drop 不发信号。 | 改造 | 0.5d | InputController.gd 改造 |
| **P0-T3** | 新增 `Data/Config/InputContexts/` 目录，建 6 份 `.tres`：`Gameplay`（默认全允许）、`PanelOpen`（仅 UI 导航）、`Modal`（仅 confirm/cancel）、`Dialogue`（仅 dialogue_skip / cancel）、`Cutscene`（仅 skip）、`Dead`（仅 confirm 用于复活）。 | 配置 | 0.5d | 6 份 .tres |
| **P0-T4** | 新增 `Script/UI/UIDurations.gd`（Resource）：定义动画时长档 XS/S/M/L 的具体毫秒值。落库到 `Data/Config/UIDurations.tres`。在 BaseWidget / Tween 工具里走它。 | 新增 | 0.5d | 1 个 .gd + 1 份 .tres |
| **P0-T5** | 在 `EventBus.gd` 新增信号：`hud_input_context_changed(old:StringName, new:StringName)` / `hud_state_changed(old:int, new:int)` / `hud_widget_pushed(layer:StringName, widget:Control)` / `hud_widget_popped(layer:StringName, widget:Control)`。 | 改造 | 0.2d | EventBus 加 4 信号 |
| **P0-T6** | 新增 `Plans/Dolphin设计/HUD开发日志.md`，记录每个 commit 的改动与现状。 | 文档 | 0.3d | 开发日志骨架 |

### 0.2 验收内容

- [ ] InputContext 栈 push/pop 行为正确：栈顶决定当前生效的允许列表。
- [ ] `inherit_from` 链能向上继承：子 context 只声明差异。
- [ ] 在 6 种 InputContext 下，`InputController` 的派发行为符合预期（用单元脚本验证）。
- [ ] UIDurations 4 档在 Tween 调用处可读取并生效。
- [ ] 4 个新信号在 EventBus 中可订阅，参数类型与命名遵循 R-EVENT-01 / R-NAME-01。

### 0.3 验收表

| 验收项 ID | 验收点 | 测试方式 | 通过标准 |
|---|---|---|---|
| P0-A1 | InputContext push/pop | 写一段 GDScript 临时脚本 push Gameplay → PanelOpen → pop 还原 | `InputContextManager.current.context_id` 跟随栈顶变化 |
| P0-A2 | 屏蔽行为 | 在 PanelOpen 下按 `combat_attack` | `EventBus.player_input_action_pressed` 不发射，日志能看到 drop |
| P0-A3 | inherit 链 | Modal 继承 PanelOpen，添加 confirm | Modal 下既有 PanelOpen 允许的 action，又有 confirm |
| P0-A4 | 时长档生效 | 取 `UIDurations.S` 喂给 `create_tween()` | Tween 时长 = 配置毫秒（误差 < 1ms） |
| P0-A5 | 信号命名规范 | `grep -nE "(hud_input_context|hud_state|hud_widget)"` | 4 个信号全部找到，命名为 snake_case 过去式 |
| P0-A6 | 现有 InputMap 不受影响 | 启动战斗关，按 WASD/QWER | 与改造前完全一致（默认 Gameplay context） |

---

## Phase 1 · 核心架构（6~8d）

> **存在原因**：搭建 HUD 系统的"骨架"。完成后所有后续 widget 都按统一规则挂载。

### 1.1 Todo 清单（commit 级）

| # | Todo | 类型 | 工作量 | 交付 |
|---|---|---|---|---|
| **P1-T1** | 新增 `Script/UI/BaseWidget.gd`（class_name BaseWidget extends Control）：字段 widget_id / data_provider / input_mode / pause_policy / visible_in_pause / theme_resource。钩子 `_on_show / _on_hide / bind_data / refresh`。内置可选 `AnimationPlayer` 自动播 show/hide。 | 新增 | 1d | BaseWidget.gd |
| **P1-T2** | 新增三份 Contract Resource：`Script/UI/Contracts/IAttributeReadable.gd`、`IWorldAnchored.gd`、`ICooldownReadable.gd`，定义最小接口与 `changed` signal。 | 新增 | 0.5d | 3 个 .gd |
| **P1-T3** | 新增 `Script/UI/HUDLayerPolicy.gd`（Resource）：layer_id / canvas_layer_index / visible / input_mode / pause_policy / enable_stack / fade_in_duration / fade_out_duration / follow_camera / debug_only。 | 新增 | 0.3d | HUDLayerPolicy.gd |
| **P1-T4** | 新增 `Script/UI/HUDManager.gd`（Autoload，**第 7 项**）：维护 8 层 CanvasLayer 节点字典 + 每层 widget 栈数组 + LayerPolicy 字典。API：`setup / push_widget / pop_widget / get_top_widget / clear_layer / apply_layer_policy`。 | 新增 | 1.5d | HUDManager.gd + 注册到 project.godot |
| **P1-T5** | 新增 `Scenes/UI/HUD_Main.tscn`：8 层 CanvasLayer（L0~L7）+ L1 内置 7 个命名 Slot（TopLeft/TopCenter/TopRight/BottomLeft/BottomCenter/BottomRight/Center）。每个 Slot 是空 Control + 锚点 + MarginContainer。 | 场景 | 1d | HUD_Main.tscn |
| **P1-T6** | 新增 `Script/UI/UIExtensionSubsystem.gd`（Autoload，**第 8 项**）：`register_widget(slot_tag, scene, priority) -> handle` / `unregister_widget(handle)` / `reload_layout(layout_res)`。维护 slot → ExtensionEntry[] 字典。 | 新增 | 1d | UIExtensionSubsystem.gd |
| **P1-T7** | 新增 `Script/UI/HUDLayoutResource.gd`（Resource）+ `Data/Config/HUDLayout_Default.tres`（暂时为空字典）。Resource 字段：mounts: Dictionary[StringName, Array[WidgetMount]]，WidgetMount 含 widget_scene / priority / enabled / config_override。 | 新增 | 0.5d | HUDLayoutResource.gd + 1 份 .tres |
| **P1-T8** | 新增 `Script/UI/HUDStateMachine.gd`（Autoload **第 9 项**，或 GameInstance 子节点）：9 个 State（Boot / MainMenu / Gameplay / Paused / PanelOpen / Dialogue / Cutscene / Dead / LevelTransition）。`change_state` 三阶段：Exit 旧（pop layer + 还原 InputContext + 还原 process_mode）→ Enter 新（push layer + 应用 InputContext + 应用 process_mode）→ emit `hud_state_changed`。 | 新增 | 1.5d | HUDStateMachine.gd |
| **P1-T9** | HUDStateMachine 与 GameInstance.GameState 双向同步：监听 `EventBus.game_state_changed` 自动切 HUD 状态；HUD 主动切状态时也能反推 GameInstance（例如打开背包 → 通知 GameInstance 切到 PanelOpen 子状态）。 | 改造 | 0.5d | HUDStateMachine.gd 增量 |
| **P1-T10** | 主场景接入：在 `main_scene.gd` `_ready()` 调 `HUDManager.setup()` + 加载默认 HUDLayout。 | 改造 | 0.2d | main_scene.gd 改造 |

### 1.2 验收内容

- [ ] BaseWidget 子类可正确执行 `_on_show / _on_hide` 动画。
- [ ] HUDManager 8 层全部生成；push/pop 操作正确，栈顶 widget 自动获得焦点。
- [ ] UIExtensionSubsystem `register_widget` 后立即在指定 Slot 看到 widget；`unregister_widget` 后立即消失。
- [ ] HUDLayoutResource 切换：清空旧布局 → 加载新布局，全过程 < 200ms。
- [ ] HUDStateMachine 切到 PanelOpen 时：L2 推开背包；InputContext 自动切换；战斗 action 被屏蔽。
- [ ] 切回 Gameplay 时：L2 清空；InputContext 还原；战斗 action 恢复。
- [ ] 无任何运行时报错；编辑器内打开 HUD_Main.tscn 不报警告。

### 1.3 验收表

| 验收项 ID | 验收点 | 测试方式 | 通过标准 |
|---|---|---|---|
| P1-A1 | BaseWidget 生命周期 | 新建 TestWidget 继承 BaseWidget，加到场景 | `_on_show` 在 ready 后触发；`_on_hide` 在 free 前触发 |
| P1-A2 | 8 层结构正确 | 编辑器打开 HUD_Main.tscn 看节点树 | 8 个 CanvasLayer 顺序与 z 值正确（0/1/2/3/4/5/6/99） |
| P1-A3 | 7 个 Slot 命名 | 同上 | 命名严格匹配（TopLeft/TopCenter/.../Center） |
| P1-A4 | push/pop 栈正确 | 调 `HUDManager.push_widget("L4_Modal", w)` 三次再 pop | 栈深度变化 0→1→2→3→2→1→0；`get_top_widget` 准确 |
| P1-A5 | UIExtension 注册 | `register_widget("L1.Slot.TopRight", MinimapScene)` | 立即看到 Minimap 出现在右上角 |
| P1-A6 | Layout 切换 | 准备 Default + BossRush 两份 .tres，切换 | Default 的 widget 全部 free；BossRush 的 widget 出现 |
| P1-A7 | 状态机切换 | 通过快捷键触发 Gameplay → Paused → Gameplay | L3 暂停菜单出现/消失；InputContext 切换正确 |
| P1-A8 | 输入屏蔽 | Paused 状态下按 `combat_attack` | 不触发；状态机日志记录 drop |
| P1-A9 | 9 个状态全覆盖 | 写一份 GDScript 用例依次切到 9 个状态 | 每次切换都有 `hud_state_changed` 信号；目标状态可见层与策划案一致 |
| P1-A10 | 与 GameInstance 同步 | 通过 EventBus.game_state_changed 触发 | HUDStateMachine 自动跟随；反向亦同 |

---

## Phase 2 · 现状迁移（3~4d）

> **存在原因**：把 7 个现有 widget 接入新架构，**不新增功能**。完成后行为应该与改造前完全一致，但代码结构干净。

### 2.1 Todo 清单（commit 级）

| # | Todo | 类型 | 工作量 | 交付 |
|---|---|---|---|---|
| **P2-T1** | 把 `Script/UI/HUD.gd`（玩家 HUD 主控）拆解成 3 个 widget：`PlayerInfoWidget`（HP/MP）、`HotbarWidget`（技能槽），各自继承 BaseWidget。原 `HUD.tscn` 改为只剩 Slot 占位。 | 重构 | 1d | 2 个新 .gd + 2 个新 .tscn + HUD.tscn 简化 |
| **P2-T2** | `BossHealthBar.gd/tscn` 改继承 BaseWidget，挂到 L1.Slot.TopCenter。绑定 Boss ASC 通过 IAttributeReadable Provider，不再直接 cast 业务类。 | 重构 | 0.5d | BossHealthBar 改造 |
| **P2-T3** | `DamagePopupPool.gd` 改继承 BaseWidget，挂到 L0 World HUD 层。`_project_to_screen` 抽到 `Script/UI/Util/WorldProjector.gd` 静态工具类。 | 重构 | 0.5d | DamagePopupPool 改造 + WorldProjector.gd |
| **P2-T4** | `OverheadHealthBarManager.gd` 改：把 `_is_boss / _is_elite` 从读 `CharacterInstanceEntry.category` 改为读 enemy 节点的 `groups`（"boss" / "elite"），消除对业务类的强依赖。继承 BaseWidget 挂到 L0。 | 重构 | 0.5d | OverheadHealthBarManager 改造 + 现有 enemy 场景加 group |
| **P2-T5** | `InventoryUI.gd/tscn` 改继承 BaseWidget。打开方式改为 `HUDStateMachine.change_state(PanelOpen) + register_widget(L2.Stack)`。Esc 关闭走栈 pop。 | 重构 | 0.5d | InventoryUI 改造 |
| **P2-T6** | `PauseMenu.gd/tscn` 同理：接入 L3 + 状态机 Paused。`SettingsMenu.gd/tscn` 同理：接入 L3。两者打开/关闭走栈。 | 重构 | 0.5d | PauseMenu / SettingsMenu 改造 |
| **P2-T7** | 把所有 widget 内的硬编码颜色 / 字号 / 像素位置抽到：`Data/Config/UITheme.tres`（字号 / 圆角）+ `Data/Config/UIColorTokens.tres`（颜色）。`HitFeedbackConfig.tres` / `HealthBarConfig.tres` 维持原状不动。 | 配置 | 0.5d | 2 份新 .tres + widget 改用 theme_override |
| **P2-T8** | 写 `Data/Config/HUDLayout_Default.tres`：声明 7 个 widget（PlayerInfo / Hotbar / BossHealthBar / Inventory / Pause / Settings / Damage / Overhead）的挂载关系。 | 配置 | 0.3d | HUDLayout_Default.tres 填充 |
| **P2-T9** | 回归测试：跑一遍 `TestArena.tscn`，验证所有现状功能不退化。 | 测试 | 0.2d | 测试日志 |

### 2.2 验收内容

- [ ] 7 个现有 widget 全部继承 BaseWidget，旧 `extends Control` 已移除。
- [ ] 现有功能 100% 无退化：HP/MP 显示、技能槽 CD、Boss 血条、敌人头顶血条、伤害飘字、背包打开关闭、暂停菜单、设置菜单。
- [ ] `grep -rn "Color(" Script/UI/` 无命中（除了 BaseWidget 自身的兜底）。
- [ ] `grep -rn "font_size *=" Script/UI/` 无命中。
- [ ] `grep -rn "position = Vector2(" Script/UI/Widgets/` 无命中（除了世界投影计算）。
- [ ] `grep -rn "as PlayerCharacter\|as EnemyCharacter\|as BaseCharacter" Script/UI/` 命中数应大幅下降，剩余的均改为依赖 Provider 接口。
- [ ] 切换 HUDLayout_Default → 空布局后再切回，所有 widget 正确重组。

### 2.3 验收表

| 验收项 ID | 验收点 | 测试方式 | 通过标准 |
|---|---|---|---|
| P2-A1 | HP/MP 显示无退化 | 跑 TestArena，攻击玩家 | 血条立即更新；数值与改造前一致 |
| P2-A2 | 技能 CD 无退化 | 按 Q/W/E/R | 槽位遮罩出现；CD 数字递减 |
| P2-A3 | Boss 血条 | 进入 BossRoom_01 | Boss 血条显示在 TopCenter；扣血同步 |
| P2-A4 | 敌人头顶血条 | 攻击 Slime | 头顶血条出现并跟随；死亡时消失 |
| P2-A5 | 飘字 | 攻击敌人 | 飘字出现在敌人头顶；普通/暴击颜色正确 |
| P2-A6 | 背包打开关闭 | 按 B | L2 推开背包；Esc 关闭；战斗输入被屏蔽 |
| P2-A7 | 暂停菜单 | 按 Esc | L3 推开暂停菜单；游戏暂停；战斗输入被屏蔽 |
| P2-A8 | 设置菜单嵌套 | 暂停菜单中点设置 | L3 栈深度 +1；设置菜单覆盖；返回键回到暂停菜单 |
| P2-A9 | 颜色/字号 grep 检查 | 命令行 grep | 无硬编码命中 |
| P2-A10 | 业务类引用 grep 检查 | 命令行 grep | `as PlayerCharacter` 等命中数 ≤ 改造前 30% |
| P2-A11 | Layout 切换不破坏 | 切空布局再切回 | 所有 widget 重新出现，状态正确 |

---

## Phase 3 · 元素补全（5~7d）

> **存在原因**：补齐策划案 §3.3 列出但当前缺失的 HUD 元素。**可按战场需要切片**：先做战斗类（玩家 / 战斗体感最直接），其他可推后。

### 3.1 Todo 清单（commit 级）

#### 3.1.1 战斗类补全（约 2.5d）

| # | Todo | 类型 | 工作量 | 交付 |
|---|---|---|---|---|
| **P3-T1** | 新增 `ExperienceBarWidget`（继承 BaseWidget）：绑定 `IAttributeReadable(experience)`，挂 L1.Slot.TopLeft 下方。 | 新增 | 0.3d | 1 widget |
| **P3-T2** | 新增 `PlayerAvatarWidget`：显示头像 + 等级数字。读 `CharacterInstanceEntry`（通过抽象 Provider）。挂 L1.Slot.TopLeft 顶部。 | 新增 | 0.3d | 1 widget |
| **P3-T3** | 扩 `HotbarWidget`：从 2 槽 → 6 槽（Q/W/E/R/Shift+Q/Ult）。槽位数据来自配置（HUDLayout 的 config_override）。 | 改造 | 0.5d | Hotbar 扩展 |
| **P3-T4** | 新增 `BuffListWidget`：订阅 `EventBus.effect_applied/removed`，流式布局图标 + 时长倒计时。最多 8 个，溢出折叠。 | 新增 | 0.5d | 1 widget |
| **P3-T5** | 新增 `DebuffListWidget`：与 Buff 类似但单独一行，颜色不同。 | 新增 | 0.3d | 1 widget |
| **P3-T6** | 新增 `Script/UI/ComboTracker.gd`（Autoload 或单纯 Resource）：监听 `damage_dealt_v2` 累加 combo，2s 不命中清零。新增 `EventBus.combo_changed(count: int)` 信号。 | 新增 | 0.4d | 1 跟踪器 + 1 信号 |
| **P3-T7** | 新增 `ComboWidget`：订阅 `combo_changed`，从 2 hit 起显示，数字带强调动画。 | 新增 | 0.3d | 1 widget |
| **P3-T8** | 新增 `KillFeedWidget`：订阅 `enemy_died`，飞过式提示「击杀: 史莱姆」。挂 L5。 | 新增 | 0.3d | 1 widget |
| **P3-T9** | 新增 `HitVignetteWidget`：订阅 `damage_dealt_v2`（target=player），屏幕边缘红色 vignette + 短暂震动。挂 L1 全屏。 | 新增 | 0.3d | 1 widget |
| **P3-T10** | 扩 `DamagePopupPool`：支持 MISS / 闪避 / 治疗三种额外类型，靠 payload 区分。 | 改造 | 0.3d | DamagePopup 扩展 |

#### 3.1.2 反馈类补全（约 1.5d）

| # | Todo | 类型 | 工作量 | 交付 |
|---|---|---|---|---|
| **P3-T11** | 新增 `ToastWidget` + 池：订阅 `hud_toast_requested`，右上堆叠 3s 后淡出。 | 新增 | 0.4d | 1 widget |
| **P3-T12** | 新增 `TooltipWidget`：通用 hover 提示，跟随光标。挂 L4。 | 新增 | 0.3d | 1 widget |
| **P3-T13** | 新增 `PickupNotificationWidget`：订阅 `inventory_changed`（增量），右下条目堆叠 5s 自动消失。 | 新增 | 0.3d | 1 widget |
| **P3-T14** | 新增 `BigBannerWidget`：死亡 / 胜利 / 失败 / Boss 出场 全屏大字。订阅 `player_died` / `level_completed` / `EventBus.hud_state_requested(boss_intro)`。 | 新增 | 0.3d | 1 widget |
| **P3-T15** | 在 `EventBus.gd` 新增信号：`pickup_displayed(item_id, qty)` / `combo_changed(count)` / `hud_big_banner_requested(banner_id)`。 | 改造 | 0.2d | EventBus 加 3 信号 |

#### 3.1.3 导航类补全（约 1.5d）

| # | Todo | 类型 | 工作量 | 交付 |
|---|---|---|---|---|
| **P3-T16** | 新增 `MinimapWidget`：使用 `SubViewport + Camera2D` 上方俯视渲染 + 玩家/敌人雷达点叠加。挂 L1.Slot.TopRight。 | 新增 | 0.7d | 1 widget |
| **P3-T17** | 新增 `QuestTrackerWidget`：订阅 `EventBus.quest_objective_changed`（QuestSystem 接入前先 Mock）。挂 L1.Slot.TopRight 下方。 | 新增 | 0.3d | 1 widget |
| **P3-T18** | 新增 `AreaNameBannerWidget`：订阅 `level_changed`，淡入淡出区域名。挂 L5 顶部。 | 新增 | 0.3d | 1 widget |
| **P3-T19** | 新增 `WaypointArrowWidget`（世界投影类）：屏幕边缘箭头指向目标点。 | 新增 | 0.3d | 1 widget |

#### 3.1.4 养成类补全（约 1d）

| # | Todo | 类型 | 工作量 | 交付 |
|---|---|---|---|---|
| **P3-T20** | 新增 `LevelUpWidget`：订阅 `attribute_changed`（attr=&"level"），全屏 LEVEL UP 特效 + 音效。挂 L5。 | 新增 | 0.4d | 1 widget |
| **P3-T21** | 新增 `EquipCompareCardWidget`：拾取装备时弹比较卡（拾取项 vs 已装备）。订阅 `equipment_changed` 派生事件。挂 L4。 | 新增 | 0.4d | 1 widget |
| **P3-T22** | 复用 DamagePopupPool 做经验 / 金币飘字（通过类型 payload 区分颜色）。 | 改造 | 0.2d | DamagePopup 扩展 |

### 3.2 验收内容

- [ ] 战斗类 10 项 widget 全部上线，在 BossRoom 实战中表现稳定。
- [ ] 反馈类 4 项 widget 全部上线，Toast / Tooltip / Pickup / BigBanner 触发自然。
- [ ] 导航类 4 项 widget 全部上线，Minimap 正常渲染玩家位置 + 敌人点。
- [ ] 养成类 3 项 widget 全部上线，升级 / 拾取装备 / 经验飘字反馈完整。
- [ ] 性能不退化：实战 60fps；同屏 20+ 飘字 + 4 个头顶血条 + 全 HUD 时帧时间 < 16ms。
- [ ] 全部 widget 必须可在 HUDShowcase（Phase 4）中喂假数据独立预览。

### 3.3 验收表

| 验收项 ID | 验收点 | 测试方式 | 通过标准 |
|---|---|---|---|
| P3-A1  | 经验条        | 击杀小怪获得经验               | 经验条平滑增长；满后归零并升级 |
| P3-A2  | 玩家头像/等级 | 升级                            | 等级数字立即更新 |
| P3-A3  | 6 槽 Hotbar    | 按 Q/W/E/R/Shift+Q/Space        | 6 个槽位都有 CD 显示 |
| P3-A4  | Buff 列表     | 服用药水                        | Buff 图标出现 + 倒计时；时长到自动消失 |
| P3-A5  | Combo 计数    | 连续命中 3 次                    | Combo 计数 1→2→3；2s 不命中清零 |
| P3-A6  | 击杀提示      | 击杀 Slime                      | 飞过式提示出现并 3s 淡出 |
| P3-A7  | 受击 Vignette | 被攻击                          | 屏幕边缘红色脉冲 + 短震动 |
| P3-A8  | MISS 飘字     | 闪避一次攻击                    | 头顶飘字显示 MISS（颜色与普通伤害不同） |
| P3-A9  | Toast         | 触发 `hud_toast_requested`       | 右上 Toast 堆叠 + 3s 淡出 |
| P3-A10 | Tooltip       | 鼠标 hover 物品 1s              | Tooltip 出现，跟随光标 |
| P3-A11 | 拾取提示      | 拾取金币                        | 右下条目堆叠 + 5s 消失 |
| P3-A12 | 死亡大字      | 玩家死亡                        | 全屏 YOU DIED 渐入 |
| P3-A13 | 小地图        | 在 TestArena 移动               | 玩家点居中；敌人点正确显示 |
| P3-A14 | 区域名提示    | 切关进入 BossRoom               | 顶部淡入区域名 |
| P3-A15 | 升级特效      | 升级                            | 全屏 LEVEL UP + 音效 |
| P3-A16 | 装备比较卡    | 拾取武器                        | 弹卡显示新旧装备属性对比 |
| P3-A17 | 性能          | 触发 20 飘字 + 4 头顶血条 + 全 HUD | 帧时间 < 16ms（Debug 层显示） |

---

## Phase 4 · 完善与验收（1~3d）

> **存在原因**：补齐配置 / 适配 / 调试支持，并跑通整体验收清单。

### 4.1 Todo 清单（commit 级）

| # | Todo | 类型 | 工作量 | 交付 |
|---|---|---|---|---|
| **P4-T1** | 设置项接入：在 `SettingsMenu.tscn` 增加 11 项 hud/* 配置控件，绑定到 `SettingsManager`。即时生效。 | 配置 | 0.5d | SettingsMenu 扩展 |
| **P4-T2** | 安全区机制：所有层根节点加 `MarginContainer`，读取 `DisplayServer.screen_get_safe_area`，无安全区时取 `hud/safe_area_padding`。 | 改造 | 0.3d | HUD_Main.tscn 改造 |
| **P4-T3** | 锚点审计：所有 widget 检查 anchor + offset 全用相对值，禁止绝对像素 position。 | 审计 | 0.3d | grep + 修复清单 |
| **P4-T4** | 多布局 .tres：新增 `HUDLayout_BossRush.tres`（隐藏 Minimap，显示 WaveCounter）和 `HUDLayout_Cutscene.tres`（仅字幕）。 | 配置 | 0.4d | 2 份新 .tres |
| **P4-T5** | 新增 `Scenes/Debug/HUDShowcase.tscn`：5 个 ShowcasePanel（Combat/Boss/Feedback/Menus/World）+ Mock Provider 喂假数据。 | 新增 | 0.7d | 1 个 showcase 场景 |
| **P4-T6** | 新增预设状态快捷键脚本：F1 满血、F2 残血、F3 暴击连发、F4 Boss 战、F5 死亡、F6 升级。仅在 Debug Build 启用。 | 新增 | 0.3d | 1 个 cheat 脚本 |
| **P4-T7** | L7 Debug 层：FPS / 帧时间 / HUD 元素数 / Draw Call / 飘字池命中率 / 各层栈深度。 | 新增 | 0.3d | DebugOverlayWidget |
| **P4-T8** | 跑完整验收表：从 P0-A1 到 P4-A 全部跑一遍，记录到 `Plans/Dolphin设计/HUD开发日志.md`。 | 测试 | 0.5d | 验收日志 |
| **P4-T9** | 视觉回归基线：截 8 张关键状态图（满血/残血/Boss/暂停/背包/对话/死亡/升级），存到 `Plans/Dolphin设计/screenshots/HUD/`。 | 测试 | 0.3d | 8 张基线图 |

### 4.2 验收内容

- [ ] 11 项 hud/* 设置项全部能在游戏内调整，运行时生效，重启保持。
- [ ] 切到 1280×720 / 1920×1080 / 3840×2160 / 21:9 四种分辨率，HUD 不变形不溢出。
- [ ] HUDLayout_Default / HUDLayout_BossRush / HUDLayout_Cutscene 三套布局可热切换，切换 < 200ms。
- [ ] HUDShowcase 场景独立运行，5 个 panel 全部能喂假数据预览。
- [ ] F1~F6 预设状态快捷键工作正常。
- [ ] L7 Debug 层信息齐全。
- [ ] 整体验收表（5 阶段累计 ≈ 60 项）全部通过或有明确豁免说明。

### 4.3 验收表

| 验收项 ID | 验收点 | 测试方式 | 通过标准 |
|---|---|---|---|
| P4-A1  | 11 项设置生效                | 在 SettingsMenu 调整每一项                 | 立即生效；重启后保持 |
| P4-A2  | 4 种分辨率                   | 切 720p / 1080p / 4K / 21:9                | HUD 不变形、不溢出、不漏角 |
| P4-A3  | 多布局热切换                 | 进入 BossRush 时切布局                     | < 200ms；Minimap 消失，WaveCounter 出现 |
| P4-A4  | HUDShowcase 5 panel 全可见   | 打开 Showcase 场景                         | 5 panel 都有内容，无报错 |
| P4-A5  | 6 个预设状态快捷键           | 战斗中按 F1~F6                              | 各预设状态正确触发 |
| P4-A6  | L7 Debug 层信息              | F11 切显示 Debug 层                        | FPS / 帧时间 / 元素数 / 池命中率 实时刷新 |
| P4-A7  | 安全区适配                   | 模拟带安全区的设备                         | HUD 在安全区内 |
| P4-A8  | 锚点审计 grep                 | grep `position = Vector2(` 排除世界投影     | 无命中 |
| P4-A9  | 8 张基线截图                 | 与基线对比                                 | 像素级无显著差异（除新增功能外） |

---

## 验收总表（一页式 Cheat Sheet）

> 所有阶段验收点汇总，建议打印贴墙。

### 总体铁律（每个 commit 都查）

| ID | 铁律 | 检查方式 |
|---|---|---|
| R-HUD-01 | HUD 不写回业务数据 | grep widget 中 emit_signal 反向写 |
| R-HUD-02 | HUD 不直接 cast 业务类 / get_node 跨场景 | grep `as PlayerCharacter` / `get_node("../Player")` |
| R-HUD-03 | 数值/颜色/像素全走 .tres | grep `Color(` / `font_size *=` / 裸像素 |
| R-HUD-04 | 可在 Showcase 独立运行 | HUDShowcase 验证 |
| R-HUD-05 | 跨模块只走 EventBus | 沿用 R-EVENT-01 |

### 各阶段通过门槛

| 阶段 | 必须通过项 | 通过门槛 | 退路 |
|---|---|---|---|
| Phase 0 | P0-A1 ~ P0-A6 | 6/6 全过 | 任一不过 → 回滚，不进 Phase 1 |
| Phase 1 | P1-A1 ~ P1-A10 | 10/10 全过 | 任一不过 → 修复后重测 |
| Phase 2 | P2-A1 ~ P2-A11 | 必须无功能退化 | 任一退化 → 回滚到 Phase 1 末态 |
| Phase 3 | P3-A1 ~ P3-A17 | 战斗类必须全过；其他类可分批补 | 性能 P3-A17 不过 → 立即介入优化 |
| Phase 4 | P4-A1 ~ P4-A9 | 9/9 全过 | 视觉回归 P4-A9 失败可豁免 |

### 累计指标（项目层面）

| 指标 | 目标 | 测量 |
|---|---|---|
| HUD widget 总数 | ≥ 30（覆盖 6 大类） | 数 widget 文件数 |
| HUD 整体帧时间 | < 0.5ms | L7 Debug 层 |
| 同屏世界 HUD 数 | ≤ 20 | OverheadHealthBarManager + DamagePopupPool 上限 |
| 飘字对象池命中率 | ≥ 95% | DamagePopupPool 统计 |
| HUDLayout 切换耗时 | ≤ 200ms | UIExtensionSubsystem.reload_layout 计时 |
| 关键路径 grep 0 命中 | Color( / font_size= / `as PlayerCharacter` | grep 命令 |
| 验收点累计通过率 | ≥ 95% | 60 项中允许 ≤ 3 项豁免 |

---

## 工作量与时间表

```
                  Day  1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
Phase 0  前置基建  ████████              (2~3d)
Phase 1  核心架构        ████████████████████  (6~8d)
Phase 2  现状迁移                              ████████████  (3~4d)
Phase 3  元素补全                                          ████████████████████  (5~7d)
Phase 4  完善验收                                                              ████████  (1~3d)
                                                                              ↑ Demo 可见
```

> **可见性节点**：
> - Day 5（Phase 1 中段）：HUDStateMachine 可演示状态切换（无业务）。
> - Day 12（Phase 2 末）：项目功能与改造前一致，但代码结构干净（**最关键的回归节点**）。
> - Day 19（Phase 3 末）：所有战斗 / 反馈 widget 上线，Demo 体感完整。
> - Day 22（Phase 4 末）：可对外演示完整 HUD。

---

## 变更日志

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-05-20 | 首次建立。基于 `05_系统框架_HUD设计_Dolphin适配.md` v0.1 + `HUD策划案.docx` v0.2 拆解，新增 Phase 0 前置基建（InputContext + 时长档），共 5 阶段、约 17~25 项 commit、累计 60 项验收。|
| v0.2 | 2026-05-21 | 关联补充：新增同目录 `07_HUD组件化设计_交互与落地.md`，定义 7 类原子组件（C1~C7） + InteractKind 枚举 + 11 条 `hud_intent_*` 信号 + HUDInteractConfig.tres，作为 Phase 3 元素补全的 widget 实施手册。本文 Phase 3 各 widget 的「类型 / 交互契约 / 节点选型」请直接对照 07 §3 清单与 §8 速查矩阵。|
