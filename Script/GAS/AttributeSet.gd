## AttributeSet 基类（Resource）。
##
## 子类用 [code]@export[/code] 声明属性。运行时通过 [method set_attr] 修改，自动 clamp + 广播。
## R-GAS-02：业务代码禁止直接 [code]attribute_set.health = x[/code]，必须经 [method set_attr]。
##
## 广播：[signal EventBus.attribute_changed(owner, attr_name, old_value, new_value)]。
##
## ── 声明式 hook 表（R-CODE-02 实现）──
##
## 子类通过覆盖 [method _get_attribute_hooks] 集中声明属性钩子，替代字符串反射式
## [code]_pre_change_<attr>[/code] / [code]_post_apply_effect[/code] 发现。
##
## 钩子结构：[code]Dictionary[StringName, Dictionary][/code]，每条目支持以下 key（全可选）：
##   - [code]clamp_min: float[/code]（默认 0.0；写 -INF 表示无下限）
##   - [code]clamp_max: float[/code]（默认 INF；可填 1.0 表示 0~1 区间）
##   - [code]max_attr: StringName[/code]（指向另一字段名；运行时取该字段值作为 clamp 上限，覆盖 clamp_max）
##   - [code]post_apply: Callable[/code]（set_attr 落值后的回调，签名 [code]func(attr, old, new)[/code]，
##     用于元属性管道，例如 health_damage 反应到 health）
##
## 例（PrimaryAttributeSet）：
## [codeblock]
## func _get_attribute_hooks() -> Dictionary:
##     return {
##         &"crit_chance":     {"clamp_min": 0.0, "clamp_max": 1.0},
##         &"def_pierce":      {"clamp_min": 0.0, "clamp_max": 1.0},
##         &"dmg_red_mul":     {"clamp_min": 0.0, "clamp_max": 1.0},
##         &"life_steal_mul":  {"clamp_min": 0.0, "clamp_max": 1.0},
##     }
## [/codeblock]
##
## 例（HealthSet 元属性管道）：
## [codeblock]
## func _get_attribute_hooks() -> Dictionary:
##     return {
##         &"health":          {"max_attr": &"max_health"},
##         &"stamina_current": {"max_attr": &"stamina_max"},
##         &"health_damage":   {"post_apply": _on_health_damage_applied},
##         &"health_healing":  {"post_apply": _on_health_healing_applied},
##     }
## [/codeblock]
##
## 内部用 [member _hooks_cache] 在 [method _init] 时缓存查表结果，避免每次 set_attr 反射。
class_name AttributeSet
extends Resource

## 持有该 AttributeSet 的节点（一般为 ASC 所在节点）。由 ASC 在 ready 时设置。
## 用于属性变更广播时携带 owner 上下文。
var owner_node: Node = null

## 钩子表缓存。[method _init] 时由 [method _get_attribute_hooks] 填充。
var _hooks_cache: Dictionary = {}


func _init() -> void:
	_hooks_cache = _get_attribute_hooks()


## 子类重写：返回属性钩子声明表。详见类注释。
##
## 默认返回空 dict（无任何钩子，所有属性走 base clamp 行为）。
func _get_attribute_hooks() -> Dictionary:
	return {}


## 修改属性值。统一入口，走 hook 查表 → clamp → set → post_apply 回调 → 广播。
## 返回最终落地值（被 clamp + 钩子修正后）。
func set_attr(attr_name: StringName, value: float) -> float:
	if not _has_attribute(attr_name):
		GameLogger.error("GAS", "AttributeSet has no attribute: %s" % attr_name)
		return 0.0
	var old_value: float = get(attr_name)

	# 从声明表查 hook（O(1) Dict lookup 替代字符串反射；R-CODE-02）
	var hook: Dictionary = _hooks_cache.get(attr_name, {})

	# 计算 clamp 上下限（优先 max_attr 动态值；否则用 clamp_max；都没填走默认 INF）
	var lo: float = hook.get(&"clamp_min", 0.0)
	var hi: float = INF
	if hook.has(&"max_attr"):
		var max_field: StringName = hook[&"max_attr"]
		if _has_attribute(max_field):
			hi = get(max_field)
	elif hook.has(&"clamp_max"):
		hi = hook[&"clamp_max"]
	else:
		# 兼容旧 max_xxx 自动映射约定（health → max_health 等）
		var max_name := StringName("max_" + String(attr_name))
		if _has_attribute(max_name):
			hi = get(max_name)

	var clamped: float = clampf(value, lo, hi)

	if is_equal_approx(clamped, old_value):
		# 数值未实际变化时仍调一次 post_apply（便于元属性管道每帧累计）；不广播 attribute_changed
		if hook.has(&"post_apply"):
			(hook[&"post_apply"] as Callable).call(attr_name, old_value, clamped)
		return clamped

	set(attr_name, clamped)

	# post_apply 钩子（元属性管道：health_damage → health 等）
	if hook.has(&"post_apply"):
		(hook[&"post_apply"] as Callable).call(attr_name, old_value, clamped)

	if owner_node != null:
		EventBus.attribute_changed.emit(owner_node, attr_name, old_value, clamped)
	return clamped


## 增量修改：value += delta。
func add_to_attr(attr_name: StringName, delta: float) -> float:
	return set_attr(attr_name, get_attr(attr_name) + delta)


## 读取属性值。
func get_attr(attr_name: StringName) -> float:
	if not _has_attribute(attr_name):
		GameLogger.error("GAS", "AttributeSet has no attribute: %s" % attr_name)
		return 0.0
	return get(attr_name)


## 便利方法：返回持有本 AttributeSet 的 ASC 节点。
##
## 约定 owner_node 通常是 ASC 的父节点（BaseCharacter）；此处兼容两种持有方式：
## 1) owner_node 自己就是 ASC（owner_node 直接挂在 BaseCharacter 上） → 返回自己
## 2) owner_node 是 BaseCharacter，通过 .asc 访问 → 返回 .asc
##
## 找不到时返回 null。
func get_owner_asc() -> Node:
	if owner_node == null:
		return null
	# 情况 1：owner_node 自己就是 AbilitySystemComponent
	if owner_node.get_class() == "Node" and owner_node.get_script() != null:
		var s := owner_node.get_script() as Script
		if s != null and s.get_global_name() == &"AbilitySystemComponent":
			return owner_node
	# 情况 2：owner_node 上挂着 ASC 子节点（如 BaseCharacter.asc）
	if &"asc" in owner_node:
		var a = owner_node.get(&"asc")
		if a is Node:
			return a as Node
	return null


func _has_attribute(attr_name: StringName) -> bool:
	for p in get_property_list():
		if p.name == String(attr_name):
			return true
	return false
