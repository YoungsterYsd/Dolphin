@tool
## 动画关键帧。
##
## 触发时由 [TimelinePlayer] 调 `caster.anim_comp.play(anim_name)`，
## 实际播放委托 [AnimationComponent]（M9 切 3D 后 sprite_3d 子实现也兼容）。
class_name AnimationKeyframe
extends SkillKeyframe

## 动画名（由 [AnimatedSprite2D.SpriteFrames] 中 animation 列表查找）。
@export var anim_name: StringName = &""

## 是否循环（默认 false，技能动画一般 oneshot）。
@export var loop: bool = false
