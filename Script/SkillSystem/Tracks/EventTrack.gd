@tool
## 事件轨道。
##
## 关键帧类型：[EventKeyframe]，覆盖 8 种 Kind（参见 [SkillEventKind]）。
## 触发：由 [TimelinePlayer] 按 kind 分派（直管类内部处理；广播类 emit EventBus 信号）。
##
## 一份 SkillTimeline 可以有多条 EventTrack（如分组：sfx 一轨 / hitbox 一轨 / 表现一轨），
## 仅为编辑器组织方便，运行时所有事件按 time 合并触发。
class_name EventTrack
extends SkillTrack

@export var keyframes: Array[EventKeyframe] = []


func get_track_kind() -> StringName:
	return SkillTrack.KIND_EVENT


func get_keyframes() -> Array:
	return keyframes
