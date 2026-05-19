## 待机状态：站立不动；玩家进入视野半径切 chase。
class_name AIState_Idle
extends AIState


func enter() -> void:
	if ctrl.enemy != null and ctrl.enemy.move_comp != null:
		ctrl.enemy.move_comp.set_input_dir(Vector3.ZERO)


func tick(_delta: float) -> void:
	if ctrl.target == null:
		return
	if ctrl.distance_to_target() <= ctrl.detect_range:
		change(&"chase")


func on_event(event_name: StringName, _payload: Variant = null) -> void:
	if event_name == &"took_damage":
		change(&"hit")
