## AI 状态机管理器。
##
## 挂在 EnemyCharacter 子节点。每物理帧由 EnemyCharacter._physics_process 调用 [method tick]。
## 状态由 [method register_state] 注册，[method change_state] 切换。
##
## 通过 [method send_event] 接收外部事件（如受击、死亡、目标丢失），转发给当前 state。
class_name AIController
extends Node

## 状态变更广播。供 EnemyCharacter 同步动画或调试。
signal state_changed(old_name: StringName, new_name: StringName)

## 视野半径（用于 IdleState 检测玩家）。
@export var detect_range: float = 220.0

## 攻击距离（进入此距离后切到 AttackState）。
@export var attack_range: float = 70.0

## 受击硬直时间（HitState 持续秒）。
@export var hit_stun: float = 0.35

## 索敌目标（M4 默认指向场景里的玩家；EnemyCharacter._ready 时设置）。
var target: Node = null

## 当前状态。
var current_state: AIState = null

## 状态注册表 StringName -> AIState 实例
var _states: Dictionary = {}

## 反向引用，便于 State 调用 EnemyCharacter / ASC / move_comp。
var enemy: Node = null


func _ready() -> void:
	# 由 EnemyCharacter._ready 设 enemy 引用并注册 states 后，再 change_state 启动
	pass


## 注册一个状态。state_name 是状态唯一标识。
func register_state(state_name: StringName, state: AIState) -> void:
	state.ctrl = self
	state.state_name = state_name
	_states[state_name] = state


## 切到指定状态。
func change_state(state_name: StringName) -> void:
	if not _states.has(state_name):
		GameLogger.warn("AI", "[%s] no such state: %s" % [enemy.name if enemy else "?", state_name])
		return
	var old_name: StringName = current_state.state_name if current_state != null else &""
	if current_state != null:
		current_state.exit()
	current_state = _states[state_name]
	current_state.enter()
	GameLogger.info("AI", "[%s] state: %s -> %s" % [enemy.name if enemy else "?", old_name, state_name])
	state_changed.emit(old_name, state_name)


## 物理帧驱动当前状态。
func tick(delta: float) -> void:
	if current_state != null:
		current_state.tick(delta)


## 转发外部事件（如 took_damage）给当前状态。
func send_event(event_name: StringName, payload = null) -> void:
	if current_state != null:
		current_state.on_event(event_name, payload)


# ─────────────────────────────────────────────────────────────
# 工具方法（State 共用）
# ─────────────────────────────────────────────────────────────

## 与目标的当前距离（含目标为空保护）。返回 INF 表示无目标。
func distance_to_target() -> float:
	if target == null or enemy == null:
		return INF
	if not target is Node2D or not enemy is Node2D:
		return INF
	return (target as Node2D).global_position.distance_to((enemy as Node2D).global_position)


## 朝目标方向（归一化），无目标返回零向量。
func direction_to_target() -> Vector3:
	if target == null or enemy == null or not target is Node2D or not enemy is Node2D:
		return Vector3.ZERO
	var d: Vector2 = (target as Node2D).global_position - (enemy as Node2D).global_position
	if d.length() < 0.001:
		return Vector3.ZERO
	d = d.normalized()
	return Vector3(d.x, d.y, 0.0)
