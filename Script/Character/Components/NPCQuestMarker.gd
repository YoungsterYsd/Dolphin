## NPC 头顶任务标记（M12 P2）。
##
## 显示规则（按优先级从高到低）：
##   - **!**（金黄）：当前 NPC 关联的 Diapack 选项中，至少有一个对话是某个**待交付任务步骤**的 Deliver_Dialogue_ID
##   - **?**（蓝色）：当前 NPC 至少有 1 个**可见**的 Diapack 选项（[ConditionEvaluator] 通过）
##   - **隐藏**：0 个可见选项（默认台词或无内容）
##
## 刷新时机（DRY：所有"可能改变状态"的信号都触发一次 refresh）：
##   - _ready 时刷一次
##   - quest_step_* 信号（步骤启动 / 进度 / 待交付 / 完成 / 系列完成）
##   - dialogue_ended（对话结束可能改变 Cond_ID 求值结果）
##
## **设计原则**（SOLID）：
##   - SRP：仅做"读取 NPCActor.npc_id → 计算应显示什么 → 设置 Label3D"
##   - DIP：依赖 NPCDialogueService + QuestSystem + ConfigCenter 抽象 API；不读 csv 不评条件
##   - OCP：未来加新标记类型（如商店 $ / 传送 ↗）= 加 1 个 KIND 枚举 + 1 个 _evaluate_kind 分支
##
## 用法：把本组件作为 NPCActor 子节点 + Label3D 组合放进 NPC.tscn。
class_name NPCQuestMarker
extends Label3D


## 标记类型枚举（用于优先级判断 + 颜色映射）。
enum Kind {
	NONE,        ## 隐藏
	HAS_DIALOG,  ## ?  有可见对话（蓝色）
	CAN_DELIVER, ## !  可交付任务（金黄）
}


## 节流：为避免一帧内多次刷新，用 deferred 合并到帧末。
var _refresh_pending: bool = false

## 当前显示的 Kind（避免重复设置 text/color）。
var _current_kind: int = Kind.NONE

## 缓存父节点 NPCActor（_ready 时取一次）。
var _npc: NPCActor = null


func _ready() -> void:
	# 初始隐藏（避免一帧空白闪烁）
	visible = false
	# Label3D 配置（部分配置 .tscn 已设；这里兜底以便代码新建实例时也能跑）
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	pixel_size = 0.0035
	font_size = 96
	outline_size = 12
	modulate = Color(1, 1, 1, 1)
	outline_modulate = Color(0, 0, 0, 0.85)
	render_priority = 10
	# 找父级 NPCActor
	_npc = _find_npc_actor()
	if _npc == null:
		GameLogger.warn("NPC", "[QuestMarker] no NPCActor parent found, marker disabled")
		return
	# 订阅刷新触发器
	EventBus.quest_step_started.connect(_on_dirty_int_int)
	EventBus.quest_step_progress.connect(_on_dirty_int_int_int_int)
	EventBus.quest_step_pending_deliver.connect(_on_dirty_int_int)
	EventBus.quest_step_completed.connect(_on_dirty_int_int)
	EventBus.quest_series_completed.connect(_on_dirty_int)
	EventBus.dialogue_ended.connect(_on_dirty_int_int)
	# 启动时刷一次（call_deferred 保证 ConfigCenter 已 bootstrap、Quest 状态已初始化）
	call_deferred(&"refresh")


# ─────────────────────────────────────────────────────────────
# 信号回调（统一标脏）
# ─────────────────────────────────────────────────────────────

func _on_dirty_int(_a: int) -> void:
	_mark_dirty()


func _on_dirty_int_int(_a: int, _b: int) -> void:
	_mark_dirty()


func _on_dirty_int_int_int_int(_a: int, _b: int, _c: int, _d: int) -> void:
	_mark_dirty()


func _mark_dirty() -> void:
	if _refresh_pending:
		return
	_refresh_pending = true
	call_deferred(&"refresh")


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 立即重新计算并刷新标记（外部强制触发用，例如 GM 命令）。
func refresh() -> void:
	_refresh_pending = false
	if _npc == null or _npc.npc_id <= 0:
		_apply(Kind.NONE)
		return
	var kind: int = _evaluate_kind(_npc.npc_id)
	_apply(kind)


# ─────────────────────────────────────────────────────────────
# 内部 - 计算逻辑
# ─────────────────────────────────────────────────────────────

## 决策当前 NPC 应显示什么标记。
func _evaluate_kind(npc_id: int) -> int:
	# 取该 NPC 当前所有可见选项（已过滤 Cond_ID）
	var visible: Array = NPCDialogueService.get_visible_options(npc_id)
	if visible.is_empty():
		return Kind.NONE
	# 提取所有可见的 Dialogue_ID
	var visible_graph_ids: Array = []
	for opt in visible:
		visible_graph_ids.append(int(opt.get("Dialogue_ID", 0)))
	# 优先级 1：CAN_DELIVER —— 是否有任务的 Deliver_Dialogue_ID 命中可见选项 + 进度已达成
	if _has_deliverable_quest(visible_graph_ids):
		return Kind.CAN_DELIVER
	# 优先级 2：HAS_DIALOG —— 至少 1 个可见选项即可
	return Kind.HAS_DIALOG


## 是否存在"可交付任务步骤"，其 Deliver_Dialogue_ID ∈ visible_graph_ids 且进度已达成。
func _has_deliverable_quest(visible_graph_ids: Array) -> bool:
	if visible_graph_ids.is_empty():
		return false
	# 遍历 GameInstance.quest_states 找匹配
	for key in GameInstance.quest_states:
		var st: Dictionary = GameInstance.quest_states[key]
		var state: StringName = st.get(&"state", &"")
		# 状态：active 满进度 也算（虽然 QuestSystem 会立即转 pending_deliver，但保险起见）
		if state != QuestSystem.STATE_ACTIVE and state != QuestSystem.STATE_PENDING_DELIVER:
			continue
		var pair: Vector2i = QuestSystem.unkey(key)
		var step: Dictionary = ConfigCenter.get_quest_step(pair.x, pair.y)
		if step.is_empty():
			continue
		var deliver: int = CsvLoader.as_int(step, "Deliver_Dialogue_ID", 0)
		if deliver <= 0:
			continue
		if not visible_graph_ids.has(deliver):
			continue
		# 检查进度是否达成
		var target: int = CsvLoader.as_int(step, "Num", 1)
		var cur: int = int(st.get(&"progress", 0))
		# Kind=NPC 的对话推进类（target=1）即使 cur<target 也算可交付（因为对话结束本身就是推进）
		var kind_str: String = CsvLoader.as_string(step, "Kind", "")
		if cur >= target or kind_str == QuestSystem.KIND_NPC:
			return true
	return false


## 应用标记结果（更新 visible / text / 颜色）。
func _apply(kind: int) -> void:
	if kind == _current_kind:
		return
	_current_kind = kind
	match kind:
		Kind.NONE:
			visible = false
		Kind.HAS_DIALOG:
			visible = true
			text = "?"
			modulate = Color(0.55, 0.85, 1.0, 1.0)  # 蓝
		Kind.CAN_DELIVER:
			visible = true
			text = "!"
			modulate = Color(1.0, 0.92, 0.2, 1.0)  # 金黄
	if _npc != null:
		GameLogger.info("NPC", "[QuestMarker] %s npc_id=%d -> %s" % [
			_npc.name,
			_npc.npc_id,
			["NONE", "HAS_DIALOG (?)", "CAN_DELIVER (!)"][kind],
		])


# ─────────────────────────────────────────────────────────────
# 工具
# ─────────────────────────────────────────────────────────────

func _find_npc_actor() -> NPCActor:
	var p: Node = get_parent()
	while p != null:
		if p is NPCActor:
			return p
		p = p.get_parent()
	return null
