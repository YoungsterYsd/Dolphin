## 动画组件（2D/3D 抽象）。
##
## R-CHAR-01：对外 API（[method play] / [method is_playing] / [signal animation_finished]）保持平台无关。
## M1 仅实现 2D 分支：自动查找父节点下的 [AnimatedSprite2D]。
## 3D 实现将以子类形式接入（查找 [AnimationPlayer]），不改外部调用方。
class_name AnimationComponent
extends Node

## 动画播放完成（含一次性与循环切换）。
signal animation_finished(anim_name: StringName)

## 2D 动画节点引用（自动查找）。
var _sprite_2d: AnimatedSprite2D = null

## 当前播放的动画名（便于查询）。
var _current_anim: StringName = &""


func _ready() -> void:
	_sprite_2d = _find_animated_sprite_2d(get_parent())
	if _sprite_2d != null:
		_sprite_2d.animation_finished.connect(_on_2d_animation_finished)
	else:
		GameLogger.warn("Character", "AnimationComponent: no AnimatedSprite2D found under parent")


## 播放指定动画。重复播放同一动画会被忽略（除非 force=true）。
func play(anim_name: StringName, force: bool = false) -> void:
	if not force and _current_anim == anim_name and is_playing(anim_name):
		return
	_current_anim = anim_name
	if _sprite_2d != null:
		_sprite_2d.play(anim_name)


## 当前是否正在播放指定动画。
func is_playing(anim_name: StringName) -> bool:
	if _sprite_2d == null:
		return false
	return _sprite_2d.is_playing() and _sprite_2d.animation == anim_name


## 停止当前动画。
func stop() -> void:
	if _sprite_2d != null:
		_sprite_2d.stop()
	_current_anim = &""


func _on_2d_animation_finished() -> void:
	animation_finished.emit(_current_anim)


## 在 node 子树中查找首个 AnimatedSprite2D（深度优先）。
func _find_animated_sprite_2d(node: Node) -> AnimatedSprite2D:
	if node == null:
		return null
	for child in node.get_children():
		if child is AnimatedSprite2D:
			return child
		var found := _find_animated_sprite_2d(child)
		if found != null:
			return found
	return null
