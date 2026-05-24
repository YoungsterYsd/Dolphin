## 硬度打断中央枢纽（静态工具类）。
##
## 由 [DamagePipeline] 第 10.5 步调用，决定本下命中是否打断目标当前 GA + 触发
## HitReact Timeline + 击退 + Cue。
##
## 5 步流程：
## 1. 算 [code]impact_level[/code]：优先 [DamageNode.hit_poise]（>= 0），否则
##    [PoiseImpactTable.resolve(dealt / target.max_health)]
## 2. 算 [code]target_level[/code]：[method AbilitySystemComponent.get_current_poise_level]
##    （含 SuperArmor → INT_MAX、PoiseBroken/Stagger → INT_MIN 的特殊压顶逻辑）
## 3. [code]impact_level > target_level[/code] 才打断，否则什么也不做
## 4. 执行打断：[method AbilitySystemComponent.cancel_active_abilities]
##    + [method AbilitySystemComponent.enter_stagger]（HitReact Timeline 由 ASC 自身订阅
##    EventBus.skill_timeline_ended 在结束时清 Stagger tag）
## 5. 派发 Cue（[code]Cue.HitReact.Light/Heavy[/code]）+ emit
##    [signal EventBus.character_interrupted]
##
## 设计：
## - 不持有状态，纯静态；任何 actor 受击都可调
## - HitReact Timeline 缺失时退化为"用最小硬直 [_FALLBACK_STAGGER_SEC] 秒计时移 tag"
## - R-EVENT-02：本类不直接 connect EventBus 信号；解 Stagger 由 ASC 用 named method 处理
class_name InterruptResolver

const _LOG_CH := "Combat"

## 退化路径下的最小硬直时长（HitReact Timeline 缺失时使用）。
const _FALLBACK_STAGGER_SEC := 0.3


## 打断判定主入口。
##
## - attacker：攻击方节点（可为 null，如陷阱）
## - target：受击方节点（必须含 [code]asc[/code] 字段）
## - dealt：本下最终扣血数值（来自 [DamagePipeline] 第 10 步）
## - damage_node：当前命中节点（可为 null；非 null 且 hit_poise >= 0 时直接采用其 hit_poise）
##
## 返回是否触发打断（用于上游日志 / 调试 / 后续扩展）。
static func try_interrupt(
	attacker: Node,
	target: Node,
	dealt: float,
	damage_node: DamageNode
) -> bool:
	# 1. 校验
	if not is_instance_valid(target):
		return false
	var target_asc: AbilitySystemComponent = _get_asc(target)
	if target_asc == null:
		return false

	# 已死则不打断（避免对 dying / dead 角色叠播 HitReact）
	if target_asc.has_tag(&"state.dead"):
		return false

	# 2. 算 impact_level
	var impact_level: int
	if damage_node != null and damage_node.hit_poise >= 0:
		impact_level = damage_node.hit_poise
	else:
		# 走伤害比例反查（dealt / max_health）
		var max_hp: float = target_asc.get_attribute(&"max_health", 0.0)
		if max_hp <= 0.0 or dealt <= 0.0:
			# 无最大血量基准（特殊角色 / 治疗等）→ 不打断
			return false
		impact_level = PoiseImpactTable.resolve(dealt / max_hp)

	# 3. 算 target_level + 比较
	var target_level: int = target_asc.get_current_poise_level()
	if impact_level <= target_level:
		# 不打断，提前退出
		return false

	# 4. 执行打断：cancel 所有激活中 GA
	var cancelled: Array[StringName] = target_asc.cancel_active_abilities()

	# 选 HitReact Timeline + 派发 Cue
	var bal: CombatBalanceConfig = ConfigCenter.get_combat_balance_config()
	var is_heavy: bool = (bal != null and impact_level >= bal.hit_react_heavy_threshold)
	var hit_react: SkillTimeline = null
	if bal != null:
		hit_react = bal.hit_react_heavy_timeline if is_heavy else bal.hit_react_light_timeline

	var handle_id: int = 0
	if hit_react != null and GameInstance.skill_timeline_player != null:
		# 播 HitReact Timeline；ASC 自己订阅 skill_timeline_ended 在结束时清 Stagger
		handle_id = GameInstance.skill_timeline_player.play(hit_react, target, attacker)

	# 进入硬直：handle_id > 0 → ASC 等 Timeline 结束清 tag；
	#         handle_id = 0 → 走退化定时器路径
	target_asc.enter_stagger(handle_id)

	if handle_id == 0:
		# 退化路径：HitReact Timeline 未配 / 启动失败 → SceneTreeTimer 计时
		_schedule_fallback_unstagger(target_asc, _FALLBACK_STAGGER_SEC)

	# 5. Cue + 信号
	var cue_tag: StringName = &"Cue.HitReact.Heavy" if is_heavy else &"Cue.HitReact.Light"
	if GameInstance.cue_manager != null:
		GameInstance.cue_manager.execute_cue(cue_tag, target, {
			"attacker": attacker,
			"impact_level": impact_level,
			"is_heavy": is_heavy,
		})
	EventBus.character_interrupted.emit(target, attacker, impact_level)

	GameLogger.info(_LOG_CH, "[%s] INTERRUPTED by [%s] impact=%d > target=%d cancelled=%s heavy=%s" % [
		target.name,
		attacker.name if is_instance_valid(attacker) else "?",
		impact_level, target_level, str(cancelled), is_heavy,
	])
	return true


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

## 在节点上找 ASC（与 [DamagePipeline._get_asc] 对齐）。
static func _get_asc(node: Node) -> AbilitySystemComponent:
	if node == null:
		return null
	if &"asc" in node:
		var a = node.get(&"asc")
		if a is AbilitySystemComponent:
			return a as AbilitySystemComponent
	return null


## 退化定时器：HitReact Timeline 未配置时用 SceneTreeTimer 计时调
## [method AbilitySystemComponent.exit_stagger]。
##
## R-EVENT-02 例外：SceneTreeTimer.timeout 是一次性 RefCounted 信号，
## lambda 仅捕获 target_asc 一个 Node 引用，加 is_instance_valid 守卫即可。
static func _schedule_fallback_unstagger(target_asc: AbilitySystemComponent, sec: float) -> void:
	if not is_instance_valid(target_asc):
		return
	var tree: SceneTree = target_asc.get_tree()
	if tree == null:
		# 极端情况：ASC 未在树里（理论不应发生），同帧直接清
		target_asc.exit_stagger()
		return
	var timer: SceneTreeTimer = tree.create_timer(sec)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(target_asc):
			target_asc.exit_stagger()
	)
