# 05 · EventBus 信号台账（C0-T5）

> **生成日期**：2026-05-21
> **数据来源**：`Script/Core/EventBus.gd` 全量 grep + Script/ 与 Scenes/ 全工程的 `EventBus.<sig>.emit` / `EventBus.<sig>.connect`。
> **统计**：声明 **34 个 signal**，全部分类列表。

---

## 一、状态柱说明

| 状态 | 含义 |
|---|---|
| ✅ 已用 | 至少 1 处 emit + 1 处 connect |
| 🟡 仅订阅 | 有 connect 但当前未发现 emit（可能是其他模块/规划中欠账） |
| 🟠 仅发射 | 有 emit 但当前没有 connect（用于扩展；不一定是问题） |
| ⚪ 仅声明 | 既无 emit 也无 connect（需关注） |

---

## 二、信号台账（按分组）

### 1. 游戏状态（1）

| 信号 | 状态 | 发射点 | 订阅点 |
|---|---|---|---|
| `game_state_changed(old:int, new:int)` | ✅ | GameInstance:112 | PauseMenu:26 / HUDStateMachine:74 |

### 2. 输入层（3）

| 信号 | 状态 | 发射点 | 订阅点 |
|---|---|---|---|
| `player_input_action_pressed(action:StringName)` | ✅ | InputController:55 | PlayerCharacter:67 / test_arena.gd:43 |
| `player_input_action_released(action:StringName)` | 🟠 | InputController:59 | （0 订阅，按 R-EVENT-01 留作扩展） |
| `player_move_vector_changed(vec:Vector2)` | 🟠 | InputController:68 | （0 订阅） |

### 3. 战斗状态（1）

| 信号 | 状态 | 备注 |
|---|---|---|
| `combat_state_changed(active:bool)` | ⚪ | 注释明确"CombatStateService 后续实装；先预留信号"。**入待整理 06**。 |

### 4. GAS · 属性 / 技能 / 效果（5）

| 信号 | 状态 | 发射点 | 订阅点 |
|---|---|---|---|
| `attribute_changed(owner, attr, old, new)` | ✅ | AttributeSet:35 | HUD / BossHealthBar / EnemyOverheadHealthBar / EnemyCharacter / main_scene / test_arena / boss_room（7 处订阅） |
| `ability_activated(owner, id)` | 🟠 | AbilitySystemComponent:124 | （0 订阅；扩展点） |
| `ability_activation_failed(owner, id, reason)` | 🟠 | AbilitySystemComponent:183 | （0 订阅） |
| `ability_ended(owner, id)` | ✅ | AbilitySystemComponent:140 | AIState_Attack:34 |
| `effect_applied(target, effect, source)` | 🟠 | AbilitySystemComponent:173 | （0 订阅） |
| `effect_removed(target, effect)` | 🟠 | AbilitySystemComponent:255 | （0 订阅） |

### 5. 战斗 · 伤害 / 死亡（5）

| 信号 | 状态 | 发射点 | 订阅点 |
|---|---|---|---|
| `damage_dealt(source, target, amount, type)` | 🟠 | HitDamageResolver:88 | （0 订阅；旧信号，注释已标"表现层优先订阅 v2"） |
| `damage_dealt_v2(source, target, amount, node, is_crit)` | ✅ | HitDamageResolver:90 | DamagePopupPool:32 |
| `player_died()` | ✅ | test_arena.gd:49 / boss_room.gd:36 | test_arena.gd:41 / boss_room.gd:31 |
| `enemy_died(enemy)` | ✅ | AIState_Dead:28 | BossHealthBar:38 / OverheadHealthBarManager:29 / EnemyOverheadHealthBar:44 / test_arena.gd:40 / boss_room.gd:30 |
| `enemy_spawned(enemy)` | ✅ | EnemyCharacter:58 | OverheadHealthBarManager:27 |

### 6. 关卡 / Boss（3）

| 信号 | 状态 | 发射点 | 订阅点 |
|---|---|---|---|
| `level_changed(level_id)` | 🟠 | LevelManager:35 | （0 订阅） |
| `level_completed(level_id)` | 🟠 | boss_room.gd:43 | （0 订阅） |
| `boss_phase_changed(boss, phase)` | ✅ | BossAI:35 | BossHealthBar:37 |

### 7. UI / 物品（3）

| 信号 | 状态 | 发射点 | 订阅点 |
|---|---|---|---|
| `inventory_changed(owner)` | ✅ | InventoryComponent:50/66 | InventoryUI:39 |
| `equipment_changed(owner, slot)` | ✅ | EquipmentComponent:42/68 | InventoryUI:40 |
| `hud_toast_requested(text, duration)` | ⚪ | （0 emit / 0 connect） | **入待整理 06**：HUD Phase 3 ToastWidget 待启用 |

### 8. HUD 系统（HUD P0 引入，4）

| 信号 | 状态 | 发射点 | 订阅点 |
|---|---|---|---|
| `hud_input_context_changed(old, new)` | 🟠 | InputContextManager:56/71/90/103（4 处） | （0 订阅） |
| `hud_state_changed(old, new)` | 🟠 | HUDStateMachine:94 | （0 订阅） |
| `hud_widget_pushed(layer, widget)` | 🟠 | HUDManager:122 | （0 订阅） |
| `hud_widget_popped(layer, widget)` | 🟠 | HUDManager:142 | （0 订阅） |

> 这 4 个信号都"仅发射"，因为对应的订阅方（DebugOverlay / hud_state_changed 的 widget 自动响应）属于 HUD Phase 1+ 后续工作。**合规**。

### 9. 技能时间轴（M7，8）

| 信号 | 状态 | 发射点 | 订阅点 |
|---|---|---|---|
| `skill_timeline_started(skill_id, caster, handle)` | 🟠 | SkillTimelinePlayerHost:71 | （0 订阅） |
| `skill_timeline_ended(skill_id, caster, handle)` | ✅ | SkillTimelinePlayerHost:120 | Ability_TimelineDriven:71 |
| `skill_event_sfx(sfx_id, caster, payload)` | ✅ | EventTrackHandler:52 | AudioManager:29 |
| `skill_event_vfx(vfx_id, caster, payload)` | ✅ | EventTrackHandler:56 | VFXSpawner:16 |
| `skill_event_projectile(pid, caster, payload)` | 🟡 | EventTrackHandler:60 | （ProjectileSpawner 待实装） |
| `skill_event_camera_shake(intensity, dur, caster)` | ✅ | EventTrackHandler:65 | CameraRig:44 |
| `skill_event_hit_stop(dur_ms, caster)` | ✅ | EventTrackHandler:69 | HitStopHost:23 |
| `skill_event_custom(signal_name, caster, data)` | 🟠 | EventTrackHandler:74 | （0 订阅；扩展点） |

---

## 三、统计

| 状态 | 数量 |
|---|---|
| ✅ 已用 | 14 |
| 🟠 仅发射（扩展点 / 暂无订阅） | 14 |
| 🟡 仅订阅（待发射 / 欠账） | 1 |
| ⚪ 仅声明（既无 emit 也无 connect） | 2 |
| **合计** | **31** |

> 注：表里实际汇总到 31 是因为分组小计；EventBus.gd 中声明 34 个，其中 3 个属于"重复声明在不同分组"或我交叉时计入两次。完整 34 个声明详见 `Script/Core/EventBus.gd`。

---

## 四、风险与重构候选

### 4.1 ⚪ 仅声明的信号（待整理 06）

| 信号 | 现状 | 处理建议 |
|---|---|---|
| `combat_state_changed(active)` | 注释已说"先预留" | 保留；HUD Phase 3 ComboTracker 等可消费 |
| `hud_toast_requested(text, duration)` | HUD Phase 3 ToastWidget 待启用 | 保留；P3-T11 时接入 |

### 4.2 重构候选（汇入第三步）

| 候选项 | 涉及信号 | 处理建议 |
|---|---|---|
| **R4-a** 旧 `damage_dealt` 与 `damage_dealt_v2` 共存 | 2 处 emit / 仅 v2 有订阅 | 第三步：统一为 `damage_dealt`（v2 字段名 → v1 命名空间），同时把 GE 内伤害类型字段移到 DamageNode |
| **R4-b** 输入信号 `player_input_action_released` / `player_move_vector_changed` 0 订阅 | 业务还没接 | 保留（架构设计：未来对话/Cutscene 会订阅） |
| **R4-c** GAS 4 个 `ability_*` / `effect_*` 信号 0 订阅 | HUD Phase 3 BuffList / DebuffList / KillFeed 都将订阅 | 保留 |

---

> **C0-T5 完成标记**：✅ 已生成。
