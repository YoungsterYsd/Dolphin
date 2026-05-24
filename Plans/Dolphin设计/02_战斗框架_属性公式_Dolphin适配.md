# 战斗框架 · 属性公式 / 13 步伤害管线（Dolphin 适配版）

> **来源**：前项目 `02_战斗操作与能量决策.md` 任务 C / F.2 / F.3 / F.9、`角色系统_属性_旧案.md`、`14_后续日程与验收清单.md` §3、`22_A3阶段最终验收报告.md` §3.1。
> **本文定位**：Dolphin 接下来落地的「属性 / 能量 / 伤害」核心，对应里程碑 **D2**。
> **不包含**：输入键位（→ 文档 01）、武器双槽 / 切入切出（→ 文档 03）、死亡 / 存档（→ 文档 04）。
> **状态**：字段结构 + 13 步公式 + 9 个 GE + 3 套 Set 锁定；具体数值挂起。

---

## 0. UE → Godot 等价物映射表

| 前项目（UE / Lyra GAS） | Dolphin（Godot 4.6 自研 GAS） |
|---|---|
| `UAttributeSet` 子类 | `Script/GAS/AttributeSet.gd` 子类（继承 Resource）|
| `FGameplayAttributeData` | AttributeSet 内的 `float` 字段 + 同名 `_max` / `_base` 配套 |
| `ATTRIBUTE_ACCESSORS` 宏 | GDScript 直接 `var health_final: float` + `set/get`|
| `UGameplayEffect`（Instant / Duration / Infinite）| `Script/GAS/GameplayEffect.gd` Resource，含 duration_type / modifiers / period |
| `FGameplayEffectModifierMagnitude::ScalableFloat` | GE.modifiers[i].magnitude（float）+ 可选 `attribute_based_source` 引用 |
| `UGameplayEffectExecutionCalculation`（执行类伤害公式）| `Script/GAS/DamagePipeline.gd` 静态函数（不走 GE 执行类）|
| `SetByCaller` 数据传递 | `GE.set_by_caller_tags: Dictionary` + 应用时 `apply_effect(spec, context)` 把 caller 数据塞 spec |
| `PreAttributeChange / PostGameplayEffectExecute` | AttributeSet 内的 `_pre_change_<attr>` / `_post_apply_effect` 钩子函数 |
| `FActiveGameplayEffectsContainer` | `AbilitySystemComponent.active_effects: Array[ActiveGameplayEffect]` |
| `OnOutOfHealth` 元属性 | EventBus.`out_of_health(target)` 信号 |
| `UDataTable`（属性成长表）| `Data/Config/AttributeGrowthTables/Growth_*.tres` Resource |

**关键差异**：Godot 没有 `ExecutionCalculation`，**13 步伤害公式集中在 `DamagePipeline.compute_and_apply()` 静态函数里**，避免分散到多个 GE。GE 只负责"乘性 / 加性 Modifier 注入"和"持续 / 周期"。

---

## 1. 三套 AttributeSet（结构锁定）

完整对应前项目 14 文档 §3.2 + §3.3 锁定的 27 字段。

### 1.1 HealthSet（6 字段，挂玩家与所有敌人）

```gdscript
# Script/GAS/Attributes/HealthSet.gd
extends AttributeSet
class_name HealthSet

@export var health_final: float = 1.0     # 当前血量（已计算护甲后）
@export var health_max: float   = 100.0   # 当前最大血量
@export var health_healing: float = 0.0   # 元属性：本帧待加血量
@export var health_damage: float  = 0.0   # 元属性：本帧待扣血量
@export var stamina_current: float = 100.0
@export var stamina_max: float     = 100.0

func _post_apply_effect(spec) -> void:
    if abs(health_damage) > 0.0001:
        health_final = clamp(health_final - health_damage, 0.0, health_max)
        health_damage = 0.0
        if health_final <= 0.0:
            EventBus.out_of_health.emit(get_owner_asc())
    if abs(health_healing) > 0.0001:
        health_final = clamp(health_final + health_healing, 0.0, health_max)
        health_healing = 0.0

func _pre_change_health_max(new_value: float) -> float:
    return max(1.0, new_value)
```

### 1.2 PrimaryAttributeSet（21 字段，仅玩家）

按前项目 §3.2.2 分 7 组：

| 组 | 字段 | 说明 |
|---|---|---|
| 主属性 | `strength` / `dexterity` / `intelligence` / `vitality` | 4 个，词条/加点入口 |
| 攻击 | `attack_base` / `attack_bonus` / `attack_mul` / `attack_final` | 衍生：Final = (Base+Bonus)*(1+Mul)|
| 法术 | `spell_power_base` / `spell_power_final` | 同上 |
| 防御 | `armor_base` / `armor_final` / `def_pierce` | def_pierce = 防御穿透% |
| 暴击 | `crit_chance` / `crit_damage_mul` | 0~1 / 倍率（默认 1.5）|
| 增减伤 | `dmg_inc_mul` / `dmg_red_mul` | 增伤 / 承伤率 |
| 能量 / 速度 | `energy_gain_mul` / `move_speed_mul` / `break_bonus` / `life_steal_mul` | 充能倍率 / 移速 / 破韧 / 吸血率 |

> **注意**：副本敌人不挂 PrimaryAttributeSet，只挂 HealthSet + CombatSet（敌人不需要 STR/DEX，由怪物配置直接给最终伤害值）。

### 1.3 CombatSet（玩家 + 敌人都挂，作为命中输入）

```gdscript
extends AttributeSet
class_name CombatSet

@export var base_damage: float = 0.0   # SetByCaller 由技能注入
@export var base_heal: float   = 0.0
```

DamagePipeline 通过这俩元属性传递每次 hit 的"基础伤害值"。

### 1.4 能量子集（独立 Set，仅玩家）

按 02 文档 F.4 锁定，**池子绑武器实例**而不是放 AttributeSet：

```gdscript
# Script/Character/Components/EnergyComponent.gd
@export var switch_energy: float       # 全局共用
@export var switch_energy_max: float = 50.0

# 大招池存放在 WeaponInstance.current_ult_energy 上（详见武器文档）
func get_current_main_ult_energy() -> float:
    return EquipmentComponent.main_hand.current_ult_energy if EquipmentComponent.main_hand else 0.0
```

### 1.5 格挡耐久（PrimaryAttributeSet 拓展，挂玩家）

```gdscript
@export var block_max: float = 100.0
@export var block_regen_delay: float = 2.0
@export var block_regen_rate: float = 10.0           # 脱战 1 秒回复点数
@export var block_regen_rate_in_combat: float = 0.0  # v3 预留，默认 0
@export var block_current: float = 100.0
```

---

## 2. 9 个 GameplayEffect（结构锁定，数值挂起）

照前项目 §3.4 锁定：

| GE 资源（.tres） | duration_type | 主要 Modifier | 触发场景 |
|---|---|---|---|
| `GE_Init_PrimaryAttributes.tres` | Instant | 11 个主属性初值 | 角色 spawn 时 |
| `GE_Init_DerivedAttributes.tres` | Infinite | 7 个衍生属性公式（attack_final = ...）| 角色 spawn 时（不可移除）|
| `GE_HealthInit_Full.tres` | Instant | health_final = health_max | spawn / 复活 / 检查点 |
| `GE_HealthRegen.tres` | Infinite + Periodic 1s | +health_healing | 默认全程挂；战斗中由 Tag 屏蔽 |
| `GE_StaminaRegen.tres` | Infinite + Periodic 0.5s | +stamina_current | 同上 |
| `GE_BlockRegen.tres` | Infinite + Periodic 0.2s | +block_current | 仅脱战时激活；判定见 1.5 |
| `GE_BlockState.tres` | Duration（按住时长）| GrantedTag = Combat.Block.Active | D 键按下时挂 |
| `GE_PerfectBlockBuff.tres` | Duration 5s | GrantedTag = Combat.Buff.PerfectBlock + dmg_inc_mul +0.5 | 完美格挡触发 |
| `GE_CombatActive.tres` | Duration 5s（由 CombatStateService 维护）| GrantedTag = State.Combat.Active | 受 / 造成伤害时刷新 |

> 派生 GE（如吸血触发的 GE_LifeSteal_Heal、暴击 buff 等）按需新增；不算入 9 个核心 GE。

---

## 3. 13 步伤害管线（DamagePipeline）

完全按前项目 22 §3.1 + 02 §F.2 锁定。`DamagePipeline.gd` 静态函数：

```gdscript
# Script/GAS/DamagePipeline.gd
class_name DamagePipeline

static func compute_and_apply(
        attacker: Node,           # 持有 ASC 的攻击方
        target: Node,             # 持有 ASC 的目标
        base_damage: float,       # 技能注入的基础伤害（已含武器倍率）
        damage_tags: Array[StringName],  # 例如 ["Damage.Physical", "Damage.Skill"]
        is_skill: bool = false,
        forced_crit: bool = false # 完美格挡 buff 强制 / 词条强制
) -> Dictionary:
    
    var atk = attacker.asc.get_attribute("attack_final") if not is_skill else attacker.asc.get_attribute("spell_power_final")
    var dmg = base_damage * atk
    
    # 1. 暴击判定
    var is_crit = forced_crit or (randf() < attacker.asc.get_attribute("crit_chance"))
    if is_crit:
        dmg *= attacker.asc.get_attribute("crit_damage_mul")  # 默认 1.5
    
    # 2. 防御穿透
    var armor = target.asc.get_attribute("armor_final") * (1.0 - attacker.asc.get_attribute("def_pierce"))
    
    # 3. 承伤率（防御公式：dmg / (1 + armor / K)，K = 100 占位）
    dmg = dmg * 100.0 / (100.0 + max(armor, 0.0))
    
    # 4. 增伤
    dmg *= (1.0 + attacker.asc.get_attribute("dmg_inc_mul"))
    
    # 5. 减伤（目标承受）
    dmg *= (1.0 - target.asc.get_attribute("dmg_red_mul"))
    
    # 6. 完美格挡 buff（攻击方持有该 tag → +50% 伤害 + 破韧 ×3）
    var has_pb = attacker.asc.has_tag(&"Combat.Buff.PerfectBlock")
    if has_pb:
        dmg *= 1.5
        attacker.asc.remove_tag(&"Combat.Buff.PerfectBlock")  # 单次释放
    
    # 7. 目标处于完美格挡窗口（按下 0.3s 内）→ 完全免伤 + 通知刷 Buff
    if target.has_method("is_perfect_block_window") and target.is_perfect_block_window():
        EventBus.damage_perfect_blocked.emit(attacker, target, dmg)
        target.trigger_perfect_block_buff()
        return {"dealt": 0.0, "is_crit": is_crit, "is_perfect_block": true}
    
    # 8. 目标处于普通格挡（持续 D 键按住）→ 按耐久 ×0.6 消耗
    if target.asc.has_tag(&"Combat.Block.Active"):
        var consume = dmg * 0.6
        target.asc.consume_block(consume)  # 内部判耐久耗尽 → 1.2s 硬直
        if target.asc.has_tag(&"Combat.Block.Broken"):
            # 9. 破防 → 全额承伤
            pass
        else:
            dmg *= 0.4  # 普通格挡减伤 60%
    
    # 10. 应用扣血（通过 CombatSet.base_damage → HealthSet 元属性管线）
    var spec = GameplayEffectSpec.make(&"GE_DamageInstant", attacker, target)
    spec.set_by_caller_tags[&"SetByCaller.Damage"] = dmg
    target.asc.apply_effect_spec(spec)
    
    # 11. 吸血（攻击方）
    var ls = attacker.asc.get_attribute("life_steal_mul")
    if ls > 0.0:
        var heal_spec = GameplayEffectSpec.make(&"GE_HealInstant", attacker, attacker)
        heal_spec.set_by_caller_tags[&"SetByCaller.Heal"] = dmg * ls
        attacker.asc.apply_effect_spec(heal_spec)
    
    # 12. 破韧值（仅在目标支持破韧时）
    var break_pts = base_damage * 0.1 * (1.0 + attacker.asc.get_attribute("break_bonus"))
    if has_pb:
        break_pts *= 3.0
    if target.has_method("apply_break"):
        target.apply_break(break_pts)
    
    # 13. 飘字 / Cue 广播
    EventBus.damage_dealt_v2.emit({
        "attacker": attacker, "target": target,
        "dealt": dmg, "is_crit": is_crit,
        "is_block": target.asc.has_tag(&"Combat.Block.Active") and not has_pb,
        "is_perfect_block": false,
        "tags": damage_tags,
    })
    
    return {"dealt": dmg, "is_crit": is_crit, "is_perfect_block": false}
```

> **关键约束**：现有 `Script/Combat/HitDamageResolver.gd`（M7.2 的 1 步公式）替换为对 `DamagePipeline.compute_and_apply()` 的直接调用，**不要并行保留两套伤害逻辑**。

---

## 4. 双池能量系统（与文档 03 共同实现）

| 池 | 上限 | 归属 | 存储位置 |
|---|---|---|---|
| 大招池（每武器各 1）| 100 | 武器实例 | `WeaponInstance.current_ult_energy` |
| 切换池 | 50 | 角色 | `EnergyComponent.switch_energy` |

### 4.1 能量获取事件钩子

```gdscript
# Script/Character/Components/EnergyComponent.gd
func _ready():
    EventBus.damage_dealt_v2.connect(_on_damage_dealt)
    EventBus.dodge_started.connect(_on_dodge)
    EventBus.block_perfect_triggered.connect(_on_perfect_block)
    EventBus.block_normal_triggered.connect(_on_normal_block)
    EventBus.enemy_killed.connect(_on_kill)

func _on_damage_dealt(payload: Dictionary):
    if payload.attacker != owner: return
    var ult_gain = _read_config(payload).ult
    var sw_gain  = _read_config(payload).switch
    # 应用 EnergyGainMul（充能倍率）
    var mul = owner.asc.get_attribute("energy_gain_mul")
    ult_gain = _prob_round(ult_gain * (1.0 + mul))
    sw_gain  = _prob_round(sw_gain  * (1.0 + mul))
    EquipmentComponent.main_hand.add_ult_energy(ult_gain)
    add_switch_energy(sw_gain)
```

`_prob_round(x)`：概率取整，`x = 4.5 → 50% 4 / 50% 5`（前项目 F.9 锁定）。

### 4.2 能量配置表（占位字段，数值挂起）

| 行为 | ult 字段 | switch 字段 | 来源 |
|---|---|---|---|
| 主普攻命中 | `energy_main_atk_ult` | `energy_main_atk_switch` | C.9 表 |
| 主技能命中 | `energy_main_skill_ult` | `energy_main_skill_switch` | — |
| 副技能命中 | `energy_off_skill_ult` | `energy_off_skill_switch` | — |
| 完美闪避 | `energy_perfect_dodge_ult` | `energy_perfect_dodge_switch` | — |
| 完美格挡 | `energy_perfect_block_ult` | `energy_perfect_block_switch` | — |
| ……（详见 02 文档 C.9 完整 31 行表）|

存储在 `Data/Config/EnergyGainTable.tres`（Resource，可热改）。

---

## 5. Godot 落地步骤（D2 里程碑分解）

| 任务 | 落地点 | 工时 |
|---|---|---|
| D2.1 重写 HealthSet（6 字段 + 元属性管道）| `Script/GAS/Attributes/HealthSet.gd` | 0.7d |
| D2.2 新建 PrimaryAttributeSet（21 字段）| `Script/GAS/Attributes/PrimaryAttributeSet.gd` | 1.0d |
| D2.3 新建 CombatSet（base_damage / base_heal）| `Script/GAS/Attributes/CombatSet.gd` | 0.2d |
| D2.4 9 个 GE 资源 .tres | `Data/GameData/GE/` | 1.0d |
| D2.5 8 步初始化顺序 | `BaseCharacter._wire_components` 末尾按 §3.3.4 严格 8 步 | 0.3d |
| D2.6 DamagePipeline.gd 13 步公式 | `Script/GAS/DamagePipeline.gd` | 1.5d |
| D2.7 CombatStateService | `Script/Combat/CombatStateService.gd`（GameInstance 子节点）| 0.3d |
| D2.8 EnergyComponent 接通命中钩子 | `Script/Character/Components/EnergyComponent.gd` | 0.5d |
| D2.9 BlockComponent 接 PerfectBlock buff | `Script/Character/Components/BlockComponent.gd` | 0.5d |
| D2.10 飘字接新公式 | M8 DamagePopup 改订 `damage_dealt_v2` 增 `is_perfect_block` / `is_block` 样式 | 0.3d |
| D2.11 验收 | TestArena 玩家 → Slime 13 步全跑通；ShowDebug 显 27 属性 | 0.4d |

---

## 6. 验收清单（D2 完成时）

- [ ] HealthSet / PrimaryAttributeSet / CombatSet 三个 .gd 编译通过；ShowDebug 一行能列全 27 属性。
- [ ] 9 个 GE 资源完整可加载，初始化 8 步走完后 `attack_final = (attack_base + attack_bonus) * (1 + attack_mul)` 正确推导。
- [ ] 玩家普攻 Slime 触发 13 步公式：暴击 → 防御穿透 → 减伤 → 增伤 → 完美格挡判定 → 普通格挡 → 应用扣血 → 吸血 → 破韧 → 飘字。
- [ ] Slime 完美格挡判定窗口内挨打 → 0 伤害 + 自身 PerfectBlock buff 5s。
- [ ] CombatStateService：玩家与 Slime 互打时 `combat_state_changed(true)`；脱离 5s 且 8m 内无敌人后 `combat_state_changed(false)`。
- [ ] EnergyComponent：普攻命中后 WeaponInstance.current_ult_energy 与 switch_energy 按配置表加值；带 `energy_gain_mul` 词条时概率取整生效。
- [ ] 飘字四样式：白普攻 / 金暴击 / 灰普通格挡 / 银完美格挡。
- [ ] `EnergyGainTable.tres` 改一个数值，不重启工程能直接生效（Resource 热改）。

---

## 7. 与其它文档的衔接

- 命中事件来源（普攻 / 技能 / 闪避 / 格挡）→ **01_战斗框架_输入映射_Dolphin适配.md** §1
- WeaponInstance / EquipmentComponent 的双槽 / 主副位 multiplier → **03_战斗框架_武器切换_Dolphin适配.md**
- 死亡时 ASC 清空 + RunSnapshot 字段对应 → **04_系统框架_死亡存档仓库_Dolphin适配.md**

---

## 8. 变更日志

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-05-20 | 从前项目 02 v3.1 任务 C / F.2 / F.3 / F.9 + 14 §3 + 22 §3.1 萃取，加 Godot 等价物映射、HealthSet/PrimaryAttributeSet/CombatSet 三套 27 字段、9 个 GE 列表、DamagePipeline 13 步完整伪代码、EnergyComponent 命中钩子骨架、D2 任务分解。**数值（C.9 表 / F.3 推荐值）参阅源文档**。|
