## 道具定义基类（Resource）。
##
## 子类：
##   - ConsumableDefinition：可使用消耗品（药水）
##   - EquipmentDefinition：装备（武器/防具/饰品）
##
## 所有道具数据走 .tres，禁止脚本魔数（R-DATA-01）。
class_name ItemDefinition
extends Resource

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null
@export var max_stack: int = 1


func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return String(item_id)
