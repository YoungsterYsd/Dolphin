@tool
## 动画关键帧。
##
## 触发时由 [TimelinePlayer] 调 `caster.anim_comp.play(anim_name)`，
## 实际播放委托 [AnimationComponent]（兼容 sprite_3d / sprite_2d）。
class_name AnimationKeyframe
extends SkillKeyframe

## 动画名（由 [AnimatedSprite2D.SpriteFrames] 中 animation 列表查找）。
@export var anim_name: StringName = &""

## 是否循环（默认 false，技能动画一般 oneshot）。
@export var loop: bool = false

## 编辑器侧色条长度自动计算（依据 SpriteFrames.frames / fps）。
## 仅影响时间轴可视化（不参与运行时调度）。
@export var auto_length: bool = true

## 手动指定的色条长度（秒）。仅在 [member auto_length] = false 时生效。
@export var manual_length: float = 0.2
