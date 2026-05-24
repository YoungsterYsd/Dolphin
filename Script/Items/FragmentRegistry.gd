## Fragment 注册表（集中元数据）。
##
## 加新 Fragment 类型只需在 [method _build_registry] 加 1 行 + 写新 .gd 文件 + 加 1 张 Frag_<Kind>.csv。
## InventoryComponent / EquipmentComponent / Loader 永不修改（OCP）。
##
## 命名约定：Fragment 类型名（kind）= 子表名去 [code]Frag_[/code] 前缀，PascalCase。
##
## **实现细节**：Godot 4.6 const 不支持引用用户 GDScript 类（"isn't a constant expression"），
## 故用 static var + 延迟初始化（首次访问时构造一次，后续走缓存）。
class_name FragmentRegistry
extends RefCounted


## 缓存的注册表。首次访问 [method get_registry] 时构造。
static var _registry_cache: Array = []


## 构造注册表（首次访问触发）。
##
## 每项字段：
##   - kind:  StringName  → Excel Fragment 列里写的标识（如 &"Currency"）
##   - class: GDScript    → 对应 Fragment 子类
##   - csv:   String      → 对应子表 CSV 路径
static func _build_registry() -> Array:
	return [
		{"kind": &"Currency", "class": Fragment_Currency, "csv": "res://Data/FromExcel/Frag_Currency.csv"},
		{"kind": &"Equip",    "class": Fragment_Equip,    "csv": "res://Data/FromExcel/Frag_Equip.csv"},
		{"kind": &"GA",       "class": Fragment_GA,       "csv": "res://Data/FromExcel/Frag_GA.csv"},
		{"kind": &"GE",       "class": Fragment_GE,       "csv": "res://Data/FromExcel/Frag_GE.csv"},
		{"kind": &"Quest",    "class": Fragment_Quest,    "csv": "res://Data/FromExcel/Frag_Quest.csv"},
	]


## 取注册表（含缓存）。
static func get_registry() -> Array:
	if _registry_cache.is_empty():
		_registry_cache = _build_registry()
	return _registry_cache


## 按 kind 查找注册项。找不到返回空 dict。
static func get_entry(kind: StringName) -> Dictionary:
	for e in get_registry():
		if e["kind"] == kind:
			return e
	return {}


## 取所有子表 CSV 路径列表（用于 CsvTableSource.load_paths 一次性加载）。
static func get_all_csv_paths() -> Array[String]:
	var paths: Array[String] = []
	for e in get_registry():
		paths.append(e["csv"])
	return paths


## 按 kind 取 Fragment 子类（GDScript 元对象）。
static func get_class_for(kind: StringName) -> GDScript:
	var e := get_entry(kind)
	if e.is_empty():
		return null
	return e["class"]


## 按 kind 取子表 CSV 路径。
static func get_csv_path_for(kind: StringName) -> String:
	var e := get_entry(kind)
	if e.is_empty():
		return ""
	return e["csv"]
