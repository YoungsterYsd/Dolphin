## HealthSet（玩家与所有敌人共享）。
##
## 对齐 [code]Plans/前项目/角色系统_属性_旧案.md[/code]：保留生命/体力/移速/治疗效率，
## 删除 mana / max_mana / block_max / block_current / block_regen_* 等 7 字段。
## 格挡耐久复用 stamina_current（旧案的 MoveSpeed 拆为 base / final 两字段）。
##
## ── 字段分组（共 13）──
## 生命 4：health_base / health_bonus / health_mul / health_final / max_health
##   公式：max_health = (health_base + health_bonus) * (1 + health_mul)
##   health 是当前血量（≤ max_health），不参与衍生
##   对应旧案：基础生命 / 额外生命 / %生命 / 最大生命（衍生）
## 元属性 2：health_damage / health_healing
##   DamagePipeline 第 10 步通过 SetByCaller 写入；_post_apply_effect 反应到 health
## 体力 2：stamina_max / stamina_current
##   玩家闪避 / 格挡耐久共用；敌人不挂体力 GE 自动跳过
## 治疗效率 1：heal_rate
##   旧案第 13 步：血量回复 = 基础回复 * (1 + heal_rate)
## 移速 2：move_speed_base / move_speed_final
##   公式：move_speed_final = move_speed_base * (1 + move_speed_mul_param)
##   注：旧案没有 %移速字段，调用 [method recompute_derived] 时 mul 参数默认传 0
##   未来 D6 词条期如加 move_speed_mul 字段，由 PrimaryAttributeSet 提供并传入
##
## ── 元属性管道核心 ──
## DamagePipeline 第 10 步通过 SetByCaller 写 [member health_damage]：
## [codeblock]
## var spec := GameplayEffectSpec.make(GE_DamageInstant, attacker, target)
## spec.set_caller(&"SetByCaller.Damage", final_dmg)
## target.asc.apply_effect_spec(spec)
## [/codeblock]
## modifier 落值后触发 [method _post_apply_effect]：health_damage → 反应到 health → 清零。
##
## HP 归零时 emit [signal EventBus.out_of_health(asc)]，业务侧（EnemyCharacter）订阅桥接 enemy_died。
class_name HealthSet
extends AttributeSet

# ─────────────────────────────────────────────────────────────
# 生命 4 件套（旧案 Hp_Basic/Hp_PostAdd/Hp_Mul + 衍生 max_health）
# ─────────────────────────────────────────────────────────────

## 基础生命（旧案 Hp_Basic）。
@export var health_base: float = 100.0

## 额外生命（旧案 Hp_PostAdd）。
@export var health_bonus: float = 0.0

## %生命（旧案 Hp_Mul）。
@export var health_mul: float = 0.0

## 最大生命（衍生：(health_base + health_bonus) * (1 + health_mul)）。
##
## 业务侧（HUD/AttributeProvider）直接订阅 max_health；recompute_derived 重算。
@export var max_health: float = 100.0

## 当前血量（≤ max_health）。
@export var health: float = 100.0

# ─────────────────────────────────────────────────────────────
# 元属性管道（DamagePipeline 第 10 步通过 SetByCaller 写入；_post_apply_effect 反应到 health）
# ─────────────────────────────────────────────────────────────

## 元属性：本帧待扣血量。任何 +health_damage 的 modifier 落值后由 [method _post_apply_effect]
## 累加到 [member health] 并清零。
@export var health_damage: float = 0.0

## 元属性：本帧待加血量。
@export var health_healing: float = 0.0

# ─────────────────────────────────────────────────────────────
# 体力（玩家闪避 + 格挡耐久共用；敌人不挂相应 Regen GE）
# ─────────────────────────────────────────────────────────────

## 体力上限。
@export var stamina_max: float = 100.0

## 当前体力（闪避消耗 / 格挡耐久消耗共用）。
@export var stamina_current: float = 100.0

# ─────────────────────────────────────────────────────────────
# 治疗效率（旧案第 13 步：血量回复 = 基础回复 * (1 + heal_rate)）
# ─────────────────────────────────────────────────────────────

## 治疗效率（默认 0=基础回复，+0.2=+20%）。
@export var heal_rate: float = 0.0

# ─────────────────────────────────────────────────────────────
# 移速 2 件套（旧案 MoveSpeed 拆 base / final）
# ─────────────────────────────────────────────────────────────

## 基础移动速度（米/秒）。
@export var move_speed_base: float = 5.0

## 最终移动速度（衍生：move_speed_base * (1 + PrimaryAttributeSet.move_speed_mul)）。
##
## 敌人无 PrimaryAttributeSet 时，final = base（recompute_derived 跳过 mul）。
@export var move_speed_final: float = 5.0


# ─────────────────────────────────────────────────────────────
# 衍生公式重算（DamagePipeline 入口 / 加点 / 装备变更后调用）
# ─────────────────────────────────────────────────────────────

## 把 max_health / move_speed_final 按公式重新算一遍。
##
## - max_health 衍生：(health_base + health_bonus) * (1 + health_mul)
## - move_speed_final 衍生：move_speed_base * (1 + move_speed_mul_param)
##
## move_speed_mul_param 由调用方传入（旧案当前没有 %移速 字段，默认传 0）。
## 玩家未来加 move_speed_mul 词条时，由 ASC._run_post_inject_init 从 PrimaryAttributeSet 取并传入。
##
## 用 set_attr 而非直接赋值，是为了走 [signal EventBus.attribute_changed] 广播链路。
func recompute_derived(move_speed_mul_param: float = 0.0) -> void:
	# 先重算 max_health（不动 health 当前值；调用方决定是否拉满）
	var new_max: float = (health_base + health_bonus) * (1.0 + health_mul)
	set_attr(&"max_health", new_max)
	# 当前 health 若超过新上限，clamp 下来
	if health > new_max:
		set_attr(&"health", new_max)
	# 重算 move_speed_final
	set_attr(&"move_speed_final", move_speed_base * (1.0 + move_speed_mul_param))


# ─────────────────────────────────────────────────────────────
# 元属性管道：health_damage / health_healing 累计 → 反应到 health
# R-CODE-02：声明式 hook 表替代字符串反射钩子。
# ─────────────────────────────────────────────────────────────

## 声明式 hook 表：
## - health：上限走 max_health（覆盖默认 max_xxx 自动映射，显式声明更清晰）
## - stamina_current：上限走 stamina_max（命名不是 max_xxx 模式，需显式映射）
## - health_damage / health_healing：post_apply 元属性管道
## - health：post_apply 检测归零 → emit out_of_health
func _get_attribute_hooks() -> Dictionary:
	return {
		&"health": {
			"max_attr": &"max_health",
			"post_apply": _on_health_applied,
		},
		&"stamina_current": {"max_attr": &"stamina_max"},
		&"health_damage": {"post_apply": _on_health_damage_applied},
		&"health_healing": {"post_apply": _on_health_healing_applied},
	}


## health_damage 落值后：扣 health 并清零本字段（避免无限递归）。
func _on_health_damage_applied(_attr: StringName, _old: float, _new: float) -> void:
	if abs(health_damage) <= 0.0001:
		return
	var dmg := health_damage
	health_damage = 0.0  # 先清零，避免后续 set_attr(health) 不必要触发
	set_attr(&"health", clampf(health - dmg, 0.0, max_health))


## health_healing 落值后：加 health 并清零本字段。
func _on_health_healing_applied(_attr: StringName, _old: float, _new: float) -> void:
	if abs(health_healing) <= 0.0001:
		return
	var heal := health_healing
	health_healing = 0.0
	set_attr(&"health", clampf(health + heal, 0.0, max_health))


## health 落值后：归零时 emit out_of_health。
func _on_health_applied(_attr: StringName, old: float, new: float) -> void:
	if new <= 0.0 and old > 0.0:
		_emit_out_of_health()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _emit_out_of_health() -> void:
	var asc := get_owner_asc()
	if asc != null:
		EventBus.out_of_health.emit(asc)
