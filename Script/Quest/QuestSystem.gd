## 任务运行时（Autoload，M12 重写）。
##
## **设计要点**（A3/A4/A5 决策）：
##   - 数据源：[code]Data/FromExcel/Quest_Data.csv[/code]（[QuestLoader]）
##   - 任务结构：[code](quest_id, sub_id)[/code] 二元组；同 quest_id 多 sub_id **顺序串行**（链式）
##   - 接取路径：① 关卡初始化 [LevelLoader.bulk_accept]；② 上一 sub 完成后**自动接**下一 sub
##     —— 对话**不能**直接接任务（A3）
##   - 交付路径：当前 sub 目标达成后：
##     - [code]Deliver_Dialogue_ID == 0[/code] → 立即完成 + 自动推进下一 sub
##     - [code]Deliver_Dialogue_ID > 0[/code] → 进入 [code]pending_deliver[/code] 中间态；玩家走完该对话
##       （监听 [signal EventBus.dialogue_ended]）后才完成（A4）
##   - 奖励发放：[code]Drop_Rule_ID > 0[/code] 时调 [LootSpawner.dispatch]（统一抽奖管线，A2）
##   - 自动推进：监听 [signal EventBus.enemy_died]（Kind=Monster）/ [signal EventBus.inventory_changed]（Kind=Item）/
##     [signal EventBus.dialogue_ended]（Kind=NPC + Deliver_Dialogue_ID）
##
## **状态机**（每个 (quest_id, sub_id)）：
##   [code]inactive → active → pending_deliver → completed[/code]
##   [code]inactive → active → completed[/code]（无交付对话时）
##
## **设计原则**（SOLID）：
##   - SRP：仅做"任务状态机推进 + 奖励派发触发"；不渲染 UI、不读 NPC 配置
##   - OCP：新增 Kind（如 Tricky/Reach）= 新增 Kind handler；不改主流程
##   - DIP：依赖 EventBus 信号 + ConfigCenter 直访；不依赖具体 NPC/敌人/物品类
##   - DRY：奖励统一走 LootSpawner.dispatch；条件统一走 ConditionEvaluator
extends Node


# ─────────────────────────────────────────────────────────────
# 状态字段（quest_id+sub_id 二元组 → 步骤状态）
# ─────────────────────────────────────────────────────────────

# 状态枚举（使用 StringName，方便 GameInstance 持久化）
const STATE_INACTIVE: StringName = &""
const STATE_ACTIVE: StringName = &"active"
const STATE_PENDING_DELIVER: StringName = &"pending_deliver"
const STATE_COMPLETED: StringName = &"completed"

# Quest_Data.Kind 枚举
const KIND_ITEM: StringName = &"Item"
const KIND_MONSTER: StringName = &"Monster"
const KIND_NPC: StringName = &"NPC"
const KIND_TRICKY: StringName = &"Tricky"


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A4：全局订阅对话结束信号 → 反查 Deliver_Dialogue_ID + KIND_NPC 推进
	EventBus.dialogue_ended.connect(_on_dialogue_ended)
	# A5：自动推进 Kind=Monster
	EventBus.enemy_died.connect(_on_enemy_died)
	# 自动推进 Kind=Item（玩家拾取道具时；item_added 携带 def，计数从 InventoryManager 实时查）
	EventBus.item_added.connect(_on_item_added)
	GameLogger.info("Quest", "QuestSystem ready (M12 rewrite, sub-id chain mode)")


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 接受任务系列。仅当 sub_id=1 步骤未激活时生效。
##
## A3：通常仅由 [LevelLoader] 在关卡启动时批量调用；
## 也可由 GM 命令手动触发测试。
##
## 返回是否成功接受。
func accept(quest_id: int) -> bool:
	if quest_id <= 0:
		return false
	if not ConfigCenter.has_quest_step(quest_id, 1):
		GameLogger.warn("Quest", "accept failed: no sub_id=1 for quest_id=%d" % quest_id)
		return false
	# 已经有 sub_id=1 状态时拒绝重复接取（不论何状态）
	if get_state(quest_id, 1) != STATE_INACTIVE:
		GameLogger.info("Quest", "accept skipped: q=%d already started" % quest_id)
		return false
	_activate_step(quest_id, 1)
	return true


## 批量接取（关卡初始化用；A3）。
func bulk_accept(quest_ids: Array) -> int:
	var n: int = 0
	for qid_v in quest_ids:
		var qid: int = int(qid_v)
		if accept(qid):
			n += 1
	GameLogger.info("Quest", "bulk_accept: %d/%d accepted" % [n, quest_ids.size()])
	return n


## 强制推进当前 active 步骤（cheat / GM 命令用）。
##
## 行为：把当前 active 步骤的 progress 直接拉到 target，触发完成 + 推进下一 sub。
func complete_current_step(quest_id: int) -> void:
	var sub: int = current_sub_id(quest_id)
	if sub <= 0:
		GameLogger.warn("Quest", "complete_current_step: q=%d no active step" % quest_id)
		return
	var step: Dictionary = ConfigCenter.get_quest_step(quest_id, sub)
	var target: int = CsvLoader.as_int(step, "Num", 1)
	_set_progress(quest_id, sub, target)
	_check_step_done(quest_id, sub)


## 主动推进步骤进度（custom kind / 单测用）。
func advance_step(quest_id: int, sub_id: int, delta: int = 1) -> void:
	if get_state(quest_id, sub_id) != STATE_ACTIVE:
		return
	var step: Dictionary = ConfigCenter.get_quest_step(quest_id, sub_id)
	if step.is_empty():
		return
	var target: int = CsvLoader.as_int(step, "Num", 1)
	var cur: int = mini(get_progress(quest_id, sub_id) + delta, target)
	_set_progress(quest_id, sub_id, cur)
	_check_step_done(quest_id, sub_id)


## 放弃整个任务系列。
func abandon(quest_id: int) -> void:
	# 把所有 sub_id 标记为已结束（用 STATE_COMPLETED 的兜底）
	var keys: Array = _step_keys_for_quest(quest_id)
	for key in keys:
		GameInstance.quest_states[key] = {
			&"state": STATE_COMPLETED,  # 用 completed 标记，避免被再次触发
			&"progress": 0,
			&"abandoned": true,
		}
	GameLogger.info("Quest", "abandoned: q=%d" % quest_id)
	EventBus.quest_abandoned.emit(quest_id)


## 查询某步骤状态。返回 STATE_* 之一；STATE_INACTIVE 表示未接取。
func get_state(quest_id: int, sub_id: int) -> StringName:
	var key: String = _key(quest_id, sub_id)
	var st: Dictionary = GameInstance.quest_states.get(key, {})
	return st.get(&"state", STATE_INACTIVE)


## 查询某步骤进度。
func get_progress(quest_id: int, sub_id: int) -> int:
	var key: String = _key(quest_id, sub_id)
	return int(GameInstance.quest_states.get(key, {}).get(&"progress", 0))


## 查询当前 active / pending_deliver 的 sub_id。无则返回 0。
##
## 因为同 quest_id 串行，**同时只有一个 sub_id 处于非 inactive 非 completed 状态**。
func current_sub_id(quest_id: int) -> int:
	var sub: int = 1
	while ConfigCenter.has_quest_step(quest_id, sub):
		var st: StringName = get_state(quest_id, sub)
		if st == STATE_ACTIVE or st == STATE_PENDING_DELIVER:
			return sub
		sub += 1
	return 0


## 该 quest_id 是否所有 sub_id 都已完成。
func is_quest_finished(quest_id: int) -> bool:
	var sub: int = 1
	while ConfigCenter.has_quest_step(quest_id, sub):
		if get_state(quest_id, sub) != STATE_COMPLETED:
			return false
		sub += 1
	return sub > 1  # 至少有 1 个 sub 才算


## 该 quest_id 当前 sub 是否处于 pending_deliver（条件求值用）。
func is_pending_deliver(quest_id: int) -> bool:
	var sub: int = current_sub_id(quest_id)
	if sub <= 0:
		return false
	return get_state(quest_id, sub) == STATE_PENDING_DELIVER


## 该 quest_id 是否处于 active（含 pending_deliver）。
func is_quest_ongoing(quest_id: int) -> bool:
	return current_sub_id(quest_id) > 0


# ─────────────────────────────────────────────────────────────
# 自动推进（信号订阅）
# ─────────────────────────────────────────────────────────────

func _on_enemy_died(enemy: Node) -> void:
	if enemy == null:
		return
	if not ("kind" in enemy) or not ("data_id" in enemy):
		return
	var k: int = int(enemy.kind)
	var monster_id: int = int(enemy.data_id)
	if k != ConfigCenter.CharacterKind.MONSTER or monster_id <= 0:
		return
	# 遍历所有 active 步骤，找 Kind=Monster 且 ID==monster_id 的推进
	_advance_active_by_kind(KIND_MONSTER, monster_id, 1)


func _on_item_added(_owner: Node, def: Resource, _count: int) -> void:
	# Kind=Item 任务：玩家持有 ID==item_id 的物品 → 进度 +count
	# 但简化处理：仅 +1 ⇒ 实际推进按当前持有数 mini target（后续若需精确，可改用 InventoryManager 查总数）
	if def == null:
		return
	if not ("item_id" in def):
		return
	var item_def_id: int = int(def.item_id)
	if item_def_id <= 0:
		return
	# 同 _advance_active_by_kind，但额外按"已持有总数"计算（相比 +1 更稳）
	# 简化：只 +1 调到 target 即可（_advance_active_by_kind 已处理 clamp）
	_advance_active_by_kind(KIND_ITEM, item_def_id, _count)


## A4：对话结束 → 反查 Deliver_Dialogue_ID 推进。
##
## 两类推进：
##   1. **交付推进**：当前 active 步骤的 [code]Deliver_Dialogue_ID == graph_id[/code] 且
##      已达成 → 完成（实际上 pending_deliver 状态等的就是这个）
##   2. **NPC 谈话推进**：Kind=NPC 且 ID==npc_id（依据 npc_id 携带）→ +1
func _on_dialogue_ended(graph_id: int, npc_id: int) -> void:
	# 类型 1：交付推进（含 active + 满进度 → 立即完成；含 pending_deliver → 完成）
	for key in GameInstance.quest_states.keys():  # .keys() 防止边遍历边改
		var st: Dictionary = GameInstance.quest_states[key]
		var state: StringName = st.get(&"state", STATE_INACTIVE)
		if state != STATE_ACTIVE and state != STATE_PENDING_DELIVER:
			continue
		var pair: Vector2i = _unkey(key)
		var step: Dictionary = ConfigCenter.get_quest_step(pair.x, pair.y)
		if step.is_empty():
			continue
		var deliver: int = CsvLoader.as_int(step, "Deliver_Dialogue_ID", 0)
		if deliver != graph_id:
			continue
		# 命中：仅当 progress >= target 时才真正完成（避免提前交付）
		var target: int = CsvLoader.as_int(step, "Num", 1)
		var cur: int = int(st.get(&"progress", 0))
		# Kind=NPC 的对话完成本身就视为达成（target 一般是 1）
		if CsvLoader.as_string(step, "Kind", "") == KIND_NPC:
			cur = target
			_set_progress(pair.x, pair.y, cur)
		if cur < target:
			# 未达目标：仅打 log，不完成
			GameLogger.info("Quest", "deliver dialogue ended but objective not done: q=%d sub=%d (%d/%d)" % [pair.x, pair.y, cur, target])
			continue
		_complete_step(pair.x, pair.y)

	# 类型 2：Kind=NPC ID==npc_id 推进（npc_id 来自 NPC_Data.csv；DialogueRunner.start 时携带）
	if npc_id > 0:
		_advance_active_by_kind(KIND_NPC, npc_id, 1)


# ─────────────────────────────────────────────────────────────
# 内部 - 步骤推进与完成
# ─────────────────────────────────────────────────────────────

## 激活一个步骤（accept / 串行推进 都走此入口）。
func _activate_step(quest_id: int, sub_id: int) -> void:
	var step: Dictionary = ConfigCenter.get_quest_step(quest_id, sub_id)
	if step.is_empty():
		GameLogger.warn("Quest", "_activate_step: not found q=%d sub=%d" % [quest_id, sub_id])
		return
	var key: String = _key(quest_id, sub_id)
	GameInstance.quest_states[key] = {
		&"state": STATE_ACTIVE,
		&"progress": 0,
		&"started_at": Time.get_ticks_msec(),
	}
	var name_str: String = CsvLoader.as_string(step, "Name", "")
	GameLogger.info("Quest", "[step started] q=%d sub=%d (%s)" % [quest_id, sub_id, name_str])
	EventBus.quest_step_started.emit(quest_id, sub_id)
	# 立即派发一次 progress=0/N，让 HUD 渲染初始进度
	var target: int = CsvLoader.as_int(step, "Num", 1)
	EventBus.quest_step_progress.emit(quest_id, sub_id, 0, target)


## 设置进度（不触发完成检查；调用方需另调 [_check_step_done]）。
func _set_progress(quest_id: int, sub_id: int, value: int) -> void:
	var key: String = _key(quest_id, sub_id)
	var st: Dictionary = GameInstance.quest_states.get(key, {})
	if st.is_empty():
		return
	var step: Dictionary = ConfigCenter.get_quest_step(quest_id, sub_id)
	var target: int = CsvLoader.as_int(step, "Num", 1)
	var clamped: int = clampi(value, 0, target)
	if int(st.get(&"progress", 0)) == clamped:
		return  # 进度无变化
	st[&"progress"] = clamped
	GameInstance.quest_states[key] = st
	EventBus.quest_step_progress.emit(quest_id, sub_id, clamped, target)


## 检查某步骤是否达成目标；达成则按 Deliver_Dialogue_ID 决定立即完成 or 进入 pending_deliver。
func _check_step_done(quest_id: int, sub_id: int) -> void:
	if get_state(quest_id, sub_id) != STATE_ACTIVE:
		return
	var step: Dictionary = ConfigCenter.get_quest_step(quest_id, sub_id)
	var target: int = CsvLoader.as_int(step, "Num", 1)
	if get_progress(quest_id, sub_id) < target:
		return
	# 达成
	var deliver: int = CsvLoader.as_int(step, "Deliver_Dialogue_ID", 0)
	if deliver > 0:
		_enter_pending_deliver(quest_id, sub_id)
	else:
		_complete_step(quest_id, sub_id)


## 进入 pending_deliver 中间态。
func _enter_pending_deliver(quest_id: int, sub_id: int) -> void:
	var key: String = _key(quest_id, sub_id)
	var st: Dictionary = GameInstance.quest_states.get(key, {})
	st[&"state"] = STATE_PENDING_DELIVER
	GameInstance.quest_states[key] = st
	GameLogger.info("Quest", "[step pending_deliver] q=%d sub=%d" % [quest_id, sub_id])
	EventBus.quest_step_pending_deliver.emit(quest_id, sub_id)


## 完成某步骤（发奖 + 自动接下一 sub_id 或派发系列完成）。
func _complete_step(quest_id: int, sub_id: int) -> void:
	var key: String = _key(quest_id, sub_id)
	var st: Dictionary = GameInstance.quest_states.get(key, {})
	st[&"state"] = STATE_COMPLETED
	GameInstance.quest_states[key] = st
	# 发奖（A2：统一走 LootSpawner.dispatch）
	var step: Dictionary = ConfigCenter.get_quest_step(quest_id, sub_id)
	var drop_id: int = CsvLoader.as_int(step, "Drop_Rule_ID", 0)
	if drop_id > 0:
		var n: int = LootSpawner.dispatch(drop_id, self)
		GameLogger.info("Quest", "[step completed] q=%d sub=%d drop=%d granted=%d" % [quest_id, sub_id, drop_id, n])
	else:
		GameLogger.info("Quest", "[step completed] q=%d sub=%d (no drop)" % [quest_id, sub_id])
	EventBus.quest_step_completed.emit(quest_id, sub_id)
	# A5：自动接下一 sub_id；若没有则系列完成
	var next_sub: int = sub_id + 1
	if ConfigCenter.has_quest_step(quest_id, next_sub):
		_activate_step(quest_id, next_sub)
	else:
		GameLogger.info("Quest", "[series completed] q=%d" % quest_id)
		EventBus.quest_series_completed.emit(quest_id)


## 推进所有 active 步骤中匹配 (kind, target_id) 的（kill / talk）。
func _advance_active_by_kind(kind: StringName, target_id: int, delta: int) -> void:
	for key in GameInstance.quest_states.keys():
		var st: Dictionary = GameInstance.quest_states[key]
		if st.get(&"state", STATE_INACTIVE) != STATE_ACTIVE:
			continue
		var pair: Vector2i = _unkey(key)
		var step: Dictionary = ConfigCenter.get_quest_step(pair.x, pair.y)
		if step.is_empty():
			continue
		if CsvLoader.as_string(step, "Kind", "") != kind:
			continue
		if CsvLoader.as_int(step, "ID", 0) != target_id:
			continue
		var target: int = CsvLoader.as_int(step, "Num", 1)
		var cur: int = mini(get_progress(pair.x, pair.y) + delta, target)
		_set_progress(pair.x, pair.y, cur)
		_check_step_done(pair.x, pair.y)


# ─────────────────────────────────────────────────────────────
# 内部 - key 工具（quest_id+sub_id ↔ String）
# ─────────────────────────────────────────────────────────────

## 把 (quest_id, sub_id) 编码为可作 Dictionary key 的 String。
##
## 用 String 而非 Vector2i 的原因：[GameInstance.quest_states] 需要持久化，
## Dictionary key 类型简单点 SaveGame 序列化更可靠。
##
## 公开 API：业务方（如 NPCQuestMarker）需要遍历 [GameInstance.quest_states] 时，
## 用 [method unkey] 把 String key 解回 (quest_id, sub_id) 二元组。
static func key(quest_id: int, sub_id: int) -> String:
	return "q%d.s%d" % [quest_id, sub_id]


static func unkey(key_str: String) -> Vector2i:
	# 解析 "q<int>.s<int>"
	var parts: PackedStringArray = key_str.trim_prefix("q").split(".s")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(parts[0].to_int(), parts[1].to_int())


# 内部别名（保留旧私有 API 调用点）
static func _key(quest_id: int, sub_id: int) -> String:
	return key(quest_id, sub_id)


static func _unkey(key_str: String) -> Vector2i:
	return unkey(key_str)


## 取某 quest_id 的所有 (quest_id, sub_id) 状态 key。
func _step_keys_for_quest(quest_id: int) -> Array:
	var out: Array = []
	var prefix: String = "q%d.s" % quest_id
	for key in GameInstance.quest_states.keys():
		if (key as String).begins_with(prefix):
			out.append(key)
	return out
