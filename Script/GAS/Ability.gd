## Ability 资源基类。
##
## 子类重写 [method _activate]（必须）/ [method _can_activate_extra]（可选）/ [method _end]（可选）。
## ASC 通过 [method try_activate] 驱动整个生命周期：
##   1. CD / Cost / Tag 通用拦截（不需子类参与）
##   2. [method _can_activate_extra]（子类自定义条件）
##   3. push activation_tags
##   4. apply cost_effect
##   5. start cooldown
##   6. [method _activate] （子类做实际效果）
##   7. （子类）调用 [method finish]（或 ASC 自动 end_ability）→ pop tags、emit ended
class_name Ability
extends Resource

@export var ability_id: StringName = &""

## 消耗效果（一般是减蓝/减子弹的 INSTANT GE）。可选。
@export var cost_effect: GameplayEffect = null

## 冷却时间（秒）。0 或负数表示无 CD。
@export var cooldown: float = 0.0

## 激活前必须持有的 tag（按父匹配）。
@export var tags_required: Array[StringName] = []

## 激活前不能持有的 tag（按父匹配）。
@export var tags_blocked: Array[StringName] = []

## 激活期间附加到 ASC 的 tag。end 时自动移除。
@export var activation_tags: Array[StringName] = []

## 调试显示名。
@export var display_name: String = ""


func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return String(ability_id)


# ─────────────────────────────────────────────────────────────
# 子类钩子（可选重写）
# ─────────────────────────────────────────────────────────────

## 子类自定义"是否可激活"的额外条件（CD/Cost/Tag 已由 ASC 检查，这里只判额外）。
func _can_activate_extra(_asc: Node) -> bool:
	return true


## 子类实现激活逻辑。激活完成后必须调用 [method finish]，
## 否则 ASC 不会 pop activation_tags 也不会 emit ended。
##
## 示例（瞬发）：
##   [code]
##   func _activate(asc):
##       asc.apply_effect_to(target_asc, damage_ge, asc.owner)
##       finish(asc)
##   [/code]
func _activate(_asc: Node) -> void:
	GameLogger.warn("GAS", "Ability._activate not overridden: %s" % ability_id)


## 子类清理钩子（可选）。在 finish 之后由 ASC 调用。
func _end(_asc: Node) -> void:
	pass


## 子类在效果完成时调用。会回到 ASC 走结束流程。
func finish(asc: Node) -> void:
	asc.end_ability(ability_id)
