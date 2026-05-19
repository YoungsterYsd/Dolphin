## AI 状态抽象基类。
##
## 子类重写 [method enter] / [method exit] / [method tick] / [method on_event]。
## 状态切换通过 [method change]，由具体子类调用。
class_name AIState
extends RefCounted

## 持有此状态的 AIController。
var ctrl: AIController = null

## 状态名（调试用，子类构造时设置）。
var state_name: StringName = &"unnamed"


## 进入本状态时调用。
func enter() -> void:
	pass


## 退出本状态时调用。
func exit() -> void:
	pass


## 物理帧驱动（由 AIController 转发）。
func tick(_delta: float) -> void:
	pass


## 接收事件（如 took_damage / death_triggered / target_lost）。
func on_event(_event_name: StringName, _payload = null) -> void:
	pass


## 工具：请求切换到另一状态。
func change(next_state_name: StringName) -> void:
	if ctrl != null:
		ctrl.change_state(next_state_name)
