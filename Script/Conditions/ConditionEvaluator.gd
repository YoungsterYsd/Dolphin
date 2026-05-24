## 触发条件求值器（静态工具）。
##
## 输入：cond_id（→ Condition.csv 子表）
## 输出：bool（满足/不满足）
##
## **求值规则**：
##   - 同一 cond_id 下所有子条件 **AND** 组合（任一不满足即返回 false）
##   - 子条件 [code]Type[/code] 取值（Enum）：
##     - [code]Lev[/code]：玩家等级 ≥ Param
##     - [code]Quest_Ongoing[/code]：任务系列 quest_id 处于"进行中"（Param=quest_id）
##     - [code]Quest_Finished[/code]：任务系列 quest_id 已全部完成（Param=quest_id）
##     - [code]Quest_PendingDeliver[/code]：当前 active 的 sub_id 已达成目标，等待交付（Param=quest_id；不区分 sub_id）
##     - [code]Quest_StepPendingDeliver[/code]：**指定 sub_id** 当前处于待交付（Param 复合编码 [code]quest_id*100+sub_id[/code]）
##       - 例 Param=101 → q=1 sub=1 待交付；Param=204 → q=2 sub=4 待交付
##       - 用于让 NPC_Diapack 选项精准对应每一步交付对话（例：村长 sub=2 仅当 q=1 sub=1 pending 时显示"我已找回证物"）
##
## **空集合语义**：cond_id <= 0 或表里找不到 → 返回 true（视为"无条件"）。
##
## **设计要点**（SOLID）：
##   - SRP：仅做求值；不读 csv（委托 ConfigCenter）、不知道 UI、不发信号
##   - OCP：新增 Type = 在 [method _eval_one] 加 1 个 match 分支；调用方零变更
##   - DIP：调用方传 cond_id；Evaluator 不知道是 NPC 选项、对话分支还是商店在用
##   - DRY：所有"过滤显示"逻辑统一走 [method eval]，不再复制条件判断代码
##
## **失败语义**（R-CODE-01）：
##   - 未知 Type → assert 崩（配置错误，启动期暴露）
##   - 配置缺玩家 / 缺 QuestSystem → 返回 false（fail-safe，避免显示了不该显示的选项）
##
## 静态工具类，请勿 new。
class_name ConditionEvaluator
extends RefCounted

# Type 常量（与 Condition.csv 的 Type 列字符串对齐）
const TYPE_LEV: StringName                          = &"Lev"
const TYPE_QUEST_ONGOING: StringName                = &"Quest_Ongoing"
const TYPE_QUEST_FINISHED: StringName               = &"Quest_Finished"
const TYPE_QUEST_PENDING_DELIVER: StringName        = &"Quest_PendingDeliver"
const TYPE_QUEST_STEP_PENDING_DELIVER: StringName   = &"Quest_StepPendingDeliver"


## 求值入口。cond_id <= 0 → true（无条件）；找不到也 → true。
##
## 同 cond_id 内所有子条件 AND 组合（短路，第一个 false 直接返回）。
static func eval(cond_id: int) -> bool:
	if cond_id <= 0:
		return true
	var entries: Array = ConfigCenter.get_condition_set(cond_id)
	if entries.is_empty():
		return true  # 未配置视为"无条件"
	for e in entries:
		if not _eval_one(e, cond_id):
			return false  # AND 短路
	return true


# ─────────────────────────────────────────────────────────────
# 内部 · 单条子条件求值
# ─────────────────────────────────────────────────────────────


## 单条子条件求值。失败语义见类头。
##
## [param e]：sub_entries 中的一行 dict { sub_id, Type, Param }
## [param cond_id]：用于打错日志时定位
static func _eval_one(e: Dictionary, cond_id: int) -> bool:
	var t: StringName = CsvLoader.as_string_name(e, "Type")
	var p: int = CsvLoader.as_int(e, "Param", 0)
	match t:
		TYPE_LEV:
			return _player_level() >= p
		TYPE_QUEST_ONGOING:
			return _is_quest_ongoing(p)
		TYPE_QUEST_FINISHED:
			return _is_quest_finished(p)
		TYPE_QUEST_PENDING_DELIVER:
			return _is_quest_pending_deliver(p)
		TYPE_QUEST_STEP_PENDING_DELIVER:
			# Param 编码：quest_id * 100 + sub_id（如 101 = q=1 sub=1）
			# sub_id 范围 1-99 够用；如未来超过 99 步可改 1000 进制（同步改 Excel 文档）
			var qid: int = p / 100
			var sid: int = p % 100
			if qid <= 0 or sid <= 0:
				return false
			return _is_step_pending_deliver(qid, sid)
		_:
			assert(false, "ConditionEvaluator: unknown Type='%s' at cond_id=%d sub_id=%s" % [
				t, cond_id, str(e.get("sub_id", "?"))])
			return false


# ─────────────────────────────────────────────────────────────
# 内部 · 桥接 · 玩家等级
# ─────────────────────────────────────────────────────────────


## 取玩家当前等级。fail-safe 返回 1。
##
## 来源优先级：BaseCharacter.level_override（>0 时） → Hero_Data.level → 1
##
## TODO（Phase 4+ 等级体系成熟时）：抽 LevelService.get_player_level() 统一收口。
static func _player_level() -> int:
	var player: PlayerCharacter = PlayerLocator.find_player_global()
	if player == null:
		return 1
	if player.level_override > 0:
		return player.level_override
	# Hero_Data 暂未携带 level 字段（仅 attr_id），返回 1 作 fail-safe
	return 1


# ─────────────────────────────────────────────────────────────
# 内部 · 桥接 · 任务状态查询
# ─────────────────────────────────────────────────────────────
#
# 当前 QuestSystem API 用 StringName quest_id；新表用 int quest_id。
# Phase 4 改造 QuestSystem 时统一改 int；此处先做桥接，避免阻塞 Phase 1 自测。


## 桥接：任务系列 quest_id 是否进行中。
##
## Phase 1 临时实现：通过 QuestSystem 节点（Autoload）调用其方法。
## Phase 4 将 QuestSystem 重写为 int + 添加 is_ongoing/is_finished/is_pending_deliver API 后简化。
static func _is_quest_ongoing(quest_id: int) -> bool:
	var qs: Node = _get_quest_system()
	if qs == null:
		return false
	if qs.has_method("is_quest_ongoing"):
		return qs.call("is_quest_ongoing", quest_id)
	return false


static func _is_quest_finished(quest_id: int) -> bool:
	var qs: Node = _get_quest_system()
	if qs == null:
		return false
	if qs.has_method("is_quest_finished"):
		return qs.call("is_quest_finished", quest_id)
	return false


static func _is_quest_pending_deliver(quest_id: int) -> bool:
	var qs: Node = _get_quest_system()
	if qs == null:
		return false
	if qs.has_method("is_quest_pending_deliver"):
		return qs.call("is_quest_pending_deliver", quest_id)
	# 兼容：Phase 4+ 改名为 is_pending_deliver
	if qs.has_method("is_pending_deliver"):
		return qs.call("is_pending_deliver", quest_id)
	return false


## 桥接：指定 (quest_id, sub_id) 步骤是否处于 PENDING_DELIVER。
##
## 实现方式：直接读 [GameInstance.quest_states] 字典，通过 [QuestSystem.key] 编码的 String key。
## 不调 QuestSystem 方法，避免新增依赖。
static func _is_step_pending_deliver(quest_id: int, sub_id: int) -> bool:
	if not Engine.has_singleton("GameInstance") and not _has_autoload("GameInstance"):
		return false
	var gi: Object = Engine.get_main_loop().root.get_node_or_null(^"GameInstance")
	if gi == null:
		return false
	var states: Dictionary = gi.get(&"quest_states")
	if states == null:
		return false
	var key: String = "q%d.s%d" % [quest_id, sub_id]
	if not states.has(key):
		return false
	var st: Dictionary = states[key]
	# 与 QuestSystem.STATE_PENDING_DELIVER 字面值对齐（StringName "pending_deliver"）
	return st.get(&"state", &"") == &"pending_deliver"


static func _has_autoload(node_name: String) -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	return tree.root.has_node(NodePath(node_name))


## 取 QuestSystem 单例节点（Autoload）。无则返回 null（fail-safe）。
static func _get_quest_system() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(^"QuestSystem")
