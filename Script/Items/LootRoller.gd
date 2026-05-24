## 战利品掉落抽样工具（静态）。
##
## 输入：drop_table_id（→ Drop_Rule 子表）
## 输出：[code]Array[Dictionary][/code] 形如：
## [codeblock]
## [
##   {"item_id": 1, "count": 1},
##   {"item_id": 2, "count": 2},
## ]
## [/codeblock]
##
## **抽样语义**（与策划文档对齐）：
##   - 同一 drop_table_id 下两类 Type **都各自走一轮**，结果合并。
##   - **Weighted**：所有 Weighted 子行 = 一个加权池，按权重**抽 1 条**（不放回到下一次 dispatch）。
##     - 同 id 下若没有 Weighted 子行 → 跳过这一轮。
##   - **Random**：每条 Random 子行**独立判定**，[code]Weight / 10000[/code] 为命中概率（10000 = 100%）。
##     - 同 id 下若没有 Random 子行 → 跳过这一轮。
##   - **Item_Num**：
##     - 长度 1（如 [code]{3}[/code]）→ 固定 3 个。
##     - 长度 2（如 [code]{1,2}[/code]）→ [min, max] 闭区间整数。
##     - 长度 ≥ 3 → 取前 2 个（多余忽略）；长度 0 / 缺省 → 1 个。
##
## **失败语义**（R-CODE-01）：
##   - drop_table_id <= 0 → 返回空数组（业务层调用前可能用 0 表示"不掉落"）。
##   - drop_table_id 在表里找不到 → 返回空数组（已 warn）。
##   - 单行 Type 字段非法（不在 Weighted/Random）→ assert 崩。
##   - Item_ID <= 0 → assert 崩（配置错误）。
class_name LootRoller
extends RefCounted

const TYPE_WEIGHTED: StringName = &"Weighted"
const TYPE_RANDOM:   StringName = &"Random"

const RANDOM_DENOMINATOR: int = 10000  # Random 概率的分母（万分比）


## 跑一次掉落抽样，返回 [code][{item_id, count}, ...][/code]。
##
## 同 drop_table_id 内 Weighted（抽 1 条）+ Random（每条独立判定）的结果会合并。
static func roll(drop_table_id: int) -> Array:
	if drop_table_id <= 0:
		return []
	var table: Dictionary = ConfigCenter.get_drop_rule(drop_table_id)
	if table.is_empty():
		GameLogger.warn("Loot", "LootRoller.roll: drop_table_id=%d not found" % drop_table_id)
		return []
	var rules: Array = table.get("sub_entries", []) as Array
	if rules.is_empty():
		return []

	# 拆分两类规则（一次扫描即可）
	var weighted_pool: Array = []
	var random_rules: Array = []
	for r in rules:
		var t: StringName = CsvLoader.as_string_name(r, "Type")
		if t == TYPE_WEIGHTED:
			weighted_pool.append(r)
		elif t == TYPE_RANDOM:
			random_rules.append(r)
		else:
			assert(false, "LootRoller: bad Type '%s' at drop_table_id=%d sub_id=%s" % [
				t, drop_table_id, str(r.get("sub_id", "?"))])

	var out: Array = []

	# 第一轮：Weighted 池抽 1 条
	if not weighted_pool.is_empty():
		var picked: Dictionary = _pick_weighted(weighted_pool)
		if not picked.is_empty():
			out.append(_make_drop_entry(picked))

	# 第二轮：Random 每条独立判定
	for r in random_rules:
		if _hit_random(r):
			out.append(_make_drop_entry(r))

	return out


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────


## 加权抽样：按 Weight 字段从池子里抽 1 条；池空 / 总权重 ≤ 0 → 返回空 dict。
static func _pick_weighted(pool: Array) -> Dictionary:
	var total: int = 0
	for e in pool:
		total += maxi(0, CsvLoader.as_int(e, "Weight", 0))
	if total <= 0:
		return {}
	var roll_val: int = randi() % total
	var acc: int = 0
	for e in pool:
		acc += maxi(0, CsvLoader.as_int(e, "Weight", 0))
		if roll_val < acc:
			return e
	return pool[pool.size() - 1]  # 兜底（理论不可达）


## 万分比独立判定：randi() % 10000 < Weight。
static func _hit_random(rule: Dictionary) -> bool:
	var weight: int = CsvLoader.as_int(rule, "Weight", 0)
	if weight <= 0:
		return false
	if weight >= RANDOM_DENOMINATOR:
		return true  # 100% 命中
	return (randi() % RANDOM_DENOMINATOR) < weight


## 把规则行打包成 [code]{item_id, count}[/code]，count 由 Item_Num 范围解算。
static func _make_drop_entry(rule: Dictionary) -> Dictionary:
	var item_id: int = CsvLoader.as_int(rule, "Item_ID", 0)
	assert(item_id > 0,
		"LootRoller: bad Item_ID at sub_id=%s (must be > 0)" % str(rule.get("sub_id", "?")))
	var nums: Array = CsvLoader.as_list_int(rule, "Item_Num")
	var count: int = _resolve_count(nums)
	return {"item_id": item_id, "count": count}


## 解析 Item_Num 字段（长度 1 = 固定，长度 ≥ 2 取前两个 = [min, max] 闭区间）。
static func _resolve_count(nums: Array) -> int:
	if nums.is_empty():
		return 1
	if nums.size() == 1:
		return maxi(0, int(nums[0]))
	var lo: int = int(nums[0])
	var hi: int = int(nums[1])
	if lo > hi:
		var tmp: int = lo; lo = hi; hi = tmp
	if lo == hi:
		return maxi(0, lo)
	return lo + (randi() % (hi - lo + 1))
