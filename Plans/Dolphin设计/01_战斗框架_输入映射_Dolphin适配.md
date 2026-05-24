# 战斗框架 · 输入映射（Dolphin 适配版）

> **来源**：前项目 `02_战斗操作与能量决策.md` v3.1 签字版（任务 A / E / F.1 / F.8）
> **本文定位**：Dolphin 工程接下来要落地的「输入层骨架」，对应里程碑 **D1**。
> **不包含**：能量数值、属性公式、武器槽（分别在文档 02 / 03 / 04）。
> **状态**：架构锁定 / 数值挂起。

---

## 0. UE → Godot 等价物映射表

| 前项目（UE / Lyra） | Dolphin（Godot 4.6） |
|---|---|
| `UInputAction`（Enhanced Input） | `project.godot` `[input]` 段下的 InputMap action |
| `UInputMappingContext` | InputMap action 的事件列表（多事件 = 多设备绑定）|
| `ULyraHeroComponent::Input_AbilityInputTagPressed` | `PlayerCharacter._unhandled_input` + `EventBus.player_input_pressed(action: StringName)` |
| `EnhancedInput Action.bConsumeInput` | `get_viewport().set_input_as_handled()` |
| `IMC_PlayerOverlay`（章节叠加映射） | 多个 InputMap action 同名前缀（`combat_*` / `ui_*`），按场景启停 |
| `URPGSettingsLocal::SetKeyBinding` | Dolphin `SettingsManager.set_key_binding(action, event)` + 持久化 `user://settings.cfg` |
| Steam Input / Xbox Controller | Godot 自带 `JoyButton` / `JoyAxis`，InputMap 同 action 加 Joy 事件 |

**关键差异**：Godot 没有 IMC 概念，**多个上下文 = 多个 action 前缀 + 运行时启停**。Dolphin 用 `combat_*` 与 `ui_*` 两套前缀解决。

---

## 1. 锁定的输入决策（直接采用前项目 v3.1）

### 1.1 战斗键位最终表（共 15 个 action）

| InputMap action | 默认按键 | 功能 | 备注 |
|---|---|---|---|
| `move_up` / `move_down` / `move_left` / `move_right` | ↑ ↓ ← → | 移动 | XZ 平面，朝向 = 移动方向 |
| `combat_attack` | A | 主手普攻（连段）| 自动锁敌 5m |
| `combat_skill_q` | Q | 主手技能 1 | 有 CD、不耗能 |
| `combat_skill_w` | W | 主手技能 2 | 有 CD、不耗能 |
| `combat_skill_e` | E | 副手技能 3 | 有 CD、不耗能 |
| `combat_skill_r` | R | 副手技能 4 | 有 CD、不耗能 |
| `combat_ultimate` | Space | 当前主手大招 | 满 100 释放 |
| `combat_dodge` | S | 闪避 | 读移动方向（F.1）|
| `combat_block` | D | 格挡（按住）| 完美窗口 0.3s |
| `combat_swap` | F | 切换主副手 | 满切 / 裸切 |
| `combat_interact` | G | 交互 | 战斗中禁深度交互 |
| `combat_consumable` | H | 恢复品 | 0.6s 硬直、不无敌、可被打断 |
| `ui_pause` | Esc | 暂停菜单 | — |
| `ui_panel_build` | Tab | Boon / Build 面板 | — |

### 1.2 朝向规则

- 移动方向 = 朝向；不动保留上次朝向。
- 720°/秒 平滑插值（避免瞬间转身穿模）。
- 普攻自动锁敌：搜索玩家前向 ±60°、半径 5m 内最近敌人，作为该次普攻的目标修正。
- 战斗中 **不使用鼠标朝向**（鼠标只用于 UI 交互）。

### 1.3 闪避方向（F.1 锁定）

- 按 S 时读取当前移动方向 → 朝该方向闪 3m。
- 无方向键 → 朝当前朝向 **后撤** 3m（不前冲）。
- 动画 0.4s（前 0.05 起手 + 中 0.3 无敌 + 后 0.05 硬直）。
- CD 0.6s。

### 1.4 格挡（F.3 / F.2 锁定）

- 按住 D 持续生效；移动 ×0.5。
- 格挡耐久属性：`block_max` / `block_regen_delay` / `block_regen_rate` / `block_regen_rate_in_combat`（默认 0，预留字段）。
- 完美格挡：按下 0.3s 内被击中 → 免伤 + 不耗耐久 + 强化下次攻击 buff（任意攻击 +50% 伤害、破韧 ×3、5 秒内有效、不可叠层、单次释放消耗）。
- 普通格挡：减伤 + 消耗耐久（伤害 ×0.6 入耐久消耗）；耗尽 → 1.2s 破防硬直 + 强制松开 D 键。

### 1.5 切换（F.4 / F.5 锁定）

| 状态 | 行为 | 消耗 | CD |
|---|---|---|---|
| 切换池 = 50 | 满切：换位 + 触发原主手切出技 + 原副手切入技 | -50 | 1.0s |
| 切换池 < 50 | 裸切：仅换位 | 0 | 0.5s |
| 半满（25~49）| 同裸切（不消耗、不触发技）| 0 | 0.5s |

切换瞬间 0.3s 无敌帧；正在硬直 / 大招中禁切换。

### 1.6 战斗状态判定（F.10 锁定）

```
combat_active = (5 秒内造成或受到伤害) OR (8 米内有处于仇恨状态的敌对单位)
```

影响：G 交互限缩为拾取金币、能量不回时间、格挡耐久不回（除非词条开启 `block_regen_rate_in_combat`）。

### 1.7 恢复品 H 键（F.6.2 锁定）

- 0.6s 站立硬直、不可移动、不无敌、可被击中打断（被打断不消耗）。

### 1.8 手柄映射（F.8 锁定）

| Xbox | Action | 备注 |
|---|---|---|
| 左摇杆 | `move_*` | 与方向键并列 |
| 右摇杆推 | `combat_lock_target_next` / `_prev` | Demo 可不做 |
| A | `combat_attack` | — |
| B | `combat_dodge` | — |
| X | `combat_skill_q` | — |
| Y | `combat_skill_w` | — |
| LB | `combat_skill_e` | — |
| RB | `combat_skill_r` | — |
| LT | `combat_block` | 按住 |
| RT | `combat_ultimate` | — |
| 十字 ← | `combat_swap` | — |
| 十字 → | `combat_interact` | — |
| 十字 ↑ | `combat_consumable` | — |
| Start | `ui_pause` | — |
| Select | `ui_panel_build` | — |

---

## 2. Godot 落地接口

### 2.1 `project.godot` `[input]` 段骨架

```ini
[input]
move_up={ "events": [<Key Up>, <Key W>, <JoyAxis -1 LeftY>] }
move_down={ "events": [<Key Down>, <Key S>, <JoyAxis +1 LeftY>] }
combat_attack={ "events": [<Key A>, <JoyButton 0 A>] }
combat_skill_q={ "events": [<Key Q>, <JoyButton 2 X>] }
... # 共 15 个 action + ui_pause + ui_panel_build
```

> 注意 `move_down` 与 `combat_dodge` 不要共用 S（前项目已锁定方向键移动；WASD 作为「设置菜单切换的次级预设」，由 `SettingsManager` 在切换预设时清掉冲突项）。Demo 默认走方向键，不在工程默认 InputMap 里把 S 同时绑两件事。

### 2.2 InputController（建议新增）

```
Script/Input/InputController.gd  (Node)
  signal input_action_pressed(action: StringName)
  signal input_action_released(action: StringName)
  signal move_vector_changed(vec: Vector2)

  func _unhandled_input(event):
      for action in WATCHED_ACTIONS:
          if event.is_action_pressed(action):
              input_action_pressed.emit(action)
          elif event.is_action_released(action):
              input_action_released.emit(action)
  
  func _process(_dt):
      var v := Input.get_vector("move_left","move_right","move_up","move_down")
      if v != _last:
          move_vector_changed.emit(v)
          _last = v
```

- 挂在 PlayerCharacter 子节点；EventBus 不直接处理输入，由 InputController 桥接，便于按场景启停（暂停菜单时 `set_process_unhandled_input(false)`）。
- 暂停 / 死亡 / 黑屏期间禁用 `combat_*` 这一组 action 监听；`ui_*` 始终可用。

### 2.3 角色控制组件分工

| 组件文件 | 职责 |
|---|---|
| `Script/Character/PlayerCharacter.gd` | 移动 + 朝向插值 + 自动锁敌 + 状态机入口 |
| `Script/Character/Components/DodgeComponent.gd` | S 键闪避（含完美闪避判定窗口）|
| `Script/Character/Components/BlockComponent.gd` | D 键格挡（含完美格挡 buff 触发）|
| `Script/Character/Components/EnergyComponent.gd` | 切换池 / 大招池查询 + 命中事件吃能量 |
| `Script/Character/Components/EquipmentComponent.gd`（M5 升级）| 双武器槽 + F 切换（详见武器框架文档）|
| `Script/Combat/CombatStateService.gd`（GameInstance 子节点）| 战斗状态全局判定 |

### 2.4 EventBus 信号补充（在现有信号基础上增加）

```gdscript
# 输入层
signal player_input_action_pressed(action: StringName)
signal player_input_action_released(action: StringName)

# 战斗状态
signal combat_state_changed(active: bool)

# 闪避 / 格挡
signal dodge_started(dir: Vector3, perfect: bool)
signal block_started()
signal block_perfect_triggered(buff_duration: float)
signal block_broken()
signal block_durability_changed(current: float, max: float)

# 切换（详见武器框架文档）
signal weapon_swap_requested(is_perfect: bool)
```

### 2.5 SettingsManager 键位重映射 API（P0 必做）

```gdscript
# Script/Core/SettingsManager.gd
func set_key_binding(action: StringName, new_event: InputEvent) -> void
func reset_key_bindings_to_default() -> void
func apply_preset(preset: String) -> void  # "arrows_default" / "wasd_alt" / "controller_default"
func save() -> void  # → user://settings.cfg
```

Demo 阶段必须能让玩家在设置 UI 改键并持久化。

---

## 3. 验收清单（D1 完成时）

- [x] `project.godot` 的 InputMap 含 11 个 combat_* action + 4 个 move_* + 2 个 ui_*（v0.2 落地，原文档"15 个 combat_*"为 v0.1 笔误）。
- [x] 玩家用方向键能控制角色在 TestArena 移动（v0.2，朝向 720°/s 插值留待动作组件补；移动连接走 `BaseCharacter._wire_components` → `MoveComponent.set_input_dir`）。
- [ ] 普攻自动锁敌：朝玩家前 5m 锥形最近敌人微调命中。
- [ ] 闪避：S 键朝移动方向 3m 后撤；动画 0.4s；CD 0.6s 内连按无效。**（v0.3 已通过 InputController 广播 `combat_dodge` 边沿事件；业务逻辑等 GA 实装）**
- [ ] 格挡：按住 D 移动 ×0.5；按下 0.3s 内挨打触发完美格挡 buff，UI 上有金色脉冲。**（v0.3 已通过 InputController 广播 `combat_block` 边沿事件；业务逻辑等 GA 实装）**
- [ ] CombatStateService 根据「5s 内伤害 ∪ 8m 仇恨怪」切换 `combat_state_changed`（v0.3 已在 EventBus 预留信号）。
- [x] 暂停菜单 Esc 弹出，弹出期间所有 combat_* action 不再触发（v0.3：InputController.process_mode = PAUSABLE，挂在 PlayerCharacter 子节点，tree paused 时自动停 process）。
- [ ] SettingsManager 能在 UI 中改一个键并持久化到 `user://settings.cfg`，重启后生效。
- [ ] 手柄热插拔：插入手柄后 A/B/X/Y/LT/RT/十字键全部能触发对应 action。

---

## 4. 与其它文档的衔接

- 能量消耗 / 命中加能量数值 → **02_战斗框架_属性公式_Dolphin适配.md** §C
- F 切换的武器槽底层数据流 → **03_战斗框架_武器切换_Dolphin适配.md**
- 死亡瞬间禁用所有 combat_* action 的回档流程 → **04_系统框架_死亡存档仓库_Dolphin适配.md** §5

---

## 5. 变更日志

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-05-20 | 从前项目 02 v3.1 任务 A / E / F.1 / F.3 / F.5 / F.6.2 / F.8 / F.10 萃取，加 Godot 等价物映射、InputMap 骨架、组件落地表、EventBus 信号补充。**数值与详细推导请参阅源文档**。|
| v0.2 | 2026-05-20 | InputMap 落地：`project.godot` 写入 4 个 move_*（方向键 + 左摇杆）、11 个 combat_*（attack/skill_q/w/e/r/ultimate/dodge/block/swap/interact/consumable，全部附 Xbox 手柄事件）、2 个 ui_*（pause/panel_build）。`GameInstance._unhandled_input` 由 `pause` 改 `ui_pause`；`InputComponent.gd` 临时把 `ability_1/ability_2/interact` 桥接到 `combat_attack/combat_skill_q/combat_interact`，完整 11 路 InputController 留给后续 D1 任务。|
| v0.3 | 2026-05-20 | **整套输入系统接入完成**（闪避/格挡的业务逻辑暂跳过，留给 GA 实装）：<br>① EventBus 新增 `player_input_action_pressed/released(action)`、`player_move_vector_changed(vec)`、`combat_state_changed(active)` 4 个信号。<br>② 新建 `Script/Input/InputController.gd`：`PROCESS_MODE_PAUSABLE` + `_unhandled_input` 桥接 11 个 combat_* + `ui_panel_build` → EventBus；`_physics_process` 差分广播移动向量。tree paused 时自动停广播。<br>③ `InputComponent.gd` 缩窄为"只输出移动方向 Vector3"，删 `ability_pressed/interact_pressed`。<br>④ `PlayerCharacter._ready` 自动 `add_child(InputController)` + 订阅 `EventBus.player_input_action_pressed`，`ability_slot_to_id` 扩展为 7 槽（普攻/QWER/Ultimate/Swap），dodge/block/consumable 留打印占位。<br>⑤ `test_arena.gd` 改用 EventBus 监听 `ui_panel_build` 切背包；`HUD.gd` 注释同步。<br>⑥ 设计文档勾选「方向键移动」「暂停期间不触发 combat_*」两项验收。|
