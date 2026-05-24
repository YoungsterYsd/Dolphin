## NPC 对话菜单 widget（M12 Phase 3.5）。
##
## 职责（A6 决策落地）：
##   - 订阅 [signal EventBus.npc_dialogue_menu_requested]：当 NPCActor 检测到 ≥2 个可见 Diapack 选项时，
##     此 Widget 弹出菜单按钮列表
##   - 玩家点击选项 → 关闭菜单 + 调 [DialogueRunner.start(graph_id, npc_id)] 进入对应对话
##   - ESC / ui_cancel → 关闭菜单（不进入任何对话）
##
## **设计原则**（SOLID）：
##   - SRP：仅做"菜单渲染 + 选项点击 → 启动对话"；不读 csv、不评条件（NPCActor 已过滤好选项）
##   - DIP：通过信号订阅获取数据，不主动反查 NPCActor / NPCDialogueService
##   - 与 DialogueWidget 互斥：菜单关闭后才会启动对话；对话期间菜单不会出现（HUDStateMachine.DIALOGUE 状态保护）
##
## 视觉：复用 DialogueWidget 的半透明黑底 + 居中 VBox 风格。
##
## 输入：
##   - 鼠标点击按钮：选项触发
##   - ESC：取消菜单（与 DialogueWidget Esc force_end 同模式）
class_name NPCDiapackMenuWidget
extends BaseWidget


@onready var bg: ColorRect = $BG
@onready var title_label: Label = $Panel/VBox/Title
@onready var options_vbox: VBoxContainer = $Panel/VBox/Options


# 当前菜单的 npc_id（点击选项时记录，用于传给 DialogueRunner.start）
var _current_npc_id: int = 0
# 选项按钮列表（供清理用）
var _option_buttons: Array[Button] = []


func _ready() -> void:
	super._ready()
	visible = false
	modulate.a = 0.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 订阅 NPC 菜单请求
	EventBus.npc_dialogue_menu_requested.connect(_on_menu_requested)
	# Mount 完成后 reparent 到 L2_GameMenu 层（与 DialogueWidget 同层；避免被 hotbar / 血条等遮挡）
	call_deferred(&"_relocate_to_dialog_layer")


## 把 widget 重新挂到 L2_GameMenu 层（DRY：与 DialogueWidget._relocate_to_dialog_layer 同模式）。
func _relocate_to_dialog_layer() -> void:
	var hm: Node = Engine.get_main_loop().root.get_node_or_null(^"HUDManager")
	if hm == null or not hm.has_method(&"get_layer"):
		return
	var layer: Node = hm.call(&"get_layer", &"L2_GameMenu")
	if layer == null:
		GameLogger.warn("UI", "[NPCDiapackMenuWidget] L2_GameMenu not found, keep current parent")
		return
	if get_parent() == layer:
		return
	reparent(layer, false)
	GameLogger.info("UI", "[NPCDiapackMenuWidget] relocated to L2_GameMenu")


# ─────────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────────

func _on_menu_requested(npc_id: int, options: Array) -> void:
	if options.is_empty():
		return
	# DialogueRunner 在跑时不弹菜单（互斥）—— 防御性兜底，正常流程下不会发生
	if DialogueRunner != null and DialogueRunner.is_running():
		GameLogger.warn("UI", "[NPCDiapackMenuWidget] dialogue running, ignore menu request")
		return
	_current_npc_id = npc_id
	_clear_options()
	# Title：取 NPC 显示名（NPCDialogueService API；零 Loader 直访，DRY）
	var npc_name: String = NPCDialogueService.get_npc_name(npc_id)
	title_label.text = npc_name if not npc_name.is_empty() else "NPC #%d" % npc_id
	# 渲染选项
	for i in range(options.size()):
		var opt: Dictionary = options[i]
		var text: String = CsvLoader.as_string(opt, "Talk_Text", "选项 %d" % (i + 1))
		var graph_id: int = CsvLoader.as_int(opt, "Dialogue_ID", 0)
		var btn := Button.new()
		btn.text = text
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override(&"font_size", 16)
		btn.custom_minimum_size = Vector2(280, 40)
		btn.pressed.connect(_on_option_pressed.bind(graph_id))
		options_vbox.add_child(btn)
		_option_buttons.append(btn)
	# 显示菜单 + 切到 DIALOGUE 状态屏蔽其他输入（与 DialogueWidget 同保护）
	HUDStateMachine.change_state(HUDStateMachine.State.DIALOGUE)
	var p: Node = get_parent()
	if p is CanvasLayer:
		(p as CanvasLayer).visible = true
	visible = true
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 1.0, 0.18)
	GameLogger.info("UI", "[NPCDiapackMenuWidget] opened: npc_id=%d (%d options)" % [npc_id, options.size()])


func _on_option_pressed(graph_id: int) -> void:
	if graph_id <= 0:
		GameLogger.warn("UI", "[NPCDiapackMenuWidget] option has invalid graph_id=0; close menu")
		_close_menu()
		return
	var npc_id: int = _current_npc_id
	GameLogger.info("UI", "[NPCDiapackMenuWidget] option chosen -> graph=%d npc=%d" % [graph_id, npc_id])
	_close_menu()
	# 启动对话（DialogueRunner 自己会切 HUDStateMachine.DIALOGUE，但我们刚切回 GAMEPLAY，
	# 它会再切一次，是幂等的）
	if DialogueRunner != null:
		DialogueRunner.start(graph_id, npc_id)


# ─────────────────────────────────────────────────────────────
# 输入：ESC 取消菜单
# ─────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		GameLogger.info("UI", "[NPCDiapackMenuWidget] cancelled by ESC")
		_close_menu()
		get_viewport().set_input_as_handled()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _close_menu() -> void:
	# 切回 GAMEPLAY；如果接下来要 start dialogue，DialogueRunner 自己会再切到 DIALOGUE
	HUDStateMachine.change_state(HUDStateMachine.State.GAMEPLAY)
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 0.0, 0.18)
	tween.tween_callback(_after_close)


func _after_close() -> void:
	visible = false
	_clear_options()
	_current_npc_id = 0


func _clear_options() -> void:
	for btn in _option_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_option_buttons.clear()
	# 防御：兜底清掉 VBox 残留
	for c in options_vbox.get_children():
		c.queue_free()
