@tool
## 轨道基类。
##
## 仅 2 类轨道：[AnimationTrack] / [EventTrack]。
## 子类持具体类型的关键帧数组。
class_name SkillTrack
extends Resource

# === 轨道类型常量（R-DATA-02：禁止散落字面量；任何派发处统一引用） ===
const KIND_ANIMATION: StringName = &"animation"
const KIND_EVENT: StringName = &"event"

## 轨道显示名（编辑器内显示）。
@export var track_name: String = ""

## 是否启用（关闭后 TimelinePlayer 跳过本轨）。
@export var enabled: bool = true


## 子类必须重写：返回轨道类型常量（[constant KIND_ANIMATION] / [constant KIND_EVENT]）。
func get_track_kind() -> StringName:
	GameLogger.error("Skill", "SkillTrack subclass must override get_track_kind()")
	return &""


## 子类必须重写：返回当前轨道的关键帧数组（基类引用，运行时按子类类型 cast）。
func get_keyframes() -> Array:
	GameLogger.error("Skill", "SkillTrack subclass must override get_keyframes()")
	return []
