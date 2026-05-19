## 属性修饰器（Resource，用于 GameplayEffect.modifiers）。
##
## 描述对单个属性的一次修改。op 决定运算方式，magnitude 是数值。
##
## 示例：health -= 10 → attribute=&"health", op=ADD, magnitude=-10.0
class_name AttributeModifier
extends Resource

enum Op {
	ADD,        # value += magnitude
	MULTIPLY,   # value *= magnitude
	OVERRIDE,   # value = magnitude
}

@export var attribute: StringName = &""
@export var op: Op = Op.ADD
@export var magnitude: float = 0.0


## 把本修饰器应用到 attribute_set。返回旧值与新值供调用方参考。
func apply_to(attribute_set: AttributeSet) -> Dictionary:
	var old_value := attribute_set.get_attr(attribute)
	var new_value: float = old_value
	match op:
		Op.ADD:
			new_value = old_value + magnitude
		Op.MULTIPLY:
			new_value = old_value * magnitude
		Op.OVERRIDE:
			new_value = magnitude
	new_value = attribute_set.set_attr(attribute, new_value)
	return {"old": old_value, "new": new_value}
