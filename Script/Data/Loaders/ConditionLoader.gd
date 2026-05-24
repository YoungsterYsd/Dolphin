## 触发条件 Loader（CSV 数据驱动）。
##
## 加载 [code]Data/FromExcel/Condition.csv[/code]（聚合模式：同 cond_id 多 sub_id = AND 组合）。
##
## CSV 表结构：
## [codeblock]
## id (cond_id), sub_id, Type, Param
## [/codeblock]
## - [code]Type[/code]：[code]Lev[/code] / [code]Quest_Ongoing[/code] / [code]Quest_Finished[/code] / [code]Quest_PendingDeliver[/code]
## - [code]Param[/code]：参数（Lev=等级阈值；Quest_*=quest_id）
## - 同 cond_id 多 sub_id = **AND** 组合（OR 通过另开一个 cond_id + 业务方处理）
##
## 设计要点：
##   - SRP：仅加载 + 索引 + 提供查询 API；不做求值（由 [ConditionEvaluator] 做）
##   - 与 [LootTableLoader] 同模式
##   - 失败语义（R-CODE-01）：CSV 缺失 → CsvLoader assert 崩
class_name ConditionLoader
extends RefCounted

const CONDITION_CSV: String = "res://Data/FromExcel/Condition.csv"

# int(cond_id) -> RowDict { id, ..., sub_entries: [{ sub_id, Type, Param }, ...] }
var _conditions: Dictionary = {}


func load() -> void:
	_conditions = CsvLoader.load_table(CONDITION_CSV, true)
	GameLogger.info("Condition", "ConditionLoader done: %d condition sets loaded" % _conditions.size())


## 取条件集合（sub_entries 数组）。找不到返回空 array（视为"无条件"，业务方按 true 处理）。
func get_set(cond_id: int) -> Array:
	if cond_id <= 0:
		return []
	var entry: Dictionary = _conditions.get(cond_id, {})
	if entry.is_empty():
		return []
	return entry.get("sub_entries", []) as Array


func has_set(cond_id: int) -> bool:
	return _conditions.has(cond_id)


func count() -> int:
	return _conditions.size()
