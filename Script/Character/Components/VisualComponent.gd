## 角色视觉组件（HD-2D / 3D Sprite Billboard 路径）。
##
## 统一负责：
##   1. 在父节点子树中定位视觉节点（[SpriteBase3D] 或 [AnimatedSprite3D]）
##   2. 按 [code]sprite_ground_offset[/code] 应用脚位 Y 偏移
##   3. 根据 [MoveComponent] 速度做水平翻转（朝向）
##   4. 根据速度切换 idle/run 动画（通过 [AnimationComponent]）
##
## 这样 [BaseCharacter] / [PlayerCharacter] / [EnemyCharacter] 不再需要持有 _sprite_3d / _resolve_sprite。
##
## R-CHAR-01：对外 API 平台无关。
## R-CHAR-02：仅 3D 视觉路径，不再兼容 [AnimatedSprite2D] / [Sprite2D]。
class_name VisualComponent
extends Node


## SpriteBase3D 的 Y 偏移（米），让 sprite 底边贴在角色根坐标 Y=0（脚位）。
## 计算公式：(单帧像素高度 × pixel_size) / 2。例：32px × 0.025 → 0.4。
## < 0 表示跳过自动应用，沿用场景里手填的 sprite.position.y。
@export_range(-1.0, 5.0, 0.005) var sprite_ground_offset: float = -1.0:
	set(v):
		sprite_ground_offset = v
		_apply_sprite_ground_offset()

## 静止判定阈值（米/秒）：水平速度 abs(vx) 低于此值不翻转。
@export var still_threshold_speed: float = 0.05

## 移动判定阈值（米/秒）：合速度高于此值视为 running。
@export var run_threshold_speed: float = 0.1

## 是否按移动方向翻转 sprite（默认开）。
@export var auto_flip_facing: bool = true

## 是否按速度切换 idle/run 动画（默认开）。
@export var auto_switch_idle_run: bool = true

## idle / run 动画名（可在 Inspector 改）。
@export var idle_anim: StringName = &"idle"
@export var run_anim: StringName = &"run"


# 缓存的视觉节点（仅 SpriteBase3D 路径）
var _sprite: SpriteBase3D = null

# 缓存的同级组件
var _move_comp: MoveComponent = null
var _anim_comp: AnimationComponent = null


func _ready() -> void:
	_sprite = NodeFinder.find_first_of_type(get_parent(), SpriteBase3D) as SpriteBase3D
	_move_comp = NodeFinder.find_first_child_of_type(get_parent(), MoveComponent) as MoveComponent
	_anim_comp = NodeFinder.find_first_child_of_type(get_parent(), AnimationComponent) as AnimationComponent
	_apply_sprite_ground_offset()


func _physics_process(_delta: float) -> void:
	if _move_comp == null:
		return
	var v: Vector3 = _move_comp.get_velocity()
	if auto_flip_facing:
		_update_facing(v)
	if auto_switch_idle_run:
		_update_anim(v)


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 取视觉节点（已缓存）。
func get_sprite() -> SpriteBase3D:
	return _sprite


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _apply_sprite_ground_offset() -> void:
	if sprite_ground_offset < 0.0:
		return
	if _sprite == null:
		# _ready 之前 setter 被调用时 _sprite 还是 null，这里直接跳过；_ready 会再调一次
		return
	var p := _sprite.position
	if absf(p.y - sprite_ground_offset) < 0.0001:
		return
	p.y = sprite_ground_offset
	_sprite.position = p


func _update_facing(v: Vector3) -> void:
	if _sprite == null:
		return
	if absf(v.x) < still_threshold_speed:
		return
	_sprite.flip_h = v.x < 0.0


func _update_anim(v: Vector3) -> void:
	if _anim_comp == null:
		return
	if v.length() > run_threshold_speed:
		_anim_comp.play(run_anim)
	else:
		_anim_comp.play(idle_anim)
