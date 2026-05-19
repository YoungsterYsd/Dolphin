## M5 测试关卡：玩家 vs 3 只 Slime + 拾取 + 装备 + Boss 传送门。
##
## 职责：
##   - 进入 PLAYING
##   - 接 Camera & HUD 引用
##   - 监听 player_died → GAME OVER
##   - 监听 enemy_died → 计数；全部死亡时打印通关
##   - I 键开/关背包
extends Node2D


@onready var camera: CameraRig = $CameraRig as CameraRig
@onready var hud: HUD = $HUDLayer/HUD as HUD
@onready var inventory_ui: InventoryUI = $HUDLayer/InventoryUI as InventoryUI
@onready var game_over_label: Label = $HUDLayer/GameOverLabel as Label

var _initial_enemy_count: int = 0
var _alive_enemy_count: int = 0


func _ready() -> void:
	GameLogger.info("Core", "TestArena ready (M5)")
	GameInstance.change_state(GameInstance.GameState.PLAYING)

	var player: BaseCharacter = $Player as BaseCharacter
	if camera != null and player != null:
		camera.target = player
	if hud != null:
		hud.player = player

	# 绑定 InventoryUI 到玩家
	if inventory_ui != null and player != null:
		inventory_ui.inventory = player.get_node_or_null("InventoryComponent")
		inventory_ui.equipment = player.get_node_or_null("EquipmentComponent")
		inventory_ui._refresh()

	_initial_enemy_count = $Enemies.get_child_count()
	_alive_enemy_count = _initial_enemy_count

	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_died.connect(_on_player_died)

	# 玩家 HP=0 监听
	EventBus.attribute_changed.connect(func(owner_node, attr_name, _old, new):
		if owner_node == player and attr_name == &"health" and new <= 0.0:
			if not GameInstance.current_state == GameInstance.GameState.GAME_OVER:
				EventBus.player_died.emit()
	)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"inventory"):
		if inventory_ui != null:
			inventory_ui.visible = not inventory_ui.visible


func _on_enemy_died(_enemy: Node) -> void:
	_alive_enemy_count -= 1
	GameLogger.info("Core", "敌人剩余 %d / %d" % [_alive_enemy_count, _initial_enemy_count])
	if _alive_enemy_count <= 0:
		GameLogger.info("Core", "全部敌人击败！")


func _on_player_died() -> void:
	GameLogger.info("Core", "玩家死亡 → GAME_OVER")
	GameInstance.change_state(GameInstance.GameState.GAME_OVER)
	game_over_label.visible = true
	get_tree().paused = true
