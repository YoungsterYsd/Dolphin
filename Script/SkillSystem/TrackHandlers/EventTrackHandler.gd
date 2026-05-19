## 事件轨道处理器（静态）。
##
## 按 [EventKeyframe.kind] 分派：
## - 直管类（HITBOX_ENABLE / HITBOX_DISABLE）：直接控制 caster 的 HitboxComponent，
##   并把 damage_node_index 存到 caster.set_meta(META_DAMAGE_NODE_INDEX) 供命中时读取
## - 广播类（其余 6 种）：emit 对应 EventBus 信号，由各 Manager 订阅处理
##
## 所有 caster.set_meta key 集中在本类常量，避免散落字符串字面量。
class_name EventTrackHandler
extends RefCounted

# === caster meta 常量（命中时由 HitDamageResolver 读取） ===
## 当前激活的 skill_id（用于 SkillDamageTable 查表）
const META_CURRENT_SKILL_ID: StringName = &"_skill_current_id"
## 当前 hitbox 应使用的伤害节点索引
const META_DAMAGE_NODE_INDEX: StringName = &"_skill_damage_node_index"
## 本次激活已命中目标列表（去重）
const META_RESOLVED_TARGETS: StringName = &"_skill_resolved_targets"

# === payload key 常量 ===
const KEY_NODE_PATH: StringName = &"node_path"
const KEY_DAMAGE_NODE_INDEX: StringName = &"damage_node_index"
const KEY_SFX_ID: StringName = &"sfx_id"
const KEY_VFX_ID: StringName = &"vfx_id"
const KEY_PROJECTILE_ID: StringName = &"projectile_id"
const KEY_INTENSITY: StringName = &"intensity"
const KEY_DURATION: StringName = &"duration"
const KEY_DURATION_MS: StringName = &"duration_ms"
const KEY_SIGNAL_NAME: StringName = &"signal_name"
const KEY_DATA: StringName = &"data"

# 默认 hitbox 节点路径（payload 未提供 node_path 时使用）
const DEFAULT_HITBOX_PATH: NodePath = ^"HitboxComponent"


## 处理一个事件关键帧。
## skill_id：用于直管类把 damage_node_index 与当前技能关联存到 caster meta。
static func handle(kf: EventKeyframe, caster: Node, skill_id: StringName) -> void:
	if kf == null or caster == null:
		return
	if not SkillEventKind.is_valid(kf.kind):
		GameLogger.warn("Skill", "EventTrack: invalid kind '%s'" % kf.kind)
		return

	match kf.kind:
		SkillEventKind.HITBOX_ENABLE:
			_handle_hitbox_enable(kf, caster, skill_id)
		SkillEventKind.HITBOX_DISABLE:
			_handle_hitbox_disable(kf, caster)
		SkillEventKind.SFX_PLAY:
			var sfx_id: StringName = kf.payload.get(KEY_SFX_ID, &"")
			EventBus.skill_event_sfx.emit(sfx_id, caster, kf.payload)
			GameLogger.info("Skill", "[%s] sfx_play %s" % [caster.name, sfx_id])
		SkillEventKind.VFX_SPAWN:
			var vfx_id: StringName = kf.payload.get(KEY_VFX_ID, &"")
			EventBus.skill_event_vfx.emit(vfx_id, caster, kf.payload)
			GameLogger.info("Skill", "[%s] vfx_spawn %s" % [caster.name, vfx_id])
		SkillEventKind.PROJECTILE_SPAWN:
			var pid: StringName = kf.payload.get(KEY_PROJECTILE_ID, &"")
			EventBus.skill_event_projectile.emit(pid, caster, kf.payload)
			GameLogger.info("Skill", "[%s] projectile_spawn %s" % [caster.name, pid])
		SkillEventKind.CAMERA_SHAKE:
			var intensity: float = float(kf.payload.get(KEY_INTENSITY, 0.0))
			var duration: float = float(kf.payload.get(KEY_DURATION, 0.0))
			EventBus.skill_event_camera_shake.emit(intensity, duration, caster)
			GameLogger.info("Skill", "[%s] camera_shake intensity=%.1f duration=%.2f" % [caster.name, intensity, duration])
		SkillEventKind.HIT_STOP:
			var duration_ms: float = float(kf.payload.get(KEY_DURATION_MS, 0.0))
			EventBus.skill_event_hit_stop.emit(duration_ms, caster)
			GameLogger.info("Skill", "[%s] hit_stop %.0fms" % [caster.name, duration_ms])
		SkillEventKind.CUSTOM_SIGNAL:
			var signal_name: StringName = kf.payload.get(KEY_SIGNAL_NAME, &"")
			var data: Dictionary = kf.payload.get(KEY_DATA, {})
			EventBus.skill_event_custom.emit(signal_name, caster, data)
			GameLogger.info("Skill", "[%s] custom_signal %s" % [caster.name, signal_name])


# ─────────────────────────────────────────────────────────────
# 内部 - 直管类处理
# ─────────────────────────────────────────────────────────────

static func _handle_hitbox_enable(kf: EventKeyframe, caster: Node, skill_id: StringName) -> void:
	var hitbox: HitboxComponent = _find_hitbox(kf, caster)
	if hitbox == null:
		return
	# 把"当前技能 + 伤害节点 index"存到 caster.set_meta，命中时由 HitDamageResolver 读取
	var damage_node_index: int = int(kf.payload.get(KEY_DAMAGE_NODE_INDEX, 0))
	caster.set_meta(META_CURRENT_SKILL_ID, skill_id)
	caster.set_meta(META_DAMAGE_NODE_INDEX, damage_node_index)
	caster.set_meta(META_RESOLVED_TARGETS, [])  # 重置去重表
	hitbox.enabled = true
	GameLogger.info("Skill", "[%s] hitbox_enable skill=%s damage_idx=%d" % [caster.name, skill_id, damage_node_index])


static func _handle_hitbox_disable(kf: EventKeyframe, caster: Node) -> void:
	var hitbox: HitboxComponent = _find_hitbox(kf, caster)
	if hitbox == null:
		return
	hitbox.enabled = false
	# 清理 meta
	if caster.has_meta(META_CURRENT_SKILL_ID):
		caster.remove_meta(META_CURRENT_SKILL_ID)
	if caster.has_meta(META_DAMAGE_NODE_INDEX):
		caster.remove_meta(META_DAMAGE_NODE_INDEX)
	if caster.has_meta(META_RESOLVED_TARGETS):
		caster.remove_meta(META_RESOLVED_TARGETS)
	GameLogger.info("Skill", "[%s] hitbox_disable" % caster.name)


static func _find_hitbox(kf: EventKeyframe, caster: Node) -> HitboxComponent:
	# 优先 BaseCharacter.hitbox 引用；否则按 payload.node_path 查
	if caster is BaseCharacter and (caster as BaseCharacter).hitbox != null:
		return (caster as BaseCharacter).hitbox
	var path: NodePath = kf.payload.get(KEY_NODE_PATH, DEFAULT_HITBOX_PATH)
	var node: Node = caster.get_node_or_null(path)
	if node is HitboxComponent:
		return node
	GameLogger.warn("Skill", "EventTrack hitbox: caster %s has no HitboxComponent at %s" % [caster.name, path])
	return null
