## 任务表 Loader（CSV 数据驱动）。
##
## 加载 [code]Data/FromExcel/Quest_Data.csv[/code]（聚合模式：同 quest_id 多 sub_id = 链式串行步骤）。
##
## CSV 表结构：
## [codeblock]
## id (quest_id), sub_id (step), Name, Desc, Kind, ID, Num, Drop_Rule_ID, Deliver_Dialogue_ID
## [/codeblock]
## - [code]Kind[/code]：[code]Item[/code] / [code]Monster[/code] / [code]NPC[/code] / [code]Tricky[/code]
## - [code]ID[/code]：目标 ID（item_id / monster_id / npc_id / tricky_id）
## - [code]Num[/code]：所需数量（NPC 类型一般 1）
## - [code]Drop_Rule_ID[/code]：完成本步骤的奖励 → [code]Drop_Rule.id[/code]，复用 [LootSpawner.dispatch]
## - [code]Deliver_Dialogue_ID[/code]：交付对话 graph_id；0=目标达成立即完成；非 0=必须走完该对话才完成
##
## 设计要点：
##   - SRP：仅加载 + 索引 + 提供查询 API；不做状态机推进（由 QuestSystem 做）
##   - 与 [LootTableLoader] 同模式
##   - 失败语义（R-CODE-01）：CSV 缺失 → CsvLoader assert 崩
class_name QuestLoader
extends RefCounted

const QUEST_CSV: String = "res://Data/FromExcel/Quest_Data.csv"

# int(quest_id) -> RowDict { id, ..., sub_entries: [{ sub_id, Name, Desc, Kind, ID, Num, Drop_Rule_ID, Deliver_Dialogue_ID }, ...] }
var _quests: Dictionary = {}


func load() -> void:
	_quests = CsvLoader.load_table(QUEST_CSV, true)
	GameLogger.info("Quest", "QuestLoader done: %d quest series loaded" % _quests.size())


## 取整张任务系列。找不到返回空 dict。
func get_quest(quest_id: int) -> Dictionary:
	return _quests.get(quest_id, {})


## 取任务系列的某一步。找不到返回空 dict。
func get_step(quest_id: int, sub_id: int) -> Dictionary:
	var quest: Dictionary = _quests.get(quest_id, {})
	if quest.is_empty():
		return {}
	for entry in (quest.get("sub_entries", []) as Array):
		if int(entry.get("sub_id", -1)) == sub_id:
			return entry
	return {}


## 任务系列是否存在该步骤。
func has_step(quest_id: int, sub_id: int) -> bool:
	return not get_step(quest_id, sub_id).is_empty()


## 取任务系列的全部步骤数（sub_entries 数量）。
func step_count(quest_id: int) -> int:
	var quest: Dictionary = _quests.get(quest_id, {})
	if quest.is_empty():
		return 0
	return (quest.get("sub_entries", []) as Array).size()


func quest_count() -> int:
	return _quests.size()


## 反查：哪个任务的某个 sub 的 Deliver_Dialogue_ID 等于此 graph_id。
##
## 用于 QuestSystem 收到 dialogue_ended 信号时反查应推进哪个任务步骤。
##
## 返回 Array[{ quest_id: int, sub_id: int }]（一段对话可能被多个任务复用）。
func find_steps_by_deliver_dialogue(graph_id: int) -> Array:
	var matches: Array = []
	if graph_id <= 0:
		return matches
	for quest_id in _quests.keys():
		var quest: Dictionary = _quests[quest_id]
		for entry in (quest.get("sub_entries", []) as Array):
			if int(entry.get("Deliver_Dialogue_ID", 0)) == graph_id:
				matches.append({"quest_id": int(quest_id), "sub_id": int(entry.get("sub_id", 0))})
	return matches
