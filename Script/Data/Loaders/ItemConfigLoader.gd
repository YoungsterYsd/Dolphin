## 道具配置装配 Loader（薄装配层）。
##
## 启动期从 CSV 装配所有 [ItemDefinition]。流程：
##   1. 读 Item_Data.csv（主表）
##   2. 对每个 id：
##      - 写 def 通用字段（item_id / display_name / description / icon_path / consumable）
##      - 解析 Fragment 列 → 按 kind 调 [ItemFragmentFactory.build] 装配显式 Fragment
##      - 按主表 Stack > 0 自动构造 [Fragment_Stackable]（隐式）
##      - 按主表 Rarity > 0 自动构造 [Fragment_Quality]（隐式）
##
## 失败语义（R-CODE-01）：
##   - Item_Data.csv 缺失 / 格式错 → CsvLoader 内部 assert 崩
##   - Fragment 列里出现未注册 kind → ItemFragmentFactory assert 崩
class_name ItemConfigLoader
extends RefCounted

const ITEMS_CSV: String = "res://Data/FromExcel/Item_Data.csv"

var _defs: Dictionary = {}  # int(id) -> ItemDefinition


## 装配入口。需调用方先用 [CsvTableSource] 加载所有相关 CSV。
func load_from(source: CsvTableSource) -> void:
	assert(source.has_table(ITEMS_CSV),
		"ItemConfigLoader.load_from: %s not loaded" % ITEMS_CSV)
	var items: Dictionary = source.get_table(ITEMS_CSV)
	_defs.clear()
	for id_key in items.keys():
		var id: int = int(id_key)
		_defs[id] = _assemble_def(id, items[id_key], source)
	GameLogger.info("Items", "ItemConfigLoader done: %d items loaded" % _defs.size())


func get_by_id(id: int) -> ItemDefinition:
	return _defs.get(id, null)


func all() -> Dictionary:
	return _defs


func count() -> int:
	return _defs.size()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────


func _assemble_def(id: int, row: Dictionary, source: CsvTableSource) -> ItemDefinition:
	var def := ItemDefinition.new()
	def.item_id      = id
	def.display_name = CsvLoader.as_string(row, "Name", "")
	def.description  = CsvLoader.as_string(row, "Desc", "")
	def.icon_path    = CsvLoader.as_string(row, "Icon", "")
	def.consumable   = (CsvLoader.as_int(row, "Consumable", 0) == 1)

	# 显式 Fragment（Fragment 列）
	var kinds: Array = _parse_kind_list(CsvLoader.as_string(row, "Fragment", ""))
	for kind in kinds:
		var f: ItemFragment = ItemFragmentFactory.build(kind, id, source)
		if f != null:
			def.fragments.append(f)
		else:
			GameLogger.warn("Items", "Item %d declares Fragment '%s' but factory returned null (no row in subtable?)" % [id, kind])

	# 隐式 Fragment（按主表字段）
	var stack: int = CsvLoader.as_int(row, "Stack", 0)
	if stack > 0:
		var fs := Fragment_Stackable.new()
		fs.initial_count = stack
		def.fragments.append(fs)

	var rarity: int = CsvLoader.as_int(row, "Rarity", 0)
	if rarity > 0:
		var fq := Fragment_Quality.new()
		fq.rarity = rarity
		def.fragments.append(fq)

	return def


## 解析 "{Currency}" / "{Equip,GA,GE}" 为 Array[StringName]。空字符串 → 空数组。
static func _parse_kind_list(s: String) -> Array:
	var t: String = s.strip_edges()
	if t.is_empty():
		return []
	assert(t.begins_with("{") and t.ends_with("}"),
		"ItemConfigLoader._parse_kind_list: expected '{...}' format, got '%s'" % s)
	var inner: String = t.substr(1, t.length() - 2).strip_edges()
	if inner.is_empty():
		return []
	var parts: PackedStringArray = inner.split(",", false)
	var out: Array = []
	for p in parts:
		var trimmed: String = p.strip_edges()
		if not trimmed.is_empty():
			out.append(StringName(trimmed))
	return out
