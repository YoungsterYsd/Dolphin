## 时间轴驱动技能（所有技能的统一基类）。
##
## 用户决策 q7=C：推翻 Ability_BasicAttack，所有技能改走本类 + SkillTimeline + SkillDamageTable 数据驱动。
##
## 工作流：
##   1. ASC.try_activate 通过 CD/Cost/Tag 通用拦截
##   2. _activate(asc)：从 ConfigCenter 取 [SkillTimeline]；调 GameInstance.skill_timeline_player.play(...)
##   3. 监听 EventBus.skill_timeline_ended（按 handle_id 匹配）→ asc.end_ability(ability_id)
##
## R-DATA-02：所有时序、伤害、表现参数走资源；本脚本无硬编码数值。
class_name Ability_TimelineDriven
extends Ability

## 该 Ability 关联的 SkillTimeline.skill_id（同时也是 SkillDamageTable 的查表 key）。
## 注意：与 [member ability_id] 是两个独立概念：
##   - ability_id：ASC 调度用（玩家按键 → try_activate(ability_id)）
##   - timeline_id：技能数据查询用（不同角色可共用 ability_id 但走不同 timeline）
@export var timeline_id: StringName = &""


func _activate(asc: Node) -> void:
	if asc == null:
		return
	var caster: Node = asc.get_parent()
	if caster == null:
		GameLogger.warn("GAS", "Ability_TimelineDriven: ASC has no parent (caster)")
		_safe_finish(asc)
		return

	# R-Core：ConfigCenter 走 class_name 强类型直访
	var timeline: SkillTimeline = ConfigCenter.get_skill_timeline(timeline_id)
	if timeline == null:
		GameLogger.warn("GAS", "Ability_TimelineDriven: timeline '%s' not found" % timeline_id)
		_safe_finish(asc)
		return

	# 取 GameInstance.skill_timeline_player（GameInstance 是 Autoload，直接走全局标识）
	if GameInstance.skill_timeline_player == null:
		GameLogger.warn("GAS", "Ability_TimelineDriven: GameInstance.skill_timeline_player missing")
		_safe_finish(asc)
		return

	# 取目标（兼容路径：caster.set_meta("ability_target")，AI 用）
	# 修复 R-FIX-01：先 has_meta 再 get_meta，避免 Godot 4.6 在 meta 不存在时 push_error。
	var target: Node = null
	if asc.has_meta(&"ability_target"):
		target = asc.get_meta(&"ability_target")

	# 启动播放
	var handle_id: int = GameInstance.skill_timeline_player.play(timeline, caster, target)
	if handle_id <= 0:
		GameLogger.warn("GAS", "Ability_TimelineDriven: play returned invalid handle for %s" % timeline_id)
		_safe_finish(asc)
		return

	# 监听该 handle 的结束事件 → 收尾
	# 修复 R-FIX-02：用 CONNECT_ONE_SHOT 让 Godot 在第一次触发后自动 disconnect，
	# 完全规避旧实现里"先建空 Callable 再赋值闭包"导致的 is_connected null 错误。
	# 注意：CONNECT_ONE_SHOT 即使 handle_id 不匹配也会 disconnect；但实际场景里 SkillTimelinePlayerHost
	# 一次只播放一个 handle，技能未结束新 cast 也走不到这里（被 ASC 的 activating tag 拦截），
	# 所以"不匹配"在当前架构下不会发生。
	var ability_id_local: StringName = ability_id
	var on_ended_cb := func(_ended_skill_id: StringName, _ended_caster: Node, ended_handle_id: int) -> void:
		if ended_handle_id != handle_id:
			# 理论不可达；保险：忽略不属于自己的 handle
			return
		# 清理 ability_target meta（has_meta 防御）
		if is_instance_valid(asc) and asc.has_meta(&"ability_target"):
			asc.remove_meta(&"ability_target")
		if is_instance_valid(asc) and asc.has_method(&"end_ability"):
			asc.call(&"end_ability", ability_id_local)
	EventBus.skill_timeline_ended.connect(on_ended_cb, CONNECT_ONE_SHOT)


# 兜底 finish：当意外失败（缺 timeline / GameInstance）时也要走 end_ability，否则 activation_tags 不会 pop。
func _safe_finish(asc: Node) -> void:
	if asc != null and asc.has_method(&"end_ability"):
		asc.call(&"end_ability", ability_id)
