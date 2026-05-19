## 一个角色类型的"属性成长表"。
##
## 内含若干 [AttributeGrowthEntry]（每个属性一条），通过 [AttributeResolver.resolve] 配合 level 解算成最终属性 dict。
##
## 命名：Data/Config/AttributeGrowthTables/Growth_<Type>.tres
class_name AttributeGrowthTable
extends Resource

## 表 id，用于 [ConfigCenter] 查找。建议 snake_case，如 &"growth_slime"。
@export var id: StringName = &""

## 该角色的成长属性集合。
@export var entries: Array[AttributeGrowthEntry] = []


## 取某个属性的 entry。找不到返回 null。
func get_entry(attribute_name: StringName) -> AttributeGrowthEntry:
	for e in entries:
		if e != null and e.attribute_name == attribute_name:
			return e
	return null
