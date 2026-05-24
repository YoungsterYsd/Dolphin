## 连击跟踪器（Autoload 单例）。
##
## 监听 [signal EventBus.damage_dealt_v2]（仅当 source 为玩家时计数），
## 累计 combo 计数；若 [member window_seconds] 内未再触发，自动清零并派发 combo_changed(0)。
##
## 派发 [signal EventBus.combo_changed]：
##   - 每次玩家造成有效伤害时 +1，立刻派发新 count
##   - 超时清零时派发 0
##
## 注：source 是否为玩家通过节点 group "player" 判定，避免与业务类强耦合（R-HUD-02）。
##     业务侧只需保证玩家 Character 加入了 "player" group（PlayerCharacter 已在 _ready 自加）。
extends Node

## 连击窗口（秒）。在此时间内未再次造成伤害则清零。
const DEFAULT_WINDOW_SECONDS: float = 2.0

var window_seconds: float = DEFAULT_WINDOW_SECONDS
var _count: int = 0
var _timer: SceneTreeTimer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.damage_dealt_v2.connect(_on_damage_dealt)
	GameLogger.info("UI", "ComboTracker ready (window=%.1fs)" % window_seconds)


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 当前连击数。
func get_count() -> int:
	return _count


## 立刻清零（外部如「玩家死亡」时可调）。
func reset() -> void:
	if _count == 0:
		return
	_count = 0
	_timer = null
	EventBus.combo_changed.emit(0)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _on_damage_dealt(source: Node, _target: Node, _amount: float, _damage_node: Resource, _is_crit: bool) -> void:
	if source == null or not source.is_in_group(&"player"):
		return
	_count += 1
	EventBus.combo_changed.emit(_count)
	# 重置计时器
	_timer = get_tree().create_timer(window_seconds)
	_timer.timeout.connect(_on_timer_timeout.bind(_timer))


func _on_timer_timeout(t: SceneTreeTimer) -> void:
	# 仅当回调来自最近一次启动的 timer 时才清零
	if t != _timer:
		return
	if _count == 0:
		return
	_count = 0
	_timer = null
	EventBus.combo_changed.emit(0)
