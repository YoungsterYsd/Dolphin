## 对峙：站立不动持续若干秒后返回 SUCCESS。
##
## 语义：「对峙」—— 行为内容 · 对峙。进入时停止移动；可选朝向目标；持续 [member duration] 秒
## （或 [member random_min]~[member random_max] 区间）。
##
## LimboAI 改造（迁移自旧 BTAction_Standoff）：
##   - extends [BTAction]（LimboAI 原生 C++ 基类）
##   - agent 由 [BTPlayer] 注入；预期 agent 是 [EnemyCharacter] 派生（含 move_comp 字段）
##   - sprite 通过 [NodeFinder.find_first_of_type] 在 _setup 时缓存
@tool
extends BTAction


## 是否进入时朝向目标。
@export var face_target: bool = true

## 固定持续时长（秒）。当 [member random_min]/[member random_max] 都 > 0 时被忽略。
@export var duration: float = 1.0

## 随机区间下限（秒）。0 = 不启用。
@export var random_min: float = 0.0

## 随机区间上限（秒）。0 = 不启用。
@export var random_max: float = 0.0


# 运行时
var _remaining: float = 0.0
var _sprite: SpriteBase3D = null


func _generate_name() -> String:
	if random_min > 0.0 and random_max > random_min:
		return "Standoff %.1f~%.1fs" % [random_min, random_max]
	return "Standoff %.1fs" % duration


func _setup() -> void:
	if agent != null:
		_sprite = NodeFinder.find_first_of_type(agent, SpriteBase3D)


func _enter() -> void:
	# 停止移动
	var move_comp: Node = agent.get(&"move_comp") if agent != null and "move_comp" in agent else null
	if move_comp != null and move_comp.has_method(&"set_input_dir"):
		move_comp.call(&"set_input_dir", Vector3.ZERO)

	# 朝向目标（仅 SpriteBase3D.flip_h，正反两面）
	if face_target and _sprite != null:
		var dir: Vector3 = _direction_to_target()
		if dir != Vector3.ZERO:
			_sprite.flip_h = (dir.x < 0.0)

	# 计算时长
	if random_min > 0.0 and random_max > random_min:
		_remaining = randf_range(random_min, random_max)
	else:
		_remaining = duration


func _tick(delta: float) -> Status:
	_remaining -= delta
	if _remaining <= 0.0:
		return SUCCESS
	return RUNNING


# ─────────────────────────────────────────────────────────────
# 工具：XZ 平面 agent → player 方向（与 BTContext.direction_to_target 等价）
# ─────────────────────────────────────────────────────────────
func _direction_to_target() -> Vector3:
	var target: Node = _find_target()
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


func _find_target() -> Node:
	# 优先黑板 target；否则 player group 首个
	if blackboard != null and blackboard.has_var(&"target"):
		var t: Variant = blackboard.get_var(&"target")
		if t is Node:
			return t as Node
	if agent != null and agent.is_inside_tree():
		var players: Array = agent.get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			return players[0]
	return null
