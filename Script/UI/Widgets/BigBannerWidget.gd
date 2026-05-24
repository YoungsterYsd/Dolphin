## 全屏大字横幅。
##
## 订阅多种事件：
##   - [signal EventBus.player_died] → 显示「YOU DIED」
##   - [signal EventBus.level_completed] → 显示「VICTORY」
##   - [signal EventBus.hud_big_banner_requested] → 显示自定义文本
##
## banner_id 与文本映射（默认）：
##   you_died    → "YOU DIED"   红色
##   victory     → "VICTORY"    金色
##   boss_intro  → "BOSS"       白色
##   level_up    → "LEVEL UP"   黄色
##   其他        → 直接用 banner_id 作为文本（大写）
##
## 显示流程：渐入 → 停留 → 渐出 → 隐藏。
class_name BigBannerWidget
extends BaseWidget

@export var fade_in_seconds: float = 0.4
@export var hold_seconds: float = 1.6
@export var fade_out_seconds: float = 0.6

@onready var label: Label = $Label

var _tween: Tween = null


func _ready() -> void:
	super._ready()
	modulate.a = 0.0
	visible = false
	EventBus.player_died.connect(_on_player_died)
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.hud_big_banner_requested.connect(_on_banner_requested)


# ─────────────────────────────────────────────────────────────
# 信号处理
# ─────────────────────────────────────────────────────────────

func _on_player_died() -> void:
	_show("YOU DIED", Color(0.9, 0.15, 0.15))


func _on_level_completed(_level_id: StringName) -> void:
	_show("VICTORY", Color(1.0, 0.85, 0.25))


func _on_banner_requested(banner_id: StringName) -> void:
	match banner_id:
		&"you_died":
			_show("YOU DIED", Color(0.9, 0.15, 0.15))
		&"victory":
			_show("VICTORY", Color(1.0, 0.85, 0.25))
		&"boss_intro":
			_show("BOSS", Color(1, 1, 1))
		&"level_up":
			_show("LEVEL UP", Color(1.0, 0.9, 0.2))
		_:
			_show(String(banner_id).to_upper(), Color(1, 1, 1))


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _show(text: String, color: Color) -> void:
	label.text = text
	label.modulate = color
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", 1.0, fade_in_seconds)
	_tween.tween_interval(hold_seconds)
	_tween.tween_property(self, ^"modulate:a", 0.0, fade_out_seconds)
	_tween.tween_callback(func(): visible = false)
