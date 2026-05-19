## 移动组件（2D 实现）。
##
## R-CHAR-01：对外 API 使用 Vector3（XY 表示平面方向，Z 暂忽略），
## 2D 内部投影到 [member CharacterBody2D.velocity]。3D 实现日后另起子类，接口一致。
class_name MoveComponent
extends Node

@export var max_speed: float = 200.0
@export var acceleration: float = 1600.0
@export var friction: float = 1600.0

## 父节点（必须为 [CharacterBody2D]）。
var _body: CharacterBody2D

## 当前归一化输入方向（Vector3.x/y 用作平面方向）。
var _input_dir: Vector3 = Vector3.ZERO


func _ready() -> void:
	var p := get_parent()
	if p is CharacterBody2D:
		_body = p
	else:
		GameLogger.error("Character", "MoveComponent expects parent CharacterBody2D, got %s" % p)


## 设置移动输入方向。dir 任意长度，内部会归一化。
## R-CHAR-01：保持 Vector3 接口，3D 接入时无需改外部调用方。
func set_input_dir(dir: Vector3) -> void:
	_input_dir = dir if dir == Vector3.ZERO else dir.normalized()


## 物理帧调用，由父节点的 _physics_process 转发。
func tick(delta: float) -> void:
	if _body == null:
		return
	var target_2d := Vector2(_input_dir.x, _input_dir.y) * max_speed
	if target_2d == Vector2.ZERO:
		_body.velocity = _body.velocity.move_toward(Vector2.ZERO, friction * delta)
	else:
		_body.velocity = _body.velocity.move_toward(target_2d, acceleration * delta)
	_body.move_and_slide()


## 当前速度（Vector3 形式，Z=0）。
func get_velocity() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	return Vector3(_body.velocity.x, _body.velocity.y, 0.0)
