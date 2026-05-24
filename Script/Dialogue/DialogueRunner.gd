## 对话执行引擎（Autoload 单例）。
##
## 业务侧通过 [method start] 启动对话；UI / 业务侧通过 [method advance] / [method select_choice]
## 推进；通过 [method force_end] 强制中断。
##
## 状态机：
##   IDLE → RUNNING（start 后） → IDLE（end 或 force_end）
##
## 与 HUD 系统协同（R-DLG-02 / R-DLG-03）：
##   - start 时调 HUDStateMachine.change_state(DIALOGUE)，**自动** push Dialogue InputContext
##   - end 时调 HUDStateMachine.change_state(GAMEPLAY)，**自动** pop InputContext
##   - DialogueWidget 由 UIExtensionSubsystem 注册到 HUDLayout（不在本 Runner 内实例化，避免耦合）
##
## **M12 重构**（A1 决策：对话纯解耦）：
##   - DialogueRunner **不再调用** EffectHandler、不知道任务/商店等业务系统
##   - 业务侧（QuestSystem / ShopSystem / 未来 TeleportSystem 等）订阅 [signal EventBus.dialogue_ended]
##     自行处理（按 graph_id 反查匹配自己的"接取/交付/触发"配置）
##   - 节点种类只剩 SpeechNode / ChoiceNode；EffectNode 已移除
##
## **设计原则**（SOLID）：
##   - SRP：仅播对话 + 发信号；不知道 NPC、不读 csv（委托 ConfigCenter）、不评条件（委托 ConditionEvaluator）
##   - OCP：未来加传送/cutscene/小游戏 = 新增 Autoload + 订阅 dialogue_ended；不改本类
extends Node

# ─────────────────────────────────────────────────────────────
# 状态
# ─────────────────────────────────────────────────────────────

var _current_graph: DialogueGraph = null
var _current_node: DialogueNode = null
var _current_npc_id: int = 0  # 当前对话关联的 NPC（仅做信号载荷，不在内部判断）
var _is_running: bool = false

## 当前 ChoiceNode 过滤后的可见选项（用于 select_choice 索引校验）。
var _current_filtered_options: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameLogger.info("Dialogue", "DialogueRunner ready")


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 启动一段对话。已在运行时静默忽略（warn + return）。
##
## [param graph_id]：对话图 ID（[code]Dialogue.id[/code]）。
## [param npc_id]：当前关联的 NPC（[code]NPC_Data.id[/code]，<=0 表示无关联，仅做信号载荷）。
func start(graph_id: int, npc_id: int = 0) -> void:
	if _is_running:
		var cur_id: int = _current_graph.graph_id if _current_graph else 0
		GameLogger.warn("Dialogue", "start: already running graph=%d, ignored new=%d" % [cur_id, graph_id])
		return
	# R-ARCH-03：ConfigCenter 直访
	var graph: DialogueGraph = ConfigCenter.get_dialogue_graph(graph_id)
	if graph == null:
		GameLogger.error("Dialogue", "start: graph not found: %d" % graph_id)
		return
	_current_graph = graph
	_current_npc_id = npc_id
	_is_running = true
	# 切到 DIALOGUE 状态（自动 push InputContext.Dialogue；R-ARCH-03 + R-CODE-02 强类型枚举）
	HUDStateMachine.change_state(HUDStateMachine.State.DIALOGUE)
	# 广播开始
	EventBus.dialogue_started.emit(graph_id, npc_id)
	GameLogger.info("Dialogue", "[start] graph=%d npc=%d" % [graph_id, npc_id])
	# 进入入口节点
	_enter_node(graph.start_node_id)


## 推进（SpeechNode 用）。
func advance() -> void:
	if not _is_running or _current_node == null:
		return
	if _current_node.get_node_kind() != &"speech":
		GameLogger.warn("Dialogue", "advance: current node is not speech (kind=%s)" % _current_node.get_node_kind())
		return
	_follow_next_link()


## 选择选项（ChoiceNode 用）。
func select_choice(index: int) -> void:
	if not _is_running or _current_node == null:
		return
	if _current_node.get_node_kind() != &"choice":
		GameLogger.warn("Dialogue", "select_choice: current node is not choice")
		return
	if index < 0 or index >= _current_filtered_options.size():
		GameLogger.warn("Dialogue", "select_choice: index %d out of range (%d options)" \
			% [index, _current_filtered_options.size()])
		return
	var option: ChoiceOption = _current_filtered_options[index]
	GameLogger.info("Dialogue", "[choice] %d: %s -> sub_id=%d" % [index, option.text, option.next_id])
	_enter_node(option.next_id)


## 正常结束（外部 / 节点走完都调这个）。
func end() -> void:
	_end_internal(false)


## 强制中断（玩家死亡 / 关卡切换 / 进入战斗时调）。
## **不**触发 dialogue_ended，仅触发 dialogue_aborted（业务方按需订阅；任务交付不应基于此推进）。
func force_end() -> void:
	_end_internal(true)


## 当前 graph_id（debug）。0 表示未运行。
func get_current_graph_id() -> int:
	return _current_graph.graph_id if _current_graph != null else 0


## 当前 node_id（debug）。
func get_current_node_id() -> int:
	return _current_node.node_id if _current_node != null else 0


## 是否在运行。
func is_running() -> bool:
	return _is_running


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _enter_node(node_id: int) -> void:
	if _current_graph == null:
		end()
		return
	# node_id<=0 视为"结束"（CSV 约定）
	if node_id <= 0:
		end()
		return
	var node: DialogueNode = _current_graph.get_node_by_id(node_id)
	if node == null:
		GameLogger.warn("Dialogue", "_enter_node: node not found: %d (graph=%d)" % [node_id, _current_graph.graph_id])
		end()
		return
	_current_node = node
	EventBus.dialogue_node_changed.emit(node)
	GameLogger.info("Dialogue", "[node] sub_id=%d kind=%s" % [node.node_id, node.get_node_kind()])
	# 按种类分发
	match node.get_node_kind():
		&"speech":
			pass  # 等 advance()
		&"choice":
			var cnode := node as ChoiceNode
			_current_filtered_options = _filter_choices(cnode.choices)
			# 0 个可见选项 → 自动结束（避免卡死）
			if _current_filtered_options.is_empty():
				GameLogger.warn("Dialogue", "_enter_node: choice node has 0 visible options, auto end (sub_id=%d)" % node.node_id)
				end()
				return
			EventBus.dialogue_choice_presented.emit(_current_filtered_options)
		_:
			GameLogger.warn("Dialogue", "_enter_node: unknown kind %s" % node.get_node_kind())
			end()


## 按 next_links 选第一条满足 cond 的推进；全 false → end。
func _follow_next_link() -> void:
	if _current_node == null:
		end()
		return
	for link in _current_node.next_links:
		if link == null:
			continue
		if ConditionEvaluator.eval(link.cond_id):
			_enter_node(link.next_id)
			return
	# 没有可走的 next → 结束
	end()


## 按 cond_id 过滤选项。
func _filter_choices(choices: Array) -> Array:
	var out: Array = []
	for c in choices:
		if c == null:
			continue
		if ConditionEvaluator.eval(c.cond_id):
			out.append(c)
	return out


## 文本占位符解析（{var:x} / {tag:x} / {player_name}）。
## 业务侧（DialogueWidget）渲染前调本方法。
func resolve_text(s: String) -> String:
	if s == "":
		return s
	var out: String = s
	# {var:xxx}
	var re_var := RegEx.new()
	re_var.compile("\\{var:([A-Za-z0-9_\\.]+)\\}")
	for m in re_var.search_all(s):
		var key: String = m.get_string(1)
		var v: Variant = _get_dialogue_vars().get(StringName(key), "")
		out = out.replace(m.get_string(), str(v))
	# {tag:xxx} → "是"/"否"
	var re_tag := RegEx.new()
	re_tag.compile("\\{tag:([A-Za-z0-9_\\.]+)\\}")
	for m in re_tag.search_all(s):
		var tag: StringName = StringName(m.get_string(1))
		var has: bool = _player_has_tag(tag)
		out = out.replace(m.get_string(), "是" if has else "否")
	# {player_name}
	if out.find("{player_name}") >= 0:
		out = out.replace("{player_name}", _get_player_name())
	return out


# ─────────────────────────────────────────────────────────────
# 结束流程
# ─────────────────────────────────────────────────────────────

func _end_internal(forced: bool) -> void:
	if not _is_running:
		return
	var graph_id: int = _current_graph.graph_id if _current_graph != null else 0
	var npc_id: int = _current_npc_id
	GameLogger.info("Dialogue", "[end] graph=%d npc=%d forced=%s" % [graph_id, npc_id, str(forced)])
	# 切回 GAMEPLAY 状态（自动 pop InputContext）
	HUDStateMachine.change_state(HUDStateMachine.State.GAMEPLAY)
	# 清理
	_current_graph = null
	_current_node = null
	_current_npc_id = 0
	_current_filtered_options = []
	_is_running = false
	# 自然结束 → dialogue_ended（业务侧据此推进任务交付等）
	# 强制中断 → dialogue_aborted（业务侧不应据此推进任务）
	if forced:
		EventBus.dialogue_aborted.emit(graph_id, npc_id)
	else:
		EventBus.dialogue_ended.emit(graph_id, npc_id)


# ─────────────────────────────────────────────────────────────
# 工具：文本占位符
# ─────────────────────────────────────────────────────────────

func _get_dialogue_vars() -> Dictionary:
	# R-ARCH-03：GameInstance 是 Autoload，直访
	return GameInstance.dialogue_vars


func _player_has_tag(tag: StringName) -> bool:
	var tags := PlayerLocator.find_player_tags(self)
	if tags == null:
		return false
	return tags.has_tag(tag)


func _get_player_name() -> String:
	# GameInstance 暂无 player_name，从 dialogue_vars 取兜底
	return str(GameInstance.dialogue_vars.get(&"player_name", "Player"))
