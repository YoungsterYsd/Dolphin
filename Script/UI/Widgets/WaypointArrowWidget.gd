## 路标箭头（屏幕边缘指向目标点）。
##
## 当 [member target] 在屏幕外时，沿屏幕边缘显示箭头指向其方向。
## 业务侧通过 [method set_target] 设置追踪目标（任务点 / 传送门 / 商店）。
##
## 简化实现：
##   - 屏幕中心 → target 屏幕坐标 的方向向量
##   - 与屏幕矩形求边缘交点，把箭头放在该点
##   - 旋转箭头使其指向 target
##
## 距离过远时显示距离数字，距离过近时隐藏（target 在屏幕内不需要箭头）。
class_name WaypointArrowWidget
extends BaseWidget

## 距离过近隐藏（玩家走到附近）。
@export var hide_when_within_pixels: float = 100.0

## 边缘内边距（避免箭头贴到屏幕角落溢出）。
@export var edge_padding: float = 48.0

@onready var arrow: Label = $Arrow

var _target: Node = null


func _ready() -> void:
	super._ready()
	visible = false


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		visible = false
		return
	var vp := get_viewport()
	if vp == null:
		return
	var screen_size: Vector2 = vp.get_visible_rect().size
	var screen_center: Vector2 = screen_size * 0.5
	var target_screen: Vector2 = WorldProjector.project(_target, vp)
	if target_screen == Vector2.INF:
		visible = false
		return
	# 在屏幕内且距中心足够近 → 隐藏
	var rect: Rect2 = Rect2(Vector2.ZERO, screen_size).grow(-edge_padding)
	if rect.has_point(target_screen):
		visible = false
		return
	# 计算屏幕中心 → target 的方向向量
	var dir: Vector2 = (target_screen - screen_center).normalized()
	# 约束到屏幕边缘内 padding 矩形
	var edge_pos: Vector2 = _intersect_rect_edge(screen_center, dir, rect)
	# 应用位置（自身锚点为左上）
	position = edge_pos - size * 0.5
	# 旋转箭头：Label 内 ↑ 字符默认朝上，所以加 PI/2 让 0 弧度对应正上
	arrow.rotation = dir.angle() + PI * 0.5
	visible = true


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 设置追踪目标。传 null 隐藏。
func set_target(node: Node) -> void:
	_target = node


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _intersect_rect_edge(origin: Vector2, dir: Vector2, rect: Rect2) -> Vector2:
	# 与四条边求交，取 t > 0 的最小 t
	var t_max: float = INF
	if dir.x > 0.0001:
		t_max = minf(t_max, (rect.position.x + rect.size.x - origin.x) / dir.x)
	elif dir.x < -0.0001:
		t_max = minf(t_max, (rect.position.x - origin.x) / dir.x)
	if dir.y > 0.0001:
		t_max = minf(t_max, (rect.position.y + rect.size.y - origin.y) / dir.y)
	elif dir.y < -0.0001:
		t_max = minf(t_max, (rect.position.y - origin.y) / dir.y)
	return origin + dir * t_max
