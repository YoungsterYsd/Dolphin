## AttributeSet 基类（Resource）。
##
## 子类用 [code]@export[/code] 声明属性。运行时通过 [method set_attr] 修改，自动 clamp + 广播。
## R-GAS-02：业务代码禁止直接 [code]attribute_set.health = x[/code]，必须经 [method set_attr]。
##
## 广播：[signal EventBus.attribute_changed(owner, attr_name, old_value, new_value)]。
##
## 子类应重写 [method get_attribute_max] 提供"上限属性"映射（例如 health → max_health），
## 由 [method set_attr] 自动应用 clamp(0, max)。无上限的属性返回 -1。
class_name AttributeSet
extends Resource

## 持有该 AttributeSet 的节点（一般为 ASC 所在节点）。由 ASC 在 ready 时设置。
## 用于属性变更广播时携带 owner 上下文。
var owner_node: Node = null


## 修改属性值。统一入口，走 clamp + 广播。
## 返回最终落地值（被 clamp 后）。
func set_attr(attr_name: StringName, value: float) -> float:
	if not _has_attribute(attr_name):
		GameLogger.error("GAS", "AttributeSet has no attribute: %s" % attr_name)
		return 0.0
	var old_value: float = get(attr_name)
	var max_val := get_attribute_max(attr_name)
	var clamped: float = value
	if max_val >= 0.0:
		clamped = clampf(value, 0.0, max_val)
	else:
		clamped = maxf(value, 0.0)  # 默认所有属性 ≥ 0
	if is_equal_approx(clamped, old_value):
		return clamped
	set(attr_name, clamped)
	if owner_node != null:
		EventBus.attribute_changed.emit(owner_node, attr_name, old_value, clamped)
	return clamped


## 增量修改：value += delta。
func add_to_attr(attr_name: StringName, delta: float) -> float:
	return set_attr(attr_name, get_attr(attr_name) + delta)


## 读取属性值。
func get_attr(attr_name: StringName) -> float:
	if not _has_attribute(attr_name):
		GameLogger.error("GAS", "AttributeSet has no attribute: %s" % attr_name)
		return 0.0
	return get(attr_name)


## 子类重写：返回属性的上限属性名（如 &"max_health"），
## 或返回固定数值上限（>=0），无上限返回 -1。
##
## 默认实现：约定凡是有 [code]max_xxx[/code] 同名属性的，自动作为 xxx 的上限。
func get_attribute_max(attr_name: StringName) -> float:
	var max_name := StringName("max_" + String(attr_name))
	if _has_attribute(max_name):
		return get(max_name)
	return -1.0


func _has_attribute(attr_name: StringName) -> bool:
	for p in get_property_list():
		if p.name == String(attr_name):
			return true
	return false
