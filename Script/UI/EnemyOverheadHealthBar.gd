## 头顶血条单体。
##
## 由 [OverheadHealthBarManager] 创建并管理；外部不直接 new。
## 自绘 2D 矩形：背景 + 红色填充；每帧位置 = enemy 投影到屏幕的坐标 + y_offset。
##
## Phase 2：投影逻辑改用 [WorldProjector] 静态工具，便于复用。
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
	EventBus.attribute_changed.connect(_on_attribute_changed)
	# 监听敌人死亡：自动隐藏（Manager 还会 queue_free 本节点）
	EventBus.enemy_died.connect(_on_enemy_died)
	# 初始 HP（R-ASC 重构：用 ASC.get_attribute 跨 Set 查找替代 attribute_set 老接口）
	if asc != null:
		_max_hp = asc.get_attribute(&"max_health", 0.0)
		_cur_hp = asc.get_attribute(&"health", 0.0)
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
	if not (_enemy is Node2D or _enemy is Node3D):
		return
	var screen_pos: Vector2 = WorldProjector.project(_enemy, vp)
	if screen_pos == Vector2.INF:
		visible = false
		return
	# 显示距离过滤
	if _cfg != null and _cfg.overhead_show_distance > 0.0:
		var cam_dist: float = WorldProjector.distance_to_camera(_enemy, vp)
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


# 注：原 _project / _distance_to_camera 已抽到 WorldProjector 静态工具（Phase 2 P2-T3/T4）
