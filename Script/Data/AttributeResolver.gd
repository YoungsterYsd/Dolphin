## 属性解算器：把成长表 + 等级 → 最终属性字典。
##
## 文档原文：{1级属性, x级限制, x级前每级增加属性, y级限制, x-y级区间每级增加属性}
## 实现：对每个 [AttributeGrowthEntry]：
##   final = base_value + Σ (该等级落在的所有完整段的级数 * per_level_delta)
##                       + (当前段已升级数 * per_level_delta)
##
## 解算结果是 Dictionary[StringName, float]，调用方可遍历后调 [CharacterAttributeSet.set_attr]
## 或直接覆盖 @export 字段（推荐 set_attr 走 clamp + 信号）。
##
## 静态工具类，请勿 new。
class_name AttributeResolver
extends RefCounted


## 解算单个 entry 在指定 level 的最终数值。
static func resolve_entry(entry: AttributeGrowthEntry, level: int) -> float:
	if entry == null:
		return 0.0
	var value: float = entry.base_value
	if level <= 1 or entry.segments.is_empty():
		return value

	# 已升的级数 = level - 1
	var levels_up_remaining: int = level - 1
	# 上一段结束等级（初始 1，因为 base_value 对应 1 级）
	var prev_breakpoint: int = 1

	for seg in entry.segments:
		if seg == null:
			continue
		# 该段可吸收的升级数 = (breakpoint_level - prev_breakpoint) 级
		var seg_capacity: int = max(0, seg.breakpoint_level - prev_breakpoint)
		var consume: int = min(levels_up_remaining, seg_capacity)
		if consume > 0:
			value += float(consume) * seg.per_level_delta
			levels_up_remaining -= consume
		prev_breakpoint = seg.breakpoint_level
		if levels_up_remaining <= 0:
			break

	# 如果 segments 不够覆盖（如等级超过最后段 breakpoint），剩余级数沿用最后段 per_level_delta
	if levels_up_remaining > 0 and not entry.segments.is_empty():
		var last_seg: GrowthSegment = entry.segments[entry.segments.size() - 1]
		if last_seg != null:
			value += float(levels_up_remaining) * last_seg.per_level_delta

	return value


## 解算整张成长表 → Dictionary[StringName, float]。
static func resolve(table: AttributeGrowthTable, level: int) -> Dictionary:
	var out: Dictionary = {}
	if table == null:
		return out
	for entry in table.entries:
		if entry == null or entry.attribute_name == &"":
			continue
		out[entry.attribute_name] = resolve_entry(entry, level)
	return out


## 把解算结果应用到一个 [CharacterAttributeSet]（走 set_attr，触发信号 + clamp）。
## 应用顺序：先 max_* 再非 max_*（保证 clamp 上限正确）。
## 同时如果有 max_health 但解算结果中无 health，会自动 health = max_health。
static func apply_to_attribute_set(values: Dictionary, attr_set: CharacterAttributeSet) -> void:
	if attr_set == null or values.is_empty():
		return

	# 先处理 max_*
	for key in values.keys():
		var k: StringName = key
		if String(k).begins_with("max_"):
			attr_set.set_attr(k, values[k])

	# 再处理其它属性
	for key in values.keys():
		var k2: StringName = key
		if not String(k2).begins_with("max_"):
			attr_set.set_attr(k2, values[k2])

	# 自动补：解算给了 max_health 但没给 health，则 health 拉满
	if values.has(&"max_health") and not values.has(&"health"):
		attr_set.set_attr(&"health", values[&"max_health"])
	if values.has(&"max_mana") and not values.has(&"mana"):
		attr_set.set_attr(&"mana", values[&"max_mana"])
