## 属性修饰器（Resource，用于 GameplayEffect.modifiers）。
##
## 描述对单个属性的一次修改。op 决定运算方式，magnitude 是数值。
##
## 示例：health -= 10 → attribute=&"health", op=ADD, magnitude=-10.0
##
## [enum MagnitudeSource] 让 magnitude 可由两种来源提供：
## - LITERAL（默认）：使用 [member magnitude] 字段值
## - SET_BY_CALLER：从 [GameplayEffectSpec.set_by_caller_data] 按 [member set_by_caller_tag] 取值
##   （DamagePipeline / 技能 caller 注入运行时计算结果，避免"每个伤害都新建一份 GE"）
class_name AttributeModifier
extends Resource

enum Op {
	ADD,        # value += magnitude
	MULTIPLY,   # value *= magnitude
	OVERRIDE,   # value = magnitude
}

## magnitude 数值来源。
enum MagnitudeSource {
	LITERAL,        # 直接用 magnitude 字段（默认）
	SET_BY_CALLER,  # 从 spec.set_by_caller_data[set_by_caller_tag] 取
}

@export var attribute: StringName = &""
@export var op: Op = Op.ADD
@export var magnitude: float = 0.0

## magnitude 来源。默认 LITERAL（与无 spec 调用兼容）。
@export var magnitude_source: MagnitudeSource = MagnitudeSource.LITERAL

## 当 magnitude_source = SET_BY_CALLER 时，从 spec.set_by_caller_data 取值的 key。
## 命名约定：以 &"SetByCaller." 开头，例如 &"SetByCaller.Damage" / &"SetByCaller.Heal"。
@export var set_by_caller_tag: StringName = &""


## 解析本 modifier 在当前 spec 下的实际 magnitude 数值。
func resolve_magnitude(spec: GameplayEffectSpec = null) -> float:
	match magnitude_source:
		MagnitudeSource.LITERAL:
			return magnitude
		MagnitudeSource.SET_BY_CALLER:
			if spec == null:
				GameLogger.warn("GAS", "AttributeModifier(%s) is SET_BY_CALLER but no spec provided, fallback to literal magnitude" % attribute)
				return magnitude
			if set_by_caller_tag == &"":
				GameLogger.warn("GAS", "AttributeModifier(%s) is SET_BY_CALLER but set_by_caller_tag is empty" % attribute)
				return magnitude
			return spec.get_set_by_caller(set_by_caller_tag, magnitude)
	return magnitude


## 把本修饰器应用到 attribute_set。返回旧值与新值供调用方参考。
##
## spec 参数可选：缺省时按 LITERAL 处理（与无 SetByCaller 数据的调用兼容）。
func apply_to(attribute_set: AttributeSet, spec: GameplayEffectSpec = null) -> Dictionary:
	var old_value := attribute_set.get_attr(attribute)
	var mag := resolve_magnitude(spec)
	var new_value: float = old_value
	match op:
		Op.ADD:
			new_value = old_value + mag
		Op.MULTIPLY:
			new_value = old_value * mag
		Op.OVERRIDE:
			new_value = mag
	new_value = attribute_set.set_attr(attribute, new_value)
	return {"old": old_value, "new": new_value}
