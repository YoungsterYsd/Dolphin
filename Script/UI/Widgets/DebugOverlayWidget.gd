## L7 Debug 层 widget。
##
## 显示运行时统计：FPS / 帧时间 / Widget 数 / Combo / 当前 HUD 状态。
## 仅 OS.is_debug_build() 显示（BaseWidget.debug_only=true 已自动）。
##
## 默认隐藏（按 F11 切换）。
class_name DebugOverlayWidget
extends BaseWidget

@onready var label: Label = $Label

var _show: bool = false


func _ready() -> void:
	debug_only = true
	super._ready()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode == KEY_F11:
		_show = not _show
		visible = _show


func _process(_delta: float) -> void:
	if not visible:
		return
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = 1000.0 / maxf(fps, 0.0001)
	var widget_count: int = 0
	var ues: Node = Engine.get_main_loop().root.get_node_or_null(^"UIExtensionSubsystem")
	if ues != null and ues.has_method(&"get_handles_in_slot"):
		# 没有总数 API，遍历 SLOT_TAGS
		for tag in [&"TopLeft", &"TopCenter", &"TopRight", &"BottomLeft", &"BottomCenter", &"BottomRight", &"Center"]:
			widget_count += (ues.get_handles_in_slot(tag) as Array).size()
	var combo: int = 0
	var ct: Node = Engine.get_main_loop().root.get_node_or_null(^"ComboTracker")
	if ct != null and ct.has_method(&"get_count"):
		combo = ct.get_count()
	var hud_state: String = "?"
	var hsm: Node = Engine.get_main_loop().root.get_node_or_null(^"HUDStateMachine")
	if hsm != null and hsm.has_method(&"state_name") and hsm.has_method(&"get_current_state"):
		hud_state = hsm.state_name(hsm.get_current_state())
	# 对话当前位置（M11）
	var dlg_str: String = "—"
	var dr: Node = Engine.get_main_loop().root.get_node_or_null(^"DialogueRunner")
	if dr != null and dr.has_method(&"is_running") and bool(dr.call(&"is_running")):
		var gid: String = String(dr.call(&"get_current_graph_id"))
		var nid: String = String(dr.call(&"get_current_node_id"))
		dlg_str = "%s / %s" % [gid, nid]
	label.text = "FPS: %.0f  (%.1fms)\nWidgets: %d\nCombo: %d\nHUDState: %s\nDialogue: %s" \
		% [fps, frame_ms, widget_count, combo, hud_state, dlg_str]
