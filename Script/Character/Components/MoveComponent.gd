## 移动组件（3D，XZ 平面）。
##
## R-CHAR-01：对外 API 使用 Vector3。平面 = XZ（Godot 3D 业界标准 Y 轴向上）。
## input_dir.x → 世界 X 轴；input_dir.z → 世界 Z 轴（向前 = -z）。
class_name MoveComponent
extends Node

@export var max_speed: float = 5.0  # 米/秒
@export var acceleration: float = 40.0  # 米/秒²
@export var friction: float = 40.0

## 父节点（必须为 [CharacterBody3D]）。
var _body: CharacterBody3D = null

## 当前归一化输入方向（XZ 平面，Y=0）。
var _input_dir: Vector3 = Vector3.ZERO


func _ready() -> void:
	var p := get_parent()
	# 配置错误直接崩，便于定位
	assert(p is CharacterBody3D,
		"MoveComponent expects parent CharacterBody3D, got %s" % str(p))
	_body = p as CharacterBody3D


## 设置移动输入方向（仅 XZ 分量有效，Y 分量被忽略）。
## 非零向量自动归一化；零向量保持零。
func set_input_dir(dir: Vector3) -> void:
	var planar := Vector3(dir.x, 0.0, dir.z)
	_input_dir = planar if planar == Vector3.ZERO else planar.normalized()


## 物理帧调用，由父节点的 _physics_process 转发。
func tick(delta: float) -> void:
	if _body == null:
		return
	# 当前 velocity 仅看 XZ 分量（Y 分量保留给重力 / 跳跃，本里程碑 Y=0）
	var current: Vector3 = _body.velocity
	current.y = 0.0
	var target: Vector3 = _input_dir * max_speed
	var next: Vector3
	if target == Vector3.ZERO:
		next = current.move_toward(Vector3.ZERO, friction * delta)
	else:
		next = current.move_toward(target, acceleration * delta)
	_body.velocity = Vector3(next.x, 0.0, next.z)
	_body.move_and_slide()


## 当前速度（Vector3）。
func get_velocity() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	return _body.velocity
