## 世界坐标 → 屏幕坐标投影工具（静态方法）。
##
## 抽离自 [DamagePopupPool._project_to_screen] / [EnemyOverheadHealthBar._project]，
## 供所有需要把 2D/3D 世界对象映射到屏幕的 HUD widget 复用。
##
## 用法：
##   var screen_pos := WorldProjector.project(target_node, viewport)
##   if screen_pos != Vector2.INF:
##       widget.position = screen_pos
##
## 行为：
##   - 2D：找 viewport 当前 Camera2D，按 zoom 偏移
##   - 3D：找 viewport 当前 Camera3D，剔除背面后 unproject_position
##   - 找不到目标 / 相机 / 背面 → 返回 Vector2.INF
class_name WorldProjector
extends RefCounted


## 把节点的世界坐标投影到屏幕。
## target：Node2D 或 Node3D
## viewport：可选，不传则取 target.get_viewport()
static func project(target: Node, viewport: Viewport = null) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.INF
	if viewport == null:
		if target.has_method("get_viewport"):
			viewport = target.get_viewport()
		if viewport == null:
			return Vector2.INF
	# 2D
	if target is Node2D:
		var wp2: Vector2 = (target as Node2D).global_position
		return _project_2d(wp2, viewport)
	# 3D
	if target is Node3D:
		var wp3: Vector3 = (target as Node3D).global_position
		return _project_3d(wp3, viewport)
	return Vector2.INF


## 直接投影一个 Vector2 / Vector3。
static func project_pos(world_pos: Variant, viewport: Viewport) -> Vector2:
	if viewport == null or world_pos == null:
		return Vector2.INF
	if world_pos is Vector2:
		return _project_2d(world_pos, viewport)
	if world_pos is Vector3:
		return _project_3d(world_pos, viewport)
	return Vector2.INF


## 计算节点到当前相机的距离（用于离屏剔除）。
static func distance_to_camera(target: Node, viewport: Viewport = null) -> float:
	if target == null or not is_instance_valid(target):
		return 0.0
	if viewport == null and target.has_method("get_viewport"):
		viewport = target.get_viewport()
	if viewport == null:
		return 0.0
	if target is Node2D:
		var cam2d: Camera2D = viewport.get_camera_2d()
		if cam2d == null:
			return 0.0
		return (target as Node2D).global_position.distance_to(cam2d.global_position)
	if target is Node3D:
		var cam3d: Camera3D = viewport.get_camera_3d()
		if cam3d == null:
			return 0.0
		return (target as Node3D).global_position.distance_to(cam3d.global_position)
	return 0.0


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

static func _project_2d(wp2: Vector2, vp: Viewport) -> Vector2:
	var cam2d: Camera2D = vp.get_camera_2d()
	if cam2d == null:
		# 没相机时直接返回原坐标（屏幕 = 世界）
		return wp2
	var screen_center: Vector2 = Vector2(vp.get_visible_rect().size) * 0.5
	return screen_center + (wp2 - cam2d.global_position) * cam2d.zoom


static func _project_3d(wp3: Vector3, vp: Viewport) -> Vector2:
	var cam3d: Camera3D = vp.get_camera_3d()
	if cam3d == null:
		return Vector2.INF
	# 背面剔除
	if cam3d.is_position_behind(wp3):
		return Vector2.INF
	return cam3d.unproject_position(wp3)
