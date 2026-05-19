## 伤害飘字池（M8 引入）。
##
## 挂在 HUD 根 Control 下；订阅 [signal EventBus.damage_dealt_v2] 自动显示飘字。
## 池化避免每次 instantiate 的内存分配；不足时按需 grow×2。
##
## 屏幕坐标投影：
##   - 2D 场景：找当前激活 Camera2D（get_viewport().get_camera_2d()），用 unproject_position 把
##     target.global_position 转屏幕坐标。
##   - 3D 场景（M9）：找 Camera3D，用 unproject_position（API 名称一致）。
##
## R-DATA-02：所有视觉参数取自 HitFeedbackConfig；不硬编码。
class_name DamagePopupPool
extends Control

# === 池 ===
var _pool: Array[DamagePopup] = []
var _busy: Array[DamagePopup] = []  # 仅用于统计

# 缓存 config
var _cfg: HitFeedbackConfig = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pull_config()
	_build_pool()
	# 监听伤害事件
	if EventBus.has_signal(&"damage_dealt_v2"):
		EventBus.damage_dealt_v2.connect(_on_damage_dealt_v2)


# ─────────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────────

func _on_damage_dealt_v2(_source: Node, target: Node, amount: float, _damage_node: Resource, is_crit: bool) -> void:
	if target == null:
		return
	# 投影屏幕坐标
	var world_pos: Variant = _get_world_position(target)
	var screen_pos: Vector2 = _project_to_screen(world_pos)
	if screen_pos == Vector2.INF:
		return
	var color: Color = _cfg.damage_popup_crit_color if is_crit else _cfg.damage_popup_normal_color
	var font_size: int = _cfg.damage_popup_crit_font_size if is_crit else _cfg.damage_popup_font_size
	_show_popup(screen_pos, amount, color, font_size)


# ─────────────────────────────────────────────────────────────
# 公开 API（外部代码也可直接调，如治疗飘字）
# ─────────────────────────────────────────────────────────────

func popup_heal(target: Node, amount: float) -> void:
	if target == null:
		return
	var screen_pos: Vector2 = _project_to_screen(_get_world_position(target))
	if screen_pos == Vector2.INF:
		return
	_show_popup(screen_pos, amount, _cfg.damage_popup_heal_color, _cfg.damage_popup_font_size)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _show_popup(screen_pos: Vector2, amount: float, color: Color, font_size: int) -> void:
	var p: DamagePopup = _acquire()
	if p == null:
		return
	_busy.append(p)
	p.show_damage(
		screen_pos + Vector2(0, _cfg.damage_popup_drift_distance * 0.2),  # 起始略偏下
		amount,
		color,
		font_size,
		_cfg.damage_popup_drift_distance,
		_cfg.damage_popup_horizontal_jitter,
		_cfg.damage_popup_lifetime,
	)


func _acquire() -> DamagePopup:
	if _pool.is_empty():
		# Grow×2
		_grow_pool(maxi(_busy.size(), 4))
	if _pool.is_empty():
		return null
	return _pool.pop_back()


func _on_recycled(p: DamagePopup) -> void:
	_busy.erase(p)
	_pool.append(p)


func _build_pool() -> void:
	var init_size: int = _cfg.damage_popup_pool_initial_size if _cfg != null else 20
	_grow_pool(init_size)


func _grow_pool(count: int) -> void:
	for i in range(count):
		var p := DamagePopup.new()
		add_child(p)
		p.recycled.connect(_on_recycled)
		_pool.append(p)


func _pull_config() -> void:
	var cfg_node: Node = get_tree().root.get_node_or_null(^"ConfigCenter")
	if cfg_node != null:
		_cfg = cfg_node.get_hit_feedback_config()
	if _cfg == null:
		_cfg = HitFeedbackConfig.new()


func _get_world_position(target: Node) -> Variant:
	# 返回 Vector2（2D 节点）或 Vector3（3D 节点）
	if target is Node2D:
		return (target as Node2D).global_position
	if target is Node3D:
		return (target as Node3D).global_position
	return null


func _project_to_screen(world_pos: Variant) -> Vector2:
	if world_pos == null:
		return Vector2.INF
	var vp := get_viewport()
	if vp == null:
		return Vector2.INF
	# 2D
	if world_pos is Vector2:
		var wp2: Vector2 = world_pos
		var cam2d: Camera2D = vp.get_camera_2d()
		if cam2d == null:
			# 没相机时直接返回原坐标（屏幕 = 世界）
			return wp2
		# 屏幕中心是相机位置 → 偏移 = world - camera
		var screen_center: Vector2 = Vector2(vp.get_visible_rect().size) * 0.5
		return screen_center + (wp2 - cam2d.global_position) * cam2d.zoom
	# 3D
	if world_pos is Vector3:
		var wp3: Vector3 = world_pos
		var cam3d: Camera3D = vp.get_camera_3d()
		if cam3d == null:
			return Vector2.INF
		return cam3d.unproject_position(wp3)
	return Vector2.INF
