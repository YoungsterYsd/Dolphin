## 通用 Toast 提示。
##
## 订阅 [signal EventBus.hud_toast_requested]（text, duration）：
##   - 在 [member vbox] 顶部加一行
##   - duration 秒后淡出移除
##   - 同屏最多 [member max_toasts] 条，溢出最旧的立刻消失
##
## 调用方式（任意业务代码）：
##     EventBus.hud_toast_requested.emit("已自动存档", 2.0)
class_name ToastWidget
extends BaseWidget

@export var max_toasts: int = 5

## 淡入淡出过渡时长。
@export var fade_seconds: float = 0.3

@onready var vbox: VBoxContainer = $VBox


func _ready() -> void:
	super._ready()
	EventBus.hud_toast_requested.connect(_on_toast_requested)


func _on_toast_requested(text: String, duration: float) -> void:
	# 溢出淘汰最旧（立即从树中移除，再 queue_free；
	# 否则 queue_free 是延迟释放、child_count 不会立刻减少 → while 死循环）
	while vbox.get_child_count() >= max_toasts:
		var oldest: Node = vbox.get_child(0)
		if oldest == null:
			break
		vbox.remove_child(oldest)
		oldest.queue_free()
	# 新条目
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override(&"font_size", 16)
	lbl.modulate.a = 0.0
	vbox.add_child(lbl)
	# 渐入 → 停留 → 渐出 → 移除
	var t := create_tween()
	t.tween_property(lbl, ^"modulate:a", 1.0, fade_seconds)
	t.tween_interval(maxf(duration, 0.5))
	t.tween_property(lbl, ^"modulate:a", 0.0, fade_seconds)
	t.tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free()
	)
