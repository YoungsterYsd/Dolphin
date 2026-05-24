## 检测怪物与目标的 XZ 平面距离。
##
## 语义：「玩家与怪物距离」。
##
## 操作符：
##   - [code]LT[/code]：距离 < [member max_dist]
##   - [code]GT[/code]：距离 > [member min_dist]
##   - [code]IN_RANGE[/code]：[member min_dist] <= 距离 <= [member max_dist]
##
## 无目标时返回 FAILURE。
##
## LimboAI 改造（迁移自旧 BTCondition_DistanceToTarget）。
@tool
extends BTCondition


enum Op {
	LT,
	GT,
	IN_RANGE,
}


@export var op: Op = Op.LT

## LT 模式：上限；IN_RANGE 模式：上限。
@export var max_dist: float = 5.0

## GT 模式：下限；IN_RANGE 模式：下限。
@export var min_dist: float = 0.0


func _generate_name() -> String:
	match op:
		Op.LT: return "Dist < %.1f" % max_dist
		Op.GT: return "Dist > %.1f" % min_dist
		Op.IN_RANGE: return "Dist in [%.1f, %.1f]" % [min_dist, max_dist]
	return "Distance"


func _tick(_delta: float) -> Status:
	var dist: float = _distance_to_target()
	if dist == INF:
		return FAILURE
	match op:
		Op.LT:
			return SUCCESS if dist < max_dist else FAILURE
		Op.GT:
			return SUCCESS if dist > min_dist else FAILURE
		Op.IN_RANGE:
			return SUCCESS if (dist >= min_dist and dist <= max_dist) else FAILURE
	return FAILURE


func _distance_to_target() -> float:
	var target: Node = null
	if blackboard != null and blackboard.has_var(&"target"):
		var t: Variant = blackboard.get_var(&"target")
		if t is Node:
			target = t as Node
	if target == null and agent != null and agent.is_inside_tree():
		var players: Array = agent.get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			target = players[0]
	if target == null or agent == null:
		return INF
	if not target is Node3D or not agent is Node3D:
		return INF
	var t_pos: Vector3 = (target as Node3D).global_position
	var a_pos: Vector3 = (agent as Node3D).global_position
	var dx: float = t_pos.x - a_pos.x
	var dz: float = t_pos.z - a_pos.z
	return sqrt(dx * dx + dz * dz)
