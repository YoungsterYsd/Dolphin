## 冻帧主机（挂在 GameInstance 子节点）。
##
## 订阅 [signal EventBus.skill_event_hit_stop]，把 [member Engine.time_scale] 临时设为 0
## 实现"打击瞬间凝滞感"。冻结 N 毫秒后用 [SceneTreeTimer] 恢复 1.0。
##
## 关键点：
##   - 本节点 [code]process_mode = ALWAYS[/code]，避免 time_scale=0 时自身 _process 也被冻结
##   - 用 `get_tree().create_timer(.., process_always=true, process_in_physics=false, ignore_time_scale=true)`
##     的 `ignore_time_scale=true` 确保恢复回调能在 time_scale=0 期间触发
##   - 同时多次冻帧请求：取最大剩余时长（不叠加），避免反复变更 time_scale
class_name HitStopHost
extends Node

# 当前冻帧剩余秒数；> 0 表示正在冻帧
var _remaining: float = 0.0
# 是否已 hook（防止重复连接）
var _hooked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _hooked:
		EventBus.skill_event_hit_stop.connect(_on_hit_stop)
		_hooked = true
	GameLogger.info("Skill", "HitStopHost ready")


## 直接冻帧 N 毫秒（外部代码也可以调用，不强制走 EventBus）。
func freeze(duration_ms: float) -> void:
	if duration_ms <= 0.0:
		return
	var dur_s: float = duration_ms * 0.001
	# 取最大剩余而非累加（防止连击多个 hit_stop 累成长时间冻帧）
	if dur_s <= _remaining:
		return
	_remaining = dur_s
	Engine.time_scale = 0.0
	# 用 ignore_time_scale 的 timer 触发恢复，否则 time_scale=0 时 timer 不会推进
	var timer := get_tree().create_timer(dur_s, true, false, true)
	timer.timeout.connect(_on_timer_done.bind(_remaining))
	GameLogger.info("Skill", "HitStop freeze %.0fms" % duration_ms)


# 信号回调
func _on_hit_stop(duration_ms: float, _caster: Node) -> void:
	freeze(duration_ms)


func _on_timer_done(scheduled_remaining: float) -> void:
	# 仅当 _remaining 仍是创建 timer 时记录的值，才恢复（避免被后续更长冻帧覆盖时误恢复）
	if not is_equal_approx(scheduled_remaining, _remaining):
		return
	Engine.time_scale = 1.0
	_remaining = 0.0
	GameLogger.info("Skill", "HitStop release")
