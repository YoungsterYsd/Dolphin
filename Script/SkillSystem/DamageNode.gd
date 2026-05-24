@tool
## 伤害节点定义。
##
## 一个技能可有多个伤害节点（连招分段），由 [SkillTimeline] 的 HITBOX_ENABLE 关键帧
## 通过 `damage_node_index` 字段引用。命中时由 [HitDamageResolver] 把
## [member damage_multiplier] 透传给 [DamagePipeline] 当 base_damage。
##
## 伤害公式起点（[DamagePipeline] 第 0 步）：
##   dmg = max(attacker.attack_final, 1) × damage_multiplier
## 后续 13 步管线再叠加暴击/防穿/承伤率/格挡/吸血/破韧 等。
##
## 后续可扩展暴击/护甲减免，扩展点放 [DamagePipeline] / [HitDamageResolver]。
class_name DamageNode
extends Resource

## 技能倍率（基于施法者 attack_final）。普攻 1.0；大招可 1.5 / 2.0 / 3.0 等。
##
## ⚠️ 这是技能配置的核心数值，不要写死系数。
@export var damage_multiplier: float = 1.0

## 伤害类型 tag，与 R-GAS-01 注册表中的 `damage.type.*` 对齐。
@export var damage_type: StringName = &"damage.type.physical"

## 命中时附加给目标的 GE 列表（如减速 / 流血 / 灼烧）。
## 主伤害单独走（不通过此列表），主伤害的 INSTANT GE 由 Resolver 在运行时按公式生成。
@export var apply_effects: Array[GameplayEffect] = []

## 削韧值（Poise Damage）。
##
## 命中时通过 [DamagePipeline] 调用 [method EnemyCharacter.apply_poise_damage] 削减目标韧性。
## 玩家 [code]poise_max[/code] 默认 100，普攻 [code]poise_damage = 10[/code] → 10 次普攻破韧。
##
## 0 = 不削韧；> 0 = 启用削韧并覆盖默认 [code]break_base_ratio[/code] 兜底公式。
##
## 受 [code]break_bonus[/code] 攻击方加成（PrimaryAttributeSet）和完美格挡 buff 影响。
@export var poise_damage: float = 10.0

## 命中冲击硬度等级（独立于 [member poise_damage] 的"打断"维度）。
##
## - [code]-1[/code]（默认） = 未配置 → [InterruptResolver] 走 [PoiseImpactTable]
##   按"本下伤害 / target.max_health"反查 Dmg_Hardness 表得出冲击等级；
## - [code]>= 0[/code] = 直接采用本字段作为冲击等级。
##
## 与目标 [method AbilitySystemComponent.get_current_poise_level] 比较：
## [code]hit_poise > target_current_poise[/code] → 打断目标当前 GA + 播 HitReact。
##
## 用例：
## - 普攻末段想"必定打断"：填 6
## - 重击想保证"压制低硬度技能"：填 3~4
## - Boss 强攻击想"打断玩家任何 GA"：填 6
@export var hit_poise: int = -1
