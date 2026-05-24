## 命中伤害结算器（薄壳）。
##
## ⚠️ D2.D 改造：本类从"1 步公式自己算"改为"转发到 [DamagePipeline] 13 步公式"。
## - 仍保留作为 [HitboxComponent.hit_landed] 的统一入口（meta 取 skill_id + damage_node_index 等保留逻辑）
## - 实际伤害计算走 [DamagePipeline.compute_and_apply]，13 步全跑（暴击/防穿/格挡/吸血/破韧 全部生效）
## - 把 [DamageNode.damage_multiplier] 直接当 [param base_damage] 透传给 DamagePipeline，
##   DamagePipeline 内部用 `dmg = max(atk, 1) × base_damage` 起点公式
##
## 同一次激活去重：依赖 caster.set_meta(EventTrackHandler.META_RESOLVED_TARGETS) 列表。
class_name HitDamageResolver
extends RefCounted


## 处理一次 HitboxComponent.hit_landed 信号。
## target_hurtbox：被命中的 HurtboxComponent（实际目标 = target_hurtbox.owner_node 或 owner）
## caster_asc：施法者 ASC（用于 apply_effect_to）
## 返回是否成功施加伤害。
static func resolve_hit(caster_asc: AbilitySystemComponent, target_hurtbox: HurtboxComponent) -> bool:
	if caster_asc == null or target_hurtbox == null:
		return false
	var caster: Node = caster_asc.get_parent()
	if caster == null:
		return false

	# 自伤过滤
	var target_node: Node = target_hurtbox.owner_node if target_hurtbox.owner_node != null else target_hurtbox.get_parent()
	if target_node == null or target_node == caster:
		return false

	# 同一次激活去重
	var resolved: Array = caster.get_meta(EventTrackHandler.META_RESOLVED_TARGETS, [])
	if target_node in resolved:
		return false
	resolved.append(target_node)
	caster.set_meta(EventTrackHandler.META_RESOLVED_TARGETS, resolved)

	# 取当前激活技能 + 伤害节点
	var skill_id: StringName = caster.get_meta(EventTrackHandler.META_CURRENT_SKILL_ID, &"")
	if skill_id == &"":
		GameLogger.warn("Skill", "HitDamageResolver: no current skill_id on caster %s" % caster.name)
		return false
	var damage_index: int = int(caster.get_meta(EventTrackHandler.META_DAMAGE_NODE_INDEX, 0))

	# R-Core：ConfigCenter 走 class_name 强类型直访
	var damage_node: DamageNode = ConfigCenter.get_damage_node(skill_id, damage_index)
	if damage_node == null:
		GameLogger.warn("Skill", "HitDamageResolver: no DamageNode for skill=%s idx=%d" % [skill_id, damage_index])
		return false

	# === D2.D 改造：所有伤害走 DamagePipeline 13 步 ===
	# damage_multiplier 直接当 base_damage 透传（语义即技能倍率，不再乘全局换算系数）
	var base_damage: float = damage_node.damage_multiplier
	if base_damage <= 0.0:
		GameLogger.info("Skill", "HitDamageResolver: damage_multiplier <= 0, skip apply")
		return false

	var damage_tags: Array[StringName] = []
	if damage_node.damage_type != &"":
		damage_tags.append(damage_node.damage_type)

	var result: Dictionary = DamagePipeline.compute_and_apply(
		caster, target_node, base_damage, damage_tags, false, false, damage_node.poise_damage, damage_node
	)

	# 附加 GE（如减速 / 流血）—— 完美格挡免伤场景仍正常附加（02 文档未明确，按 Dolphin 现行逻辑）
	for extra_ge in damage_node.apply_effects:
		if extra_ge != null:
			var target_asc: AbilitySystemComponent = _find_asc(target_node)
			if target_asc != null:
				caster_asc.apply_effect_to(target_asc, extra_ge, caster)

	# 触发本地受击信号 → 驱动 HitFlash / AI hit 状态 / 击退等订阅方
	# 注：result.dealt 已是 13 步管线的最终值（含格挡减伤等）；完美格挡 dealt=0 时本回调仍调用，让本地表现层（如 HitFlash）正确反应
	target_hurtbox.take_damage(float(result.dealt), caster)

	# 老 EventBus.damage_dealt 信号（M5 期表现层兼容）
	EventBus.damage_dealt.emit(caster, target_node, float(result.dealt), damage_node.damage_type)

	# 注：damage_dealt_v2 信号已由 DamagePipeline 第 13 步广播，此处不再重复
	GameLogger.info("Skill", "HIT %s -> %s skill=%s idx=%d dealt=%.1f crit=%s pb=%s" % [
		caster.name, target_node.name, skill_id, damage_index, result.dealt, result.is_crit, result.is_perfect_block,
	])
	return true


# 内部：在节点上找 ASC
static func _find_asc(node: Node) -> AbilitySystemComponent:
	if node == null:
		return null
	# 优先走 BaseCharacter.asc 字段
	if &"asc" in node:
		var a = node.get(&"asc")
		if a is AbilitySystemComponent:
			return a as AbilitySystemComponent
	var direct: Node = node.get_node_or_null(^"AbilitySystemComponent")
	if direct is AbilitySystemComponent:
		return direct
	if node.has_method(&"get_asc"):
		var got = node.call(&"get_asc")
		if got is AbilitySystemComponent:
			return got
	return null
