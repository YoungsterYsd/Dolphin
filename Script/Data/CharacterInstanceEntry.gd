## 一种角色实例的定义（如"史莱姆 1 级" / "Boss Demo 10 级"）。
##
## 由 [CharacterInstanceTable] 聚合；运行时通过 [ConfigCenter.get_character_def(id)] 查询。
##
## 字段对应文档原文：怪物 id / 类型 / 等级 / 名称 / 移动速度 / 怪物属性表索引。
class_name CharacterInstanceEntry
extends Resource

## 实例 id，全局唯一。如 &"slime_lv1" / &"slime_elite_lv5" / &"boss_demo_lv10"。
@export var id: StringName = &""

enum Category { NORMAL, ELITE, BOSS }

## 类别（普通 / 精英 / Boss），用于头顶血条样式选择。
@export var category: int = Category.NORMAL

## 默认等级。运行时如需指定不同等级，可在 spawn 时覆盖。
@export var level: int = 1

## 显示名（UI 用）。
@export var display_name: String = ""

## 移动速度（覆盖成长表的 move_speed，便于"同属性表不同移速"的变体）。
## 设为 < 0 表示沿用成长表里的 move_speed。
@export var move_speed_override: float = -1.0

## 关联的成长表 id（指向 [AttributeGrowthTable.id]）。
@export var growth_table_id: StringName = &""

## 该角色的场景资源（可选，预留给后续 Spawner 使用）。
@export var scene: PackedScene = null

## 起始授予的技能集（Ability .tres 数组）。预留给 M7。
@export var ability_set: Array[Resource] = []
