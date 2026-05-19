@tool
## 伤害节点定义。
##
## 一个技能可有多个伤害节点（连招分段），由 [SkillTimeline] 的 HITBOX_ENABLE 关键帧
## 通过 `damage_node_index` 字段引用。命中时由 [HitDamageResolver] 计算最终伤害。
##
## 最终伤害公式（M7 默认线性）：
##   final_damage = caster.attack * damage_multiplier + extra_flat_damage
##
## 后续可扩展暴击/护甲减免，扩展点放 [HitDamageResolver]。
class_name DamageNode
extends Resource

## 基于施法者 attack 的倍率（1.0 = 100%）。
@export var damage_multiplier: float = 1.0

## 额外固定伤害（不受 attack 影响）。
@export var extra_flat_damage: float = 0.0

## 伤害类型 tag，与 R-GAS-01 注册表中的 `damage.type.*` 对齐。
@export var damage_type: StringName = &"damage.type.physical"

## 命中时附加给目标的 GE 列表（如减速 / 流血 / 灼烧）。
## 主伤害单独走（不通过此列表），主伤害的 INSTANT GE 由 Resolver 在运行时按公式生成。
@export var apply_effects: Array[GameplayEffect] = []
