## 玩家输入控制器（挂在 PlayerCharacter 子节点）。
##
## 职责：
##   - 把 InputMap 的 11 个 combat_* + ui_panel_build action 桥接到 EventBus 信号
##   - 移动向量变化（move_*）每物理帧 emit 一次
##   - 暂停 / 死亡 / 黑屏期间通过 process_mode = INHERIT 自动停（玩家分支被 paused）
##
## 不负责：
##   - 移动方向 → MoveComponent 的连接（仍由 InputComponent 负责，本控制器只做"广播"）
##   - ui_pause（由 GameInstance Autoload 全局接管，不在此处）
##   - 闪避/格挡的业务信号（dodge/block 后续作为 GA 实装；本控制器只 emit player_input_action_pressed）
##
## R-INPUT-01：InputMap action 名 ↔ 业务事件解耦走 EventBus.player_input_action_pressed。
##
## 参考：Plans/Dolphin设计/01_战斗框架_输入映射_Dolphin适配.md §2.2 / §2.4
class_name InputController
extends Node

## 监听的离散按键 action（pressed/released 都广播）。
const WATCHED_ACTIONS: Array[StringName] = [
	&"combat_attack",
	&"combat_skill_q",
	&"combat_skill_w",
	&"combat_skill_e",
	&"combat_skill_r",
	&"combat_ultimate",
	&"combat_dodge",
	&"combat_block",
	&"combat_swap",
	&"combat_interact",
	&"combat_consumable",
	&"ui_panel_build",
]

## 启用开关。设为 false 时停止广播任何信号（不影响 InputMap 本身）。
@export var enabled: bool = true

# 上一次广播的移动向量，用于差分
var _last_move_vec: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Pausable：tree paused 时本节点不再 _process / _physics_process / _unhandled_input
	process_mode = Node.PROCESS_MODE_PAUSABLE
	GameLogger.info("Input", "InputController ready (watched=%d)" % WATCHED_ACTIONS.size())


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	for action in WATCHED_ACTIONS:
		if event.is_action_pressed(action, false, true):  # allow_echo=false, exact_match=true
			if not _is_allowed(action):
				continue
			EventBus.player_input_action_pressed.emit(action)
		elif event.is_action_released(action, true):
			if not _is_allowed(action):
				continue
			EventBus.player_input_action_released.emit(action)


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	var v := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if not v.is_equal_approx(_last_move_vec):
		_last_move_vec = v
		EventBus.player_move_vector_changed.emit(v)


# ─────────────────────────────────────────────────────────────
# 鉴权（R-INPUT-02）
# ─────────────────────────────────────────────────────────────
## 通过 InputContextManager 鉴权当前 action 是否允许派发。
## 兜底：若 Manager 不可用（早期启动 / 单元测试），全部允许。
func _is_allowed(action: StringName) -> bool:
	var icm: Node = Engine.get_main_loop().root.get_node_or_null(^"InputContextManager")
	if icm == null:
		return true
	return icm.is_action_allowed(action)
