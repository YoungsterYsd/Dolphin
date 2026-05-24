## 属性数据 Provider —— [IAttributeReadable] 的标准实现。
##
## 包一个 [AbilitySystemComponent]（持有 AttributeSet）+ 主属性名 + 上限属性名，
## 订阅 [signal EventBus.attribute_changed]，在 owner 匹配时派发 [signal value_changed]。
##
## 用法（业务侧 / Phase 3 widget bind_data 时构造）：
##     var p := AttributeProvider.new()
##     p.asc = player.asc
##     p.attribute_name = &"health"
##     p.max_attribute_name = &"max_health"   # 留空时 max=1.0（按纯数值显示）
##     widget.bind_data(p)
class_name AttributeProvider
extends IAttributeReadable

## 关联的 ASC（持有 attribute_sets）。
## 注：因 Resource 子类不能 @export Node 派生类，必须由业务侧通过代码赋值（不能在 Inspector 拖入）。
## 业务侧用法：
##     var p := AttributeProvider.new()
##     p.asc = player.asc
##     p.attribute_name = &"health"
##     p.max_attribute_name = &"max_health"
##     widget.bind_data(p)
var asc: AbilitySystemComponent = null

## 主属性名（如 &"health"）。可在 Inspector 编辑。
@export var attribute_name: StringName = &""

## 上限属性名（如 &"max_health"）。空字符串 → 视为无上限，[method get_max_value] 返回 1.0。
@export var max_attribute_name: StringName = &""


func _init() -> void:
	# 自动接入 EventBus.attribute_changed
	EventBus.attribute_changed.connect(_on_attribute_changed)


# ─────────────────────────────────────────────────────────────
# IAttributeReadable 实现（R-ASC 重构：用 ASC.get_attribute 跨 Set 查找替代 attribute_set 老接口）
# ─────────────────────────────────────────────────────────────

func get_value() -> float:
	if asc == null or attribute_name == &"":
		return 0.0
	return asc.get_attribute(attribute_name, 0.0)


func get_max_value() -> float:
	if max_attribute_name == &"":
		return 1.0
	if asc == null:
		return 1.0
	return asc.get_attribute(max_attribute_name, 1.0)


func get_attribute_name() -> StringName:
	return attribute_name


# ─────────────────────────────────────────────────────────────
# 信号转发
# ─────────────────────────────────────────────────────────────

func _on_attribute_changed(owner_node: Node, attr_name: StringName, old_value: float, new_value: float) -> void:
	if asc == null:
		return
	# 比对：业务侧 attribute_changed 派发时 owner = ASC 的 parent（角色根节点）
	if owner_node != asc.get_parent():
		return
	if attr_name == attribute_name or attr_name == max_attribute_name:
		value_changed.emit(old_value, new_value)
