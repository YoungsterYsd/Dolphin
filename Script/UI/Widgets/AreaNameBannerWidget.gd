## 区域名提示。
##
## 订阅 [signal EventBus.level_changed]：进入新关卡时顶部淡入区域名 → 停留 → 淡出。
## 区域名解析：用 level_id 作为文本（业务侧后期可加 level_id → 可读名映射表）。
class_name AreaNameBannerWidget
extends BaseWidget

@export var fade_in_seconds: float = 0.5
@export var hold_seconds: float = 2.0
@export var fade_out_seconds: float = 0.6

@onready var label: Label = $Label

var _tween: Tween = null


func _ready() -> void:
	super._ready()
	modulate.a = 0.0
	visible = false
	EventBus.level_changed.connect(_on_level_changed)


func _on_level_changed(level_id: StringName) -> void:
	label.text = String(level_id).to_upper()
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", 1.0, fade_in_seconds)
	_tween.tween_interval(hold_seconds)
	_tween.tween_property(self, ^"modulate:a", 0.0, fade_out_seconds)
	_tween.tween_callback(func(): visible = false)
