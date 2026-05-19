## 全局角色实例表（一份 .tres，全游戏共用）。
##
## 由 [ConfigCenter] 启动时加载；提供 [method get_by_id] 查询。
##
## 命名：Data/Config/CharacterInstances.tres
class_name CharacterInstanceTable
extends Resource

## 所有角色实例条目。
@export var entries: Array[CharacterInstanceEntry] = []


## 按 id 取条目，未找到返回 null。
func get_by_id(id: StringName) -> CharacterInstanceEntry:
	for e in entries:
		if e != null and e.id == id:
			return e
	return null


## 返回所有 id 列表（调试用）。
func get_all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in entries:
		if e != null:
			out.append(e.id)
	return out
