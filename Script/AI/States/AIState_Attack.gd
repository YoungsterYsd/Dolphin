## 攻击状态：try_activate 普攻；ability_ended 后切回 chase。
##
## ASC 内部 Ability 执行完毕通过 EventBus.ability_ended 通知；
## 这里订阅一次性事件等待结束。
class_name AIState_Attack
extends AIState

var _waiting: bool = false


func enter() -> void:
	if ctrl.enemy == null or ctrl.enemy.move_comp == null:
		return
	ctrl.enemy.move_comp.set_input_dir(Vector3.ZERO)

	# 朝向目标
	var dir := ctrl.direction_to_target()
	if dir != Vector3.ZERO:
		var sprite: AnimatedSprite2D = _find_sprite()
		if sprite != null:
			sprite.flip_h = dir.x < 0.0

	# 触发普攻
	var asc := ctrl.enemy.asc as AbilitySystemComponent
	if asc == null:
		change(&"chase")
		return

	if not asc.try_activate(&"enemy_basic_attack"):
		# CD 中或被拦截：回 chase 等下次
		change(&"chase")
		return

	# 等待 ability_ended
	_waiting = true
	EventBus.ability_ended.connect(_on_ability_ended)


func exit() -> void:
	if _waiting:
		_waiting = false
		if EventBus.ability_ended.is_connected(_on_ability_ended):
			EventBus.ability_ended.disconnect(_on_ability_ended)


func on_event(event_name: StringName, _payload: Variant = null) -> void:
	if event_name == &"took_damage":
		change(&"hit")


func _on_ability_ended(owner_node: Node, ability_id: StringName) -> void:
	if owner_node != ctrl.enemy:
		return
	if ability_id != &"enemy_basic_attack":
		return
	change(&"chase")


func _find_sprite() -> AnimatedSprite2D:
	if ctrl.enemy == null:
		return null
	for child in ctrl.enemy.get_children():
		if child is AnimatedSprite2D:
			return child
	return null
