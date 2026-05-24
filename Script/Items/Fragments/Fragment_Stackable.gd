## 堆叠 Fragment（隐式 —— 由 ItemConfigLoader 根据主表 Stack > 0 自动构造）。
##
## InventoryComponent._add_stackable 通过 def.get_max_stack() 读取本字段决定合并行为。
class_name Fragment_Stackable
extends ItemFragment

@export var initial_count: int = 1


static func from_csv_row(_row: Dictionary, _source) -> ItemFragment:
	# Stackable 是隐式 Fragment，由 ItemConfigLoader 直接 new 构造
	return null
