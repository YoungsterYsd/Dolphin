## NPC 配置 Loader（CSV 数据驱动）。
##
## 加载两张 CSV：
##   - [code]Data/FromExcel/NPC_Data.csv[/code]：NPC 元信息（Name / Diapack_ID / Scene / Talk_Show）
##   - [code]Data/FromExcel/NPC_Diapack.csv[/code]：对话包（每个 NPC 互动时弹出的选项菜单）
##
## CSV 表结构：
## [codeblock]
## # NPC_Data.csv （平铺，无 sub_entries）
## id, sub_id(空), Name, Diapack_ID, Scene, Talk_Show
##
## # NPC_Diapack.csv （聚合：同 id 多 sub_id = 一个对话包的多个选项）
## id, sub_id, Talk_Text, Dialogue_ID, Condition
## [/codeblock]
##
## 设计要点：
##   - SRP：仅加载 + 索引 + 提供查询 API；不做条件过滤、不打开对话
##   - 与 [LootTableLoader] 同模式（CsvLoader.load_table 聚合）
##   - 失败语义（R-CODE-01）：必备 CSV 缺失 → CsvLoader assert 崩
class_name NPCConfigLoader
extends RefCounted

const NPC_DATA_CSV: String = "res://Data/FromExcel/NPC_Data.csv"
const NPC_DIAPACK_CSV: String = "res://Data/FromExcel/NPC_Diapack.csv"

# int(npc_id) -> RowDict { id, Name, Diapack_ID, Scene, Talk_Show }
var _npc_data: Dictionary = {}

# int(diapack_id) -> RowDict（含 sub_entries: Array[Dictionary] 选项数组）
var _diapacks: Dictionary = {}


func load() -> void:
	_npc_data = CsvLoader.load_table(NPC_DATA_CSV, false)  # 平铺，无子项
	_diapacks = CsvLoader.load_table(NPC_DIAPACK_CSV, true)  # 聚合
	GameLogger.info("NPC", "NPCConfigLoader done: %d npcs, %d diapacks loaded" % [
		_npc_data.size(), _diapacks.size()])


## 取 NPC 元信息。找不到返回空 dict。
func get_npc(npc_id: int) -> Dictionary:
	return _npc_data.get(npc_id, {})


## 取对话包（含 sub_entries 选项数组）。找不到返回空 dict。
func get_diapack(diapack_id: int) -> Dictionary:
	return _diapacks.get(diapack_id, {})


## 取对话包的全部选项（sub_entries），按 sub_id 升序。
func get_diapack_entries(diapack_id: int) -> Array:
	var pack: Dictionary = _diapacks.get(diapack_id, {})
	if pack.is_empty():
		return []
	return pack.get("sub_entries", []) as Array


func npc_count() -> int:
	return _npc_data.size()


func diapack_count() -> int:
	return _diapacks.size()
