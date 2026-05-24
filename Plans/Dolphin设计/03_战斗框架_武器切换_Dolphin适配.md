# 战斗框架 · 武器切换架构（Dolphin 适配版）

> **来源**：前项目 `02_战斗操作与能量决策.md` 任务 B / F.4 / F.4.X / F.5 / F.7、`05_架构骨架梳理.md` §3、`23_A4落地计划讨论稿.md` §A5。
> **本文定位**：Dolphin 接下来落地的「双武器槽 + 双形态妥协 A + F 切换 + 双池大招」核心，对应里程碑 **D4**。
> **不包含**：13 步伤害公式 / 双池字段（→ 02 文档）、武器仓库 / 卸装清空与存档协同（→ 04 文档）。
> **状态**：数据结构 / 切换流程 / Demo 妥协 A 锁定；4 把武器具体配置数值挂起。

---

## 0. UE → Godot 等价物映射表

| 前项目（UE / Lyra Equipment） | Dolphin（Godot 4.6） |
|---|---|
| `ULyraEquipmentDefinition`（Data Asset）| `Script/Equipment/WeaponDefinition.gd`（Resource）|
| `ULyraEquipmentInstance`（运行时）| `Script/Equipment/WeaponInstance.gd`（RefCounted）|
| `ULyraEquipmentManagerComponent` + `FFastArraySerializer` | `Script/Items/EquipmentComponent.gd`（M5 升级，**Demo 不联机** → 不需要 FastArray，直接 Dictionary + 手动 emit）|
| `OnEquipped / OnUnequipped` 钩子 | EquipmentComponent.signal `weapon_equipped(slot, instance)` / `weapon_unequipped(slot, instance)` |
| `SpawnEquipmentActors`（武器挂点 Actor）| `WeaponInstance.attach_visual_to(socket: Node3D)` 在角色挂点 spawn 视觉 Sprite3D / MeshInstance3D |
| `ULyraGameplayAbility_FromEquipment::GetAssociatedEquipment` | Ability.gd `func get_owning_weapon() -> WeaponInstance: return EquipmentComponent.get_slot_for_ability(self)` |
| `AbilitySet.GiveToAbilitySystem` | `ASC.give_ability_set(ability_set: AbilitySet, source: WeaponInstance) -> Array[AbilityHandle]` |
| `MainHandSkills[]` / `OffHandSkills[]` 数组 | WeaponDefinition 同名 `Array[StringName]` 字段 |

**关键差异**：Demo 单机 → 不需要 Replicate；F 切换瞬间在主线程改 Dictionary + emit 信号即可。

---

## 1. 锁定的设计决策（02 v3.1 / 14 §A5 / F.7）

### 1.1 武器结构（决策 #14、F.7 妥协 A + 扩展约束）

每把武器有 **13 项资产**：

| 项 | Demo 是否独特 |
|---|---|
| 主位被动 | ✅ 独特设计 |
| 副位被动 | ✅ 独特设计 |
| 主形态技能 1 / 2（Q / W）| ⚠️ Demo：与副形态共用本体，按位乘子差异化 |
| 副形态技能 3 / 4（E / R）| ⚠️ Demo：同上 |
| 大招（Space）| ✅ 独特设计 |
| 切入技 | ✅ 独特设计 |
| 切出技 | ✅ 独特设计 |

**强制工程约束**：WeaponDefinition 必须分 `MainHandSkills[]` 与 `OffHandSkills[]` 两个独立数组，Demo 阶段两数组可填同一组 SkillID，**未来升级到独立技能集时不需重构数据结构**。

### 1.2 主副位语义（决策 #2 / #3）

| 操作 | 主手生效 | 副手生效 |
|---|---|---|
| A 普攻 | ✅ | ❌ |
| Q / W 技能 | ✅（MainHandSkills[0/1]）| ❌ |
| E / R 技能 | ❌ | ✅（OffHandSkills[0/1]）|
| Space 大招 | ✅ | ❌ |
| 主位被动 | ✅ | ❌ |
| 副位被动 | ❌ | ✅ |

### 1.3 双池（F.4 锁定 / 02 文档 §C.6）

```
weaponA.current_ult_energy ∈ [0, 100]   # 跟随武器实例
weaponB.current_ult_energy ∈ [0, 100]
switch_energy ∈ [0, 50]                 # 全局共用
current_main: WeaponInstance              # = main_hand 引用

UI 显示大招池 = current_main.current_ult_energy / 100
```

### 1.4 F 切换语义（F.5 锁定）

| 切换池状态 | 行为 | 消耗 | CD |
|---|---|---|---|
| ≥ 50 | 满切：换位 + 触发原主手切出技 + 原副手切入技 | -50 | 1.0s |
| < 50（含半满）| 裸切：仅换位 | 0 | 0.5s |

切换瞬间 0.3s 无敌帧；硬直/大招中禁切换。

### 1.5 卸装清空（F.4.X 锁定）

| 操作 | 行为 |
|---|---|
| F 切换主副手 | **不清池**（只换位） |
| 商店 / 拾取替换主或副手 | 被卸下武器**永久丢弃 + 大招池清零**（Demo 无仓库期）|
| 装备空槽 / 替换后的新武器 | `current_ult_energy = 0` 起步 |
| 进 / 出仓库（Meta 档功能，→ 04 文档）| **入库瞬间池子归零；出库装回池仍 0** |

### 1.6 切换 UI（C.8 / F.4）

- 主手图标 + 大招池实显条
- 副手图标 + 副位池**虚显环形进度条**（细线、灰色、半透明）
- 切换池单独 1 条
- 切换瞬间数字过渡渐变 0.3s（80 → 30）

---

## 2. Godot 落地结构

### 2.1 WeaponDefinition.gd（Resource，4 把武器各一份 .tres）

```gdscript
# Script/Equipment/WeaponDefinition.gd
extends Resource
class_name WeaponDefinition

@export var weapon_id: StringName              # "Weapon_Sword"
@export var display_name: String
@export var weapon_type: StringName            # "Sword" / "Spear" / "Bow" / "Staff"

# 技能（按位独立数组——Demo 阶段两组可填相同 ID）
@export var main_hand_skills: Array[StringName] = []   # [Skill_Q_id, Skill_W_id]
@export var off_hand_skills:  Array[StringName] = []   # [Skill_E_id, Skill_R_id]

# 主副位乘子（按位独立）
@export var main_hand_multipliers: Dictionary = {"dmg": 1.0, "range": 1.0, "cd": 1.0}
@export var off_hand_multipliers:  Dictionary = {"dmg": 0.7, "range": 0.8, "cd": 1.2}

# 被动
@export var main_hand_passive_id: StringName    # PassiveAbility ID
@export var off_hand_passive_id:  StringName

# 大招 / 切入切出
@export var ultimate_skill_id:    StringName    # 仅主手位生效
@export var switch_in_skill_id:   StringName    # 此武器从副切到主时触发
@export var switch_out_skill_id:  StringName    # 此武器从主切到副时触发

# 视觉 / 资源
@export var icon: Texture2D
@export var sprite_frames: SpriteFrames         # HD-2D 角色挂点用
@export var attach_socket_main: StringName = &"WeaponSocket_Main"
@export var attach_socket_off:  StringName = &"WeaponSocket_Off"

# Affix 槽数（→ 04 文档使用）
@export var affix_slot_count: int = 2
```

### 2.2 WeaponInstance.gd（RefCounted，运行时）

```gdscript
# Script/Equipment/WeaponInstance.gd
extends RefCounted
class_name WeaponInstance

signal ult_energy_changed(current: float, maximum: float)

var instance_uuid: String                          # UUIDv4 全局唯一（仓库追踪用）
var source_definition_id: StringName               # 指向 WeaponDefinition.weapon_id
var current_ult_energy: float = 0.0
const ULT_ENERGY_MAX: float = 100.0
var equipped_affixes: Array[Resource] = []         # AffixInstance 列表
var runtime_seed: int = 0                          # Roll 词条 / 显示用
var acquired_at_unix: int = 0
var acquired_source: StringName                    # "Loot" / "Shop" / "Quest" / "Storage"

func add_ult_energy(amount: float) -> void:
    var new_v = clamp(current_ult_energy + amount, 0.0, ULT_ENERGY_MAX)
    if abs(new_v - current_ult_energy) > 0.0001:
        current_ult_energy = new_v
        ult_energy_changed.emit(current_ult_energy, ULT_ENERGY_MAX)

func reset_ult_energy() -> void:
    if current_ult_energy != 0.0:
        current_ult_energy = 0.0
        ult_energy_changed.emit(0.0, ULT_ENERGY_MAX)

func is_ult_ready() -> bool:
    return current_ult_energy >= ULT_ENERGY_MAX

func get_definition() -> WeaponDefinition:
    return ConfigCenter.get_weapon_def(source_definition_id)

func to_dict() -> Dictionary:   # 仓库 / 存档序列化
    return {
        "uuid": instance_uuid,
        "def_id": source_definition_id,
        "ult": current_ult_energy,
        "affixes": equipped_affixes.map(func(a): return a.to_dict()),
        "seed": runtime_seed,
        "acquired_at": acquired_at_unix,
        "acquired_src": acquired_source,
    }

static func from_dict(d: Dictionary) -> WeaponInstance:
    var inst = WeaponInstance.new()
    inst.instance_uuid = d["uuid"]
    inst.source_definition_id = StringName(d["def_id"])
    inst.current_ult_energy = d.get("ult", 0.0)
    inst.runtime_seed = d.get("seed", 0)
    inst.acquired_at_unix = d.get("acquired_at", 0)
    inst.acquired_source = StringName(d.get("acquired_src", &"Unknown"))
    # affixes 由 AffixSystem 反序列化（→ 后续）
    return inst
```

### 2.3 EquipmentComponent.gd（M5 升级 → 双槽）

```gdscript
# Script/Items/EquipmentComponent.gd
extends Node
class_name EquipmentComponent

signal weapon_equipped(slot: StringName, inst: WeaponInstance)
signal weapon_unequipped(slot: StringName, inst: WeaponInstance)
signal weapons_swapped(new_main: WeaponInstance, new_off: WeaponInstance, was_perfect_swap: bool)

const SLOT_MAIN := &"main_hand"
const SLOT_OFF  := &"off_hand"

var main_hand: WeaponInstance = null
var off_hand:  WeaponInstance = null

@onready var owner_character: BaseCharacter = get_parent()
@onready var energy_comp: EnergyComponent = owner_character.get_node("EnergyComponent")

# === 装备 / 卸下 ===
func equip_to_slot(slot: StringName, inst: WeaponInstance, on_unequipped_old: Callable = Callable()) -> void:
    var old: WeaponInstance = _get_slot(slot)
    if old:
        unequip_from_slot(slot, on_unequipped_old)
    _set_slot(slot, inst)
    _grant_ability_set_for(slot, inst)
    _attach_visual(slot, inst)
    weapon_equipped.emit(slot, inst)

func unequip_from_slot(slot: StringName, on_unequipped: Callable = Callable()) -> WeaponInstance:
    var old: WeaponInstance = _get_slot(slot)
    if not old: return null
    _take_ability_set_for(slot, old)
    _detach_visual(slot, old)
    _set_slot(slot, null)
    
    # F.4.X 铁律：卸下即清能量池（Demo 阶段，进仓库由仓库系统再决定）
    old.reset_ult_energy()
    
    weapon_unequipped.emit(slot, old)
    if on_unequipped.is_valid():
        on_unequipped.call(old)
    return old

# === F 切换 ===
func swap_hands(force_perfect: bool = false) -> void:
    # 1. 检查能否切换（硬直 / 大招 / CD）
    if not _can_swap():
        return
    
    # 2. 判定满切 / 裸切
    var is_perfect = force_perfect or energy_comp.switch_energy >= energy_comp.SWITCH_MAX
    
    # 3. 消耗切换池
    if is_perfect:
        energy_comp.consume_switch(energy_comp.SWITCH_MAX)
    
    # 4. 拿原主手/副手准备触发切入切出技
    var old_main := main_hand
    var old_off  := off_hand
    
    # 5. 触发切入切出（满切才触发）
    if is_perfect:
        if old_main and old_main.get_definition().switch_out_skill_id != &"":
            owner_character.asc.try_activate_ability_by_id(old_main.get_definition().switch_out_skill_id, old_main)
        if old_off and old_off.get_definition().switch_in_skill_id != &"":
            owner_character.asc.try_activate_ability_by_id(old_off.get_definition().switch_in_skill_id, old_off)
    
    # 6. 撤掉原主位/副位授予的 Ability，按新位重新 grant
    _take_ability_set_for(SLOT_MAIN, old_main)
    _take_ability_set_for(SLOT_OFF,  old_off)
    main_hand = old_off
    off_hand  = old_main
    _grant_ability_set_for(SLOT_MAIN, main_hand)
    _grant_ability_set_for(SLOT_OFF,  off_hand)
    
    # 7. 触发 0.3s 无敌帧 + CD
    var cd = 1.0 if is_perfect else 0.5
    _start_swap_lock(cd)
    owner_character.start_invincibility(0.3)
    
    # 8. 重新挂视觉到对应 socket
    _swap_visuals()
    
    # 9. 广播
    weapons_swapped.emit(main_hand, off_hand, is_perfect)
    EventBus.weapon_swap_completed.emit(main_hand, off_hand, is_perfect)

func _can_swap() -> bool:
    if _swap_lock_until > Time.get_ticks_msec(): return false
    if owner_character.asc.has_tag(&"State.Stunned"): return false
    if owner_character.asc.has_tag(&"State.UltimateActive"): return false
    return main_hand != null and off_hand != null  # 至少要两把武器才能切

# === Ability 授予 ===
# 按位读取 WeaponDefinition.main_hand_skills / off_hand_skills
# Demo 阶段可两数组相同 ID + multiplier 不同
func _grant_ability_set_for(slot: StringName, inst: WeaponInstance) -> void:
    if not inst: return
    var def = inst.get_definition()
    var skills = def.main_hand_skills if slot == SLOT_MAIN else def.off_hand_skills
    var mults  = def.main_hand_multipliers if slot == SLOT_MAIN else def.off_hand_multipliers
    var passive = def.main_hand_passive_id if slot == SLOT_MAIN else def.off_hand_passive_id
    for sid in skills:
        owner_character.asc.give_ability_with_source(sid, inst, mults)
    if slot == SLOT_MAIN and def.ultimate_skill_id != &"":
        owner_character.asc.give_ability_with_source(def.ultimate_skill_id, inst, mults)
    if passive != &"":
        owner_character.asc.give_passive_ability(passive, inst)
```

### 2.4 命中事件如何充能（与 02 文档 EnergyComponent 协同）

```
A 普攻命中 → DamagePipeline.compute_and_apply 后 emit damage_dealt_v2
EnergyComponent._on_damage_dealt 读 attacker == owner、payload.tags
  ↓
查 EnergyGainTable.tres 取 ult / switch 配置
  ↓
ult 加到 main_hand.current_ult_energy（注意：不是 off_hand！）
switch 加到 owner.switch_energy
  ↓
副手 E / R 命中也充 main_hand.current_ult_energy（v3 锁定，详见 02 §C.3.1）
```

### 2.5 大招释放（Space）

```gdscript
# Script/Combat/Abilities/Ability_Ultimate.gd
func _can_activate() -> bool:
    var inst = EquipmentComponent.main_hand
    return inst and inst.is_ult_ready()

func _on_activate():
    var inst = EquipmentComponent.main_hand
    var ult_id = inst.get_definition().ultimate_skill_id
    inst.add_ult_energy(-100.0)
    asc.activate_ability_by_id(ult_id, inst)
```

---

## 3. 4 把占位武器（Demo 阶段，只填 SkillTimeline 资产骨架）

| WeaponDefinition .tres | 类型 | 主位被动占位 | 副位被动占位 |
|---|---|---|---|
| `Weapon_Sword.tres` | Sword（主向）| 连段第3段必暴击 | 副位时为主普攻附加飞剑 |
| `Weapon_Spear.tres` | Spear（主向）| 普攻穿透 | 副位时大幅提升闪避无敌帧 |
| `Weapon_Bow.tres`   | Bow（副向）| 远程精度 | 副位时主攻击附带蓄力箭 |
| `Weapon_Staff.tres` | Staff（副向）| 法术暴击 | 副位时大招回血 50% |

> Demo 阶段每把武器的 4 个技能均共用本体（Q/W = E/R），靠 `main_hand_multipliers` / `off_hand_multipliers` 数值差异化（副位 dmg ×0.7 / range ×0.8 / cd ×1.2）。**双被动 + 大招 + 切入切出共 6 项必须独特**（避免 4 把武器手感雷同）。

技能本体由 Dolphin 现有 SkillTimeline（M7）配——这是迁移最大的工程红利。

---

## 4. D4 里程碑任务分解

| 任务 | 落地点 | 工时 |
|---|---|---|
| D4.1 WeaponDefinition.gd | `Script/Equipment/WeaponDefinition.gd` | 0.5d |
| D4.2 WeaponInstance.gd（含序列化）| `Script/Equipment/WeaponInstance.gd` | 0.5d |
| D4.3 EquipmentComponent 重构（双槽 + swap_hands）| `Script/Items/EquipmentComponent.gd` | 1.2d |
| D4.4 EnergyComponent 接通 4 个池+命中钩子 | `Script/Character/Components/EnergyComponent.gd` | 1.0d |
| D4.5 Ability_Ultimate / Ability_FromEquipment 基类 | `Script/Combat/Abilities/` | 0.8d |
| D4.6 4 把占位 WeaponDefinition .tres + 6 项独特资产 × 4 = 24 个 SkillTimeline | `Data/GameData/Weapons/` + SkillTimeline | 1.5d |
| D4.7 切换 UI（HUD 大招实显 + 副位虚显 + 切换池）| `Scenes/UI/HUD.tscn` | 0.5d |
| D4.8 满切触发切入切出 + 0.3s 无敌帧 + CD | EquipmentComponent.swap_hands | 已含 D4.3 |
| D4.9 验收 | 见下 § 5 | 0.5d |

---

## 5. 验收清单（D4 完成时）

- [ ] WeaponDefinition / WeaponInstance 编译通过；4 把 .tres 加载无错。
- [ ] PlayerCharacter 起手默认 main_hand = Sword、off_hand = Bow；HUD 显示主手图标 + Sword 大招池实显条 + Bow 池虚显环形条 + 切换池条。
- [ ] 普攻 A 触发 Sword 主形态 Q/W 的 SkillTimeline；副技能 E/R 触发 Bow 副形态（应用 off_hand_multipliers 的乘子）。
- [ ] 副技能 E 命中 Slime → main_hand（Sword）的 current_ult_energy 增长（**不**是 off_hand）。
- [ ] 切换池 = 50 时按 F → 满切：原主手 Sword 切出技触发 + 原副手 Bow 切入技触发；主副位互换；切换池清零；CD 1.0s 内再按 F 无效；HUD 大招池数字过渡渐变。
- [ ] 切换池 < 50 时按 F → 裸切：仅换位、不触发切入切出；CD 0.5s。
- [ ] 切换瞬间 0.3s 内被攻击 → 无敌（不掉血）。
- [ ] 卸下 main_hand（替换装备测试） → 该武器 current_ult_energy 立刻归零；新装备的 current_ult_energy 起始 0。
- [ ] Sword 当主手时 main_hand_passive 生效（连段第3段必暴击）；切到副手位时主位被动失效、副位被动生效。
- [ ] 大招池满 + 按 Space → 释放 main_hand 大招；池清 100；CD 内不能再放。
- [ ] 玩家死亡 → 双武器、所有池子、ASC 状态全部按 04 文档 RunSnapshot 字段被记录（验收点跨 D5）。

---

## 6. 与其它文档的衔接

- F 键监听 / 切换 CD 内禁所有 combat_* → **01_战斗框架_输入映射_Dolphin适配.md**
- 命中事件 → 13 步公式 → 充能 → ult/switch 字段 → **02_战斗框架_属性公式_Dolphin适配.md**
- WeaponInstance 进 / 出仓库 / 跟随存档点回滚 → **04_系统框架_死亡存档仓库_Dolphin适配.md**

---

## 7. 变更日志

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-05-20 | 从前项目 02 v3.1 任务 B / F.4 / F.4.X / F.5 / F.7 + 23 §A5 萃取，加 UE→Godot 等价物映射、WeaponDefinition / WeaponInstance / EquipmentComponent 完整 GDScript 骨架、F 切换 9 步流程、4 把占位武器表、D4 任务分解。**主副位独立技能数组结构是强制工程约束**（防 v1.0 重构）。|
