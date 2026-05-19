@tool
## 关键帧基类。
##
## 所有具体关键帧（动画/事件）继承此类。仅持时间戳。
## 子类按轨道类型扩展字段（参见 [AnimationKeyframe] / [EventKeyframe]）。
##
## 时间单位：秒（相对于 SkillTimeline 起始）。
class_name SkillKeyframe
extends Resource

## 在时间轴上的触发时刻（秒），范围 [0, SkillTimeline.duration]。
@export var time: float = 0.0
