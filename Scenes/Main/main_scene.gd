## M3 主场景驱动（M9 起 3D）。
##
## 职责：
##   - 进入 PLAYING 状态
##   - 把 Player 引用接入 CameraRig 与 HUD
##   - 训练假人血量为 0 时自动复活，便于无限测试
##
## 注：ESC 暂停由 GameInstance Autoload 接管（设为 PROCESS_MODE_ALWAYS）。
##     本场景及子节点保持 INHERIT，会被 paused 正确停帧。
##     HUD 系统由 HUDManager Autoload 自动初始化（_ready deferred）；关卡侧无需调 setup。
extends Node3D


var _dummy_node: Node = null
var _dummy_asc: AbilitySystemComponent = null


func _ready() -> void:
	GameLogger.info("Core", "MainScene ready (M9 3D)")
	GameInstance.change_state(GameInstance.GameState.PLAYING)

	var player: BaseCharacter = $Player as BaseCharacter
	var camera: CameraRig = $CameraRig as CameraRig
	var hud: HUD = $HUDLayer/HUD as HUD

	if camera != null and player != null:
		camera.target = player
	if hud != null:
		hud.player = player

	# 训练假人血量归 0 自动满血复活 —— 走 named method（场景 free 时 Godot 4 自动 disconnect，
	# 避免匿名 lambda 捕获 freed dummy_asc / $TrainingDummy 引发 "Lambda capture was freed" 报错）
	_dummy_node = $TrainingDummy
	_dummy_asc = $TrainingDummy/AbilitySystemComponent as AbilitySystemComponent
	EventBus.attribute_changed.connect(_on_attribute_changed)


func _on_attribute_changed(owner_node: Node, attr_name: StringName, _old_value: float, _new_value: float) -> void:
	if not is_instance_valid(_dummy_node) or not is_instance_valid(_dummy_asc):
		return
	if owner_node != _dummy_node:
		return
	if attr_name == &"health" and _new_value <= 0.0:
		GameLogger.info("Character", "训练假人倒下，复活满血")
		_dummy_asc.attribute_set.set_attr(&"health", _dummy_asc.attribute_set.get_attr(&"max_health"))
