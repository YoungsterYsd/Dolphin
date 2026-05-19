## 特效生成器（M8 引入）。
##
## 挂在 [GameInstance] 子节点；订阅 [signal EventBus.skill_event_vfx]：
##   payload 约定：{vfx_scene_path: String, offset_2d: Vector2 = (0,0), offset_3d: Vector3 = (0,0,0), lifetime: float = 1.5}
##
## 实例化的特效挂在当前场景根下，按 lifetime 自动 free。
## M9 切 3D 后：当 caster 是 Node3D 时用 offset_3d；2D 时用 offset_2d。
class_name VFXSpawner
extends Node

const DEFAULT_LIFETIME: float = 1.5


func _ready() -> void:
	if EventBus.has_signal(&"skill_event_vfx"):
		EventBus.skill_event_vfx.connect(_on_skill_event_vfx)


func _on_skill_event_vfx(_vfx_id: StringName, caster: Node, payload: Dictionary) -> void:
	var path: String = String(payload.get("vfx_scene_path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		# M8 阶段 vfx_scene_path 还没普及；不报 error 只提示
		GameLogger.info("Skill", "VFXSpawner: no vfx_scene_path in payload, skip")
		return
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		GameLogger.warn("Skill", "VFXSpawner: failed to load %s" % path)
		return
	var inst: Node = ps.instantiate()
	# 加到当前激活场景根（保持位置坐标系一致）
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		inst.free()
		return
	scene_root.add_child(inst)
	# 位置：caster 位置 + 偏移
	if inst is Node2D and caster is Node2D:
		var off2: Vector2 = payload.get("offset_2d", Vector2.ZERO)
		(inst as Node2D).global_position = (caster as Node2D).global_position + off2
	elif inst is Node3D and caster is Node3D:
		var off3: Vector3 = payload.get("offset_3d", Vector3.ZERO)
		(inst as Node3D).global_position = (caster as Node3D).global_position + off3
	# 生命周期
	var lifetime: float = float(payload.get("lifetime", DEFAULT_LIFETIME))
	var t := get_tree().create_timer(lifetime)
	t.timeout.connect(func() -> void:
		if is_instance_valid(inst):
			inst.queue_free()
	)
