## 词条加权抽样工具（静态）。
##
## 输入：plan_id（→ attr_plan 池）+ count
## 输出：[code]Array[Dictionary][/code] 纯数据（不放回加权抽样），格式：
## [codeblock]
## [
##   {"attribute": "health_base", "op": "add",      "magnitude": 20.0},
##   {"attribute": "attack_bonus", "op": "multiply", "magnitude": 0.1 },
## ]
## [/codeblock]
##
## **设计要点**：
##   - 输出纯 Dict 数组（不是 AttributeModifier 对象）→ 持久化友好（直接 JSON 序列化）
##   - 装备时通过 [method dicts_to_modifiers] 还原为 AttributeModifier
##   - 不放回抽样：同一池内候选词条不会被重复抽到
##   - 池子条数 < count 时只抽到那么多就停（不报错）
class_name AffixRoller
extends RefCounted

const STAT_KEY_AFFIX_MODS: StringName = &"affix_mods"


## 从 plan_id 加权抽 count 条 → 输出 Array[Dictionary]。
##
## count <= 0 / plan_id <= 0 时返回空数组。
## plan_id 找不到 → assert 崩（R-CODE-01）。
static func roll_to_dicts(plan_id: int, count: int) -> Array:
	if count <= 0 or plan_id <= 0:
		return []
	var plan: Dictionary = ConfigCenter.get_affix_plan(plan_id)
	assert(not plan.is_empty(), "AffixRoller: plan_id=%d not found" % plan_id)
	var pool: Array = (plan.get("sub_entries", []) as Array).duplicate()
	if pool.is_empty():
		return []

	var picked: Array = []
	for i in count:
		if pool.is_empty():
			break
		var total: int = 0
		for e in pool:
			total += CsvLoader.as_int(e, "Weight", 1)
		if total <= 0:
			# 所有 weight=0 → 退化为均匀抽样第一条
			picked.append(pool[0])
			pool.remove_at(0)
			continue
		var roll_val: int = randi() % total
		var acc: int = 0
		for j in pool.size():
			acc += CsvLoader.as_int(pool[j], "Weight", 1)
			if roll_val < acc:
				picked.append(pool[j])
				pool.remove_at(j)
				break

	# 转纯 Dict 数组（去掉 CSV 元字段，只留逻辑字段）
	var out: Array = []
	for p in picked:
		out.append({
			"attribute": CsvLoader.as_string(p, "Attr_Type", ""),
			"op":        CsvLoader.as_string(p, "Op", "add"),
			"magnitude": CsvLoader.as_float(p, "Val", 0.0),
		})
	return out


## 把存档/滚字结果的 dict 数组还原为 [AttributeModifier] 数组（装备时用）。
static func dicts_to_modifiers(dicts: Array) -> Array[AttributeModifier]:
	var mods: Array[AttributeModifier] = []
	for d in dicts:
		var m := AttributeModifier.new()
		m.attribute = StringName(d.get("attribute", ""))
		m.op = _parse_op(String(d.get("op", "add")))
		m.magnitude = float(d.get("magnitude", 0.0))
		mods.append(m)
	return mods


static func _parse_op(s: String) -> AttributeModifier.Op:
	match s.to_lower():
		"add":      return AttributeModifier.Op.ADD
		"multiply": return AttributeModifier.Op.MULTIPLY
		"override": return AttributeModifier.Op.OVERRIDE
	push_warning("AffixRoller: unknown op '%s', fallback to ADD" % s)
	return AttributeModifier.Op.ADD
