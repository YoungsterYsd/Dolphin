## 道具定义（Resource，运行时只读模板）。
##
## Fragment 组合式物品定义：[member fragments] 数组承载所有具体能力。
## 主表通用字段：item_id / display_name / description / icon_path / consumable。
##
## **不直接存** rarity / max_stack —— 这些由 Fragment_Quality / Fragment_Stackable 承载，
## 主表 CSV 字段在 Loader 期会自动构造对应 Fragment 加入数组（单一真相源）。
##
## 业务侧通过 [method find_fragment] / [method has_fragment] 查询能力。
class_name ItemDefinition
extends Resource

@export var item_id: int = 0
@export var display_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var consumable: bool = false  ## use() 后是否扣 1 个堆叠（通用 flag）

## 该物品挂载的 Fragment 清单（组合式能力声明）。
@export var fragments: Array[ItemFragment] = []


# ─────────────────────────────────────────────────────────────
# Fragment 查询（业务侧主入口）
# ─────────────────────────────────────────────────────────────


## 查询某类型 Fragment（核心 API，对标 Lyra FindFragmentByClass<T>）。
##
## 用法：
## [codeblock]
## var equip := def.find_fragment(Fragment_Equip) as Fragment_Equip
## if equip != null:
##     ...
## [/codeblock]
func find_fragment(fragment_type: GDScript) -> ItemFragment:
	for f in fragments:
		if is_instance_of(f, fragment_type):
			return f
	return null


## 是否含某类型 Fragment。
func has_fragment(fragment_type: GDScript) -> bool:
	return find_fragment(fragment_type) != null


# ─────────────────────────────────────────────────────────────
# 兼容字段读取（rarity / max_stack 从 Fragment 取）
# ─────────────────────────────────────────────────────────────


## 取最大堆叠数（从 Fragment_Stackable 读，无则返回 1）。
func get_max_stack() -> int:
	for f in fragments:
		if f is Fragment_Stackable:
			return (f as Fragment_Stackable).initial_count
	return 1


## 取品质（从 Fragment_Quality 读，无则返回 0=无品质显示）。
func get_rarity() -> int:
	for f in fragments:
		if f is Fragment_Quality:
			return (f as Fragment_Quality).rarity
	return 0


# ─────────────────────────────────────────────────────────────
# 显示
# ─────────────────────────────────────────────────────────────


func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return "Item_%d" % item_id
