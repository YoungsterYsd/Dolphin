## Boss 房（M5；M9 起 3D）。
##
## 进入时：
##   - HUD 引用 / 相机跟随
##   - BossHealthBar 绑定 boss
##   - 监听 boss 死亡 → 通关提示
extends Node3D


@onready var camera: CameraRig = $CameraRig as CameraRig
@onready var hud: HUD = $HUDLayer/HUD as HUD
@onready var boss_hp_bar: BossHealthBar = $HUDLayer/BossHealthBar as BossHealthBar
@onready var game_over_label: Label = $HUDLayer/GameOverLabel as Label

var _player: BaseCharacter = null


func _ready() -> void:
	GameLogger.info("Core", "BossRoom ready (M9 3D)")
	GameInstance.change_state(GameInstance.GameState.PLAYING)

	_player = $Player as BaseCharacter
	var boss: Node = $Boss

	if camera != null and _player != null:
		camera.target = _player
	if hud != null:
		hud.player = _player
	if boss_hp_bar != null and boss != null:
		boss_hp_bar.bind_boss(boss)

	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_died.connect(_on_player_died)

	# 玩家 HP=0 监听 —— 走 named method（场景 free 时 Godot 4 自动 disconnect，
	# 避免匿名 lambda 捕获 freed player 引发 "Lambda capture was freed" 报错）
	EventBus.attribute_changed.connect(_on_attribute_changed)


func _on_attribute_changed(owner_node: Node, attr_name: StringName, _old_value: float, new_value: float) -> void:
	if not is_instance_valid(_player):
		return
	if owner_node != _player:
		return
	if attr_name == &"health" and new_value <= 0.0:
		if GameInstance.current_state != GameInstance.GameState.GAME_OVER:
			EventBus.player_died.emit()


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
