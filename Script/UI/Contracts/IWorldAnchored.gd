## 「世界锚点」契约（Resource）。
##
## 用于头顶血条 / 互动提示 / 飘字定位 / 目标点指引 等需要把世界对象映射到屏幕的 widget。
## widget 不持有 Node3D / Node2D 业务节点引用，仅依赖本契约获取世界坐标与可见性。
##
## 实现方应：
##   1) 在 [method get_world_position] 返回 Vector2 / Vector3
##   2) 当目标对象移动 / 销毁 / 不可见时 emit [signal world_anchor_changed]
class_name IWorldAnchored
extends Resource

## 世界坐标变化或可见性变化。
signal world_anchor_changed

## 返回当前世界坐标。Vector2（2D）或 Vector3（3D）。返回 null 表示不可投影（已销毁）。
func get_world_position() -> Variant:
	return null

## 是否当前对相机可见（用于离屏剔除）。
func is_visible_to_camera() -> bool:
	return true

## 调试 / 标签用。
func get_anchor_id() -> StringName:
	return &""
