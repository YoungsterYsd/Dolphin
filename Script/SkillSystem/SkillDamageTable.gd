@tool
## 全局技能伤害表（一份 .tres，全游戏共用，用户决策 q3=A）。
##
## 数据结构：`Dictionary[skill_id:StringName, Array[DamageNode]]`。
## 命中时：`get_node(skill_id, damage_node_index) -> DamageNode`。
##
## 命名：`Data/Config/SkillDamageTable.tres`。
##
## ⚠ Godot 4 的 @export Dictionary 不支持泛型，运行时仍是 Variant；
##    故约定 value 必须是 `Array[DamageNode]`，访问处做类型校验。
class_name SkillDamageTable
extends Resource

## 主表。Key=skill_id，Value=Array[DamageNode]。
## 在编辑器内手动配置，或通过工具脚本生成。
@export var table: Dictionary = {}


## 取某技能的全部伤害节点。返回空数组表示该技能未配置。
func get_damage_nodes(skill_id: StringName) -> Array:
	if not table.has(skill_id):
		return []
	var arr = table[skill_id]
	if not arr is Array:
		return []
	return arr


## 取某技能的第 N 个伤害节点。out-of-range 返回 null。
func get_node_at(skill_id: StringName, index: int) -> DamageNode:
	var arr := get_damage_nodes(skill_id)
	if index < 0 or index >= arr.size():
		return null
	var n = arr[index]
	if n is DamageNode:
		return n
	return null


## 返回所有 skill_id 列表（调试用）。
func get_all_skill_ids() -> Array:
	return table.keys()
