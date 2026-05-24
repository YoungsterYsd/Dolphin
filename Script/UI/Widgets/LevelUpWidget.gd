## 升级横幅。
##
## 订阅 [signal EventBus.attribute_changed]，当 [code]attr == &"level"[/code] 且 new > old 时显示
## 「LEVEL UP」+ 新等级。也可由 [signal EventBus.hud_big_banner_requested.emit(&"level_up")] 兜底触发。
##
## **前置依赖**：当前 AttributeSet 体系没有 [code]level[/code] 属性，
## 业务侧暂不会派发；本 widget 用于占位。等等级系统接入后自动连通。
class_name LevelUpWidget
extends BaseWidget

@export var fade_in_seconds: float = 0.3
@export var hold_seconds: float = 1.5
@export var fade_out_seconds: float = 0.5

@onready var label: Label = $Label

var _tween: Tween = null


func _ready() -> void:
	super._ready()
	modulate.a = 0.0
	visible = false
	EventBus.attribute_changed.connect(_on_attribute_changed)


func _on_attribute_changed(owner_node: Node, attr_name: StringName, old_value: float, new_value: float) -> void:
	if owner_node == null or not owner_node.is_in_group(&"player"):
		return
	if attr_name != &"level":
		return
	if new_value <= old_value:
		return
	_show(int(new_value))


func _show(level: int) -> void:
	label.text = "LEVEL UP\n%d" % level
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", 1.0, fade_in_seconds)
	_tween.tween_interval(hold_seconds)
	_tween.tween_property(self, ^"modulate:a", 0.0, fade_out_seconds)
	_tween.tween_callback(func(): visible = false)
