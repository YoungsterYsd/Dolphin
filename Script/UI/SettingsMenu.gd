## 设置菜单。
##
## 三总线音量滑条 + 4 项 HUD 配置 + 写盘到 SettingsManager。
## 每次值变化即时生效（emit setting_changed）+ 持久化保存。
##
## ## M11 HUD 收尾：新增 4 项 hud/* 配置
## - HUD 透明度（0.5~1.0）
## - 飘字大小（0.7~1.5）
## - Hotbar 显示按键提示（bool）
## - 默认显示 Debug Overlay（bool）
##
## Phase 2：继承 BaseWidget；process_mode=ALWAYS 保留。
class_name SettingsMenu
extends BaseWidget

@onready var bgm_slider: HSlider = $Panel/Margin/VBox/BGMRow/Slider
@onready var sfx_slider: HSlider = $Panel/Margin/VBox/SFXRow/Slider
@onready var ui_slider: HSlider = $Panel/Margin/VBox/UIRow/Slider

# M11 HUD 4 项
@onready var hud_opacity_slider: HSlider = $Panel/Margin/VBox/HudOpacityRow/Slider
@onready var damage_popup_slider: HSlider = $Panel/Margin/VBox/DamagePopupRow/Slider
@onready var hotbar_keys_check: CheckBox = $Panel/Margin/VBox/HotbarKeysRow/Check
@onready var debug_overlay_check: CheckBox = $Panel/Margin/VBox/DebugOverlayRow/Check


func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 用 SettingsManager 当前值初始化
	bgm_slider.value = SettingsManager.bgm_volume
	sfx_slider.value = SettingsManager.sfx_volume
	ui_slider.value = SettingsManager.ui_volume
	hud_opacity_slider.value = SettingsManager.hud_opacity
	damage_popup_slider.value = SettingsManager.damage_popup_size
	hotbar_keys_check.button_pressed = SettingsManager.hotbar_show_keys
	debug_overlay_check.button_pressed = SettingsManager.debug_overlay_visible

	# 音频
	bgm_slider.value_changed.connect(_on_bgm)
	sfx_slider.value_changed.connect(_on_sfx)
	ui_slider.value_changed.connect(_on_ui)
	# HUD
	hud_opacity_slider.value_changed.connect(_on_hud_opacity)
	damage_popup_slider.value_changed.connect(_on_damage_popup)
	hotbar_keys_check.toggled.connect(_on_hotbar_keys)
	debug_overlay_check.toggled.connect(_on_debug_overlay)
	# 关闭
	($Panel/Margin/VBox/CloseBtn as Button).pressed.connect(_on_close)


# ─────────────────────────────────────────────────────────────
# 音频
# ─────────────────────────────────────────────────────────────

func _on_bgm(v: float) -> void:
	SettingsManager.set_bgm_volume(v)
	SettingsManager.save()


func _on_sfx(v: float) -> void:
	SettingsManager.set_sfx_volume(v)
	SettingsManager.save()


func _on_ui(v: float) -> void:
	SettingsManager.set_ui_volume(v)
	SettingsManager.save()


# ─────────────────────────────────────────────────────────────
# HUD（M11）
# ─────────────────────────────────────────────────────────────

func _on_hud_opacity(v: float) -> void:
	SettingsManager.set_hud_opacity(v)
	SettingsManager.save()


func _on_damage_popup(v: float) -> void:
	SettingsManager.set_damage_popup_size(v)
	SettingsManager.save()


func _on_hotbar_keys(b: bool) -> void:
	SettingsManager.set_hotbar_show_keys(b)
	SettingsManager.save()


func _on_debug_overlay(b: bool) -> void:
	SettingsManager.set_debug_overlay_visible(b)
	SettingsManager.save()


func _on_close() -> void:
	visible = false
