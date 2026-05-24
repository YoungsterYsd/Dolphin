## 进入破韧状态：停止移动 + 加 [code]Status.PoiseBroken[/code] tag + 持续 [member duration] 秒。
##
## 与 [DamagePipeline] / [EnemyCharacter] 的链路：
##   1. 玩家命中 → [DamagePipeline] 第 12 步调 [method EnemyCharacter.apply_poise_damage]
##   2. 韧性归零 → [method EnemyCharacter._trigger_poise_broken] 加 tag + emit [signal EventBus.poise_broken]
##   3. EnemyCharacter._on_poise_broken 把事件写黑板键 [code]&"event_poise_broken"[/code]
##   4. 顶层 Selector 高优先级分支命中 [BTCondition_OnEvent](&"poise_broken") → 进本 Action
##   5. 本 Action 持续 5s（[member duration] 默认）→ 退出时移 tag + emit [signal EventBus.poise_recovered]
##
## Q1 决策：破韧期间受击不会延长本 Action 时长（[method EnemyCharacter.apply_poise_damage] 内部 tag 早退）。
##
## LimboAI 改造（迁移自旧 BTAction_EnterPoiseBroken）。
@tool
extends BTAction


## 破韧持续秒。0 = 取 [member CombatBalanceConfig.poise_broken_duration_sec] 配置（默认 5.0）。
@export var duration: float = 0.0


# 运行时
var _remaining: float = 0.0


func _generate_name() -> String:
	if duration > 0.0:
		return "Enter PoiseBroken %.1fs" % duration
	return "Enter PoiseBroken (config)"


func _enter() -> void:
	# 停止移动
	var move_comp: Node = agent.get(&"move_comp") if agent != null and "move_comp" in agent else null
	if move_comp != null and move_comp.has_method(&"set_input_dir"):
		move_comp.call(&"set_input_dir", Vector3.ZERO)

	# 解析时长
	if duration > 0.0:
		_remaining = duration
	else:
		var bal: CombatBalanceConfig = ConfigCenter.get_combat_balance_config()
		_remaining = bal.poise_broken_duration_sec if bal != null else 5.0

	GameLogger.info("AI", "[%s] enter PoiseBroken (%.1fs)" % [_agent_name(), _remaining])


func _tick(delta: float) -> Status:
	_remaining -= delta
	if _remaining <= 0.0:
		return SUCCESS
	return RUNNING


func _exit() -> void:
	# 1. 移除 tag（DamagePipeline 不再施加易伤）
	var asc: Node = agent.get(&"asc") if agent != null and "asc" in agent else null
	if asc != null and asc.has_method(&"remove_tag"):
		asc.call(&"remove_tag", &"Status.PoiseBroken")

	# 2. 韧性条恢复满（_trigger_poise_broken 时已重置，这里冗余保险）
	if agent != null and "poise_max" in agent and "poise_current" in agent:
		agent.set(&"poise_current", agent.get(&"poise_max"))

	# 3. 清掉 took_damage 黑板键（避免破韧结束瞬间立切 HurtReact）
	if blackboard != null and blackboard.has_var(&"event_took_damage"):
		blackboard.erase_var(&"event_took_damage")

	# 4. 广播恢复（HUD 韧性条等订阅）
	if agent != null:
		EventBus.emit_signal(&"poise_recovered", agent)

	GameLogger.info("AI", "[%s] exit PoiseBroken" % _agent_name())


func _agent_name() -> String:
	if agent == null:
		return "?"
	return agent.name
