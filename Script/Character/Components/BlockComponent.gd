## 格挡组件（D2.D，仅玩家挂载）。
##
## 02 文档 §1.4 / 01 文档 §1.4 锁定的格挡机制：
## - 按住 D 键持续生效；移动 ×0.5（D2.E 接入）
## - 完美格挡：按下 [code]PERFECT_BLOCK_WINDOW[/code](0.3s) 内被击中 → 免伤 + 不耗耐久 + 强化下次攻击 buff
## - 普通格挡：减伤 ×0.4 落地 + 消耗耐久（dmg ×0.6 入耐久消耗）；耗尽 → 1.2s 破防硬直 + 强制松开 D 键
##
## 与 GE 协作：
## - [method start_block] apply [code]GE_BlockState[/code]（granted_tags=[Combat.Block.Active]）
## - [method stop_block] 调 [method AbilitySystemComponent.remove_effects_with_granted_tag]([code]Combat.Block.Active[/code]）
##   主动 detach（不等 GE_BlockState 60s 自然过期）
## - 完美格挡触发时 apply [code]GE_PerfectBlockBuff[/code]（DURATION 5s）
##
## 输入耦合：监听 [signal EventBus.player_input_action_pressed/released] 的 [code]combat_block[/code] action。
class_name BlockComponent
extends Node


## 完美格挡判定窗口（按下后多少秒内挨打 → 完美格挡）。
const PERFECT_BLOCK_WINDOW: float = 0.3

## 当前是否在按住 D 键格挡中。
var _is_blocking: bool = false

## 上次按下 D 键的时刻（秒）。
var _block_pressed_at: float = -1.0


func _ready() -> void:
	EventBus.player_input_action_pressed.connect(_on_input_pressed)
	EventBus.player_input_action_released.connect(_on_input_released)
	# R-ASC：耐久耗尽时 ASC emit block_broken；本组件自己 stop_block（去越权）
	EventBus.block_broken.connect(_on_block_broken)


func _on_block_broken(blocker: Node) -> void:
	if blocker == get_parent():
		stop_block()


# ─────────────────────────────────────────────────────────────
# 输入回调
# ─────────────────────────────────────────────────────────────

func _on_input_pressed(action: StringName) -> void:
	if action == &"combat_block":
		start_block()


func _on_input_released(action: StringName) -> void:
	if action == &"combat_block":
		stop_block()


# ─────────────────────────────────────────────────────────────
# 公开 API（也供 DamagePipeline 第 7 步调用）
# ─────────────────────────────────────────────────────────────

func start_block() -> void:
	if _is_blocking:
		return
	var asc := _get_asc()
	# 破防硬直期间不允许按格挡
	if asc != null and asc.has_tag(&"Combat.Block.Broken"):
		return
	_is_blocking = true
	_block_pressed_at = Time.get_ticks_msec() / 1000.0
	# apply GE_BlockState（granted_tags=[Combat.Block.Active]）
	if asc != null:
		var ge: GameplayEffect = _get_ge(&"BlockState")
		if ge != null:
			asc.apply_effect_to(asc, ge, get_parent())
	GameLogger.info("Combat", "[%s] start_block" % _owner_name())


func stop_block() -> void:
	if not _is_blocking:
		return
	_is_blocking = false
	var asc := _get_asc()
	if asc != null:
		# 重构 R1：使用 ASC 公共 API，不再 _detach_active 越权
		asc.remove_effects_with_granted_tag(&"Combat.Block.Active")
	GameLogger.info("Combat", "[%s] stop_block" % _owner_name())


## 由 DamagePipeline 第 7 步调用：是否在完美格挡判定窗口内。
func is_perfect_block_window() -> bool:
	if not _is_blocking:
		return false
	return (Time.get_ticks_msec() / 1000.0 - _block_pressed_at) <= PERFECT_BLOCK_WINDOW


## 由 DamagePipeline 第 7 步调用：完美格挡触发时 apply GE_PerfectBlockBuff。
func trigger_perfect_block_buff() -> void:
	var asc := _get_asc()
	if asc == null:
		return
	var ge: GameplayEffect = _get_ge(&"PerfectBlockBuff")
	if ge != null:
		asc.apply_effect_to(asc, ge, get_parent())
		EventBus.block_perfect_triggered.emit(get_parent())
		GameLogger.info("Combat", "[%s] PERFECT BLOCK BUFF applied (5s)" % _owner_name())


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _get_asc() -> AbilitySystemComponent:
	var parent := get_parent()
	if parent == null:
		return null
	# BaseCharacter.asc 已是强类型 AbilitySystemComponent
	if &"asc" in parent:
		return parent.get(&"asc") as AbilitySystemComponent
	return null


func _get_ge(ge_id: StringName) -> GameplayEffect:
	return ConfigCenter.get_ge(ge_id)


func _owner_name() -> String:
	var p := get_parent()
	return p.name if p != null else "?"
