## 系统设置管理器（Autoload 单例）。
##
## 持久化到 [code]user://settings.cfg[/code]。
##
## ## M11 HUD 收尾：增加 hud/* 配置项
## - hud_opacity (0.5~1.0)：HUD 整体透明度
## - damage_popup_size (0.7~1.5)：飘字缩放
## - hotbar_show_keys (bool)：Hotbar 是否显示按键提示
## - debug_overlay_visible (bool)：F11 默认是否显示调试 Overlay
## 设置变更时 emit `setting_changed(key, value)`，业务侧（HUD widget / DamagePopupPool）
## 订阅后即时生效；同时写盘持久化。
extends Node

const SETTINGS_PATH := "user://settings.cfg"


## 任意设置项变更时派发。业务侧用此信号即时刷新 UI / 视觉。
signal setting_changed(key: StringName, value: Variant)


# ─────────────────────────────────────────────────────────────
# 音频（线性 0.0–1.0）
# ─────────────────────────────────────────────────────────────

var bgm_volume: float = 1.0
var sfx_volume: float = 1.0
var ui_volume: float = 1.0


# ─────────────────────────────────────────────────────────────
# HUD（M11）
# ─────────────────────────────────────────────────────────────

var hud_opacity: float = 1.0
var damage_popup_size: float = 1.0
var hotbar_show_keys: bool = true
var debug_overlay_visible: bool = false


func _ready() -> void:
	GameLogger.info("Settings", "SettingsManager ready")
	load_from_disk()


# ─────────────────────────────────────────────────────────────
# 音频 setter
# ─────────────────────────────────────────────────────────────

## 设置 BGM 音量。
func set_bgm_volume(linear: float) -> void:
	bgm_volume = clamp(linear, 0.0, 1.0)
	AudioManager.set_bus_volume(AudioManager.Bus.BGM, bgm_volume)
	setting_changed.emit(&"bgm_volume", bgm_volume)


## 设置 SFX 音量。
func set_sfx_volume(linear: float) -> void:
	sfx_volume = clamp(linear, 0.0, 1.0)
	AudioManager.set_bus_volume(AudioManager.Bus.SFX, sfx_volume)
	setting_changed.emit(&"sfx_volume", sfx_volume)


## 设置 UI 音量。
func set_ui_volume(linear: float) -> void:
	ui_volume = clamp(linear, 0.0, 1.0)
	AudioManager.set_bus_volume(AudioManager.Bus.UI, ui_volume)
	setting_changed.emit(&"ui_volume", ui_volume)


# ─────────────────────────────────────────────────────────────
# HUD setter（M11）
# ─────────────────────────────────────────────────────────────

## HUD 整体透明度（HUDManager 把它应用到 L1_Game 层 modulate.a）。
func set_hud_opacity(v: float) -> void:
	hud_opacity = clamp(v, 0.5, 1.0)
	setting_changed.emit(&"hud_opacity", hud_opacity)


## 飘字大小（DamagePopupPool 创建 popup 时乘以本系数）。
func set_damage_popup_size(v: float) -> void:
	damage_popup_size = clamp(v, 0.7, 1.5)
	setting_changed.emit(&"damage_popup_size", damage_popup_size)


## Hotbar 是否显示按键提示。
func set_hotbar_show_keys(b: bool) -> void:
	hotbar_show_keys = b
	setting_changed.emit(&"hotbar_show_keys", hotbar_show_keys)


## DebugOverlay 默认可见性。
func set_debug_overlay_visible(b: bool) -> void:
	debug_overlay_visible = b
	setting_changed.emit(&"debug_overlay_visible", debug_overlay_visible)


# ─────────────────────────────────────────────────────────────
# 持久化
# ─────────────────────────────────────────────────────────────

## 持久化到 user://settings.cfg。
func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "ui_volume", ui_volume)
	cfg.set_value("hud", "opacity", hud_opacity)
	cfg.set_value("hud", "damage_popup_size", damage_popup_size)
	cfg.set_value("hud", "hotbar_show_keys", hotbar_show_keys)
	cfg.set_value("hud", "debug_overlay_visible", debug_overlay_visible)
	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		GameLogger.error("Settings", "save failed: %s" % err)


## 从磁盘读取。失败时使用默认值。
func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SETTINGS_PATH)
	if err != OK:
		GameLogger.info("Settings", "no settings file, using defaults")
		return
	bgm_volume = clamp(cfg.get_value("audio", "bgm_volume", 1.0), 0.0, 1.0)
	sfx_volume = clamp(cfg.get_value("audio", "sfx_volume", 1.0), 0.0, 1.0)
	ui_volume = clamp(cfg.get_value("audio", "ui_volume", 1.0), 0.0, 1.0)
	hud_opacity = clamp(cfg.get_value("hud", "opacity", 1.0), 0.5, 1.0)
	damage_popup_size = clamp(cfg.get_value("hud", "damage_popup_size", 1.0), 0.7, 1.5)
	hotbar_show_keys = bool(cfg.get_value("hud", "hotbar_show_keys", true))
	debug_overlay_visible = bool(cfg.get_value("hud", "debug_overlay_visible", false))
	GameLogger.info("Settings", "loaded: bgm=%.2f sfx=%.2f ui=%.2f hud_op=%.2f popup=%.2f keys=%s dbg=%s" % [
		bgm_volume, sfx_volume, ui_volume,
		hud_opacity, damage_popup_size, hotbar_show_keys, debug_overlay_visible
	])
