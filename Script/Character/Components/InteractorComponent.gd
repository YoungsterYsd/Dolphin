## 交互组件（玩家挂载，按 G 触发）。
##
## 职责：
##   - 订阅 [signal EventBus.player_input_action_pressed] 监听 [code]combat_interact[/code]
##   - 在 [code]interact_max_distance[/code] 米内寻找最近且 [method InteractableTarget.is_interactable] 的目标
##   - 调目标的 [method InteractableTarget.interact]([code]get_parent()[/code])
##
## 不负责：
##   - 范围进入/离开提示（由 [InteractableTarget] 子类自身的 Area3D 处理）
##   - 交互成功后的具体业务（对话/拾取/打开等由 InteractableTarget 子类自定义）
##
## 用法：玩家场景里挂一个 InteractorComponent 子节点即可，无需配置（除非要改距离）。
class_name InteractorComponent
extends Node


## 交互最大距离（米）。默认 4m（兼容历史 16 m² = 4m）。
@export var interact_max_distance: float = 4.0

## 监听的输入 action 名（默认 [code]combat_interact[/code]）。
@export var interact_action: StringName = &"combat_interact"


func _ready() -> void:
	EventBus.player_input_action_pressed.connect(_on_input_action_pressed)


func _on_input_action_pressed(action: StringName) -> void:
	if action != interact_action:
		return
	_try_interact()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _try_interact() -> void:
	var owner_node: Node3D = get_parent() as Node3D
	if owner_node == null:
		# 父节点必须是 Node3D（玩家是 CharacterBody3D 派生）。配置错误直接崩，便于定位。
		assert(false, "InteractorComponent: parent must be Node3D, got %s" % str(get_parent()))
		return

	var target: InteractableTarget = _find_nearest_target(owner_node.global_position)
	if target == null:
		GameLogger.info("Interaction", "%s interact: no target in range" % owner_node.name)
		return
	GameLogger.info("Interaction", "%s interact -> %s" % [owner_node.name, target.name])
	target.interact(owner_node)


func _find_nearest_target(from_pos: Vector3) -> InteractableTarget:
	var best: InteractableTarget = null
	var best_dist_sq: float = INF
	var max_dist_sq: float = interact_max_distance * interact_max_distance
	for n in get_tree().get_nodes_in_group(&"interactable"):
		var t: InteractableTarget = n as InteractableTarget
		if t == null:
			continue
		if not t.is_interactable():
			continue
		var d: float = t.global_position.distance_squared_to(from_pos)
		if d > max_dist_sq:
			continue
		if d < best_dist_sq:
			best = t
			best_dist_sq = d
	return best
