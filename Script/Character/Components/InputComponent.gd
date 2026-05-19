## 输入组件（玩家专用）。
##
## 读取 InputMap 输出方向与按键事件。其他组件通过本节点信号订阅。
## R-CHAR-01：输出 Vector3（XY 平面方向）。
##
## 实现：
##   - 移动方向：每物理帧 Input.get_axis 广播
##   - 离散按键（ability_1 / ability_2 / interact）：每帧 Input.is_action_just_pressed 边沿检测
##     不依赖事件传递（_input/_unhandled_input），避免 Control 节点拦截
##   - pause：由 GameInstance Autoload 接管（不在本组件处理）
class_name InputComponent
extends Node

## 输入方向变化（每物理帧广播；Vector3.x/y 为平面方向）。
signal input_dir_changed(dir: Vector3)

## 技能按键（ability_1 / ability_2）按下。
signal ability_pressed(slot: int)

## 交互键按下。
signal interact_pressed()

@export var enabled: bool = true


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	var x := Input.get_axis(&"move_left", &"move_right")
	var y := Input.get_axis(&"move_up", &"move_down")
	input_dir_changed.emit(Vector3(x, y, 0.0))


func _process(_delta: float) -> void:
	if not enabled:
		return
	if Input.is_action_just_pressed(&"ability_1"):
		ability_pressed.emit(1)
	if Input.is_action_just_pressed(&"ability_2"):
		ability_pressed.emit(2)
	if Input.is_action_just_pressed(&"interact"):
		interact_pressed.emit()
