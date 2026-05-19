## 关卡管理器（Autoload 单例）。
##
## M5 实装：
##   - load_level(LevelDef)：切换场景 + 切 BGM + 广播 level_changed
##   - 进入 boss room 时广播让 HUD 显示 BossHealthBar
extends Node

## 当前关卡 id（M5 起有效）。
var current_level_id: StringName = &""


func _ready() -> void:
	GameLogger.info("Level", "LevelManager ready")


## 加载指定关卡（同步切场景；M3 需要异步可后续扩展）。
func load_level(level: LevelDef) -> void:
	if level == null or level.scene == null:
		GameLogger.warn("Level", "load_level: invalid LevelDef")
		return
	GameLogger.info("Level", "loading level: %s" % level.level_id)
	current_level_id = level.level_id

	# 切 BGM
	if level.bgm != null:
		AudioManager.play_bgm(level.bgm, 0.5)

	# 切场景（packed scene → tree.change_scene_to_packed）
	# 注意：本调用会延迟到下一帧切换
	var err := get_tree().change_scene_to_packed(level.scene)
	if err != OK:
		GameLogger.error("Level", "change_scene_to_packed failed: %s" % err)
		return

	EventBus.level_changed.emit(level.level_id)


## 卸载当前关卡。M5 简化：直接重载当前场景。
func unload_current() -> void:
	get_tree().reload_current_scene()
