## M5 测试关卡（M9 起 3D HD-2D）：玩家 vs 3 只 Slime + 拾取 + 装备 + Boss 传送门。
##
## 职责：
##   - 进入 PLAYING
##   - 接 Camera & HUD 引用
##   - 监听 player_died → GAME OVER
##   - 监听 enemy_died → 计数；全部死亡时打印通关
##   - I 键开/关背包（沿用旧绑定 → 现已映射到 ui_panel_build / Tab 键）
##
## 注：HUD 系统由 HUDManager Autoload 自动初始化（HUDManager._ready 内 deferred 完成
##     setup + 默认布局加载），关卡侧无需重复挂载，切关也不重建。
extends Node3D


@onready var camera: CameraRig = $CameraRig as CameraRig
@onready var hud: HUD = $HUDLayer/HUD as HUD
@onready var inventory_ui: InventoryUI = $HUDLayer/InventoryUI as InventoryUI
@onready var game_over_label: Label = $HUDLayer/GameOverLabel as Label

var _initial_enemy_count: int = 0
var _alive_enemy_count: int = 0
var _player: BaseCharacter = null


func _ready() -> void:
	GameLogger.info("Core", "TestArena ready (M9 3D)")
	GameInstance.change_state(GameInstance.GameState.PLAYING)

	# PR1 硬度打断系统验收：装上调试日志器（屏幕右上角弹打断 toast + GameLogger）
	InterruptDebugLogger.install()

	_player = $Player as BaseCharacter
	if camera != null and _player != null:
		camera.target = _player
	if hud != null:
		hud.player = _player

	# 绑定 InventoryUI 到玩家
	if inventory_ui != null and _player != null:
		inventory_ui.inventory = _player.get_node_or_null("InventoryComponent")
		inventory_ui.equipment = _player.get_node_or_null("EquipmentComponent")
		# InventoryUI._ready 自身已 _refresh_all；外部 setter 改动后调 refresh_all 触发刷新
		if inventory_ui.has_method(&"refresh_all"):
			inventory_ui.refresh_all()

	_initial_enemy_count = $Enemies.get_child_count()
	_alive_enemy_count = _initial_enemy_count

	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.player_died.connect(_on_player_died)
	# 订阅 Tab 键（ui_panel_build）切换背包；EventBus 由 InputController 广播
	EventBus.player_input_action_pressed.connect(_on_input_action_pressed)

	# 玩家 HP=0 监听 —— 走 named method（场景 free 时 Godot 4 自动 disconnect，
	# 避免匿名 lambda 捕获 freed player 引发 "Lambda capture was freed" 报错）
	EventBus.attribute_changed.connect(_on_attribute_changed)


func _on_attribute_changed(owner_node: Node, attr_name: StringName, _old_value: float, new_value: float) -> void:
	# 守卫：跨场景残留订阅时 _player 可能已无效；防御 freed Object
	if not is_instance_valid(_player):
		return
	if owner_node != _player:
		return
	if attr_name == &"health" and new_value <= 0.0:
		if GameInstance.current_state != GameInstance.GameState.GAME_OVER:
			EventBus.player_died.emit()


func _on_input_action_pressed(action: StringName) -> void:
	if action == &"ui_panel_build" and inventory_ui != null:
		# M11 HUD 收尾：改用 InventoryUI.toggle() 走 HUDManager 栈
		inventory_ui.toggle()


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
