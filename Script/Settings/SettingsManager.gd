## 系统设置管理器（Autoload 单例）。
##
## M5 实装：音量持久化到 [code]user://settings.cfg[/code]。
extends Node

const SETTINGS_PATH := "user://settings.cfg"

# ─────────────────────────────────────────────────────────────
# 音量（线性 0.0–1.0）
# ─────────────────────────────────────────────────────────────

var bgm_volume: float = 1.0
var sfx_volume: float = 1.0
var ui_volume: float = 1.0


func _ready() -> void:
	GameLogger.info("Settings", "SettingsManager ready")
	load_from_disk()


## 设置 BGM 音量。
func set_bgm_volume(linear: float) -> void:
	bgm_volume = clamp(linear, 0.0, 1.0)
	AudioManager.set_bus_volume(AudioManager.Bus.BGM, bgm_volume)


## 设置 SFX 音量。
func set_sfx_volume(linear: float) -> void:
	sfx_volume = clamp(linear, 0.0, 1.0)
	AudioManager.set_bus_volume(AudioManager.Bus.SFX, sfx_volume)


## 设置 UI 音量。
func set_ui_volume(linear: float) -> void:
	ui_volume = clamp(linear, 0.0, 1.0)
	AudioManager.set_bus_volume(AudioManager.Bus.UI, ui_volume)


## 持久化到 user://settings.cfg。
func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "ui_volume", ui_volume)
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
	GameLogger.info("Settings", "loaded: bgm=%.2f sfx=%.2f ui=%.2f" % [bgm_volume, sfx_volume, ui_volume])
