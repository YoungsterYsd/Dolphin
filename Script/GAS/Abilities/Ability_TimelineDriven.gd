## 时间轴驱动技能（M7.3 起所有技能的统一基类）。
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

	# 从 ConfigCenter 取时间轴
	var cfg: Node = caster.get_tree().root.get_node_or_null(^"ConfigCenter")
	if cfg == null:
		GameLogger.warn("GAS", "Ability_TimelineDriven: ConfigCenter not found")
		_safe_finish(asc)
		return
	var timeline: SkillTimeline = cfg.get_skill_timeline(timeline_id)
	if timeline == null:
		GameLogger.warn("GAS", "Ability_TimelineDriven: timeline '%s' not found" % timeline_id)
		_safe_finish(asc)
		return

	# 取 GameInstance.skill_timeline_player
	var gi: Node = caster.get_tree().root.get_node_or_null(^"GameInstance")
	if gi == null or gi.skill_timeline_player == null:
		GameLogger.warn("GAS", "Ability_TimelineDriven: GameInstance.skill_timeline_player missing")
		_safe_finish(asc)
		return

	# 取目标（M2 兼容路径：set_meta("ability_target")，AI 用）
	var target: Node = asc.get_meta(&"ability_target", null)

	# 启动播放
	var handle_id: int = (gi.skill_timeline_player as SkillTimelinePlayerHost).play(timeline, caster, target)
	if handle_id <= 0:
		GameLogger.warn("GAS", "Ability_TimelineDriven: play returned invalid handle for %s" % timeline_id)
		_safe_finish(asc)
		return

	# 监听该 handle 的结束事件 → 收尾
	# 使用 Callable + bind，避免连接到全局会泄漏（一次性 disconnect）
	var on_ended_cb: Callable = Callable()
	on_ended_cb = func(ended_skill_id: StringName, ended_caster: Node, ended_handle_id: int) -> void:
		if ended_handle_id != handle_id:
			return
		if EventBus.skill_timeline_ended.is_connected(on_ended_cb):
			EventBus.skill_timeline_ended.disconnect(on_ended_cb)
		# 清理 ability_target meta
		if asc.has_meta(&"ability_target"):
			asc.remove_meta(&"ability_target")
		_safe_finish(asc)
	EventBus.skill_timeline_ended.connect(on_ended_cb)


# 兜底 finish：当意外失败（缺 timeline / GameInstance）时也要走 end_ability，否则 activation_tags 不会 pop。
func _safe_finish(asc: Node) -> void:
	if asc != null and asc.has_method(&"end_ability"):
		asc.call(&"end_ability", ability_id)
