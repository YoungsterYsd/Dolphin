## 动画组件（HD-2D / 3D Sprite Billboard 路径）。
##
## 在父节点子树中查找首个 [AnimatedSprite3D]，封装 [method play] / [method is_playing] /
## [signal animation_finished] 三个对外 API。
##
## R-CHAR-01：对外 API 平台无关。
## R-CHAR-02：仅 3D 路径，已删除 [AnimatedSprite2D] 兼容代码。
##
## 找不到 [AnimatedSprite3D] 时仅 warn，不报错（适用于 BossDemo 这种用 [MeshInstance3D] 占位的场景）。
class_name AnimationComponent
extends Node


## 动画播放完成（含一次性与循环切换）。
signal animation_finished(anim_name: StringName)

# 视觉节点（仅 3D 路径）
var _sprite: AnimatedSprite3D = null

## 当前播放的动画名（便于查询）。
var _current_anim: StringName = &""


func _ready() -> void:
	_sprite = NodeFinder.find_first_of_type(get_parent(), AnimatedSprite3D) as AnimatedSprite3D
	if _sprite != null:
		_sprite.animation_finished.connect(_on_animation_finished)
	else:
		# 占位类敌人（如 Boss_Demo 用 MeshInstance3D）允许找不到，仅 warn
		GameLogger.warn("Character", "AnimationComponent: no AnimatedSprite3D under %s" %
			(get_parent().name if get_parent() != null else "?"))


## 播放指定动画。重复播放同一动画会被忽略（除非 force=true）。
## 动画名不存在时静默跳过（[SpriteFrames] 没声明该动画 → 不播）。
func play(anim_name: StringName, force: bool = false) -> void:
	if _sprite == null:
		return
	if not force and _current_anim == anim_name and is_playing(anim_name):
		return
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation(anim_name):
		return
	_current_anim = anim_name
	_sprite.play(anim_name)


## 当前是否正在播放指定动画。
func is_playing(anim_name: StringName) -> bool:
	if _sprite == null:
		return false
	return _sprite.is_playing() and _sprite.animation == anim_name


## 停止当前动画。
func stop() -> void:
	if _sprite != null:
		_sprite.stop()
	_current_anim = &""


func _on_animation_finished() -> void:
	animation_finished.emit(_current_anim)
