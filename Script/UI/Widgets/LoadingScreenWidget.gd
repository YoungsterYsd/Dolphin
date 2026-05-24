## 加载界面 widget（关卡切换期间全屏覆盖）。
##
## 订阅 [signal EventBus.level_loading_started] / [signal EventBus.level_loading_finished]
##   - started: fade out 黑幕 + 显示 "正在加载…<display_name>"
##   - finished: fade in 黑幕（自动隐藏）
##
## 设计：
##   - 接受 LevelManager 主动调 [method begin_fade_out] / [method begin_fade_in] 完成精确控制
##   - 默认 ALWAYS process_mode（关卡切换期间 paused=true 也能跑完 tween）
##   - 自动 reparent 到 L6_Loading 层（高于其他所有 HUD widget）
class_name LoadingScreenWidget
extends BaseWidget

@onready var bg: ColorRect = $BG
@onready var center_box: VBoxContainer = $CenterBox
@onready var title_label: Label = $CenterBox/Title
@onready var tip_label: Label = $CenterBox/Tip


func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"loading_screen")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP  # 拦截一切点击
	bg.color = Color.BLACK
	bg.modulate.a = 0.0
	center_box.modulate.a = 0.0
	# 订阅 EventBus
	EventBus.level_loading_started.connect(_on_loading_started)
	EventBus.level_loading_finished.connect(_on_loading_finished)
	call_deferred(&"_relocate_to_loading_layer")


## 把 widget 挪到 L6_Loading 层，确保 z-order 在最顶。
func _relocate_to_loading_layer() -> void:
	var hm: Node = Engine.get_main_loop().root.get_node_or_null(^"HUDManager")
	if hm == null or not hm.has_method(&"get_layer"):
		return
	var layer: Node = hm.call(&"get_layer", &"L6_Loading")
	if layer == null:
		return
	if get_parent() == layer:
		return
	reparent(layer, false)
	# L6 默认 visible=false（HUD_Main.tscn）；切场景前显式打开
	if layer is CanvasLayer:
		(layer as CanvasLayer).visible = true


# ─────────────────────────────────────────────────────────────
# 主动控制 API（LevelManager 调用）
# ─────────────────────────────────────────────────────────────

## fade out（黑幕渐显）。Awaitable：完成后 resume。
func begin_fade_out(seconds: float, color: Color = Color.BLACK,
		title: String = "正在加载...", tip: String = "") -> void:
	bg.color = color
	visible = true
	title_label.text = title
	tip_label.text = tip
	tip_label.visible = tip != ""
	var t := create_tween()
	t.tween_property(bg, ^"modulate:a", 1.0, seconds)
	t.parallel().tween_property(center_box, ^"modulate:a", 1.0, seconds * 0.6)
	await t.finished


## fade in（黑幕渐隐）。Awaitable。
func begin_fade_in(seconds: float) -> void:
	var t := create_tween()
	t.tween_property(center_box, ^"modulate:a", 0.0, seconds * 0.4)
	t.parallel().tween_property(bg, ^"modulate:a", 0.0, seconds)
	await t.finished
	visible = false


# ─────────────────────────────────────────────────────────────
# EventBus fallback（业务侧不主动调时也能工作）
# ─────────────────────────────────────────────────────────────

func _on_loading_started(_from: StringName, to: StringName) -> void:
	# 仅当 LevelManager 没主动调 begin_fade_out 时（极少；防御）
	if visible:
		return
	begin_fade_out(0.35, Color.BLACK, "正在加载...%s" % String(to))


func _on_loading_finished(_id: StringName) -> void:
	if not visible:
		return
	begin_fade_in(0.35)
