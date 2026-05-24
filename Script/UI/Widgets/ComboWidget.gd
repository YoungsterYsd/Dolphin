## Combo 计数显示 widget。
##
## 订阅 [signal EventBus.combo_changed]：
##   - count >= 2 时显示「N HIT」
##   - count == 0 时淡出隐藏
##
## 显示位置：挂 TopCenter Slot（HUDLayout 配置）。
## 强调动画：每次 count 变大时对 [member label] 做轻微 scale punch（0.05s）。
class_name ComboWidget
extends BaseWidget

## 显示阈值。低于此值不显示。
@export var min_count_to_show: int = 2

## 淡出时长。
@export var fade_seconds: float = 0.25

## 强调缩放峰值（1.0 = 不变）。
@export var emphasis_scale_peak: float = 1.25

## 强调缩放时长。
@export var emphasis_seconds: float = 0.18


@onready var label: Label = $Label

var _last_count: int = 0


func _ready() -> void:
	super._ready()
	modulate.a = 0.0
	visible = false
	EventBus.combo_changed.connect(_on_combo_changed)


func _on_combo_changed(count: int) -> void:
	if count >= min_count_to_show:
		label.text = "%d HIT" % count
		_show_with_emphasis(count > _last_count)
	else:
		_hide()
	_last_count = count


func _show_with_emphasis(grew: bool) -> void:
	visible = true
	# 渐入
	create_tween().tween_property(self, ^"modulate:a", 1.0, fade_seconds)
	# 强调脉冲
	if grew:
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2.ONE
		var t := create_tween()
		t.tween_property(label, ^"scale", Vector2.ONE * emphasis_scale_peak, emphasis_seconds * 0.4)
		t.tween_property(label, ^"scale", Vector2.ONE, emphasis_seconds * 0.6)


func _hide() -> void:
	var t := create_tween()
	t.tween_property(self, ^"modulate:a", 0.0, fade_seconds)
	t.tween_callback(func(): visible = false)
