## 应用阶段速度倍率：基于"基础速度 × 倍率"修改 [MoveComponent.max_speed]，瞬时返回 SUCCESS。
##
## 语义：替代旧 [code]BossAI._apply_phase[/code]，配合 [BTCondition_SelfHealthBelow] 实现
## "HP 跨阈值进入新阶段 → 加速"的 Boss 演出。
##
## 状态防抖：用 [Node.get_meta]/[Node.set_meta] 在 agent 上记 [code]_bt_phase_speed_mult[/code]
## 标志，倍率与上次相同时直接 SUCCESS 不重复设值。
##
## 基础速度记忆：第一次调时把 [member MoveComponent.max_speed] 当前值存入 agent meta
## [code]_bt_phase_base_speed[/code]，后续按"基础 × 倍率"算最终速度。
##
## LimboAI 改造（迁移自旧 BTAction_ApplyPhaseSpeed）。
@tool
extends BTAction


## 速度倍率。1.0 = 基础速度；1.3 = +30%。
@export var speed_multiplier: float = 1.0

## 是否同时 emit [signal EventBus.boss_phase_changed]（仅 Boss 用，普通敌人填 -1 不广播）。
@export var emit_phase_index: int = -1


# 状态防抖 meta key
const _META_PHASE_MULT: StringName = &"_bt_phase_speed_mult"
const _META_BASE_SPEED: StringName = &"_bt_phase_base_speed"


func _generate_name() -> String:
	if emit_phase_index >= 0:
		return "Phase %d Speed x%.2f" % [emit_phase_index, speed_multiplier]
	return "Speed x%.2f" % speed_multiplier


func _tick(_delta: float) -> Status:
	if agent == null:
		return FAILURE
	var move_comp: Node = agent.get(&"move_comp") if "move_comp" in agent else null
	if move_comp == null:
		return FAILURE

	# 防抖：相同倍率不重设
	var last_mult: float = float(agent.get_meta(_META_PHASE_MULT, -1.0))
	if is_equal_approx(last_mult, speed_multiplier):
		return SUCCESS

	# 第一次调：记基础速度
	if not agent.has_meta(_META_BASE_SPEED):
		agent.set_meta(_META_BASE_SPEED, move_comp.get(&"max_speed"))

	var base_speed: float = float(agent.get_meta(_META_BASE_SPEED))
	var new_speed: float = base_speed * speed_multiplier
	move_comp.set(&"max_speed", new_speed)
	agent.set_meta(_META_PHASE_MULT, speed_multiplier)

	GameLogger.info("AI", "[%s] phase speed: base=%.2f mult=%.2f -> %.2f" % [
		agent.name, base_speed, speed_multiplier, new_speed,
	])

	# 可选：广播 boss_phase_changed
	if emit_phase_index >= 0:
		EventBus.emit_signal(&"boss_phase_changed", agent, emit_phase_index)

	return SUCCESS
