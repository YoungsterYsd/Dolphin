## 交互提示 widget（NPC 头顶 / 物体上方显示「[G] 对话」）。
##
## 订阅 [signal EventBus.interaction_target_entered] / [signal EventBus.interaction_target_left]
## 自动显隐；每帧用 [WorldProjector] 把 3D 锚点投到屏幕坐标。
##
## 仅追踪当前 [InteractableTarget]（同时只显示 1 个提示；多目标场景由 PlayerCharacter
## 选最近的派发 entered 信号）。
class_name InteractionPromptWidget
extends BaseWidget

@onready var label: Label = $Label

var _current_target: Node = null


func _ready() -> void:
	super._ready()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.interaction_target_entered.connect(_on_target_entered)
	EventBus.interaction_target_left.connect(_on_target_left)
	# 对话开始时强制隐藏（避免和对话框重叠）—— 走 named method 让 Godot 4 在本节点 free 时自动 disconnect
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)
	set_process(false)


func _on_dialogue_started(_g: int, _npc_id: int) -> void:
	_hide()


func _on_dialogue_ended(_g: int, _npc_id: int) -> void:
	_refresh_after_dialogue()


func _process(_delta: float) -> void:
	if _current_target == null or not is_instance_valid(_current_target):
		_hide()
		return
	# 投影到屏幕
	var anchor: Vector3
	if _current_target.has_method(&"get_prompt_anchor"):
		anchor = _current_target.call(&"get_prompt_anchor")
	else:
		anchor = (_current_target as Node3D).global_position + Vector3.UP * 1.8
	var screen_pos: Vector2 = WorldProjector.project_pos(anchor, get_viewport())
	if screen_pos == Vector2.INF:
		visible = false
		return
	visible = true
	# 居中显示
	position = screen_pos - Vector2(label.size.x * 0.5, label.size.y + 4)


func _on_target_entered(target: Node) -> void:
	_current_target = target
	if target.has_method(&"is_interactable") and not bool(target.call(&"is_interactable")):
		return
	var prompt: String = "[G] 交互"
	if target.has_method(&"get") and target.get(&"prompt_text") != null:
		prompt = String(target.get(&"prompt_text"))
	var dn: String = ""
	if target.has_method(&"get") and target.get(&"display_name") != null:
		dn = String(target.get(&"display_name"))
	label.text = "%s\n%s" % [dn, prompt] if dn != "" else prompt
	visible = true
	set_process(true)


func _on_target_left(target: Node) -> void:
	if _current_target == target:
		_hide()


func _refresh_after_dialogue() -> void:
	# 对话结束后，若玩家仍在范围内（PlayerCharacter 会再次 emit entered），
	# 这里不做特殊处理；等下一次 entered 信号即可
	pass


func _hide() -> void:
	_current_target = null
	visible = false
	set_process(false)
