## 死亡状态：广播 enemy_died，淡出后 queue_free。
##
## 进入后不再响应任何事件。
class_name AIState_Dead
extends AIState

const FADE_DURATION: float = 0.5

var _elapsed: float = 0.0
var _emitted: bool = false


func enter() -> void:
	if ctrl.enemy == null:
		return
	# 停止移动
	if ctrl.enemy.move_comp != null:
		ctrl.enemy.move_comp.set_input_dir(Vector3.ZERO)
	# 关闭碰撞，避免 hitbox/hurtbox 在淡出期间继续触发
	if ctrl.enemy.hitbox != null:
		ctrl.enemy.hitbox.enabled = false
	if ctrl.enemy.hurtbox != null:
		(ctrl.enemy.hurtbox as Area2D).monitoring = false
		(ctrl.enemy.hurtbox as Area2D).monitorable = false
	# 广播一次
	if not _emitted:
		EventBus.enemy_died.emit(ctrl.enemy)
		_emitted = true
		GameLogger.info("AI", "[%s] died" % ctrl.enemy.name)


func tick(delta: float) -> void:
	if ctrl.enemy == null:
		return
	_elapsed += delta
	# 淡出 modulate
	var alpha: float = clampf(1.0 - _elapsed / FADE_DURATION, 0.0, 1.0)
	if ctrl.enemy is CanvasItem:
		(ctrl.enemy as CanvasItem).modulate = Color(1.0, 1.0, 1.0, alpha)
	if _elapsed >= FADE_DURATION:
		ctrl.enemy.queue_free()


func on_event(_event_name: StringName, _payload: Variant = null) -> void:
	pass  # 死亡不响应任何事件
