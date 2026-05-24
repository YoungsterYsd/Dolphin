## 词条池配置 Loader。
##
## 加载 attr_plan.csv（聚合模式：同 plan_id 多个子行 = 词条池候选项）。
## 业务侧通过 [method get_plan] 取整个池子（dict，含 sub_entries 数组）。
##
## 失败语义：CSV 缺失 → CsvLoader 内部 assert 崩。
class_name AffixPlanLoader
extends RefCounted

const ATTR_PLAN_CSV: String = "res://Data/FromExcel/attr_plan.csv"

var _plans: Dictionary = {}  # int(plan_id) -> RowDict (含 sub_entries)


func load() -> void:
	_plans = CsvLoader.load_table(ATTR_PLAN_CSV, true)
	GameLogger.info("Items", "AffixPlanLoader done: %d plans loaded" % _plans.size())


## 取词条池（按 plan_id）。找不到返回空 dict（AffixRoller 自行 assert）。
func get_plan(plan_id: int) -> Dictionary:
	return _plans.get(plan_id, {})


func count() -> int:
	return _plans.size()
