## CombatSet。
##
## 命中输入 Set，玩家与敌人都挂。
## 仅 2 字段，作为 SetByCaller 的"中转管道"——调用方写入 base_damage / base_heal，
## 由 GE.modifier 通过 [code]magnitude_source = SET_BY_CALLER[/code] 在 [method AttributeModifier.apply_to]
## 时取出，最终落到 HealthSet.health_damage / health_healing 元属性。
class_name CombatSet
extends AttributeSet

## 本次命中的基础伤害值（DamagePipeline 注入；GE_DamageInstant 通过 SetByCaller 读取）。
@export var base_damage: float = 0.0

## 本次治疗量。
@export var base_heal: float = 0.0
