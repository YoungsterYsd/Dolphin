## 暂停菜单（M5）。
##
## ESC 切到 PAUSED 时本 UI 自动 visible（订阅 EventBus.game_state_changed）。
## 包含：继续 / 设置 / 退出。
class_name PauseMenu
extends Control

@onready var settings_menu: Control = $SettingsMenuLayer

var _was_paused_by_user: bool = false


func _ready() -> void:
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
	elif new == GameInstance.GameState.PLAYING:
		visible = false
		settings_menu.visible = false


func _on_resume() -> void:
	GameInstance.toggle_pause()


func _on_settings() -> void:
	settings_menu.visible = not settings_menu.visible


func _on_quit() -> void:
	GameLogger.info("UI", "Quit requested")
	get_tree().paused = false
	get_tree().quit()
