## M12 对话/任务/NPC 联调测试场（独立 Demo）。
##
## 用途（按操作流程验收）：
##   ■ 数据驱动 NPC：走近村长 / 铁匠 → 头顶提示 [G] 对话 → 按 G 进入对话
##   ■ 对话纯解耦：对话节点只播文本与分支；任务/商店/传送由各业务系统自行订阅信号
##   ■ 任务链：村长任务 quest_id=1 共 4 个 sub_id 串行
##     - sub=1 收集证物 ×2  → 交付对话 graph=1101 → Drop=2001
##     - sub=2 击杀小怪 A ×3 → 交付对话 graph=1102 → Drop=2002
##     - sub=3 拜访铁匠 ×1   → 交付对话 graph=1103 → Drop=2003
##     - sub=4 击败 BOSS B ×1 → 无交付对话直接完成 → Drop=2004
##
## 操作指引（HUD InfoLabel 显示）：
##   ■ G   → 走近 NPC 后对话
##   ■ Shift+F8 → bulk_accept 任务 quest_id=1（模拟关卡初始化）
##   ■ Shift+F7 → 强制完成当前 active 步骤（自动接下一 sub）
##   ■ F10  → 直接启动村长接任务对话（DialogueRunner.start(1001, 1)）
##   ■ F12  → 强制中断当前对话
##   ■ R    → reload 当前场景
##
## **不含**敌人 AI / Boss 战斗 / 道具拾取 —— 任务推进通过 GM 命令 / 对话信号验证；
## 击杀 / 拾取的端到端验证去 TestArena.tscn / ItemTestArena.tscn。
extends Node3D


## **DEPRECATED → 已替代**：旧版 hard-coded 关卡数据，现在改为读 LevelDef_DialogueTest.tres 模拟 LevelManager.bulk_accept 流程（DRY，与正式关卡走同一路径）。
## 关卡定义路径（直启场景时手动模拟 LevelManager 接取流程）。
const LEVEL_DEF_PATH: String = "res://Data/Levels/LevelDef_DialogueTest.tres"


@onready var camera: CameraRig = $CameraRig as CameraRig
@onready var hud: HUD = $HUDLayer/HUD as HUD
@onready var info_label: Label = $HUDLayer/InfoLabel as Label


func _ready() -> void:
	# 相机跟随 Player
	camera.target = $Player

	# 信息提示（HUD 右上 InfoLabel 已在 .tscn 配好 text；这里只补一段动态确认）
	GameLogger.info("DialogueTest", "DialogueTestArena ready (M12 NPC/对话/任务联调测试)")
	# 简单验证 ConfigCenter 数据可用（数量已在 ConfigCenter bootstrap done 日志里显示，这里不重复）
	var elder: Dictionary = ConfigCenter.get_npc_def(1)
	var smith: Dictionary = ConfigCenter.get_npc_def(2)
	GameLogger.info("DialogueTest", "  - NPC[1]=%s  NPC[2]=%s" % [
		CsvLoader.as_string(elder, "Name", "<missing>"),
		CsvLoader.as_string(smith, "Name", "<missing>"),
	])
	# 订阅任务信号在屏上滚字（便于测试观察）
	EventBus.quest_step_started.connect(_on_step_started)
	EventBus.quest_step_progress.connect(_on_step_progress)
	EventBus.quest_step_pending_deliver.connect(_on_step_pending_deliver)
	EventBus.quest_step_completed.connect(_on_step_completed)
	EventBus.quest_series_completed.connect(_on_series_completed)
	# 订阅对话信号
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)
	# A3 决策：模拟 LevelManager 关卡初始化时调 QuestSystem.bulk_accept(LevelDef.init_quest_ids)。
	# **直启场景的兼容**：正式流程走 LevelManager.load_level → level_changed → bulk_accept；
	# 这里直启场景没经过 LevelManager，所以手动读 LevelDef.tres 复用同一份配置（DRY）。
	call_deferred(&"_simulate_level_init")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_R:
			get_tree().reload_current_scene()


# ─────────────────────────────────────────────────────────────
# 信号回调（GM Toast 而非 print；让 HUD 能直观看到推进）
# ─────────────────────────────────────────────────────────────

func _on_step_started(quest_id: int, sub_id: int) -> void:
	GameLogger.info("DialogueTest", "[STEP STARTED] q=%d sub=%d" % [quest_id, sub_id])


func _on_step_progress(quest_id: int, sub_id: int, current: int, target: int) -> void:
	GameLogger.info("DialogueTest", "[STEP PROGRESS] q=%d sub=%d %d/%d" % [quest_id, sub_id, current, target])


func _on_step_pending_deliver(quest_id: int, sub_id: int) -> void:
	GameLogger.info("DialogueTest", "[STEP PENDING DELIVER] q=%d sub=%d → 回去汇报" % [quest_id, sub_id])


func _on_step_completed(quest_id: int, sub_id: int) -> void:
	GameLogger.info("DialogueTest", "[STEP COMPLETED] q=%d sub=%d" % [quest_id, sub_id])


func _on_series_completed(quest_id: int) -> void:
	GameLogger.info("DialogueTest", "[SERIES COMPLETED] q=%d  ★全部完成★" % quest_id)


func _on_dialogue_started(graph_id: int, npc_id: int) -> void:
	GameLogger.info("DialogueTest", "[DLG STARTED] graph=%d npc=%d" % [graph_id, npc_id])


func _on_dialogue_ended(graph_id: int, npc_id: int) -> void:
	GameLogger.info("DialogueTest", "[DLG ENDED] graph=%d npc=%d" % [graph_id, npc_id])


# ─────────────────────────────────────────────────────────────
# 关卡初始化模拟（A3）
# ─────────────────────────────────────────────────────────────

## 直启场景时手动模拟 LevelManager 流程：读 LevelDef.tres → bulk_accept(init_quest_ids)。
##
## DRY：与 LevelManager._run_load 内的 bulk_accept 走完全相同的数据路径，
## 改 LevelDef.tres 即可同时影响"正式 LevelManager 加载"和"直启场景调试"两条流程。
func _simulate_level_init() -> void:
	if not ResourceLoader.exists(LEVEL_DEF_PATH):
		GameLogger.warn("DialogueTest", "LevelDef not found: %s" % LEVEL_DEF_PATH)
		return
	var level_def: LevelDef = load(LEVEL_DEF_PATH) as LevelDef
	if level_def == null:
		GameLogger.warn("DialogueTest", "LevelDef load failed: %s" % LEVEL_DEF_PATH)
		return
	if level_def.init_quest_ids.size() == 0:
		GameLogger.info("DialogueTest", "LevelDef has no init_quest_ids; skip bulk_accept")
		return
	var quest_arr: Array = []
	for qid in level_def.init_quest_ids:
		quest_arr.append(int(qid))
	QuestSystem.bulk_accept(quest_arr)
	GameLogger.info("DialogueTest", "[level init] simulated bulk_accept: %s" % str(quest_arr))
