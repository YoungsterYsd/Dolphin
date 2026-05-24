## 掉落表 Loader。
##
## 加载 [code]Data/FromExcel/Drop_Rule.csv[/code]（聚合模式：同 drop_table_id 多个子行 = 该掉落表的全部规则）。
##
## CSV 表结构（参见 [code]Tools/Excel/掉落表.xlsx[/code]）：
## [codeblock]
## id, sub_id, Type, Weight, Item_ID, Item_Num
## [/codeblock]
## - [code]id[/code]：掉落表主键（drop_table_id），怪物 / 任务通过这个 id 引用。
## - [code]sub_id[/code]：该表内每条规则的子 id。
## - [code]Type[/code]：[code]Weighted[/code] / [code]Random[/code]，详见 [LootRoller]。
## - [code]Weight[/code]：
##   - Weighted 子行：加权抽样的权重（同 id 下所有 Weighted 子行参与同一池子，抽 1 条）。
##   - Random 子行：万分比概率（每条独立判定，10000 = 100%）。
## - [code]Item_ID[/code]：道具主键（[Item_Data.id]）。
## - [code]Item_Num[/code]：[code]List(Int)[/code] 字面量；
##   - 长度 1（如 [code]{1}[/code]）→ 固定数量。
##   - 长度 2（如 [code]{1,2}[/code]）→ [min, max] 整数闭区间随机。
##
## 失败语义：CSV 缺失 → CsvLoader 内部 assert 崩（R-CODE-01）。
class_name LootTableLoader
extends RefCounted

const DROP_RULE_CSV: String = "res://Data/FromExcel/Drop_Rule.csv"

var _tables: Dictionary = {}  # int(drop_table_id) -> RowDict (含 sub_entries)


func load() -> void:
	if not FileAccess.file_exists(DROP_RULE_CSV):
		# 允许缺失（早期项目阶段没配掉落也能跑）；缺失时 dispatch 全部静默返回 0
		GameLogger.warn("Loot", "LootTableLoader: %s not found, drops disabled" % DROP_RULE_CSV)
		_tables = {}
		return
	_tables = CsvLoader.load_table(DROP_RULE_CSV, true)
	GameLogger.info("Loot", "LootTableLoader done: %d drop tables loaded" % _tables.size())


## 取整张子表（按 drop_table_id）。返回的 dict 含 [code]sub_entries[/code] 数组（每条规则一个子行）。
##
## 找不到时返回空 dict（[LootRoller] 自行处理"无配置"语义）。
func get_table(drop_table_id: int) -> Dictionary:
	return _tables.get(drop_table_id, {})


## 是否存在该 drop_table_id（含至少一条 sub_entries）。
func has_table(drop_table_id: int) -> bool:
	if not _tables.has(drop_table_id):
		return false
	var t: Dictionary = _tables[drop_table_id]
	return (t.get("sub_entries", []) as Array).size() > 0


func count() -> int:
	return _tables.size()
