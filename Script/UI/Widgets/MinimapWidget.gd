## 小地图（雷达式）。
##
## **简化实现**：不用 SubViewport 渲染场景，改为纯雷达点（_draw 自绘）。
##   - 玩家在中心（白色三角形，朝玩家朝向）
##   - 敌人（"enemy" group）红色点
##   - Boss（"boss" group）红色大点
##   - NPC（"npc" group）黄色点
##   - 拾取物（"pickup" group）绿色点
##
## 比例 [member world_to_minimap_scale]：1.0 = 1 世界单位 → 1 像素。
## 半径外的目标不显示（保留圆形边缘）。
##
## 后期需要"看到地形"时再升级为 SubViewport + Camera2D + 雷达点 overlay 双层方案。
class_name MinimapWidget
extends BaseWidget

@export var radius_pixels: float = 80.0
@export var world_to_minimap_scale: float = 0.25

@onready var bg: Panel = $BG

var _player: Node = null


func _ready() -> void:
	super._ready()
	set_process(true)


func _process(_delta: float) -> void:
	# 找一次玩家（容错）
	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	queue_redraw()


func _draw() -> void:
	# 圆形背景遮罩
	var center: Vector2 = size * 0.5
	draw_circle(center, radius_pixels, Color(0, 0, 0, 0.4))
	# 玩家中心点（白色三角形 / 圆点占位）
	if _player != null and is_instance_valid(_player):
		draw_circle(center, 4.0, Color(1, 1, 1))
	else:
		return
	var player_pos: Vector3 = _to_v3((_player as Node3D).global_position) if _player is Node3D else _to_v3((_player as Node2D).global_position) if _player is Node2D else Vector3.ZERO
	# 遍历 SceneTree 找雷达可见目标
	_draw_group_dots(&"boss", player_pos, center, Color(1.0, 0.2, 0.2), 6.0)
	_draw_group_dots(&"enemy", player_pos, center, Color(0.95, 0.35, 0.35), 3.5)
	_draw_group_dots(&"npc", player_pos, center, Color(1.0, 0.85, 0.2), 3.5)
	_draw_group_dots(&"pickup", player_pos, center, Color(0.4, 1.0, 0.4), 3.0)


func _draw_group_dots(group: StringName, player_pos: Vector3, center: Vector2, color: Color, radius: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(group):
		if node == _player:
			continue
		var pos: Vector3 = _to_v3((node as Node3D).global_position) if node is Node3D else _to_v3((node as Node2D).global_position) if node is Node2D else Vector3.ZERO
		var delta: Vector3 = pos - player_pos
		# 用 X / Z 平面（3D）或 X / Y（2D 投影）
		var minimap_offset: Vector2 = Vector2(delta.x, delta.z) * world_to_minimap_scale
		# 半径裁剪
		if minimap_offset.length() > radius_pixels:
			continue
		draw_circle(center + minimap_offset, radius, color)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _find_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var arr: Array = tree.get_nodes_in_group(&"player")
	if arr.is_empty():
		return null
	return arr[0]


func _to_v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Vector2:
		return Vector3(v.x, 0.0, v.y)
	return Vector3.ZERO
