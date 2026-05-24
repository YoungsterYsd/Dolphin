## 释放技能：调 [method AbilitySystemComponent.try_activate]，可选等待 [signal EventBus.ability_ended]。
##
## 语义：「释放技能」—— 行为内容 · 释放技能。
##
## 返回值：
##   - try_activate 失败（CD 中 / 缺 tag / 子类条件不满足）→ FAILURE
##   - 成功且 [member wait_for_end]=false → 立即 SUCCESS
##   - 成功且 [member wait_for_end]=true → RUNNING 直到收到 [signal EventBus.ability_ended]
##
## LimboAI 改造（迁移自旧 BTAction_CastAbility）：
##   - 旧硬度字段 [code]poise_level[/code] / [code]interruptible_by_hurt[/code] 暂未对接（LimboAI 无内置硬度系统）；
##     未来需要时在本 task 的 _tick 开头检查 blackboard.event_took_damage + payload.attacker_poise_level，主动 return FAILURE 即可
@tool
extends BTAction


## 要释放的 ability_id。
@export var ability_id: StringName = &""

## 是否等待 [signal EventBus.ability_ended] 才返回 SUCCESS。
@export var wait_for_end: bool = true

## 激活前是否朝目标转向。
@export var face_target_first: bool = true


# 运行时
var _waiting: bool = false
var _activated_ok: bool = false
var _sprite: SpriteBase3D = null


func _generate_name() -> String:
	return "Cast %s" % (ability_id if ability_id != &"" else "(unset)")


func _setup() -> void:
	if agent != null:
		_sprite = NodeFinder.find_first_of_type(agent, SpriteBase3D)


func _enter() -> void:
	_waiting = false
	_activated_ok = false

	if ability_id == &"":
		GameLogger.warn("AI", "[%s] BTAction_CastAbility: ability_id is empty" % _agent_name())
		return

	# 转向（仅 SpriteBase3D.flip_h，正反两面）
	if face_target_first and _sprite != null:
		var dir: Vector3 = _direction_to_target()
		if dir != Vector3.ZERO:
			_sprite.flip_h = (dir.x < 0.0)

	# 停止移动（边追边放由上层 Sequence 编排）
	var move_comp: Node = agent.get(&"move_comp") if agent != null and "move_comp" in agent else null
	if move_comp != null and move_comp.has_method(&"set_input_dir"):
		move_comp.call(&"set_input_dir", Vector3.ZERO)

	# 激活
	var asc: Node = agent.get(&"asc") if agent != null and "asc" in agent else null
	if asc == null or not asc.has_method(&"try_activate"):
		return
	_activated_ok = asc.call(&"try_activate", ability_id)
	if not _activated_ok:
		return

	# 进入等待（仅 wait_for_end=true 时连 signal）
	if wait_for_end:
		_waiting = true
		EventBus.connect(&"ability_ended", _on_ability_ended)


func _tick(_delta: float) -> Status:
	# enter 失败 → FAILURE
	if not _activated_ok:
		return FAILURE
	# 不等待 → 立即 SUCCESS
	if not wait_for_end:
		return SUCCESS
	# 等待中
	if _waiting:
		return RUNNING
	# 等待已完成
	return SUCCESS


func _exit() -> void:
	# 清理 signal 连接（abort 时也走这里）
	if EventBus.is_connected(&"ability_ended", _on_ability_ended):
		EventBus.disconnect(&"ability_ended", _on_ability_ended)
	_waiting = false


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _on_ability_ended(_owner_node: Node, ended_id: StringName) -> void:
	if ended_id != ability_id:
		return
	_waiting = false
	if EventBus.is_connected(&"ability_ended", _on_ability_ended):
		EventBus.disconnect(&"ability_ended", _on_ability_ended)


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


func _agent_name() -> String:
	if agent == null:
		return "?"
	return agent.name
