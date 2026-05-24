## 品质 Fragment（隐式 —— 由 ItemConfigLoader 根据主表 Rarity ≥ 1 自动构造）。
##
## 用于 UI 染色（边框颜色 / Tooltip 标题色）。
## 当前只持品质等级；后续可扩展 tint_color 等字段。
class_name Fragment_Quality
extends ItemFragment

@export var rarity: int = 1


static func from_csv_row(_row: Dictionary, _source) -> ItemFragment:
	# Quality 是隐式 Fragment，由 ItemConfigLoader 直接 new 构造
	# 不通过 CSV 子表注册（无对应 Frag_Quality.csv）
	return null
