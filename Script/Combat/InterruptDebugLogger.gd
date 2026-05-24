## 硬度打断系统验收用调试日志器（PR1 验收期使用，可后续删除）。
##
## 订阅 [signal EventBus.character_interrupted] / [signal EventBus.ability_interrupted]，
## 把每次打断 / 被打断的事件打到：
## 1. [GameLogger] info（控制台 + 日志文件）
## 2. [signal EventBus.hud_toast_requested]（屏幕右上角飘字 2s）
##
## 用法：在场景脚本（如 [code]test_arena.gd[/code]）的 [code]_ready[/code] 加一行：
## [codeblock]
## InterruptDebugLogger.install()
## [/codeblock]
##
## 设计：单例（Autoload-like）；首次 install 时把 Node 挂到 SceneTree.root 下永久订阅；
## 重复 install 直接返回。
class_name InterruptDebugLogger
extends Node

const _LOG_CH := "Combat"
static var _instance: InterruptDebugLogger = null


## 安装单例并订阅 EventBus 信号。
##
## 重复调用安全：第二次 install 直接返回（不重复 connect）。
static func install() -> void:
	if _instance != null and is_instance_valid(_instance):
		return
	_instance = InterruptDebugLogger.new()
	_instance.name = "InterruptDebugLogger"
	# 挂在 SceneTree.root 下，跨场景常驻
	var root: Window = Engine.get_main_loop().root
	root.add_child(_instance)
	GameLogger.info(_LOG_CH, "InterruptDebugLogger installed (subscribe character_interrupted / ability_interrupted)")


func _ready() -> void:
	# R-EVENT-02：named method 订阅
	EventBus.character_interrupted.connect(_on_character_interrupted)
	EventBus.ability_interrupted.connect(_on_ability_interrupted)


func _on_character_interrupted(target: Node, attacker: Node, impact_level: int) -> void:
	if not is_instance_valid(target):
		return
	var t_name: String = target.name if is_instance_valid(target) else "?"
	var a_name: String = attacker.name if is_instance_valid(attacker) else "?"
	var msg: String = "[%s] 被 [%s] 打断 impact=%d" % [t_name, a_name, impact_level]
	GameLogger.info(_LOG_CH, "[DBG] " + msg)
	EventBus.hud_toast_requested.emit(msg, 2.0)


func _on_ability_interrupted(owner_node: Node, ability_id: StringName) -> void:
	if not is_instance_valid(owner_node):
		return
	var n: String = owner_node.name if is_instance_valid(owner_node) else "?"
	var msg: String = "[%s] GA[%s] 被中止" % [n, ability_id]
	GameLogger.info(_LOG_CH, "[DBG] " + msg)
	# ability_interrupted 不发 toast 避免与 character_interrupted 重复弹（character_interrupted 后紧接着也会 emit ability_ended）
