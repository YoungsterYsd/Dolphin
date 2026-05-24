## 单个伤害飘字。
##
## 由 [DamagePopupPool] 创建并复用；外部不直接 new。
##
## 生命周期：show_damage 启动 → Tween 飘 lifetime 秒 → recycle 回池。
class_name DamagePopup
extends Label

signal recycled(popup: DamagePopup)

# === 视觉常量（不入 R-DATA-02：均可被 HitFeedbackConfig 覆盖） ===
const _OUTLINE_COLOR := Color(0, 0, 0, 0.85)
const _OUTLINE_SIZE: int = 2

var _tween: Tween = null


func _ready() -> void:
	# 让 Label 不响应鼠标
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_color_override(&"font_outline_color", _OUTLINE_COLOR)
	add_theme_constant_override(&"outline_size", _OUTLINE_SIZE)
	visible = false


## 显示一次伤害飘字。
##   screen_pos: 屏幕坐标（由 Pool 通过 unproject 投影得到）
##   amount:    伤害数值
##   color:     颜色（普通 / 暴击 / 治疗）
##   font_size: 字号
##   drift:     向上飘移距离（像素）
##   jitter:    水平随机偏移 ±jitter
##   lifetime:  存活秒
func show_damage(screen_pos: Vector2, amount: float, color: Color, font_size: int, drift: float, jitter: float, lifetime: float) -> void:
	show_text(screen_pos, "%d" % int(round(amount)), color, font_size, drift, jitter, lifetime)


## 显示任意文本飘字（MISS / 闪避 / 经验 +N / 金币 +N 等）。
## 与 show_damage 共享 Tween 流程，仅文本不同。
func show_text(screen_pos: Vector2, text_str: String, color: Color, font_size: int, drift: float, jitter: float, lifetime: float) -> void:
	# 杀掉旧 tween
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# 文本与样式
	text = text_str
	add_theme_color_override(&"font_color", color)
	add_theme_font_size_override(&"font_size", font_size)
	# 位置：在屏幕坐标偏移一个随机抖动
	var x_off: float = randf_range(-jitter, jitter)
	position = screen_pos + Vector2(x_off - size.x * 0.5, 0.0)
	visible = true
	modulate.a = 1.0
	# Tween：向上飘 + 后半段淡出
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:y", position.y - drift, lifetime).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)
	_tween.chain().tween_callback(_recycle)


func _recycle() -> void:
	visible = false
	modulate.a = 1.0
	recycled.emit(self)
