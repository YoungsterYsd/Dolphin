## 暂停菜单。
##
## ESC 切到 PAUSED 时本 UI 自动 visible（订阅 EventBus.game_state_changed）。
## 包含：继续 / 设置 / 退出。
##
## ## M11 HUD 收尾改造
## PAUSED 时**自动 push 到 L3_Modal 层**（HUDManager 栈管理）；PLAYING 时 pop。
## HUDStateMachine 联动 InputContext.PanelOpen 自动屏蔽战斗按键。
##
## Phase 2：继承 BaseWidget；保留 process_mode=ALWAYS 不变。
class_name PauseMenu
extends BaseWidget

@onready var settings_menu: Control = $SettingsMenuLayer

var _was_paused_by_user: bool = false
var _pushed_to_hudmanager: bool = false


func _ready() -> void:
	super._ready()
	# UI 自身需在暂停时仍能交互
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	settings_menu.visible = false

	($Panel/Margin/VBox/ResumeBtn as Button).pressed.connect(_on_resume)
	($Panel/Margin/VBox/SettingsBtn as Button).pressed.connect(_on_settings)
	($Panel/Margin/VBox/QuitBtn as Button).pressed.connect(_on_quit)

	EventBus.game_state_changed.connect(_on_state_changed)


func _on_state_changed(_old: int, new: int) -> void:
	if new == GameInstance.GameState.PAUSED:
		visible = true
		_attach_to_modal_layer()
	elif new == GameInstance.GameState.PLAYING:
		visible = false
		settings_menu.visible = false
		_detach_from_modal_layer()


# ─────────────────────────────────────────────────────────────
# HUDManager 栈接入（M11 HUD 收尾，DEP-13 兑现）
# ─────────────────────────────────────────────────────────────

func _attach_to_modal_layer() -> void:
	if _pushed_to_hudmanager:
		return
	var hm: Node = Engine.get_main_loop().root.get_node_or_null(^"HUDManager")
	if hm == null or not hm.has_method(&"push_widget"):
		return
	var layer: Node = hm.call(&"get_layer", &"L3_Modal")
	if layer == null:
		return
	if get_parent() != layer:
		reparent(layer, false)
		if layer is CanvasLayer:
			(layer as CanvasLayer).visible = true
	hm.call(&"push_widget", &"L3_Modal", self)
	_pushed_to_hudmanager = true
	GameLogger.info("UI", "PauseMenu pushed to L3_Modal")


func _detach_from_modal_layer() -> void:
	if not _pushed_to_hudmanager:
		return
	_pushed_to_hudmanager = false
	var hm: Node = Engine.get_main_loop().root.get_node_or_null(^"HUDManager")
	if hm != null and hm.has_method(&"pop_widget"):
		hm.call(&"pop_widget", &"L3_Modal")


func _on_resume() -> void:
	GameInstance.toggle_pause()


func _on_settings() -> void:
	settings_menu.visible = not settings_menu.visible


func _on_quit() -> void:
	GameLogger.info("UI", "Quit requested")
	get_tree().paused = false
	get_tree().quit()
