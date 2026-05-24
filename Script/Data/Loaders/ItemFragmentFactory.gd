## Fragment 装配工厂（路由层）。
##
## 按 kind 路由到对应 Fragment 子类的 [method ItemFragment.from_csv_row] 静态工厂方法。
## 路由表来自 [FragmentRegistry]。
##
## 设计目标：
##   - SRP：把"kind → 类 → CSV 行"的路由逻辑集中在此，ItemConfigLoader 不必关心
##   - OCP：加新 Fragment 类型只动 FragmentRegistry，本类零修改
class_name ItemFragmentFactory
extends RefCounted


## 按 kind 路由到对应 Fragment 子类的 from_csv_row 工厂方法。
##
## [param kind]：FragmentRegistry 注册的 StringName（如 &"Currency"）
## [param item_id]：物品主键，用于反查子表对应行
## [param source]：CsvTableSource，提供已加载的子表
##
## 返回构造好的 ItemFragment（可能为 null：子表无对应行 / kind 注册但子类决定不构造）。
## kind 未注册 → assert 崩。
static func build(kind: StringName, item_id: int, source: CsvTableSource) -> ItemFragment:
	var entry: Dictionary = FragmentRegistry.get_entry(kind)
	assert(not entry.is_empty(),
		"ItemFragmentFactory.build: unknown Fragment kind '%s' (check FragmentRegistry.REGISTRY)" % kind)

	var cls: GDScript = entry["class"]
	var csv_path: String = entry["csv"]
	assert(source.has_table(csv_path),
		"ItemFragmentFactory.build: CSV not loaded: %s (forgot to load_paths?)" % csv_path)

	var row: Dictionary = source.get_table(csv_path).get(item_id, {})
	# row 为空也允许（子类决定是否构造，或返回 null）
	return cls.from_csv_row(row, source) as ItemFragment
