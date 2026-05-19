## 装备定义。
##
## 装备时给持有者 ASC 应用一个 Duration=Infinite 的 GE（granted_tags + modifiers）；
## 卸下时移除该 GE。M5 实现：直接使用 modifiers 即时改属性，卸下时反向改回，
## 简化设计避免引入 infinite duration（GE 系统当前无 infinite 概念）。
class_name EquipmentDefinition
extends ItemDefinition

enum Slot {
	WEAPON,
	ARMOR,
	ACCESSORY,
}

@export var slot: Slot = Slot.WEAPON

## 装备时附加的属性增量（卸下时反向应用）。
@export var attribute_modifiers: Array[AttributeModifier] = []

## 装备时授予的 Ability（卸下时撤销）。
@export var granted_abilities: Array[Ability] = []
