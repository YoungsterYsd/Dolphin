## 单个属性的成长定义（如 health 的初始值 + 各段每级增量）。
##
## 文档原文：{1级属性, x级限制, x级前每级增加属性, y级限制, x-y级区间每级增加属性}
## 抽象为：base_value（1 级初值） + segments[]（多段，每段含 breakpoint_level + per_level_delta）。
##
## 解算见 [AttributeResolver.resolve]。
class_name AttributeGrowthEntry
extends Resource

## 属性名（与 [CharacterAttributeSet] 的 @export 字段同名），如 &"health" / &"attack"。
@export var attribute_name: StringName = &""

## 1 级时的初始值。
@export var base_value: float = 0.0

## 成长分段列表，按 breakpoint_level 升序生效。
## 例：[{bp=5, +5}, {bp=10, +8}] 表示 1→5 每级 +5，6→10 每级 +8。
@export var segments: Array[GrowthSegment] = []
