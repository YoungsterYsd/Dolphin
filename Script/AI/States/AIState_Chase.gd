## 追击状态：朝玩家移动；进入攻击距离切 attack；脱离视野（detect_range * 1.5）回 idle。
class_name AIState_Chase
extends AIState


func tick(_delta: float) -> void:
	if ctrl.target == null:
		change(&"idle")
		return
	var dist: float = ctrl.distance_to_target()
	if dist <= ctrl.attack_range:
		change(&"attack")
		return
	if dist > ctrl.detect_range * 1.5:
		change(&"idle")
		return
	# 移动
	if ctrl.enemy != null and ctrl.enemy.move_comp != null:
		ctrl.enemy.move_comp.set_input_dir(ctrl.direction_to_target())


func exit() -> void:
	if ctrl.enemy != null and ctrl.enemy.move_comp != null:
		ctrl.enemy.move_comp.set_input_dir(Vector3.ZERO)


func on_event(event_name: StringName, _payload: Variant = null) -> void:
	if event_name == &"took_damage":
		change(&"hit")
