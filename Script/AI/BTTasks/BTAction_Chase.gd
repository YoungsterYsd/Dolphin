## 追逐玩家：朝目标方向持续移动，直到进入 [member stop_distance] 或超时。
##
## 语义：「追逐玩家」—— 行为内容 · 追逐玩家。
##
## 返回值：
##   - 进入 stop_distance → SUCCESS
##   - 超过 [member timeout] 秒未到达 → FAILURE
##   - 目标丢失 → FAILURE
##   - 正在追 → RUNNING
##
## LimboAI 改造（迁移自旧 BTAction_Chase）。
@tool
extends BTAction


## 进入此距离后视为到达，返回 SUCCESS。
@export var stop_distance: float = 1.5

## 最长持续秒（避免无限追下去）。0 = 无超时。
@export var timeout: float = 5.0

## 是否每帧根据移动方向更新 sprite.flip_h。
@export var face_movement: bool = true


# 运行时
var _elapsed: float = 0.0
var _sprite: SpriteBase3D = null


func _generate_name() -> String:
	return "Chase (stop=%.1f)" % stop_distance


func _setup() -> void:
	if agent != null:
		_sprite = NodeFinder.find_first_of_type(agent, SpriteBase3D)


func _enter() -> void:
	_elapsed = 0.0


func _tick(delta: float) -> Status:
	_elapsed += delta
	# 超时
	if timeout > 0.0 and _elapsed >= timeout:
		return FAILURE
	# 目标丢失
	var target: Node = _find_target()
	if target == null:
		return FAILURE
	# 距离判定
	var dist: float = _distance_to_target(target)
	if dist <= stop_distance:
		return SUCCESS
	# 移动
	var move_comp: Node = agent.get(&"move_comp") if agent != null and "move_comp" in agent else null
	if move_comp != null and move_comp.has_method(&"set_input_dir"):
		var dir: Vector3 = _direction_to(target)
		move_comp.call(&"set_input_dir", dir)
		# 朝向（按移动方向 X 分量）
		if face_movement and dir != Vector3.ZERO and _sprite != null:
			_sprite.flip_h = (dir.x < 0.0)
	return RUNNING


func _exit() -> void:
	# 停止移动（无论 SUCCESS / FAILURE / abort 都清零）
	var move_comp: Node = agent.get(&"move_comp") if agent != null and "move_comp" in agent else null
	if move_comp != null and move_comp.has_method(&"set_input_dir"):
		move_comp.call(&"set_input_dir", Vector3.ZERO)


# ─────────────────────────────────────────────────────────────
# 工具
# ─────────────────────────────────────────────────────────────
func _find_target() -> Node:
	if blackboard != null and blackboard.has_var(&"target"):
		var t: Variant = blackboard.get_var(&"target")
		if t is Node:
			return t as Node
	if agent != null and agent.is_inside_tree():
		var players: Array = agent.get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			return players[0]
	return null


func _distance_to_target(target: Node) -> float:
	if target == null or agent == null:
		return INF
	if not target is Node3D or not agent is Node3D:
		return INF
	var t_pos: Vector3 = (target as Node3D).global_position
	var a_pos: Vector3 = (agent as Node3D).global_position
	var dx: float = t_pos.x - a_pos.x
	var dz: float = t_pos.z - a_pos.z
	return sqrt(dx * dx + dz * dz)


func _direction_to(target: Node) -> Vector3:
	if target == null or agent == null:
		return Vector3.ZERO
	if not target is Node3D or not agent is Node3D:
		return Vector3.ZERO
	var t_pos: Vector3 = (target as Node3D).global_position
	var a_pos: Vector3 = (agent as Node3D).global_position
	var d: Vector3 = Vector3(t_pos.x - a_pos.x, 0.0, t_pos.z - a_pos.z)
	if d.length() < 0.001:
		return Vector3.ZERO
	return d.normalized()
