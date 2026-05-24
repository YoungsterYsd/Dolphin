## NPC（非玩家角色）— [InteractableTarget] 的对话子类。
##
## 职责：
##   1. 内含 Area3D（InteractRange）检测玩家进入/离开 → 派发 EventBus.interaction_target_*
##   2. 玩家按 G 触发 [method interact] → 经 [NPCDialogueService] 决定弹菜单或直接进入对话
##   3. 朝向玩家（可选，[member face_player_on_interact]）
##
## **M12 数据驱动**（A6/A7/A8 决策）：
##   - 仅需配 [member npc_id]（指向 NPC_Data.csv 的 id）
##   - 互动时由 [NPCDialogueService] 读 NPC_Data.Diapack_ID → NPC_Diapack 子项 → 过滤 Condition
##     - 0 个可见 → 静默关闭
##     - 1 个可见 → 直接进入对话（跳过菜单）
##     - ≥2 个可见 → 通过 [signal EventBus.npc_dialogue_menu_requested] 让 UI 显示菜单
##
## 用法：
##   - 把 NPC.tscn 拖入关卡，Inspector 仅配 [member npc_id]
##   - 不需要再配 dialogue_graph_id（已 deprecated；保留仅为旧 .tscn 兼容）
##
## 设计选择（SOLID）：
##   - SRP：NPCActor 只是"场景里那个能互动的玩偶"；不读配表、不评条件、不开对话
##   - 业务交给 NPCDialogueService（服务）+ DialogueRunner（执行）
class_name NPCActor
extends InteractableTarget


## NPC 唯一 ID（[code]NPC_Data.id[/code]）。<=0 表示占位 NPC（按 G 仅打 log）。
@export var npc_id: int = 0

## **DEPRECATED**：旧字段，保留仅为 .tscn 实例兼容；新场景请不要使用此字段。
##
## 设置 >0 时**强制**走"直接进入此对话"路径（不调 NPCDialogueService）；
## <=0 时走数据驱动路径（NPCDialogueService 决策）。
@export var dialogue_graph_id: int = 0

## 交互时是否朝向玩家。
@export var face_player_on_interact: bool = true

## 交互范围半径（米；默认 2.5m）。在 _ready 时应用到 Area3D 的 CollisionShape3D。
@export var interact_radius: float = 2.5


@onready var interact_range: Area3D = $InteractRange
@onready var visual: Node3D = $Visual

# 当前在范围内的玩家（同时只追踪一个）
var _player_in_range: Node = null


func _ready() -> void:
	add_to_group(&"npc")
	add_to_group(&"interactable")
	# 应用 interact_radius 到子 SphereShape3D（如果是 Sphere）
	var col: CollisionShape3D = interact_range.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is SphereShape3D:
		(col.shape as SphereShape3D).radius = interact_radius
	# Area 信号
	interact_range.body_entered.connect(_on_body_entered)
	interact_range.body_exited.connect(_on_body_exited)
	# 数据驱动：若仅配了 npc_id，自动读 NPC_Data 取 display_name 兜底
	if npc_id > 0 and display_name.is_empty():
		var nm: String = NPCDialogueService.get_npc_name(npc_id)
		if not nm.is_empty():
			display_name = nm
	GameLogger.info("NPC", "%s ready (npc_id=%d, legacy_graph=%d, radius=%.1f)" % [name, npc_id, dialogue_graph_id, interact_radius])


# ─────────────────────────────────────────────────────────────
# Area3D 信号
# ─────────────────────────────────────────────────────────────

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player"):
		return
	_player_in_range = body
	if not enabled:
		return
	EventBus.interaction_target_entered.emit(self)


func _on_body_exited(body: Node) -> void:
	if body != _player_in_range:
		return
	_player_in_range = null
	EventBus.interaction_target_left.emit(self)


# ─────────────────────────────────────────────────────────────
# InteractableTarget 实现
# ─────────────────────────────────────────────────────────────

func interact(player: Node) -> void:
	if not enabled:
		return
	# 朝向玩家
	if face_player_on_interact and player is Node3D:
		_face_position((player as Node3D).global_position)

	if DialogueRunner == null:
		GameLogger.warn("NPC", "DialogueRunner not available")
		return

	# 路径 1：旧兼容（dialogue_graph_id>0 时强制进入此对话）
	if dialogue_graph_id > 0:
		DialogueRunner.start(dialogue_graph_id, npc_id)
		return

	# 路径 2：数据驱动（M12 主路径；npc_id 必填）
	if npc_id <= 0:
		GameLogger.info("NPC", "%s interacted (npc_id=0; placeholder)" % name)
		return

	var entry_id: int = NPCDialogueService.resolve_entry(npc_id)
	match entry_id:
		NPCDialogueService.RESULT_NONE:
			GameLogger.info("NPC", "%s: 0 visible diapack options for npc_id=%d, silent close" % [name, npc_id])
			# 0 选项：静默关闭（未来可配 Default_Text 字段做兜底台词；本期不做）
		NPCDialogueService.RESULT_MENU:
			# ≥2 选项：广播让 UI 显示菜单（业务侧 NPCDiapackMenuWidget 订阅 npc_dialogue_menu_requested）
			var options: Array = NPCDialogueService.get_visible_options(npc_id)
			GameLogger.info("NPC", "%s: %d diapack options, request menu" % [name, options.size()])
			# **Phase 3.5 待实装兜底**：若无 Widget 订阅 npc_dialogue_menu_requested，退化为直接进入第一个可见选项。
			# Widget 实装并 connect 后，此 fallback 自动失效（不进 if 分支）。
			var has_listener: bool = not EventBus.npc_dialogue_menu_requested.get_connections().is_empty()
			if has_listener:
				EventBus.npc_dialogue_menu_requested.emit(npc_id, options)
			else:
				var first_id: int = int(options[0].get("Dialogue_ID", 0))
				GameLogger.info("NPC", "%s: no menu widget subscribed; fallback to first option graph=%d" % [name, first_id])
				if first_id > 0:
					DialogueRunner.start(first_id, npc_id)
		_:
			# 单个 graph_id（>0）：直接进入
			GameLogger.info("NPC", "%s: single visible option, auto-enter graph=%d" % [name, entry_id])
			DialogueRunner.start(entry_id, npc_id)


func get_prompt_anchor() -> Vector3:
	# Visual 节点（如果存在）通常是 NPC 模型；用它的位置 + 1.8m 做头顶锚
	if visual != null:
		return visual.global_position + Vector3.UP * 1.8
	return global_position + Vector3.UP * 1.8


# ─────────────────────────────────────────────────────────────
# 工具
# ─────────────────────────────────────────────────────────────

func _face_position(target_pos: Vector3) -> void:
	if visual == null:
		return
	var to: Vector3 = target_pos - global_position
	to.y = 0.0
	if to.length_squared() < 0.001:
		return
	# Y 轴旋转面向目标（仅 visual 节点；NPC 根节点 transform 不动）
	visual.look_at(visual.global_position - to, Vector3.UP)
