## 头顶血条单体（M8 引入）。
##
## 由 [OverheadHealthBarManager] 创建并管理；外部不直接 new。
## 自绘 2D 矩形：背景 + 红色填充；每帧位置 = enemy 投影到屏幕的坐标 + y_offset。
class_name EnemyOverheadHealthBar
extends Control

const _ELITE_CATEGORY: StringName = &"elite"

var _enemy: Node = null  # CharacterBody2D / CharacterBody3D，需有 AbilitySystemComponent
var _asc: AbilitySystemComponent = null
var _cfg: HealthBarConfig = null
var _is_elite: bool = false

# 缓存的 HP 值（避免每帧查 ASC）
var _max_hp: float = 1.0
var _cur_hp: float = 1.0

# 满血自动隐藏计时
var _full_hp_seconds: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	visible = false


## 绑定到敌人。
func bind_to(enemy: Node, asc: AbilitySystemComponent, cfg: HealthBarConfig, is_elite: bool = false) -> void:
	_enemy = enemy
	_asc = asc
	_cfg = cfg
	_is_elite = is_elite
	custom_minimum_size = cfg.overhead_bar_size
	size = cfg.overhead_bar_size
	# 监听属性变化
	if EventBus.has_signal(&"attribute_changed"):
		EventBus.attribute_changed.connect(_on_attribute_changed)
	# 监听敌人死亡：自动隐藏（Manager 还会 queue_free 本节点）
	if EventBus.has_signal(&"enemy_died"):
		EventBus.enemy_died.connect(_on_enemy_died)
	# 初始 HP
	if asc != null and asc.attribute_set != null:
		_max_hp = asc.attribute_set.get_attr(&"max_health")
		_cur_hp = asc.attribute_set.get_attr(&"health")
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		# 已被销毁 → 隐藏（Manager 会 free）
		visible = false
		return
	# 满血自动隐藏倒计时
	if _cfg != null and _cfg.overhead_auto_hide_when_full_seconds > 0.0:
		if _cur_hp >= _max_hp - 0.001:
			_full_hp_seconds += delta
			if _full_hp_seconds >= _cfg.overhead_auto_hide_when_full_seconds:
				visible = false
				return
		else:
			_full_hp_seconds = 0.0
	# 跟随敌人
	_update_position()
	queue_redraw()


func _update_position() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var world_pos: Variant = null
	if _enemy is Node2D:
		world_pos = (_enemy as Node2D).global_position
	elif _enemy is Node3D:
		world_pos = (_enemy as Node3D).global_position
	if world_pos == null:
		return
	var screen_pos: Vector2 = _project(world_pos, vp)
	if screen_pos == Vector2.INF:
		visible = false
		return
	# 显示距离过滤
	if _cfg != null and _cfg.overhead_show_distance > 0.0:
		var cam_dist: float = _distance_to_camera(world_pos)
		if cam_dist > _cfg.overhead_show_distance:
			visible = false
			return
		else:
			# 距离 OK：若 visible=false（之前被隐过且未死），重新打开
			if not visible and (_cur_hp < _max_hp - 0.001 or _cfg.overhead_auto_hide_when_full_seconds <= 0.0):
				visible = true
	# 应用位置：屏幕坐标 - 自身尺寸/2，y 加 offset
	var y_off: float = _cfg.overhead_y_offset if _cfg != null else -40.0
	position = screen_pos + Vector2(-size.x * 0.5, y_off)


func _draw() -> void:
	if _cfg == null:
		return
	var bar_size: Vector2 = size
	# 背景
	draw_rect(Rect2(Vector2.ZERO, bar_size), _cfg.overhead_bg_color, true)
	# 填充
	var fill_ratio: float = 0.0
	if _max_hp > 0.0:
		fill_ratio = clampf(_cur_hp / _max_hp, 0.0, 1.0)
	var fill_color: Color = _cfg.overhead_fill_color_elite if _is_elite else _cfg.overhead_fill_color
	draw_rect(Rect2(Vector2(1, 1), Vector2(bar_size.x - 2, bar_size.y - 2) * Vector2(fill_ratio, 1.0)), fill_color, true)


# ─────────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────────

func _on_attribute_changed(owner_node: Node, attr_name: StringName, _old: float, new: float) -> void:
	if owner_node != _enemy:
		return
	if attr_name == &"health":
		_cur_hp = new
	elif attr_name == &"max_health":
		_max_hp = new
	# 受伤后强制可见
	if _cur_hp < _max_hp - 0.001:
		visible = true
		_full_hp_seconds = 0.0
	queue_redraw()


func _on_enemy_died(enemy: Node) -> void:
	if enemy == _enemy:
		visible = false


# ─────────────────────────────────────────────────────────────
# 投影
# ─────────────────────────────────────────────────────────────

func _project(world_pos: Variant, vp: Viewport) -> Vector2:
	if world_pos is Vector2:
		var wp2: Vector2 = world_pos
		var cam2d: Camera2D = vp.get_camera_2d()
		if cam2d == null:
			return wp2
		var screen_center: Vector2 = Vector2(vp.get_visible_rect().size) * 0.5
		return screen_center + (wp2 - cam2d.global_position) * cam2d.zoom
	if world_pos is Vector3:
		var wp3: Vector3 = world_pos
		var cam3d: Camera3D = vp.get_camera_3d()
		if cam3d == null:
			return Vector2.INF
		# 摄像机背面剔除
		if cam3d.is_position_behind(wp3):
			return Vector2.INF
		return cam3d.unproject_position(wp3)
	return Vector2.INF


func _distance_to_camera(world_pos: Variant) -> float:
	var vp := get_viewport()
	if vp == null:
		return 0.0
	if world_pos is Vector2:
		var cam2d: Camera2D = vp.get_camera_2d()
		if cam2d == null:
			return 0.0
		return (world_pos as Vector2).distance_to(cam2d.global_position)
	if world_pos is Vector3:
		var cam3d: Camera3D = vp.get_camera_3d()
		if cam3d == null:
			return 0.0
		return (world_pos as Vector3).distance_to(cam3d.global_position)
	return 0.0
