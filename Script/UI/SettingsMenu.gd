## 设置菜单（M5）。
##
## 三总线音量滑条 + 写盘到 SettingsManager。
## 按下"应用"立即生效；"返回"关闭面板。
class_name SettingsMenu
extends Control

@onready var bgm_slider: HSlider = $Panel/Margin/VBox/BGMRow/Slider
@onready var sfx_slider: HSlider = $Panel/Margin/VBox/SFXRow/Slider
@onready var ui_slider: HSlider = $Panel/Margin/VBox/UIRow/Slider


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 用 SettingsManager 当前值初始化
	bgm_slider.value = SettingsManager.bgm_volume
	sfx_slider.value = SettingsManager.sfx_volume
	ui_slider.value = SettingsManager.ui_volume

	bgm_slider.value_changed.connect(_on_bgm)
	sfx_slider.value_changed.connect(_on_sfx)
	ui_slider.value_changed.connect(_on_ui)
	($Panel/Margin/VBox/CloseBtn as Button).pressed.connect(_on_close)


func _on_bgm(v: float) -> void:
	SettingsManager.set_bgm_volume(v)
	SettingsManager.save()


func _on_sfx(v: float) -> void:
	SettingsManager.set_sfx_volume(v)
	SettingsManager.save()


func _on_ui(v: float) -> void:
	SettingsManager.set_ui_volume(v)
	SettingsManager.save()


func _on_close() -> void:
	visible = false
