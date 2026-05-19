## Boss 房（M5）。
##
## 进入时：
##   - HUD 引用 / 相机跟随
##   - BossHealthBar 绑定 boss
##   - 监听 boss 死亡 → 通关提示
extends Node2D


@onready var camera: CameraRig = $CameraRig as CameraRig
@onready var hud: HUD = $HUDLayer/HUD as HUD
@onready var boss_hp_bar: BossHealthBar = $HUDLayer/BossHealthBar as BossHealthBar
@onready var game_over_label: Label = $HUDLayer/GameOverLabel as Label


func _ready() -> void:
	GameLogger.info("Core", "BossRoom ready")
	GameInstance.change_state(GameInstance.GameState.PLAYING)

	var player: BaseCharacter = $Player as BaseCharacter
	var boss: Node = $Boss

	if camera != null and player != null:
		camera.target = player
	if hud != null:
		hud.player = player
	if boss_hp_bar != null and boss != null:
		boss_hp_bar.bind_boss(boss)

	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_died.connect(_on_player_died)

	EventBus.attribute_changed.connect(func(owner_node, attr_name, _old, new):
		if owner_node == player and attr_name == &"health" and new <= 0.0:
			if not GameInstance.current_state == GameInstance.GameState.GAME_OVER:
				EventBus.player_died.emit()
	)


func _on_enemy_died(enemy: Node) -> void:
	if enemy == $Boss:
		GameLogger.info("Core", "BOSS 击杀！通关！")
		EventBus.level_completed.emit(LevelManager.current_level_id)
		_show_victory()


func _on_player_died() -> void:
	GameLogger.info("Core", "玩家死亡 → GAME_OVER")
	GameInstance.change_state(GameInstance.GameState.GAME_OVER)
	game_over_label.visible = true
	get_tree().paused = true


func _show_victory() -> void:
	game_over_label.text = "VICTORY!\n按 R 返回"
	game_over_label.visible = true
	GameInstance.change_state(GameInstance.GameState.GAME_OVER)
	get_tree().paused = true
