## 转向：仅设 [SpriteBase3D.flip_h]，瞬时返回 SUCCESS。
##
## 语义：「转移朝向」—— 行为内容 · 仅需要正反两个角度。
##
## 模式：
##   - [code]AUTO[/code]：根据目标 X 方向自动判定（目标在左则 flip_h=true）
##   - [code]FORCE_LEFT[/code]：强制朝左（flip_h=true）
##   - [code]FORCE_RIGHT[/code]：强制朝右（flip_h=false）
##   - [code]TOGGLE[/code]：取反当前 flip_h
##
## 无 sprite 时返回 FAILURE。
##
## LimboAI 改造（迁移自旧 BTAction_FaceTarget）。
@tool
extends BTAction


enum FaceMode {
	AUTO,
	FORCE_LEFT,
	FORCE_RIGHT,
	TOGGLE,
}


@export var mode: FaceMode = FaceMode.AUTO


# 运行时
var _sprite: SpriteBase3D = null


func _generate_name() -> String:
	match mode:
		FaceMode.AUTO: return "Face Target (auto)"
		FaceMode.FORCE_LEFT: return "Face Left"
		FaceMode.FORCE_RIGHT: return "Face Right"
		FaceMode.TOGGLE: return "Face Toggle"
	return "FaceTarget"


func _setup() -> void:
	if agent != null:
		_sprite = NodeFinder.find_first_of_type(agent, SpriteBase3D)


func _tick(_delta: float) -> Status:
	if _sprite == null:
		return FAILURE
	match mode:
		FaceMode.AUTO:
			var dir: Vector3 = _direction_to_target()
			if dir == Vector3.ZERO:
				return FAILURE
			_sprite.flip_h = (dir.x < 0.0)
		FaceMode.FORCE_LEFT:
			_sprite.flip_h = true
		FaceMode.FORCE_RIGHT:
			_sprite.flip_h = false
		FaceMode.TOGGLE:
			_sprite.flip_h = not _sprite.flip_h
	return SUCCESS


func _direction_to_target() -> Vector3:
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
		return Vector3.ZERO
	if not target is Node3D or not agent is Node3D:
		return Vector3.ZERO
	var t_pos: Vector3 = (target as Node3D).global_position
	var a_pos: Vector3 = (agent as Node3D).global_position
	var d: Vector3 = Vector3(t_pos.x - a_pos.x, 0.0, t_pos.z - a_pos.z)
	if d.length() < 0.001:
		return Vector3.ZERO
	return d.normalized()
