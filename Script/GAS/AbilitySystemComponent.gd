## AbilitySystemComponent（ASC）。
##
## 聚合：
##   - attribute_set : AttributeSet（属性）
##   - tags : GameplayTagContainer（运行时 tag）
##   - granted_abilities : Dictionary[StringName, Ability]
##   - cooldowns : Dictionary[StringName, float]（剩余 CD 秒）
##   - active_effects : Array[ActiveEffectHandle]（仅 DURATION/PERIODIC）
##
## 每物理帧驱动 CD 倒计时与持续/周期 GE 的 tick。
## 信号转发：tag_added/removed 转发到 EventBus（M2 暂以日志体现，M3 起 UI 订阅）。
class_name AbilitySystemComponent
extends Node

# ─────────────────────────────────────────────────────────────
# 公开字段
# ─────────────────────────────────────────────────────────────

## 由场景或代码设置的 AttributeSet 资源（可在 Inspector 拖入 .tres）。
@export var attribute_set: AttributeSet = null

## 起始就授予的技能集（可在 Inspector 拖入多个 .tres）。M3 起也支持运行时 grant。
@export var startup_abilities: Array[Ability] = []

# ─────────────────────────────────────────────────────────────
# 运行时
# ─────────────────────────────────────────────────────────────

var tags: GameplayTagContainer = GameplayTagContainer.new()
var granted_abilities: Dictionary = {}        # StringName -> Ability
var cooldowns: Dictionary = {}                # StringName -> float (剩余秒)
var active_effects: Array = []                # ActiveEffectHandle 内部数组


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	# attribute_set 是 Resource，从 .tres 加载会被多个实例共享。这里复制一份避免污染。
	if attribute_set != null:
		attribute_set = attribute_set.duplicate(true)
		attribute_set.owner_node = get_parent()

	for ab in startup_abilities:
		if ab != null:
			grant_ability(ab)

	GameLogger.info("GAS", "ASC ready on %s, abilities=%d" % [get_parent().name, granted_abilities.size()])


func _physics_process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_active_effects(delta)


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
	ab._end(self)
	EventBus.ability_ended.emit(get_parent(), ability_id)


## 应用一个 GE 到指定 ASC（可以是自身）。返回是否成功应用。
## source 用于事件溯源（"谁打的我"），可为 null。
func apply_effect_to(target_asc: Node, ge: GameplayEffect, source: Node) -> bool:
	if ge == null or target_asc == null:
		return false

	# 应用前 tag 检查（target 侧）
	if not ge.application_required_tags.is_empty() and not target_asc.tags.has_all(ge.application_required_tags):
		return false
	if not ge.application_blocked_tags.is_empty() and target_asc.tags.has_any(ge.application_blocked_tags):
		return false

	GameLogger.info("GAS", "[%s] apply %s -> [%s]" % [
		get_parent().name if get_parent() != null else "?",
		ge.get_display_name(),
		target_asc.get_parent().name if target_asc.get_parent() != null else "?",
	])

	# 一次性强制清除目标的 tag（净化类）
	for t in ge.removed_tags:
		target_asc.tags.force_remove_matching(t)

	match ge.effect_type:
		GameplayEffect.EffectType.INSTANT:
			_apply_modifiers(target_asc, ge)
		GameplayEffect.EffectType.DURATION:
			_attach_active(target_asc, ge, source)
		GameplayEffect.EffectType.PERIODIC:
			_attach_active(target_asc, ge, source)

	EventBus.effect_applied.emit(target_asc.get_parent(), ge, source)
	return true


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _emit_failed(ability_id: StringName, reason: String) -> void:
	GameLogger.warn("GAS", "%s try_activate %s failed: %s" % [get_parent().name, ability_id, reason])
	EventBus.ability_activation_failed.emit(get_parent(), ability_id, reason)


func _apply_modifiers(target_asc: Node, ge: GameplayEffect) -> void:
	if target_asc.attribute_set == null:
		return
	for m in ge.modifiers:
		var result := m.apply_to(target_asc.attribute_set)
		GameLogger.info("GAS", "  [%s] %s: %.1f -> %.1f" % [
			target_asc.get_parent().name if target_asc.get_parent() != null else "?",
			m.attribute,
			result.old,
			result.new,
		])


func _attach_active(target_asc: Node, ge: GameplayEffect, source: Node) -> void:
	# 建一个轻量 handle dict（避免再造一个类，简化 M2 实现）
	var handle := {
		"ge": ge,
		"target": target_asc,
		"source": source,
		"remaining": ge.duration,           # <=0 表示永久（仅 PERIODIC 允许）
		"period_acc": 0.0,
		"granted_tags": ge.granted_tags.duplicate(),
	}
	# 推入 granted_tags
	for t in ge.granted_tags:
		target_asc.tags.add_tag(t)
	target_asc.active_effects.append(handle)


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
	target_asc.active_effects.erase(handle)
	EventBus.effect_removed.emit(target_asc.get_parent(), handle["ge"])
