## PrimaryAttributeSet（玩家挂载，敌人不挂）。
##
## 对齐 [code]Plans/前项目/角色系统_属性_旧案.md[/code]：仅保留旧案明确的攻防/暴击/特殊属性。
## 已删除：strength / dexterity / intelligence / vitality（主属性 4 件套）；
##         spell_power_base / spell_power_final（法术攻击 2 件套）。
##
## ── 字段分组（共 16）──
## 攻击 4：attack_base / attack_bonus / attack_mul / attack_final
##   公式：attack_final = (attack_base + attack_bonus) * (1 + attack_mul)
##   对应旧案：基础攻击 / 额外攻击 / %攻击 / 最终攻击
## 防御 5：armor_base / armor_bonus / armor_mul / armor_final / def_pierce
##   公式：armor_final = (armor_base + armor_bonus) * (1 + armor_mul)
##   对应旧案：基础防御 / 额外防御 / %防御 / 最终防御 / %防御穿透
## 暴击 2：crit_chance / crit_damage_mul
##   对应旧案：%暴击 / %暴伤
## 增减伤 2：dmg_inc_mul / dmg_red_mul
##   对应旧案：%增伤 / %减伤
## 特殊 3：energy_gain_mul / break_bonus / life_steal_mul
##   对应旧案：%充能倍率 / %击破加成 / %吸血
## 速度 1：normal_skill_speed
##   对应旧案：%普攻速度（普攻速度 = %普攻速度，move_speed 由 HealthSet 管）
##
## ⚠️ 派生公式：DamagePipeline 入口动态计算，本 Set 内**不做衍生**。
## 玩家加点 / 装备词条改 attack_bonus / attack_mul 后由调用方手动调用 [method recompute_derived]。
class_name PrimaryAttributeSet
extends AttributeSet

# ─────────────────────────────────────────────────────────────
# 攻击 4
# ─────────────────────────────────────────────────────────────

## 基础攻击（旧案 Atk_Basic）。
@export var attack_base: float = 10.0

## 额外攻击（装备/词条加成，旧案 Atk_PostAdd）。
@export var attack_bonus: float = 0.0

## %攻击（百分比加成，旧案 Atk_Mul）。0=无，0.2=+20%。
@export var attack_mul: float = 0.0

## 最终攻击（衍生：(attack_base + attack_bonus) * (1 + attack_mul)）。
@export var attack_final: float = 10.0

# ─────────────────────────────────────────────────────────────
# 防御 5
# ─────────────────────────────────────────────────────────────

## 基础防御（旧案 Def_Basic）。
@export var armor_base: float = 5.0

## 额外防御（旧案 Def_PostAdd）。
@export var armor_bonus: float = 0.0

## %防御（旧案 Def_Mul）。
@export var armor_mul: float = 0.0

## 最终防御（衍生）。
@export var armor_final: float = 5.0

## %防御穿透 (0~1)。0 不穿，1 全穿（旧案 IgnDef）。
@export var def_pierce: float = 0.0

# ─────────────────────────────────────────────────────────────
# 暴击 2
# ─────────────────────────────────────────────────────────────

## 暴击率 (0~1)（旧案 Crit）。
@export var crit_chance: float = 0.0

## 暴击伤害倍率（默认 1.5 = 暴击多 50%，旧案 CritDmg）。
@export var crit_damage_mul: float = 1.5

# ─────────────────────────────────────────────────────────────
# 增减伤 2
# ─────────────────────────────────────────────────────────────

## 我方造成伤害的增伤率（旧案 Dmg_Mul）。
@export var dmg_inc_mul: float = 0.0

## 我方承受伤害的减伤率（旧案 DmgRed_Mul）。
@export var dmg_red_mul: float = 0.0

# ─────────────────────────────────────────────────────────────
# 特殊 3
# ─────────────────────────────────────────────────────────────

## %充能倍率（旧案 PowerRegenRate）。EnergyComponent 命中加能量时使用。
@export var energy_gain_mul: float = 0.0

## %击破加成（旧案 BreakBonus）。DamagePipeline 第 12 步使用。
@export var break_bonus: float = 0.0

## %吸血（旧案 HealthSteal，0~1）。DamagePipeline 第 11 步使用。
@export var life_steal_mul: float = 0.0

# ─────────────────────────────────────────────────────────────
# 速度 1
# ─────────────────────────────────────────────────────────────

## %普攻速度（旧案 NormalSkillSpeed）。0=基础速度，0.2=+20%。
@export var normal_skill_speed: float = 0.0


# ─────────────────────────────────────────────────────────────
# 衍生公式重算（DamagePipeline 入口调用，玩家加点 / 装备词条变更后也调用）
# ─────────────────────────────────────────────────────────────

## 把 attack/armor 的 _final 字段按公式重新算一遍。
##
## 调用时机：
## 1. DamagePipeline.compute_and_apply 入口
## 2. 玩家加点 / 装备词条变更后（手动调）
##
## 注：用 set_attr 而非直接赋值，是为了走 [signal EventBus.attribute_changed] 广播链路（HUD 刷新）。
func recompute_derived() -> void:
	set_attr(&"attack_final", (attack_base + attack_bonus) * (1.0 + attack_mul))
	set_attr(&"armor_final", (armor_base + armor_bonus) * (1.0 + armor_mul))


## 上限钳制：暴击 / 防穿 / 减伤 / 吸血率 应钳到 [0, 1] 区间。
##
## R-CODE-02：声明式 hook 表，O(1) 查表替代字符串反射钩子。
func _get_attribute_hooks() -> Dictionary:
	return {
		&"crit_chance":     {"clamp_min": 0.0, "clamp_max": 1.0},
		&"def_pierce":      {"clamp_min": 0.0, "clamp_max": 1.0},
		&"dmg_red_mul":     {"clamp_min": 0.0, "clamp_max": 1.0},
		&"life_steal_mul":  {"clamp_min": 0.0, "clamp_max": 1.0},
	}
