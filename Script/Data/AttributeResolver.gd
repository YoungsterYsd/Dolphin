## 属性解算器：把 CSV 表行（Char_Attr / Monster_Attr）+ 等级 → 最终属性字典。
##
## ── 数据格式 ──
## 主属性表（Char_Attr / Monster_Attr）每一列代表一个属性：
##   - 数值字段（如 stamina_max / crit_chance）：直接是 Float
##   - 成长曲线字段（如 health_base / attack_base / armor_base）：5 元组 List(Float)
##     [code]{1级值, x前每级+, x断点, x-y每级+, y断点}[/code]
##     兼容 3 元组：[code]{1级值, x前每级+, x断点}[/code]（视为 y 段不再成长）
##
## 5 元组解算公式（level >= 1）：
##   - 1 级 → 1级值
##   - 2..x 级 → 1级值 + (level-1) * x前每级+
##   - x..y 级 → 1级值 + (x-1) * x前每级+ + (level-x) * x-y每级+
##   - y+ 级 → 不再成长（封顶到 y 级）
##
## ── 输出契约 ──
## 解算结果是 [code]Dictionary[StringName, float][/code]，跨多个 AttributeSet 路由写入 ASC。
## 调用方为 [AbilitySystemComponent.bootstrap_from_entity]：
##   - max_* 字段先写（让 clamp 上限就位）
##   - 上限有限制的属性会自动同步当前值（max_health → health；stamina_max → stamina_current）
##   - 找不到字段的属性静默丢弃（敌人无 PrimaryAttributeSet 是预期）
##   - 派生字段（_final）由各 AttributeSet.recompute_derived 计算，不在这里写
##
## 静态工具类，请勿 new。
class_name AttributeResolver
extends RefCounted


# ─────────────────────────────────────────────────────────────
# 字段名 → 取值方式映射
# ─────────────────────────────────────────────────────────────
# CSV 表里下列字段为成长曲线（List(Float) 五元组）；其余按 Float 取。
# 维护原则：与策划在 Excel 表头里使用 List(Float) 类型的字段保持一致。
const _GROWTH_LIST_FIELDS: Array[StringName] = [
	&"health_base", &"health_bonus",
	&"attack_base", &"attack_bonus",
	&"armor_base", &"armor_bonus",
	# 后续若新增曲线字段（如 stamina_max_base、heal_rate_base），加在这里即可
]


# ─────────────────────────────────────────────────────────────
# 单字段解算：5 元组 + 等级 → 最终值
# ─────────────────────────────────────────────────────────────


## 解算单条成长曲线在指定等级的最终值。
##
## [param tuple] 形如 [code][1级值, x前每级+, x断点, x-y每级+, y断点][/code]，
## 也允许 3 元组（视后两位为 0）。
static func resolve_growth(tuple: Array, level: int) -> float:
	if tuple.is_empty():
		return 0.0
	var base_v: float = float(tuple[0]) if tuple.size() >= 1 else 0.0
	if level <= 1:
		return base_v
	var per_x: float = float(tuple[1]) if tuple.size() >= 2 else 0.0
	var bp_x: int   = int(tuple[2])   if tuple.size() >= 3 else 0
	var per_y: float = float(tuple[3]) if tuple.size() >= 4 else 0.0
	var bp_y: int   = int(tuple[4])   if tuple.size() >= 5 else 0

	# 已升的级数 = level - 1
	var lv: int = level
	# 1..x 段（含 1 级到 x 级，跨度 = x - 1 级升级）
	var seg1_capacity: int = max(0, bp_x - 1)
	# x..y 段（跨度 = y - x 级升级）
	var seg2_capacity: int = max(0, bp_y - bp_x)

	var value: float = base_v
	# 段 1
	var levels_in_seg1: int = min(lv - 1, seg1_capacity)
	if levels_in_seg1 > 0:
		value += float(levels_in_seg1) * per_x
	var leftover: int = (lv - 1) - levels_in_seg1
	if leftover <= 0:
		return value
	# 段 2
	var levels_in_seg2: int = min(leftover, seg2_capacity)
	if levels_in_seg2 > 0:
		value += float(levels_in_seg2) * per_y
	# y 级以上不再成长（封顶；策划要求过 y 级不增长）
	return value


# ─────────────────────────────────────────────────────────────
# 整张 row 解算：CSV row dict + 等级 → 属性 dict
# ─────────────────────────────────────────────────────────────


## 把一行 attr 表（[code]Char_Attr[/code] / [code]Monster_Attr[/code]） + 等级
## 解算为 [code]Dictionary[StringName, float][/code]。
##
## 字段类型自动选择：
## - 字段名在 [_GROWTH_LIST_FIELDS] 中 → 用 [method as_list_float] 解析为 5 元组，再调
##   [method resolve_growth]
## - 否则视为 Float（直接 [method as_float]）
##
## 排除掉 id / sub_id / sub_entries 这些表元字段，只输出真正的属性。
static func resolve_row(row: Dictionary, level: int) -> Dictionary:
	var out: Dictionary = {}
	if row.is_empty():
		return out
	for k in row.keys():
		var key_str: String = String(k)
		if key_str == "id" or key_str == "sub_id" or key_str == "sub_entries":
			continue
		var attr_name: StringName = StringName(key_str)
		if attr_name in _GROWTH_LIST_FIELDS:
			var tuple: Array = CsvLoader.as_list_float(row, key_str)
			out[attr_name] = resolve_growth(tuple, level)
		else:
			out[attr_name] = CsvLoader.as_float(row, key_str, 0.0)
	return out


# ─────────────────────────────────────────────────────────────
# 把解算结果按多 AttributeSet 路由写入 ASC
# ─────────────────────────────────────────────────────────────


## 上限属性 → 当前值字段 映射。
## 把 max_* 写入后，自动把对应当前值字段（如有且 ASC 有该属性）拉满到上限。
##
## 设计来自用户决策（2026-05-23）：CSV 中没有当前值列；上限有限制的属性，
## 当前值需在初始化时同步到上限。
const _MAX_TO_CURRENT: Dictionary = {
	&"max_health":  &"health",
	&"stamina_max": &"stamina_current",
}


## 把解算结果按多 AttributeSet 路由写入 ASC。
##
## - 跨 HealthSet / PrimaryAttributeSet / CombatSet 路由（由 ASC.set_attribute 内部 find_set_with_attr）
## - 找不到字段的属性静默丢弃（敌人无 PrimaryAttributeSet 是预期）
## - 顺序：max_* → 当前值字段（同步到上限）→ 其它属性，确保 clamp 正确
## - 派生 _final 字段不在这里写（由各 AttributeSet.recompute_derived 计算）
##
## [param sync_max_to_current]：是否把当前值（health / stamina_current）拉满到新上限。
## - 初始化（bootstrap）：true，拉满
## - 升级时重算：false，由调用方按"保留比例"等策略自己处理
static func apply_to_asc(values: Dictionary, asc: AbilitySystemComponent,
		sync_max_to_current: bool = true) -> void:
	if asc == null or values.is_empty():
		return

	# 1) 先写 max_* / *_max 类上限字段
	var max_keys: Array = []
	for k in values.keys():
		var s: String = String(k)
		if s.begins_with("max_") or s.ends_with("_max"):
			max_keys.append(k)
	for mk in max_keys:
		if asc.has_attribute(mk):
			asc.set_attribute(mk, values[mk])

	# 2) 自动同步当前值（CSV 没显式列；初始化时拉满到上限）
	if sync_max_to_current:
		for max_attr in _MAX_TO_CURRENT.keys():
			if not values.has(max_attr):
				continue
			var cur_attr: StringName = _MAX_TO_CURRENT[max_attr]
			if asc.has_attribute(cur_attr):
				asc.set_attribute(cur_attr, values[max_attr])

	# 3) 写其它非上限、非派生字段
	for k in values.keys():
		var s2: String = String(k)
		if s2.begins_with("max_") or s2.ends_with("_max"):
			continue
		# 派生字段保护（兜底）：CSV 不应配 _final，但万一有也跳过
		if s2.ends_with("_final"):
			continue
		if asc.has_attribute(k):
			asc.set_attribute(k, values[k])
