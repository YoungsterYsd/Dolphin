## 受击硬直：固定 hit_stun 秒后回 chase。
##
## 期间停止移动，不响应索敌；可被 took_damage 重新触发（重置硬直时长）。
class_name AIState_Hit
extends AIState

var _remaining: float = 0.0


func enter() -> void:
	_remaining = ctrl.hit_stun
	if ctrl.enemy != null and ctrl.enemy.move_comp != null:
		ctrl.enemy.move_comp.set_input_dir(Vector3.ZERO)


func tick(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		change(&"chase")


func on_event(event_name: StringName, _payload: Variant = null) -> void:
	if event_name == &"took_damage":
		# 连击叠硬直
		_remaining = ctrl.hit_stun
