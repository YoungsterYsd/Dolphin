@tool
## 动画轨道。
##
## 关键帧类型：[AnimationKeyframe]。
## 触发：由 [TimelinePlayer] 调 `caster.anim_comp.play(kf.anim_name)`。
##
## 一份 SkillTimeline 通常只有一条 AnimationTrack，但允许多条（多层动画混合，预留）。
class_name AnimationTrack
extends SkillTrack

@export var keyframes: Array[AnimationKeyframe] = []


func get_track_kind() -> StringName:
	return SkillTrack.KIND_ANIMATION


func get_keyframes() -> Array:
	return keyframes
