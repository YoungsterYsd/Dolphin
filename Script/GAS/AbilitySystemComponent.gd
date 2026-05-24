## AbilitySystemComponent（ASC）。
##
## 聚合：
##   - attribute_sets : Array[AttributeSet]（属性集合，玩家=HealthSet+PrimaryAttributeSet+CombatSet）
##   - tags : GameplayTagContainer（运行时 tag）
##   - granted_abilities : Dictionary[StringName, Ability]
##   - cooldowns : Dictionary[StringName, float]（剩余 CD 秒）
##   - active_effects : Array[ActiveEffectHandle]（仅 DURATION/PERIODIC）
##
## 每物理帧驱动 CD 倒计时与持续/周期 GE 的 tick + 激活中 Ability 的 _tick 钩子。
## 信号转发：tag_added/removed 转发到 EventBus 给 UI 订阅。
##
## 设计原则（参见 [code]Plans/全局规则.md[/code]）：
##   - R-CODE-01：必备资源 / 必备组件缺失 → assert 崩；不做兜底
##   - R-ARCH-04：跨模块状态变更走 EventBus（如格挡耐久耗尽 emit block_broken；不反向调 BlockComponent）
##   - 业务侧统一通过 [member attribute_sets] 多 Set 路由（[method get_attribute] / [method set_attribute]
##     自动跨 Set 查找）；不再有 M2 时代单 attribute_set 老接口
class_name AbilitySystemComponent
extends Node

# ─────────────────────────────────────────────────────────────
# 公开字段
# ─────────────────────────────────────────────────────────────

## 多 AttributeSet 数组（一个角色可挂多个 Set，例如 玩家 = HealthSet + PrimaryAttributeSet + CombatSet）。
##
## 顺序约定：HealthSet 通常作为 [code]attribute_sets[0][/code]（许多业务直接读 health/max_health）。
##
## 推荐用 [method get_attribute] / [method set_attribute]，自动跨 Set 路由查找。
@export var attribute_sets: Array[AttributeSet] = []

## 起始就授予的技能集（可在 Inspector 拖入多个 .tres）。也支持运行时 grant。
@export var startup_abilities: Array[Ability] = []

# ─────────────────────────────────────────────────────────────
# 运行时
# ─────────────────────────────────────────────────────────────

var tags: GameplayTagContainer = GameplayTagContainer.new()
var granted_abilities: Dictionary = {}        # StringName -> Ability
var cooldowns: Dictionary = {}                # StringName -> float (剩余秒)
var active_effects: Array = []                # ActiveEffectHandle 内部数组

## 当前激活中的 ability_id 集合。
##
## 由 [method try_activate] push、[method end_ability] / [method cancel_active_abilities] pop。
## [method get_current_poise_level] / [method _tick_active_abilities] 据此查激活中 GA。
##
## 设计：用 Dictionary 当 Set 用（key=ability_id, value=true），避免 Array 遍历查找。
var _activating_ids: Dictionary = {}          # StringName -> true

## InterruptResolver 进入硬直时挂的 HitReact Timeline handle_id。
## 0 = 当前未在硬直 / 已用退化定时器路径。
##
## 仅供 [method _on_skill_timeline_ended_for_stagger] 匹配使用，避免静态 InterruptResolver
## 在 EventBus 上挂匿名 lambda（违反 R-EVENT-02）。
var _pending_stagger_handle: int = 0


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	# 复制一份所有 AttributeSet（Resource 从 .tres 加载会被多实例共享）
	var dup_list: Array[AttributeSet] = []
	for s in attribute_sets:
		if s == null:
			continue
		var dup := s.duplicate(true) as AttributeSet
		dup.owner_node = get_parent()
		dup_list.append(dup)
	attribute_sets = dup_list

	for ab in startup_abilities:
		if ab != null:
			grant_ability(ab)

	# R-EVENT-02：connect EventBus 必须用 named method（自动 disconnect on free）
	EventBus.skill_timeline_ended.connect(_on_skill_timeline_ended_for_stagger)

	GameLogger.info("GAS", "ASC ready on %s, abilities=%d, sets=%d" % [
		get_parent().name, granted_abilities.size(), attribute_sets.size()
	])


func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_active_effects(delta)
	_tick_active_abilities(delta)


# ─────────────────────────────────────────────────────────────
# 公共 API
# ─────────────────────────────────────────────────────────────

## 授予一个技能。
func grant_ability(ability: Ability) -> void:
	if ability == null or ability.ability_id == &"":
		GameLogger.error("GAS", "grant_ability: invalid ability or empty id")
		return
	granted_abilities[ability.ability_id] = ability


## 撤销一个技能。
func revoke_ability(ability_id: StringName) -> void:
	granted_abilities.erase(ability_id)


## 是否拥有某技能。
func has_ability(ability_id: StringName) -> bool:
	return granted_abilities.has(ability_id)


## 取剩余 CD 秒。
func get_cooldown_remaining(ability_id: StringName) -> float:
	return cooldowns.get(ability_id, 0.0)


## 尝试激活技能。返回是否成功。
## 失败原因通过 EventBus.ability_activation_failed 广播。
func try_activate(ability_id: StringName) -> bool:
	var ab: Ability = granted_abilities.get(ability_id, null)
	if ab == null:
		_emit_failed(ability_id, "ability not granted")
		return false

	# CD
	if get_cooldown_remaining(ability_id) > 0.0:
		_emit_failed(ability_id, "on cooldown (%.2fs)" % get_cooldown_remaining(ability_id))
		return false

	# Tag required
	if not ab.tags_required.is_empty() and not tags.has_all(ab.tags_required):
		_emit_failed(ability_id, "missing required tags: %s" % str(ab.tags_required))
		return false

	# Tag blocked
	if not ab.tags_blocked.is_empty() and tags.has_any(ab.tags_blocked):
		_emit_failed(ability_id, "blocked by tags: %s" % str(ab.tags_blocked))
		return false

	# 全局硬直拦截：Stagger / PoiseBroken 期间所有 GA 一律不能激活
	# 设计：避免每份 ability .tres 都要在 tags_blocked 显式列这两个 tag
	if tags.has_tag(&"Status.Stagger") or tags.has_tag(&"Status.PoiseBroken"):
		_emit_failed(ability_id, "global block: staggered or poise broken")
		return false

	# 子类额外条件
	if not ab._can_activate_extra(self):
		_emit_failed(ability_id, "extra condition failed")
		return false

	# Cost
	if ab.cost_effect != null:
		apply_effect_to(self, ab.cost_effect, get_parent())

	# 启动 CD
	if ab.cooldown > 0.0:
		cooldowns[ability_id] = ab.cooldown

	# 推入 activation_tags
	for t in ab.activation_tags:
		tags.add_tag(t)

	# 标记激活中（供 cancel_active_abilities / get_current_poise_level 使用）
	_activating_ids[ability_id] = true

	EventBus.ability_activated.emit(get_parent(), ability_id)
	GameLogger.info("GAS", "%s activated %s" % [get_parent().name, ability_id])

	# 子类执行
	ab._activate(self)
	return true


## 由 Ability.finish 回调，pop activation_tags + emit ended。
func end_ability(ability_id: StringName) -> void:
	var ab: Ability = granted_abilities.get(ability_id, null)
	if ab == null:
		return
	for t in ab.activation_tags:
		tags.remove_tag(t)
	# 出激活集合（不在集合里也无副作用，erase 安全）
	_activating_ids.erase(ability_id)
	ab._end(self)
	EventBus.ability_ended.emit(get_parent(), ability_id)


## 强制中止所有正在激活的 ability。
##
## 用于 [InterruptResolver] 的打断流程：受到高硬度命中时清空当前所有激活中 GA。
##
## 与 [method end_ability] 的区别：
## - end_ability：ability 自己 finish 调用，正常收尾
## - cancel_active_abilities：外部强制打断，pop activation_tags + ab._end + 派发
##   [signal EventBus.ability_interrupted] 让上层（AI / UI / Cue）感知
##
## 返回被中止的 ability_id 列表。
func cancel_active_abilities() -> Array[StringName]:
	if _activating_ids.is_empty():
		return []
	var cancelled: Array[StringName] = []
	# 拷贝 keys 避免迭代时修改
	var ids: Array = _activating_ids.keys()
	for id in ids:
		var ab_id: StringName = id as StringName
		var ab: Ability = granted_abilities.get(ab_id, null)
		if ab == null:
			_activating_ids.erase(ab_id)
			continue
		# pop activation_tags
		for t in ab.activation_tags:
			tags.remove_tag(t)
		_activating_ids.erase(ab_id)
		ab._end(self)
		cancelled.append(ab_id)
		EventBus.ability_interrupted.emit(get_parent(), ab_id)
		# ended 信号也派一次，保证订阅 ended 的清理逻辑（cooldown UI、动画收尾）也走到
		EventBus.ability_ended.emit(get_parent(), ab_id)

	if not cancelled.is_empty():
		GameLogger.info("GAS", "[%s] cancel_active_abilities: %s" % [
			get_parent().name if get_parent() != null else "?",
			str(cancelled),
		])
	return cancelled


## 取当前生效硬度等级（供 [InterruptResolver] 判定是否打断当前 GA 用）。
##
## 计算规则（按优先级）：
## 1. 持有 [code]Combat.SuperArmor[/code] tag → INT_MAX（霸体免打断）
## 2. 持有 [code]Status.PoiseBroken[/code] 或 [code]Status.Stagger[/code] tag → INT_MIN（任何攻击都打断）
## 3. 有激活中 GA → 取所有激活中 GA 的 [member Ability.cast_poise] 最大值
## 4. 否则 → 取宿主 [code]base_poise[/code] 字段（[BaseCharacter] 提供，缺失则 0）
##
## 设计：把"特殊状态"统一压在硬度数值上，[InterruptResolver] 只做整数比较，逻辑极简。
func get_current_poise_level() -> int:
	# 霸体压顶
	if tags.has_tag(&"Combat.SuperArmor"):
		return 0x7FFFFFFF  # INT_MAX
	# 破韧 / 硬直 → 任何冲击都能打断
	if tags.has_tag(&"Status.PoiseBroken") or tags.has_tag(&"Status.Stagger"):
		return -0x7FFFFFFF - 1  # INT_MIN

	# 激活中 GA 取最大 cast_poise
	if not _activating_ids.is_empty():
		var max_cast: int = -0x7FFFFFFF - 1
		for id in _activating_ids.keys():
			var ab: Ability = granted_abilities.get(id, null)
			if ab != null and ab.cast_poise > max_cast:
				max_cast = ab.cast_poise
		# 至少有一个激活中 GA 时返回其最大 cast_poise
		if max_cast > -0x7FFFFFFF:
			return max_cast

	# 兜底：宿主 base_poise
	var host: Node = get_parent()
	if host != null and &"base_poise" in host:
		return int(host.get(&"base_poise"))
	return 0


## 应用一个 GE 到指定 ASC（可以是自身）。返回是否成功应用。
## source 用于事件溯源（"谁打的我"），可为 null。
##
## 本方法是无 SetByCaller 数据的便利入口，内部转换为 [GameplayEffectSpec] 后调用 [method apply_effect_spec]。
## 携带运行时数据的场景（DamagePipeline / 复杂技能）应直接调 [method apply_effect_spec]。
func apply_effect_to(target_asc: Node, ge: GameplayEffect, source: Node) -> bool:
	if ge == null or target_asc == null:
		return false
	var spec := GameplayEffectSpec.make(ge, source, target_asc.get_parent())
	return (target_asc as AbilitySystemComponent).apply_effect_spec(spec)


## 以 [GameplayEffectSpec] 为输入应用 GE。
##
## 与 [method apply_effect_to] 的区别：spec 携带 SetByCaller 数据，让调用方注入运行时计算值。
## 例如 DamagePipeline 第 10 步：
## [code]
## var spec := GameplayEffectSpec.make(GE_DamageInstant, attacker, target)
## spec.set_by_caller_data[&"SetByCaller.Damage"] = final_dmg
## target.asc.apply_effect_spec(spec)
## [/code]
func apply_effect_spec(spec: GameplayEffectSpec) -> bool:
	if spec == null or spec.ge == null:
		return false
	var ge: GameplayEffect = spec.ge

	# 应用前 tag 检查（self 即目标侧）
	if not ge.application_required_tags.is_empty() and not tags.has_all(ge.application_required_tags):
		return false
	if not ge.application_blocked_tags.is_empty() and tags.has_any(ge.application_blocked_tags):
		return false

	GameLogger.info("GAS", "[%s] apply %s%s -> [%s]" % [
		spec.source.name if spec.source != null else "?",
		ge.get_display_name(),
		(" SetByCaller=%s" % spec.set_by_caller_data) if not spec.set_by_caller_data.is_empty() else "",
		get_parent().name if get_parent() != null else "?",
	])

	# 一次性强制清除目标的 tag（净化类）
	for t in ge.removed_tags:
		tags.force_remove_matching(t)

	match ge.effect_type:
		GameplayEffect.EffectType.INSTANT:
			_apply_modifiers(self, ge, spec)
		GameplayEffect.EffectType.DURATION:
			_attach_active(self, ge, spec.source)
		GameplayEffect.EffectType.PERIODIC:
			_attach_active(self, ge, spec.source)

	EventBus.effect_applied.emit(get_parent(), ge, spec.source)
	return true


# ─────────────────────────────────────────────────────────────
# 便利方法：tag 透传 + 占位 API
# ─────────────────────────────────────────────────────────────

## 是否持有某 tag（按父匹配）。透传 [member tags].has_tag。
func has_tag(t: StringName) -> bool:
	return tags.has_tag(t)


## 添加一个 tag（计数引用）。透传 [member tags].add_tag。
func add_tag(t: StringName) -> void:
	tags.add_tag(t)


## 移除一个 tag（计数 -1，到 0 才真正移除）。透传 [member tags].remove_tag。
func remove_tag(t: StringName) -> void:
	tags.remove_tag(t)


## 消耗格挡耐久（复用 stamina_current 字段）。
##
## 受击时按比例（[code]CombatBalanceConfig.block_durability_consume_ratio[/code]）入耐久消耗；
## 耗尽 → [code]CombatBalanceConfig.block_broken_stun_sec[/code] 秒破防硬直 + Combat.Block.Broken tag。
##
## R-ARCH-04：破防时 emit [signal EventBus.block_broken]，BlockComponent 自己订阅并 stop_block；
## 不反向调 BlockComponent（去越权耦合）。
func consume_block(amount: float) -> void:
	if not has_attribute(&"stamina_current"):
		return
	var current: float = get_attribute(&"stamina_current")
	var new_val: float = maxf(current - amount, 0.0)
	set_attribute(&"stamina_current", new_val)
	GameLogger.info("Combat", "[%s] consume_block %.1f → %.1f" % [
		get_parent().name if get_parent() != null else "?",
		amount, new_val,
	])
	if new_val <= 0.0:
		_trigger_block_broken()


## 破防硬直流程（耗尽时调用 + 内部 timer 自动 remove tag）。
func _trigger_block_broken() -> void:
	var stun_sec: float = ConfigCenter.get_combat_balance_config().block_broken_stun_sec
	add_tag(&"Combat.Block.Broken")
	var t: SceneTreeTimer = get_tree().create_timer(stun_sec)
	t.timeout.connect(func():
		remove_tag(&"Combat.Block.Broken")
	)
	# R-ARCH-04：通知 BlockComponent 强制松开（信号广播，不反向调）
	EventBus.block_broken.emit(get_parent())


# ─────────────────────────────────────────────────────────────
# 多 AttributeSet 路由
# ─────────────────────────────────────────────────────────────

## 跨所有挂载的 AttributeSet 查找属性，返回第一个找到的 Set；找不到返回 null。
func find_set_with_attr(attr_name: StringName) -> AttributeSet:
	for s in attribute_sets:
		if s == null:
			continue
		# AttributeSet._has_attribute 是 private 命名但 GDScript 仍可调
		if s.call(&"_has_attribute", attr_name):
			return s
	return null


## 跨所有 AttributeSet 取属性值。找不到返回 default_value（默认 0.0），并打 push_warning。
func get_attribute(attr_name: StringName, default_value: float = 0.0) -> float:
	var s := find_set_with_attr(attr_name)
	if s == null:
		# 仅 push_warning，不打 error 日志（敌人不挂 PrimaryAttributeSet，DamagePipeline 取 attack_final 等会大量降级，避免日志炸刷）
		return default_value
	return s.get_attr(attr_name)


## 跨所有 AttributeSet 写属性值。找不到时仅 warn 不 set。
func set_attribute(attr_name: StringName, value: float) -> float:
	var s := find_set_with_attr(attr_name)
	if s == null:
		GameLogger.warn("GAS", "[%s] set_attribute(%s) but no AttributeSet has it" % [
			get_parent().name if get_parent() != null else "?", attr_name
		])
		return 0.0
	return s.set_attr(attr_name, value)


## 检查是否有任一 Set 持有该属性（不发 warn，纯查询）。
func has_attribute(attr_name: StringName) -> bool:
	return find_set_with_attr(attr_name) != null


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _emit_failed(ability_id: StringName, reason: String) -> void:
	GameLogger.warn("GAS", "%s try_activate %s failed: %s" % [get_parent().name, ability_id, reason])
	EventBus.ability_activation_failed.emit(get_parent(), ability_id, reason)


func _apply_modifiers(target_asc: Node, ge: GameplayEffect, spec: GameplayEffectSpec = null) -> void:
	# 跨多 AttributeSet 路由：modifier.attribute 在哪个 Set 就应用到哪个 Set
	for m in ge.modifiers:
		var asc := target_asc as AbilitySystemComponent
		var s: AttributeSet = null
		if asc != null:
			s = asc.find_set_with_attr(m.attribute)
		if s == null:
			GameLogger.warn("GAS", "  [%s] %s: NO SET HAS THIS ATTRIBUTE, skip" % [
				target_asc.get_parent().name if target_asc.get_parent() != null else "?",
				m.attribute,
			])
			continue
		var result := m.apply_to(s, spec)
		GameLogger.info("GAS", "  [%s] %s: %.2f -> %.2f" % [
			target_asc.get_parent().name if target_asc.get_parent() != null else "?",
			m.attribute,
			result.old,
			result.new,
		])


func _attach_active(target_asc: Node, ge: GameplayEffect, source: Node) -> void:
	# 建一个轻量 handle dict（避免再造一个类，简化实现）
	var handle := {
		"ge": ge,
		"target": target_asc,
		"source": source,
		"remaining": ge.duration,           # <=0 表示永久（仅 PERIODIC 允许）
		"period_acc": 0.0,
		"granted_tags": ge.granted_tags.duplicate(),
		"cue_tags": ge.cue_tags_while_active.duplicate(),
	}
	# 推入 granted_tags
	for t in ge.granted_tags:
		target_asc.tags.add_tag(t)
	target_asc.active_effects.append(handle)

	# 启动持续 cue（cue_tags_while_active 字段）
	# instigator 是受 GE 影响的角色（target_asc.get_parent()），cue 视觉应附着在其身上
	var instigator: Node = target_asc.get_parent() if target_asc.get_parent() != null else target_asc
	for cue_tag in ge.cue_tags_while_active:
		GameInstance.cue_manager.add_active_cue(cue_tag, instigator, {})


func _tick_cooldowns(delta: float) -> void:
	if cooldowns.is_empty():
		return
	var to_clear: Array[StringName] = []
	for k in cooldowns.keys():
		var v: float = cooldowns[k] - delta
		if v <= 0.0:
			to_clear.append(k)
		else:
			cooldowns[k] = v
	for k in to_clear:
		cooldowns.erase(k)


func _tick_active_effects(delta: float) -> void:
	if active_effects.is_empty():
		return
	var to_remove: Array = []
	for h in active_effects:
		var ge: GameplayEffect = h["ge"]
		# Periodic 周期触发
		if ge.effect_type == GameplayEffect.EffectType.PERIODIC and ge.period > 0.0:
			h["period_acc"] += delta
			while h["period_acc"] >= ge.period:
				h["period_acc"] -= ge.period
				_apply_modifiers(h["target"], ge)
		# 倒计时
		if h["remaining"] > 0.0:
			h["remaining"] -= delta
			if h["remaining"] <= 0.0:
				to_remove.append(h)
	for h in to_remove:
		_detach_active(h)


func _detach_active(handle: Dictionary) -> void:
	var target_asc: Node = handle["target"]
	for t in handle["granted_tags"]:
		target_asc.tags.remove_tag(t)

	# 停止持续 cue
	var instigator: Node = target_asc.get_parent() if target_asc.get_parent() != null else target_asc
	var cue_tags: Array = handle.get("cue_tags", [])
	for cue_tag in cue_tags:
		GameInstance.cue_manager.remove_active_cue(cue_tag, instigator)

	target_asc.active_effects.erase(handle)
	EventBus.effect_removed.emit(target_asc.get_parent(), handle["ge"])


# ─────────────────────────────────────────────────────────────
# 调度激活中 Ability 的 _tick 钩子
# ─────────────────────────────────────────────────────────────

## 每物理帧调用所有"激活中"Ability 的 [method Ability._tick]。
##
## 激活判定：[code]_activating_ids[/code] 集合（由 [method try_activate] push、
## [method end_ability] / [method cancel_active_abilities] pop）。
func _tick_active_abilities(delta: float) -> void:
	if _activating_ids.is_empty():
		return
	# 拷贝 keys 防 _tick 内 finish 改动集合
	var ids: Array = _activating_ids.keys()
	for id in ids:
		var ab: Ability = granted_abilities.get(id, null)
		if ab != null:
			ab._tick(self, delta)


# ─────────────────────────────────────────────────────────────
# 属性 Bootstrap（数据驱动属性初始化，由 [BaseCharacter] 或子类调用）
# ─────────────────────────────────────────────────────────────

## 数据驱动属性初始化主入口。从 ConfigCenter 解算属性 → 写入 AttributeSet → 触发 8 步初始化序列。
##
## 调用方（[BaseCharacter] / 子类）只需提供：
## - [param kind]：[code]ConfigCenter.CharacterKind[/code]（HERO / MONSTER）
## - [param data_id]：Hero_Data 或 Monster_Data 中的主键 id
## - [param level_override]：等级覆盖（<=0 时由 ConfigCenter.resolve_level 决定）
## - [param required_set_classes]：本角色必备的 AttributeSet 类（数组，例如玩家
##   [code][HealthSet, PrimaryAttributeSet, CombatSet][/code]，敌人 [code][HealthSet, CombatSet][/code]）
## - [param skip_regens]：是否跳过 Stamina/Block Regen（敌人可传 true）
##
## 返回 ConfigCenter 解算结果 dict，调用方可读 [code]values[&"move_speed_base"][/code] 同步 MoveComponent。
##
## 失败语义（按"移除兜底，崩溃式失败"路线）：
## - data_id <= 0 → assert 崩
## - ConfigCenter / 实例 / 属性表 缺失 → resolve_character_attributes 返回空 dict → assert 崩
## - required_set_classes 中某个类无法实例化 → assert 崩
func bootstrap_from_entity(
	kind: int,
	data_id: int,
	level_override: int,
	required_set_classes: Array,
	skip_regens: bool
) -> Dictionary:
	assert(data_id > 0, "ASC.bootstrap_from_entity: data_id must be > 0")
	assert(not required_set_classes.is_empty(),
		"ASC.bootstrap_from_entity: required_set_classes must not be empty")

	# 1. 解算等级
	var lv: int = ConfigCenter.resolve_level(kind, data_id, level_override)

	# 2. 解算属性 dict
	var values: Dictionary = ConfigCenter.resolve_character_attributes(kind, data_id, lv)
	assert(not values.is_empty(),
		"ASC.bootstrap_from_entity: resolve_character_attributes empty (kind=%d data_id=%d lv=%d)" % [kind, data_id, lv])

	# 3. 确保挂载所有必备 AttributeSet（场景未挂时显式声明性创建；不是兜底，是 contract）
	ensure_attribute_sets(required_set_classes)

	# 4. 写入属性（apply_to_asc 内部跨 Set 路由 + max_*→当前值同步）
	AttributeResolver.apply_to_asc(values, self)

	# 4.1 衍生公式重算：让 attack_final / armor_final / max_health 等基于刚写入的 base/bonus/mul 立刻就位。
	# 避免「bootstrap 完到第一次 DamagePipeline 调用之间」窗口期 _final 字段还是 export 默认值的问题。
	# DamagePipeline 入口仍会再调一次（应对装备词条期变更），这里是稳健性兜底。
	for s in attribute_sets:
		if s != null and s.has_method(&"recompute_derived"):
			s.call(&"recompute_derived")

	# 5. 8 步初始化的第 3/5/6/8 步
	_run_post_inject_init(skip_regens)

	GameLogger.info("GAS", "[%s] bootstrap_from_entity done: kind=%d data_id=%d lv=%d sets=%d" % [
		get_parent().name if get_parent() != null else "?",
		kind, data_id, lv, attribute_sets.size(),
	])

	return values


## 显式声明性创建必备 AttributeSet。仅创建不存在的；已存在的（场景里手动挂的）不重复。
##
## 与"兜底"的区别：调用方明确知道它要哪几套 Set，本方法只是把"声明"落到运行时。
## [code]ensure_attribute_sets[/code] 内部调用 [code].new()[/code] 失败会直接崩。
func ensure_attribute_sets(set_classes: Array) -> void:
	for cls in set_classes:
		assert(cls != null, "ASC.ensure_attribute_sets: null class in list")
		# 已存在则跳过
		var has_it: bool = false
		for s in attribute_sets:
			if s != null and s.get_script() == cls:
				has_it = true
				break
		if has_it:
			continue
		# 不存在则创建
		var inst: AttributeSet = cls.new()
		assert(inst != null, "ASC.ensure_attribute_sets: failed to instantiate %s" % str(cls))
		inst.owner_node = get_parent()
		attribute_sets.append(inst)


## 撤销所有 granted_tag 中含指定 tag 的 active_effect。
##
## 给 [BlockComponent] 等"主动停止某 GE"的场景使用。R-CHAR-01：组件不应直接调
## ASC 的 [code]_detach_active[/code] 私有 API；用本公共方法。
##
## 返回被撤销的 effect 数量。
func remove_effects_with_granted_tag(target_tag: StringName) -> int:
	var to_remove: Array = []
	for handle in active_effects:
		if handle == null:
			continue
		var granted: Array = handle.get("granted_tags", [])
		if target_tag in granted:
			to_remove.append(handle)
	for h in to_remove:
		_detach_active(h)
	return to_remove.size()


# ─────────────────────────────────────────────────────────────
# 内部：8 步初始化序列的第 3/5/6/8 步
# ─────────────────────────────────────────────────────────────

## 8 步序列：
## 1. 应用 GE_Init_PrimaryAttributes ← AttributeResolver.apply_to_asc 已完成主属性写入
## 2. ConfigCenter resolve 等级 ← bootstrap_from_entity 已完成
## 3. 应用 GE_Init_DerivedAttributes（衍生公式）← 调 PrimaryAttributeSet.recompute_derived
## 4. 装备覆盖词条 ← 装备系统接入时实装
## 5. 应用 GE_HealthInit_Full（health = max_health）← 本方法
## 6. 挂 GE_HealthRegen / StaminaRegen ← 本方法
## 7. 注册 CombatStateService ← 由 CombatStateService 自身订阅 character_initialized
## 8. emit EventBus.character_initialized ← 本方法
func _run_post_inject_init(skip_regens: bool) -> void:
	# 第 3 步：衍生属性
	# PrimaryAttributeSet.recompute_derived（仅玩家）
	for s in attribute_sets:
		if s is PrimaryAttributeSet:
			(s as PrimaryAttributeSet).recompute_derived()
	# HealthSet.recompute_derived（max_health 衍生 + move_speed_final 衍生）
	# 注：当前没有 %移速 字段，move_speed_mul 默认 0；如未来加该词条再传入
	for s in attribute_sets:
		if s is HealthSet:
			(s as HealthSet).recompute_derived(0.0)

	# 第 5/6 步：取 GE 通过 ConfigCenter 强类型直访
	# 第 5 步：HealthInit_Full
	var ge_full: GameplayEffect = ConfigCenter.get_ge(&"HealthInit_Full")
	if ge_full != null:
		apply_effect_to(self, ge_full, get_parent())

	# 第 6 步：Regen 套件
	if not skip_regens:
		_apply_ge_if_present(&"HealthRegen")
	# StaminaRegen 仅玩家挂；敌人 skip_regens=true 时跳过
	# 注：格挡耐久复用 stamina_current 字段，由 StaminaRegen 兼任回充（不再单独 BlockRegen GE）
	if not skip_regens and has_attribute(&"stamina_current"):
		_apply_ge_if_present(&"StaminaRegen")
	# 敌人也需要 HealthRegen（field 存在时挂；不存在时由 GE 自身 modifier 路由跳过）
	if skip_regens and has_attribute(&"health"):
		_apply_ge_if_present(&"HealthRegen")

	# 第 7 步：CombatStateService 注册（由 Service 自身订阅 character_initialized 完成）

	# 第 8 步：完成事件
	EventBus.character_initialized.emit(get_parent())


func _apply_ge_if_present(ge_id: StringName) -> void:
	var ge: GameplayEffect = ConfigCenter.get_ge(ge_id)
	if ge != null:
		apply_effect_to(self, ge, get_parent())


# ─────────────────────────────────────────────────────────────
# 升级时的属性重算（玩家 LevelComponent 调用）
# ─────────────────────────────────────────────────────────────

## 按新等级重算成长属性（不动 GE，不发 character_initialized，不拉满当前值）。
##
## ── 与 [method bootstrap_from_entity] 的区别 ──
## bootstrap 是"角色 spawn 时一次性 8 步初始化"，包含 GE_HealthInit_Full、GE_HealthRegen 等
## 一次性 / 持续效果挂载 + emit character_initialized；
## 本方法是"运行时随等级变化重算 base 字段"，**仅做：**
##   1) 按新等级重新解算 [code]Char_Attr / Monster_Attr[/code] 成长曲线
##   2) [code]apply_to_asc(values, self, sync_max_to_current=false)[/code] 写 base/bonus 等
##   3) 调各 AttributeSet 的 [method recompute_derived] 重算 max_health / attack_final / armor_final
##
## **不**重挂任何 GE、**不**拉满当前 HP/体力——调用方（[LevelComponent]）按业务策略
## （保留比例 / 保持数值 / 升级回满）自行调整 [code]health[/code] / [code]stamina_current[/code]。
##
## ── 失败语义 ──
## - data_id <= 0 / new_level <= 0 → assert 崩
## - ConfigCenter 解算返回空 dict → assert 崩
##
## 当前主要使用方：玩家升级（HERO + LevelComponent）；
## 怪物等级在 spawn 时静态定死（Monster_Data.csv），永不调用本方法。
func recompute_level_attributes(kind: int, data_id: int, new_level: int) -> void:
	assert(data_id > 0, "ASC.recompute_level_attributes: data_id must be > 0")
	assert(new_level > 0, "ASC.recompute_level_attributes: new_level must be > 0")

	var values: Dictionary = ConfigCenter.resolve_character_attributes(kind, data_id, new_level)
	assert(not values.is_empty(),
		"ASC.recompute_level_attributes: resolve empty (kind=%d data_id=%d lv=%d)" % [kind, data_id, new_level])

	# 写 base/bonus 字段，但不拉满当前值
	AttributeResolver.apply_to_asc(values, self, false)

	# 重算衍生（max_health / attack_final / armor_final / move_speed_final）
	for s in attribute_sets:
		if s != null and s.has_method(&"recompute_derived"):
			s.call(&"recompute_derived")

	GameLogger.info("GAS", "[%s] recompute_level_attributes: lv=%d (current values preserved)" % [
		get_parent().name if get_parent() != null else "?",
		new_level,
	])


# ─────────────────────────────────────────────────────────────
# 硬直（Stagger）追踪：与 InterruptResolver 配合
# ─────────────────────────────────────────────────────────────

## 进入硬直状态。由 [InterruptResolver] 在判定打断后调用。
##
## 加 [code]Status.Stagger[/code] tag + 记录 HitReact Timeline handle_id；
## Timeline 结束后由 [method _on_skill_timeline_ended_for_stagger] 清 tag。
##
## [param handle_id] = 0 表示走"退化定时器"路径（HitReact Timeline 缺失），
## 由 [InterruptResolver] 自己用 SceneTreeTimer 计时移 tag。
func enter_stagger(handle_id: int) -> void:
	add_tag(&"Status.Stagger")
	_pending_stagger_handle = handle_id


## 强制退出硬直（移 Status.Stagger tag + 清 handle 跟踪）。
##
## 退化定时器路径 / 死亡清理路径调用。
func exit_stagger() -> void:
	if _pending_stagger_handle != 0:
		_pending_stagger_handle = 0
	if has_tag(&"Status.Stagger"):
		remove_tag(&"Status.Stagger")


## EventBus.skill_timeline_ended 回调。
##
## 仅在该 ended_handle_id == [member _pending_stagger_handle] 时清 Stagger tag，
## 避免误清非 HitReact Timeline 结束触发的解硬直。
func _on_skill_timeline_ended_for_stagger(_skill_id: StringName, _caster: Node, ended_handle_id: int) -> void:
	if _pending_stagger_handle == 0 or ended_handle_id != _pending_stagger_handle:
		return
	_pending_stagger_handle = 0
	if has_tag(&"Status.Stagger"):
		remove_tag(&"Status.Stagger")
