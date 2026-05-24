## 对话表 Loader（CSV 数据驱动）。
##
## 加载 [code]Data/FromExcel/Dialogue.csv[/code]（聚合模式：同 id 多 sub_id = 一段对话的多个节点）。
##
## CSV 表结构：
## [codeblock]
## id (graph_id), sub_id (node_id), Text, Branch_Text, Branch_ID, Branch_Cond
## [/codeblock]
## - [code]id[/code]：graph_id（DialogueGraph 主键）
## - [code]sub_id[/code]：节点 ID（graph 内唯一；sub_id=0 是工具的"主行"占位，无业务数据）
## - [code]Text[/code]：对话文本
## - [code]Branch_Text[/code]：[code]List(String)[/code]，选项文本
## - [code]Branch_ID[/code]：[code]List(Int)[/code]，选项跳转目标 sub_id
## - [code]Branch_Cond[/code]：[code]List(Int)[/code]，选项显示条件 cond_id（0=无条件）
##
## 节点流转规则：
##   - 无 Branch → 自动进 sub_id+1（无 sub_id+1 则结束）
##   - 有 Branch → 弹选项菜单
##
## 设计要点：
##   - SRP：仅加载 + 索引 + 提供查询 API；不构造 DialogueGraph（由 DialogueGraphLoader 做）
##   - 与 [LootTableLoader] 同模式
##   - 失败语义（R-CODE-01）：CSV 缺失 → CsvLoader assert 崩
class_name DialogueCsvLoader
extends RefCounted

const DIALOGUE_CSV: String = "res://Data/FromExcel/Dialogue.csv"

# int(graph_id) -> RowDict { id, ..., sub_entries: [{ sub_id, Text, Branch_Text, Branch_ID, Branch_Cond }, ...] }
var _graphs: Dictionary = {}


func load() -> void:
	_graphs = CsvLoader.load_table(DIALOGUE_CSV, true)
	GameLogger.info("Dialogue", "DialogueCsvLoader done: %d graphs loaded" % _graphs.size())


## 取整张 graph 的 RowDict。找不到返回空 dict。
func get_graph(graph_id: int) -> Dictionary:
	return _graphs.get(graph_id, {})


## 取 graph 的全部节点（sub_entries），按 sub_id 升序。
func get_nodes(graph_id: int) -> Array:
	var graph: Dictionary = _graphs.get(graph_id, {})
	if graph.is_empty():
		return []
	return graph.get("sub_entries", []) as Array


func has_graph(graph_id: int) -> bool:
	return _graphs.has(graph_id)


func count() -> int:
	return _graphs.size()
