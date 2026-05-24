## HUD 状态机（Autoload 单例）。
##
## 9 个全局状态（与游戏顶层状态联动）：
##   BOOT / MAIN_MENU / GAMEPLAY / PAUSED / PANEL_OPEN /
##   DIALOGUE / CUTSCENE / DEAD / LEVEL_TRANSITION
##
## 与 [GameInstance.GameState]（5 状态）的映射：
##   GameInstance.BOOT      → HUD.BOOT
##   GameInstance.MENU      → HUD.MAIN_MENU
##   GameInstance.PLAYING   → HUD.GAMEPLAY
##   GameInstance.PAUSED    → HUD.PAUSED
##   GameInstance.GAME_OVER → HUD.DEAD
##
## 其余 4 个状态（PANEL_OPEN / DIALOGUE / CUTSCENE / LEVEL_TRANSITION）
## 是 HUD 内部子状态（不污染 GameInstance），由具体 widget / 流程主动调
## [method change_state] 进入。
##
## 切换三阶段：
##   1) Exit 旧状态：清空对应层 + 还原 InputContext + 还原 process_mode
##   2) Enter 新状态：push 对应 InputContext / 设置层可见性 / 必要时切 GameInstance
##   3) emit [signal EventBus.hud_state_changed]
##
## R-VERIFY-01：本节点 Phase 1 仅做骨架；具体「打开背包 → push PANEL_OPEN」
## 等行为在 Phase 2 widget 迁移时具化。
extends Node


## HUD 顶层状态。
enum State {
	BOOT,
	MAIN_MENU,
	GAMEPLAY,
	PAUSED,
	PANEL_OPEN,
	DIALOGUE,
	CUTSCENE,
	DEAD,
	LEVEL_TRANSITION,
}


# ─────────────────────────────────────────────────────────────
# 字段
# ─────────────────────────────────────────────────────────────

var _current_state: int = State.BOOT

## 状态 -> InputContext 资源路径（按需加载，避免启动开销）。
const _STATE_TO_CONTEXT: Dictionary = {
	State.BOOT:             "",  # 不切（默认 Gameplay）
	State.MAIN_MENU:        "res://Data/Config/InputContexts/PanelOpen.tres",
	State.GAMEPLAY:         "",  # 不切（恢复默认）
	State.PAUSED:           "res://Data/Config/InputContexts/PanelOpen.tres",
	State.PANEL_OPEN:       "res://Data/Config/InputContexts/PanelOpen.tres",
	State.DIALOGUE:         "res://Data/Config/InputContexts/Dialogue.tres",
	State.CUTSCENE:         "res://Data/Config/InputContexts/Cutscene.tres",
	State.DEAD:             "res://Data/Config/InputContexts/Dead.tres",
	State.LEVEL_TRANSITION: "res://Data/Config/InputContexts/Cutscene.tres",
}

## 当前状态压栈了几层 InputContext（用于 Exit 时正确 pop）。
## 0 = 未压栈；>0 = 退出时需 pop 该数量。
var _pushed_context_count: int = 0


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 监听 GameInstance 状态变化 → 自动同步本状态机
	EventBus.game_state_changed.connect(_on_game_state_changed)
	GameLogger.info("UI", "HUDStateMachine ready (current=%s)" % state_name(_current_state))


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 切换到目标状态。同状态调用静默忽略。
func change_state(new_state: int) -> void:
	if new_state == _current_state:
		return
	var old_state := _current_state
	# Exit 旧状态
	_exit_state(old_state)
	# Enter 新状态
	_current_state = new_state
	_enter_state(new_state)
	# 广播
	EventBus.hud_state_changed.emit(old_state, new_state)
	GameLogger.info("UI", "HUDStateMachine state: %s -> %s" % [state_name(old_state), state_name(new_state)])


## 当前状态。
func get_current_state() -> int:
	return _current_state


## 状态名（debug）。
func state_name(s: int) -> String:
	match s:
		State.BOOT: return "BOOT"
		State.MAIN_MENU: return "MAIN_MENU"
		State.GAMEPLAY: return "GAMEPLAY"
		State.PAUSED: return "PAUSED"
		State.PANEL_OPEN: return "PANEL_OPEN"
		State.DIALOGUE: return "DIALOGUE"
		State.CUTSCENE: return "CUTSCENE"
		State.DEAD: return "DEAD"
		State.LEVEL_TRANSITION: return "LEVEL_TRANSITION"
		_: return "UNKNOWN(%d)" % s


# ─────────────────────────────────────────────────────────────
# 内部：状态进入 / 退出
# ─────────────────────────────────────────────────────────────

func _enter_state(s: int) -> void:
	# 1) 切 InputContext（如有）
	var ctx_path: String = _STATE_TO_CONTEXT.get(s, "")
	if ctx_path != "":
		var icm: Node = Engine.get_main_loop().root.get_node_or_null(^"InputContextManager")
		if icm != null and ResourceLoader.exists(ctx_path):
			var ctx: Resource = load(ctx_path)
			icm.push(ctx)
			_pushed_context_count = 1
	# 2) Phase 1 骨架：层 push 由具体 widget 流程主动调，此处不主动 push
	#    （Phase 2 接入暂停菜单 / 背包等 widget 时具化 _enter_panel_open / _enter_paused 等）


func _exit_state(s: int) -> void:
	# 1) 还原 InputContext
	if _pushed_context_count > 0:
		var icm: Node = Engine.get_main_loop().root.get_node_or_null(^"InputContextManager")
		if icm != null:
			for i in _pushed_context_count:
				icm.pop()
		_pushed_context_count = 0


# ─────────────────────────────────────────────────────────────
# 与 GameInstance 联动
# ─────────────────────────────────────────────────────────────

func _on_game_state_changed(_old: int, new_state: int) -> void:
	# GameInstance 5 状态映射 HUD 状态
	var target := -1
	if Engine.has_singleton("GameInstance"):
		# 不直接依赖 GameInstance.GameState 枚举值，按 int 直接映射
		pass
	# 直接按 GameInstance.gd 的 enum 顺序：0=BOOT 1=MENU 2=PLAYING 3=PAUSED 4=GAME_OVER
	match new_state:
		0: target = State.BOOT
		1: target = State.MAIN_MENU
		2: target = State.GAMEPLAY
		3: target = State.PAUSED
		4: target = State.DEAD
		_: target = -1
	if target >= 0 and target != _current_state:
		change_state(target)
