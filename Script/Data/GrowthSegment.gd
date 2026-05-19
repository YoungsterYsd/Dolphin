## 属性成长曲线的一段区间。
##
## 表达："直到 [member breakpoint_level] 级为止，每级增量为 [member per_level_delta]"。
## 最后一段的 breakpoint_level 一般填一个很大的数（如 99999），表示开放上限。
##
## 注：本资源类无逻辑，仅作数据载体；由 [AttributeGrowthEntry] 解算时按顺序消费。
class_name GrowthSegment
extends Resource

## 本段结束等级（含）。例如 1-5 级走该段，breakpoint_level = 5。
@export var breakpoint_level: int = 5

## 本段每升一级的增量。例如 +5 HP/级。
@export var per_level_delta: float = 0.0
