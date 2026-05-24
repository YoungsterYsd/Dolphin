## 技能时间轴播放器宿主（全局单例语义）。
##
## 用户决策 q6=A：挂在 [GameInstance] 子节点，对外通过 `GameInstance.skill_timeline_player` 访问；
## 不新增 Autoload，不破坏 R-ARCH-02 的白名单 6 个上限。
##
## 职责：
##   - 维护 [code]Array[ActiveTimeline][/code]，每物理帧推进 elapsed
##   - 触发到的关键帧分派给对应 TrackHandler
##   - 结束时 emit [signal EventBus.skill_timeline_ended]
##
## 支持多 caster 并发播放（玩家、敌人各自激活技能时互不干扰）。
class_name SkillTimelinePlayerHost
extends Node

# 当前所有活动播放
var _actives: Array[ActiveTimeline] = []
# 自增 handle_id（用于 stop / 区分同 caster 多次激活）
var _next_handle_id: int = 1


func _ready() -> void:
	# 暂停时也运行：HitStop 期间 Engine.time_scale=0，但 PROCESS_MODE_ALWAYS 仍接收
	# 实际此处保持默认 INHERIT 即可（PAUSED 时玩法停止），但 PlayerHost 走 _process（受 time_scale 影响）。
	# 暂留 INHERIT；后续如果发现 hit_stop 帧导致 timeline 也卡住可改为单独驱动。
	GameLogger.info("Skill", "SkillTimelinePlayerHost ready")


func _process(delta: float) -> void:
	if _actives.is_empty():
		return
	# 推进所有活动；finished 的收尾后从列表移除
	var finished_list: Array[ActiveTimeline] = []
	for active in _actives:
		if active == null:
			continue
		# 防御：caster 可能在动画/事件轨触发途中被 queue_free（例如敌人被打死）。
		# Godot 4 freed 后引用并非 null，需用 is_instance_valid 判定。
		# 一旦 caster 失效，立即标记 finished，让 _finalize 走清理流程，避免 _dispatch_keyframe 把
		# freed Object 当 Node 传给 TrackHandler.handle 触发 SCRIPT ERROR。
		if not is_instance_valid(active.caster):
			active.mark_terminated()
			finished_list.append(active)
			continue
		var to_fire: Array = active.advance(delta)
		for item in to_fire:
			_dispatch_keyframe(active, item)
		if active.finished:
			finished_list.append(active)

	for active in finished_list:
		_finalize(active)
		_actives.erase(active)


# ─────────────────────────────────────────────────────────────
# 公共 API
# ─────────────────────────────────────────────────────────────

## 播放一份时间轴。返回 handle_id；失败返回 0。
## caster 必填（一般为 BaseCharacter）；target 可选（瞄准型技能传入）。
func play(timeline: SkillTimeline, caster: Node, target: Node = null) -> int:
	if timeline == null:
		GameLogger.warn("Skill", "play: timeline is null")
		return 0
	if caster == null:
		GameLogger.warn("Skill", "play: caster is null")
		return 0

	var handle_id: int = _next_handle_id
	_next_handle_id += 1

	var active: ActiveTimeline = ActiveTimeline.new()
	active.init(timeline, caster, target, handle_id)
	_actives.append(active)

	GameLogger.info("Skill", "PLAY skill=%s caster=%s handle=%d duration=%.2fs kfs=%d" % [
		timeline.skill_id, caster.name, handle_id, timeline.duration, timeline.collect_sorted_keyframes().size()
	])
	EventBus.skill_timeline_started.emit(timeline.skill_id, caster, handle_id)
	return handle_id


## 主动停止某次播放（按 handle_id）。返回是否找到并停止。
## 停止时会立即关闭可能仍在 enabled 的 hitbox（防止悬挂）。
func stop(handle_id: int) -> bool:
	for i in range(_actives.size()):
		var a: ActiveTimeline = _actives[i]
		if a != null and a.handle_id == handle_id:
			_force_disable_hitbox_if_active(a)
			a.mark_terminated()
			_finalize(a)
			_actives.remove_at(i)
			return true
	return false


## 当前活动播放数（调试用）。
func get_active_count() -> int:
	return _actives.size()


# ─────────────────────────────────────────────────────────────
# 内部 - 分派
# ─────────────────────────────────────────────────────────────

func _dispatch_keyframe(active: ActiveTimeline, item: Dictionary) -> void:
	var kf: SkillKeyframe = item["kf"]
	var track: SkillTrack = item["track"]
	if track == null or kf == null:
		return
	# 二次防御：advance 期间到 dispatch 之间也有微小窗口可能让 caster 被 free。
	if not is_instance_valid(active.caster):
		return
	var kind: StringName = track.get_track_kind()
	if kind == SkillTrack.KIND_ANIMATION and kf is AnimationKeyframe:
		AnimationTrackHandler.handle(kf as AnimationKeyframe, active.caster)
	elif kind == SkillTrack.KIND_EVENT and kf is EventKeyframe:
		EventTrackHandler.handle(kf as EventKeyframe, active.caster, active.timeline.skill_id)
	else:
		GameLogger.warn("Skill", "Unknown track/keyframe combination: kind=%s kf=%s" % [kind, kf.get_class()])


func _finalize(active: ActiveTimeline) -> void:
	if active == null or active.timeline == null:
		return
	# 结束时若 hitbox 仍开着，强制关闭（防止时间轴写漏 disable）
	_force_disable_hitbox_if_active(active)
	var caster_name: String = active.caster.name if is_instance_valid(active.caster) else "?"
	GameLogger.info("Skill", "END skill=%s caster=%s handle=%d" % [
		active.timeline.skill_id, caster_name, active.handle_id
	])
	# 注意：caster 可能已 freed，但信号仍 emit 兼容下游订阅者（订阅者需自行 is_instance_valid）。
	EventBus.skill_timeline_ended.emit(active.timeline.skill_id, active.caster, active.handle_id)


func _force_disable_hitbox_if_active(active: ActiveTimeline) -> void:
	var caster: Node = active.caster
	if not is_instance_valid(caster):
		return
	if caster is BaseCharacter and (caster as BaseCharacter).hitbox != null:
		var hb: HitboxComponent = (caster as BaseCharacter).hitbox
		if hb.enabled:
			hb.enabled = false
	# 清理 meta
	for k in [EventTrackHandler.META_CURRENT_SKILL_ID, EventTrackHandler.META_DAMAGE_NODE_INDEX, EventTrackHandler.META_RESOLVED_TARGETS]:
		if caster.has_meta(k):
			caster.remove_meta(k)
