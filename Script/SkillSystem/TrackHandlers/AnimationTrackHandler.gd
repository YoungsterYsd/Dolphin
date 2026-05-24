## 动画轨道处理器（静态）。
##
## 收到 [AnimationKeyframe] 时调 caster 的 [AnimationComponent.play(name)]。
## 兼容 2D 与 3D：AnimationComponent 内部按 sprite 类型分支。
class_name AnimationTrackHandler
extends RefCounted


## 处理一个动画关键帧。
static func handle(kf: AnimationKeyframe, caster: Node) -> void:
	if kf == null or caster == null:
		return
	var anim_comp: Node = null
	if caster is BaseCharacter:
		anim_comp = (caster as BaseCharacter).anim_comp
	if anim_comp == null:
		# 兜底：按节点名查
		anim_comp = caster.get_node_or_null(^"AnimationComponent")
	if anim_comp == null:
		GameLogger.warn("Skill", "AnimationTrack: caster %s has no AnimationComponent" % caster.name)
		return
	if not anim_comp.has_method(&"play"):
		GameLogger.warn("Skill", "AnimationTrack: AnimationComponent has no play() method")
		return
	anim_comp.call(&"play", kf.anim_name)
	GameLogger.info("Skill", "[%s] anim play '%s'" % [caster.name, kf.anim_name])
