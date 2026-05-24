## GameplayEffectSpec。
##
## 一次 GE 应用的"运行时携带数据"包装类。Lyra UE 的 FGameplayEffectSpec 等价物。
##
## 用途：让 [GameplayEffect] 资源（设计期数据）保持不可变，把"本次应用的可变数据"
## （如施法者注入的伤害值、目标方向、随机种子等）放进 spec 里随调用流转。
##
## 主要承载 [b]SetByCaller[/b] 数据：
##   - GE.modifier 中 [member AttributeModifier.magnitude_source] = SET_BY_CALLER 时，
##     从 [member set_by_caller_data] 按 [member AttributeModifier.set_by_caller_tag] 取值。
##   - 例如 DamagePipeline 第 10 步：
##     [code]
##     var spec := GameplayEffectSpec.make(GE_DamageInstant, attacker, target)
##     spec.set_by_caller_data[&"SetByCaller.Damage"] = final_dmg
##     target_asc.apply_effect_spec(spec)
##     [/code]
##
## 设计要点：
## - RefCounted（不需要节点生命周期，单次调用用完即释）
## - 老 API [code]apply_effect_to(target, ge, source)[/code] 内部转 spec，向后 100% 兼容
class_name GameplayEffectSpec
extends RefCounted

## 关联的 GE 资源（Resource）。同一个 GE 资源可被多次复用，spec 是每次应用的运行时副本。
var ge: GameplayEffect = null

## 施法者节点（一般是攻击方 BaseCharacter）。可为 null（瞬发自买 buff 等）。
var source: Node = null

## 目标节点（一般是 BaseCharacter，BaseCharacter.asc 持有 AttributeSet）。可为 null。
var target: Node = null

## SetByCaller 数据：tag → float 值。
## key 命名建议：以 &"SetByCaller." 开头，例如 &"SetByCaller.Damage" / &"SetByCaller.Heal"。
var set_by_caller_data: Dictionary = {}

## 等级（D6 词条 / 武器升级用，spec 携带等级信息便于 GE 按等级算最终值）。
## 默认 1；当前阶段未启用，仅保留字段。
var level: int = 1


## 静态构造：从 GE 资源 + source/target 构造一个新 spec。
##
## 用法：[code]var spec := GameplayEffectSpec.make(ge_resource, attacker, target)[/code]
##
## ge_resource 必填；source/target 可为 null。
static func make(ge_resource: GameplayEffect, source_node: Node = null, target_node: Node = null) -> GameplayEffectSpec:
	var spec := GameplayEffectSpec.new()
	spec.ge = ge_resource
	spec.source = source_node
	spec.target = target_node
	return spec


## 取一个 SetByCaller 数据。未设置时返回 default_value（默认 0.0）。
func get_set_by_caller(tag: StringName, default_value: float = 0.0) -> float:
	if set_by_caller_data.has(tag):
		return float(set_by_caller_data[tag])
	return default_value


## 设置一个 SetByCaller 数据（链式 API 风格，便于 spec.set_caller(...).set_caller(...)）。
func set_caller(tag: StringName, value: float) -> GameplayEffectSpec:
	set_by_caller_data[tag] = value
	return self
