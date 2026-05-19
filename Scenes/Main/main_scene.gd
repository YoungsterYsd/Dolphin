## M3 主场景驱动。
##
## 职责：
##   - 进入 PLAYING 状态
##   - 把 Player 引用接入 CameraRig 与 HUD
##   - 训练假人血量为 0 时自动复活，便于无限测试
##
## 注：ESC 暂停由 GameInstance Autoload 接管（设为 PROCESS_MODE_ALWAYS）。
## 本场景及子节点保持 INHERIT，会被 paused 正确停帧。
extends Node2D


func _ready() -> void:
	GameLogger.info("Core", "MainScene ready (M3)")
	GameInstance.change_state(GameInstance.GameState.PLAYING)

	var player: BaseCharacter = $Player as BaseCharacter
	var camera: CameraRig = $CameraRig as CameraRig
	var hud: HUD = $HUDLayer/HUD as HUD

	if camera != null and player != null:
		camera.target = player
	if hud != null:
		hud.player = player

	# 训练假人血量归 0 自动满血复活
	var dummy_asc: AbilitySystemComponent = $TrainingDummy/AbilitySystemComponent as AbilitySystemComponent
	EventBus.attribute_changed.connect(func(owner_node, attr_name, _old, new):
		if owner_node != $TrainingDummy:
			return
		if attr_name == &"health" and new <= 0.0:
			GameLogger.info("Character", "训练假人倒下，复活满血")
			dummy_asc.attribute_set.set_attr(&"health", dummy_asc.attribute_set.get_attr(&"max_health"))
	)
