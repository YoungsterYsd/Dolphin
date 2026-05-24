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

## 释放期抗打断硬度等级（0~6）。
##
## 受击时若 [code]attacker_hit_poise <= 该 GA 的 cast_poise[/code] 则**不被打断**；
## 否则 [InterruptResolver] 调 [method AbilitySystemComponent.cancel_active_abilities]
## 中止本 GA + 播 HitReact Timeline + 击退。
##
## 角色没有任一激活中 GA 时，回退到 [code]BaseCharacter.base_poise[/code]。
##
## 设计参考：
## - 0：普攻 / 走路状态等无抗性
## - 1~2：蓄力 / 重击中段
## - 3~4：Boss 大招 / 终结技
## - 5~6：霸体型释放（霸体 tag 也可用 Combat.SuperArmor 走 INT_MAX 路径）
@export var cast_poise: int = 0


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


# ─────────────────────────────────────────────────────────────
# AbilityTask 轻量钩子（不引入完整 Lyra Task 体系）
# ─────────────────────────────────────────────────────────────

## 子类可重写：每物理帧由 ASC 调用一次（仅在该 ability 处于激活期）。
## 用于"蓄力 / 持续判定 / 完美格挡 0.3s 窗口判定"等 SkillTimeline 表达不了的运行时逻辑。
##
## ⚠️ 设计要点：SkillTimeline + EventTrack 是首选；本钩子仅用于 Timeline 表达不了的 5% 死角。
## 不要在这里写"播动画 / 触发 hitbox"等表现层逻辑——那些走 Timeline。
##
## 激活期判定：ASC 持有 [code]ability.activating.<ability_id>[/code] tag 时即视为激活中。
func _tick(_asc: Node, _delta: float) -> void:
	pass


## 助手方法：等待 EventBus 信号或超时（基于 SceneTreeTimer + 一次性 connect/disconnect）。
##
## 用法：
## [codeblock]
## var data = await ability.wait_event(asc, EventBus.damage_dealt_v2, 2.0)
## if data == null:
##     # 超时
## else:
##     # data 为信号 emit 的第一个参数（如需多参数请自行写 connect 闭包）
## [/codeblock]
##
## 限制：仅支持单参数信号；多参数信号请自行 connect 闭包。
##
## - asc: AbilitySystemComponent 节点（用于 get_tree 创建 Timer）
## - sig: EventBus 上的 Signal 引用
## - timeout_sec: 超时秒数；超时返回 null
func wait_event(asc: Node, sig: Signal, timeout_sec: float) -> Variant:
	if asc == null or sig.is_null():
		return null
	var box := { "result": null, "fired": false }
	var on_sig: Callable
	on_sig = func(value):
		box.result = value
		box.fired = true
		if sig.is_connected(on_sig):
			sig.disconnect(on_sig)
	sig.connect(on_sig)

	var timer := asc.get_tree().create_timer(timeout_sec)
	await timer.timeout

	if not box.fired:
		# 超时未触发：清理 connection
		if sig.is_connected(on_sig):
			sig.disconnect(on_sig)
	return box.result
