## 命中伤害结算器（静态）。
##
## 由命中订阅方调用：从 caster.set_meta 取当前 skill_id + damage_node_index，
## 查 [SkillDamageTable] 得到 [DamageNode]，按公式计算最终伤害，构造一份临时的 INSTANT GE 应用到 target ASC。
##
## 公式（M7 默认线性，M8 可扩展暴击 / 护甲减免）：
##   final_damage = caster.attack * damage_node.damage_multiplier + damage_node.extra_flat_damage
##
## 同一次激活的命中去重：依赖 caster.set_meta(EventTrackHandler.META_RESOLVED_TARGETS) 列表。
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

	# 通过 ConfigCenter 查 SkillDamageTable
	var cfg: Node = caster.get_tree().root.get_node_or_null(^"ConfigCenter")
	if cfg == null:
		GameLogger.warn("Skill", "HitDamageResolver: ConfigCenter not found")
		return false
	var damage_node: DamageNode = cfg.get_damage_node(skill_id, damage_index)
	if damage_node == null:
		GameLogger.warn("Skill", "HitDamageResolver: no DamageNode for skill=%s idx=%d" % [skill_id, damage_index])
		return false

	# 找目标 ASC
	var target_asc: AbilitySystemComponent = _find_asc(target_node)
	if target_asc == null:
		GameLogger.warn("Skill", "HitDamageResolver: target %s has no ASC" % target_node.name)
		return false

	# 计算伤害值
	var caster_attack: float = 0.0
	if caster_asc.attribute_set != null:
		caster_attack = caster_asc.attribute_set.get_attr(&"attack")
	var raw_damage: float = caster_attack * damage_node.damage_multiplier + damage_node.extra_flat_damage
	if raw_damage <= 0.0:
		GameLogger.info("Skill", "HitDamageResolver: damage <= 0, skip apply")
		return false

	# 构造临时 INSTANT GE：health -= raw_damage
	var ge: GameplayEffect = GameplayEffect.new()
	ge.effect_type = GameplayEffect.EffectType.INSTANT
	ge.display_name = "DynamicDamage_%s_%d" % [skill_id, damage_index]
	var modifier: AttributeModifier = AttributeModifier.new()
	modifier.attribute = &"health"
	modifier.op = AttributeModifier.Op.ADD
	modifier.magnitude = -raw_damage
	ge.modifiers = [modifier]

	caster_asc.apply_effect_to(target_asc, ge, caster)

	# 附加 GE（如减速 / 流血）
	for extra_ge in damage_node.apply_effects:
		if extra_ge != null:
			caster_asc.apply_effect_to(target_asc, extra_ge, caster)

	# 广播伤害事件（给飘字、HUD 等订阅）
	EventBus.damage_dealt.emit(caster, target_node, raw_damage, damage_node.damage_type)
	# M8：扩展版伤害事件（带 DamageNode + 暴击标记；M10 GAS 扩展后 is_crit 才会真正生效）
	EventBus.damage_dealt_v2.emit(caster, target_node, raw_damage, damage_node, false)
	GameLogger.info("Skill", "HIT %s -> %s damage=%.1f (skill=%s idx=%d)" % [caster.name, target_node.name, raw_damage, skill_id, damage_index])
	return true


# 内部：在节点上找 ASC
static func _find_asc(node: Node) -> AbilitySystemComponent:
	if node == null:
		return null
	var direct: Node = node.get_node_or_null(^"AbilitySystemComponent")
	if direct is AbilitySystemComponent:
		return direct
	if node.has_method(&"get_asc"):
		var got = node.call(&"get_asc")
		if got is AbilitySystemComponent:
			return got
	return null
