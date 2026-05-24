## DamagePipeline。
##
## 旧案 §基础数值公式锁定的 13 步伤害结算管线。所有伤害（玩家普攻、技能、敌人攻击、AOE 等）统一走本类。
##
## ⚠️ 设计要点：
## - **静态类**：无 AbilitySystemComponent 实例数据；按 (attacker, target, base_damage) 输入即可计算
## - **不直接扣血**：通过 [GameplayEffectSpec] + SetByCaller 走 [HealthSet] 元属性管道（health_damage → health）
## - **降级策略**：敌人 ASC 没挂 PrimaryAttributeSet 时，crit_chance / def_pierce 等返回 0；attack_final 回退到 0
## - **数值进配置**：所有平衡系数（DEFENSE_K / 格挡减伤系数 / 破韧基础占比 等）走 [CombatBalanceConfig]（R-DATA-02）
##
## 旧案 13 步公式（[code]Plans/前项目/角色系统_属性_旧案.md[/code]）：
## 1. 暴击判定（基础+%暴击 → 概率）
## 2. 防御穿透（armor *= 1 - def_pierce）
## 3. 承伤率 = K / (K + armor)，dmg *= 承伤率
## 4. 增伤（dmg *= 1 + dmg_inc_mul）
## 5. 减伤（dmg *= 1 - dmg_red_mul）
## 6. 完美格挡 buff（攻击方）：+50% 伤害 + 破韧 ×3
## 7. 目标完美格挡窗口：免伤 + 触发 buff
## 8. 普通格挡：耐久 ×0.6，未破防减伤 ×0.4
## 9. 破防判定（已并入第 8 步内部）
## 10. 应用扣血（GameplayEffectSpec + SetByCaller）
## 11. 吸血（攻击方按 life_steal_mul × dealt 回血）
## 12. 破韧值（base_damage × 0.1 × (1 + break_bonus)）
## 13. 飘字 / Cue 广播
##
## 使用示例（HitDamageResolver）：
## [codeblock]
## var result := DamagePipeline.compute_and_apply(
##     attacker, target,
##     base_damage,                 # SkillDamageTable 提供
##     [&"damage.type.physical"],
##     true,                        # is_skill
##     false                        # forced_crit
## )
## # result = {"dealt": float, "is_crit": bool, "is_perfect_block": bool}
## [/codeblock]
class_name DamagePipeline

const _LOG_CH := "Damage"


## 13 步伤害管线主入口。
##
## - attacker：发起者节点（一般是 BaseCharacter，需挂 ASC）
## - target：目标节点
## - base_damage：技能倍率（= [DamageNode.damage_multiplier]；语义为"基于施法者攻击的倍率"，
##   普攻 1.0、技能可 1.5/2.0/...；武器系统接入后可改为 weapon_base × skill_mul 的组合）
## - damage_tags：伤害标签数组（如 [&"damage.type.physical"]，飘字 / Cue 路由用）
## - is_skill：保留参数（旧案没有法术攻击概念，目前与 attack_final 等价；D6 词条可扩展）
## - forced_crit：是否强制暴击（完美格挡 buff / 词条等场景）
## - poise_damage：削韧值（来自 [DamageNode.poise_damage]；0 = 回退到 base_damage * break_base_ratio 兜底公式）
## - damage_node：本次命中的 [DamageNode]（可选，>=0 的 [code]hit_poise[/code] 可由
##   [InterruptResolver] 直接采用，避免走伤害比例反查；为 null 时退到比例反查）
##
## 返回：{"dealt": float, "is_crit": bool, "is_perfect_block": bool}
static func compute_and_apply(
	attacker: Node,
	target: Node,
	base_damage: float,
	damage_tags: Array[StringName],
	is_skill: bool = false,
	forced_crit: bool = false,
	poise_damage: float = 0.0,
	damage_node: DamageNode = null
) -> Dictionary:
	if attacker == null or target == null or base_damage <= 0.0:
		return {"dealt": 0.0, "is_crit": false, "is_perfect_block": false}

	var attacker_asc: AbilitySystemComponent = _get_asc(attacker)
	var target_asc: AbilitySystemComponent = _get_asc(target)
	if attacker_asc == null or target_asc == null:
		return {"dealt": 0.0, "is_crit": false, "is_perfect_block": false}

	# 取战斗平衡配置（R-DATA-02 数据驱动；R-Core 后走 class_name 强类型直访）
	var bal: CombatBalanceConfig = ConfigCenter.get_combat_balance_config()

	# 进入入口先 recompute_derived，让 attack_final 等衍生属性是最新的
	for s in attacker_asc.attribute_sets:
		if s is PrimaryAttributeSet:
			(s as PrimaryAttributeSet).recompute_derived()
			break

	# 取攻击力（敌人无 PrimaryAttributeSet → fallback 到 0.0）
	# 注：旧案没有法术攻击概念；is_skill 保留参数但当前与物理统一走 attack_final
	var atk: float = attacker_asc.get_attribute(&"attack_final", attacker_asc.get_attribute(&"attack_base", 0.0))

	# 伤害公式起点：dmg = atk × 技能倍率（base_damage 即 DamageNode.damage_multiplier 透传）
	# 例：atk=10 普攻倍率=1.0 → dmg=10；atk=10 大招倍率=2.5 → dmg=25。
	# 武器系统接入后，base_damage 可由 weapon_base_damage × skill_mul 组合得出。
	var dmg: float = maxf(atk, 1.0) * base_damage

	# === 第 1 步：暴击判定 ===
	var crit_chance: float = attacker_asc.get_attribute(&"crit_chance", 0.0)
	var is_crit: bool = forced_crit or (randf() < crit_chance)
	if is_crit:
		var crit_mul: float = attacker_asc.get_attribute(&"crit_damage_mul", 1.5)
		dmg *= crit_mul

	# === 第 2 步：防御穿透 ===
	var def_pierce: float = attacker_asc.get_attribute(&"def_pierce", 0.0)
	var armor_raw: float = target_asc.get_attribute(&"armor_final", target_asc.get_attribute(&"armor_base", 0.0))
	var armor: float = armor_raw * (1.0 - def_pierce)

	# === 第 3 步：承伤率（旧案：K / (K + armor)，K 默认 500）===
	dmg = dmg * bal.defense_k / (bal.defense_k + maxf(armor, 0.0))

	# === 第 4 步：增伤 ===
	var dmg_inc: float = attacker_asc.get_attribute(&"dmg_inc_mul", 0.0)
	dmg *= (1.0 + dmg_inc)

	# === 第 5 步：减伤（目标承受）===
	var dmg_red: float = target_asc.get_attribute(&"dmg_red_mul", 0.0)
	dmg *= (1.0 - dmg_red)

	# === 第 5.5 步：破韧期间易伤（Q1 决策配套，输出窗口）===
	# 破韧期间不削韧（apply_poise_damage 内部 tag 早退）但伤害仍正常结算并放大。
	if target_asc.has_tag(&"Status.PoiseBroken"):
		dmg *= bal.poise_broken_damage_taken_mul

	# === 第 6 步：完美格挡 buff（攻击方）→ +50% 伤害 + 破韧 ×3，单次释放消耗 ===
	var has_pb_buff: bool = attacker_asc.has_tag(&"Combat.Buff.PerfectBlock")
	if has_pb_buff:
		dmg *= (1.0 + bal.perfect_block_buff_dmg_bonus)
		# 单次释放：清除 buff（GE_PerfectBlockBuff DURATION 5s 由 ASC active_effects 维护，找到匹配 handle 直接 detach）
		attacker_asc.remove_effects_with_granted_tag(&"Combat.Buff.PerfectBlock")

	# === 第 7 步：目标处于完美格挡窗口 → 完全免伤 + 通知刷 buff ===
	# R-CHAR-01 + R-ARCH-04：has_method 鸭子类型 → NodeFinder + BlockComponent 强类型
	var bc: BlockComponent = NodeFinder.find_first_child_of_type(target, BlockComponent) as BlockComponent
	if bc != null and bc.is_perfect_block_window():
		EventBus.damage_perfect_blocked.emit(attacker, target, dmg)
		bc.trigger_perfect_block_buff()
		# 发 v3 信号让飘字显示银色"完美格挡"
		EventBus.damage_dealt_v3.emit(attacker, target, 0.0, false, false, true, damage_tags)
		GameLogger.info(_LOG_CH, "[%s -> %s] PERFECT BLOCK! 0 dmg" % [attacker.name, target.name])
		return {"dealt": 0.0, "is_crit": is_crit, "is_perfect_block": true}

	# === 第 8 步：目标处于普通格挡（持续 D 键按住）→ 按耐久 ×0.6 消耗 ===
	var is_block: bool = false
	if target_asc.has_tag(&"Combat.Block.Active"):
		var consume: float = dmg * bal.block_durability_consume_ratio
		target_asc.consume_block(consume)
		# === 第 9 步：消耗后判破防 → 全额承伤；未破防 → ×0.4 减伤 ===
		if target_asc.has_tag(&"Combat.Block.Broken"):
			pass  # 全额承伤，dmg 不变
		else:
			dmg *= bal.block_damage_reduction
			is_block = true

	# === 第 10 步：应用扣血（通过 GameplayEffectSpec + SetByCaller → HealthSet 元属性管道）===
	# R-Core：ConfigCenter 走 class_name 强类型直访
	var ge_dmg: GameplayEffect = ConfigCenter.get_ge(&"DamageInstant")
	if ge_dmg != null:
		var spec := GameplayEffectSpec.make(ge_dmg, attacker, target)
		spec.set_caller(&"SetByCaller.Damage", dmg)
		target_asc.apply_effect_spec(spec)

	# === 第 11 步：吸血（攻击方）===
	var life_steal: float = attacker_asc.get_attribute(&"life_steal_mul", 0.0)
	if life_steal > 0.0:
		var ge_heal: GameplayEffect = ConfigCenter.get_ge(&"HealInstant")
		if ge_heal != null:
			var heal_spec := GameplayEffectSpec.make(ge_heal, attacker, attacker)
			heal_spec.set_caller(&"SetByCaller.Heal", dmg * life_steal)
			attacker_asc.apply_effect_spec(heal_spec)

	# === 第 12 步：削韧（Poise Damage）===
	# 数据驱动：优先取 [DamageNode.poise_damage]（>0）；为 0 时回退到 base_damage * break_base_ratio 兜底（兼容未配 poise_damage 的旧技能）。
	# 受攻击方 break_bonus 加成 + 完美格挡 buff ×3 倍率。
	# 实际削减由 [EnemyCharacter.apply_poise_damage] 完成（破韧期间 tag 早退，不再二次削）。
	var effective_poise: float = poise_damage if poise_damage > 0.0 else (base_damage * bal.break_base_ratio)
	if effective_poise > 0.0 and target.has_method(&"apply_poise_damage"):
		var final_poise: float = effective_poise * (1.0 + attacker_asc.get_attribute(&"break_bonus", 0.0))
		if has_pb_buff:
			final_poise *= bal.perfect_block_buff_break_bonus
		target.call(&"apply_poise_damage", final_poise)

	# === 第 12.5 步：硬度打断判定（双轨与削韧并列，互不替代）===
	# - 削韧：累积型，攻击多次 → 韧性归零进入 PoiseBroken 5s（已有，第 12 步处理）
	# - 硬度：即时型，本下 hit_poise > target.cast_poise → 立即 cancel 当前 GA + 播 HitReact
	# 注：完美格挡（dealt=0）已在第 7 步早退，本步不会被走到；普通格挡 dealt 已减伤后入此步判定。
	InterruptResolver.try_interrupt(attacker, target, dmg, damage_node)

	# === 第 13 步：飘字 / Cue 广播 ===
	# 老 EventBus.damage_dealt_v2 信号（兼容 HitVignetteWidget / ComboTracker / CombatStateService / EnergyComponent）
	EventBus.damage_dealt_v2.emit(attacker, target, dmg, _make_damage_node_payload(damage_tags), is_crit)
	# v3 信号：携带 4 样式标记（is_crit / is_block / is_perfect_block + tags），DamagePopup 订阅
	EventBus.damage_dealt_v3.emit(attacker, target, dmg, is_crit, is_block, false, damage_tags)
	# Cue 派发（CueManager 是 GameInstance 子模块；走 R-ARCH-03 强类型直访）
	# 启动期 GameInstance.cue_manager 必有，缺失即代码 bug 应崩
	GameInstance.cue_manager.execute_cue(&"Cue.Damage.Default.Hit", attacker, {
		"target": target,
		"dealt": dmg,
		"is_crit": is_crit,
		"is_block": is_block,
		"tags": damage_tags,
	})

	GameLogger.info(_LOG_CH, "[%s -> %s] dmg=%.1f crit=%s block=%s atk=%.1f armor=%.1f" % [
		attacker.name, target.name, dmg, is_crit, is_block, atk, armor_raw,
	])

	return {"dealt": dmg, "is_crit": is_crit, "is_perfect_block": false}


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

## 在节点上找 ASC（强类型走 BaseCharacter.asc 字段）。
##
## R-Core：BaseCharacter / TrainingDummy 都有 asc 字段；找不到说明调用方传错节点，崩出来更好。
static func _get_asc(node: Node) -> AbilitySystemComponent:
	if node == null:
		return null
	if &"asc" in node:
		var a = node.get(&"asc")
		if a is AbilitySystemComponent:
			return a as AbilitySystemComponent
	# 节点上无 asc 字段：调用方传错（如传了 Visual 节点而非 Character）
	GameLogger.warn(_LOG_CH, "_get_asc: node '%s' has no asc field" % node.name)
	return null


## 构造一个轻量 DamageNode-like Resource 给 damage_dealt_v2 用。
## 注：直接传 damage_tags 数组当 payload；M8 飘字 widget 只读 is_crit 即可，DamageNode 不强求。
static func _make_damage_node_payload(_damage_tags: Array[StringName]) -> Resource:
	# 当前 EventBus.damage_dealt_v2 签名要求 damage_node: Resource，但 M8 期 widget 实测仅用 is_crit
	# 这里返回 null 即可（飘字 widget 应当处理 null）
	return null
