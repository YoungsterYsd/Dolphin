## 对话框 widget（HUD）。
##
## 订阅 EventBus.dialogue_* 信号驱动 UI：
##   - dialogue_started → 入场动画 + visible=true
##   - dialogue_node_changed → 按 NodeKind 渲染（speech：打字机；choice：渲染选项）
##   - dialogue_choice_presented → 重建选项按钮
##   - dialogue_ended → 退场动画 + visible=false
##
## 输入：订阅 EventBus.player_input_action_pressed 捕获 combat_interact / ui_navigate_up / down。
## 仅在 [DialogueRunner.is_running] 时响应输入；不消费其他 widget 的 action（R-HUD-02 同源）。
##
## 默认在 HUDLayout 中 enabled=true，但 visible=false（自身 _ready 设）；
## 由 dialogue_started 自动唤起；不依赖业务侧调 push_widget。
class_name DialogueWidget
extends BaseWidget

@onready var bg: ColorRect = $BG
@onready var portrait: TextureRect = $HBox/Portrait
@onready var speaker_label: Label = $HBox/RightPanel/Speaker
@onready var text_label: RichTextLabel = $HBox/RightPanel/Text
@onready var continue_indicator: Label = $HBox/RightPanel/ContinueIndicator
@onready var choices_vbox: VBoxContainer = $HBox/RightPanel/ChoicesVBox

# 当前渲染节点（用于跨 process 帧打字机推进 / 输入响应）
var _current_node: DialogueNode = null
var _typewriter_active: bool = false
var _typewriter_total_chars: int = 0
var _typewriter_elapsed: float = 0.0
var _typewriter_speed: float = 40.0
var _selected_choice_index: int = 0
var _choice_buttons: Array[Button] = []

# Config 缓存
var _dlg_cfg: DialogueConfig = null
var _portraits_cfg: PortraitsConfig = null


func _ready() -> void:
	super._ready()
	visible = false
	modulate.a = 0.0
	# mouse_filter 已在 .tscn 设定（根=STOP / HBox=PASS / RightPanel=PASS / ChoicesVBox=PASS）
	# super._ready() 会把 process_mode 设为 INHERIT；这里改回 ALWAYS
	# 让对话框在游戏 paused 时也能响应（未来防护）
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pull_configs()
	# 订阅对话信号
	EventBus.dialogue_started.connect(_on_dialogue_started)
	EventBus.dialogue_node_changed.connect(_on_node_changed)
	EventBus.dialogue_choice_presented.connect(_on_choice_presented)
	EventBus.dialogue_ended.connect(_on_dialogue_ended)
	# 订阅输入（仅响应自己关心的 action）
	EventBus.player_input_action_pressed.connect(_on_input_action_pressed)
	set_process(false)
	# Mount 完成后 reparent 到 L2_GameMenu 层（高于 L1_Game 的 HUD widget）
	# 避免被 hotbar / 血条等遮挡，并且按钮点击不被下层 widget 拦截
	call_deferred(&"_relocate_to_dialog_layer")


## 把 DialogueWidget 从 L1_Game/<Slot> 重新挂到 L2_GameMenu 层。
## 仅做一次，调用 reparent 保持现有 transform；call_deferred 等同帧内其他 setup 完成。
func _relocate_to_dialog_layer() -> void:
	var hm: Node = Engine.get_main_loop().root.get_node_or_null(^"HUDManager")
	if hm == null or not hm.has_method(&"get_layer"):
		return
	var layer: Node = hm.call(&"get_layer", &"L2_GameMenu")
	if layer == null:
		GameLogger.warn("UI", "[DialogueWidget] L2_GameMenu not found, keep current parent")
		return
	if get_parent() == layer:
		return
	reparent(layer, false)
	GameLogger.info("UI", "[DialogueWidget] relocated to L2_GameMenu")


# 自接 unhandled input：捕获 ui_accept / ui_cancel
# （InputController 不 watch ui_accept，必须自己接）
func _unhandled_input(event: InputEvent) -> void:
	if not visible or _current_node == null:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"combat_interact"):
		_handle_advance()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel"):
		# 对话期间 Esc 强制结束（避免玩家卡死）
		if DialogueRunner != null and DialogueRunner.has_method(&"force_end"):
			DialogueRunner.force_end()
		get_viewport().set_input_as_handled()


## 鼠标点击对话框任意区域 → 推进（仅 Speech 节点；Choice 节点让玩家点按钮，避免误触）。
## 由根节点 mouse_filter=STOP 自动捕获 GUI 事件。
func _gui_input(event: InputEvent) -> void:
	if not visible or _current_node == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# Choice 节点不响应背景点击（让按钮独占点击）
	if _current_node.get_node_kind() == &"choice":
		return
	# Speech / Effect 节点：点击 = 推进
	_handle_advance()
	accept_event()


func _handle_advance() -> void:
	# 打字机进行中：跳过到末尾
	if _typewriter_active:
		text_label.visible_characters = -1
		_typewriter_active = false
		set_process(false)
		continue_indicator.visible = (_current_node.get_node_kind() == &"speech")
		return
	# Speech：推进
	if _current_node.get_node_kind() == &"speech":
		DialogueRunner.advance()
	# Choice：仅 1 个选项时直接选；多选项靠鼠标点击


func _process(delta: float) -> void:
	if not _typewriter_active:
		return
	_typewriter_elapsed += delta
	var target: int = int(_typewriter_elapsed * _typewriter_speed)
	if target >= _typewriter_total_chars:
		text_label.visible_characters = -1
		_typewriter_active = false
		set_process(false)
		continue_indicator.visible = (_current_node != null and _current_node.get_node_kind() == &"speech")
	else:
		text_label.visible_characters = target


# ─────────────────────────────────────────────────────────────
# 对话信号处理
# ─────────────────────────────────────────────────────────────

func _on_dialogue_started(_graph_id: int, _npc_id: int) -> void:
	GameLogger.info("UI", "[DialogueWidget] dialogue_started -> show panel")
	_pull_configs()  # 重新拉一次，允许运行时改 Config
	# L2_GameMenu 默认 visible=false（HUD_Main.tscn），对话期间显式打开
	var p: Node = get_parent()
	if p is CanvasLayer:
		(p as CanvasLayer).visible = true
	visible = true
	_clear_choices()
	continue_indicator.visible = false
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 1.0, _get_enter_seconds())


func _on_node_changed(node: Resource) -> void:
	_current_node = node as DialogueNode
	_clear_choices()
	continue_indicator.visible = false
	# 动态切光标：Speech=手型（点击推进），Choice=箭头（让按钮独占交互）
	# M12：effect 节点已移除；对话纯解耦，业务方订阅 dialogue_ended 自处理
	match _current_node.get_node_kind():
		&"speech":
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			_render_speech(_current_node as SpeechNode)
		&"choice":
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			_render_choice_intro(_current_node as ChoiceNode)


func _on_choice_presented(options: Array) -> void:
	_clear_choices()
	_choice_buttons.clear()
	_selected_choice_index = 0
	for i in range(options.size()):
		var opt: ChoiceOption = options[i]
		var btn := Button.new()
		btn.text = _resolve(opt.text)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override(&"font_size", 16)
		btn.pressed.connect(_on_choice_button_pressed.bind(i))
		choices_vbox.add_child(btn)
		_choice_buttons.append(btn)
	_update_choice_highlight()


func _on_dialogue_ended(_graph_id: int, _npc_id: int) -> void:
	_typewriter_active = false
	set_process(false)
	var tween := create_tween()
	tween.tween_property(self, ^"modulate:a", 0.0, _get_exit_seconds())
	tween.tween_callback(func():
		visible = false
		_clear_choices()
		_current_node = null
	)


# ─────────────────────────────────────────────────────────────
# 渲染
# ─────────────────────────────────────────────────────────────

func _render_speech(node: SpeechNode) -> void:
	speaker_label.text = String(node.speaker)
	_update_portrait(node.portrait_id)
	var resolved: String = _resolve(node.text)
	text_label.text = resolved
	# 打字机
	if _typewriter_speed > 0.0:
		text_label.visible_characters = 0
		_typewriter_total_chars = text_label.get_total_character_count()
		_typewriter_elapsed = 0.0
		_typewriter_active = true
		set_process(true)
	else:
		text_label.visible_characters = -1
		continue_indicator.visible = true


func _render_choice_intro(node: ChoiceNode) -> void:
	# ChoiceNode 的 prompt 用 speaker 位置显示
	if node.prompt != "":
		speaker_label.text = "—"
		text_label.text = _resolve(node.prompt)
		text_label.visible_characters = -1
	else:
		speaker_label.text = ""
		text_label.text = ""
	continue_indicator.visible = false
	# 选项按钮等 dialogue_choice_presented 信号触发


func _update_portrait(portrait_id: StringName) -> void:
	if portrait_id == &"":
		portrait.texture = null
		portrait.visible = false
		return
	var path: String = _portraits_cfg.get_texture_path(portrait_id) if _portraits_cfg != null else ""
	if path == "" and _dlg_cfg != null:
		path = _dlg_cfg.default_portrait_path
	if path == "" or not ResourceLoader.exists(path):
		portrait.visible = false
		return
	portrait.texture = load(path) as Texture2D
	portrait.visible = portrait.texture != null


func _clear_choices() -> void:
	for c in choices_vbox.get_children():
		c.queue_free()
	_choice_buttons.clear()


func _update_choice_highlight() -> void:
	for i in range(_choice_buttons.size()):
		var btn: Button = _choice_buttons[i]
		if i == _selected_choice_index:
			btn.modulate = Color(1, 0.95, 0.4)  # 高亮黄
		else:
			btn.modulate = Color.WHITE


# ─────────────────────────────────────────────────────────────
# 输入
# ─────────────────────────────────────────────────────────────

func _on_input_action_pressed(action: StringName) -> void:
	if not visible or _current_node == null:
		return
	# 打字机进行中：任意推进键直接跳过打字
	if _typewriter_active and action == &"combat_interact":
		text_label.visible_characters = -1
		_typewriter_active = false
		set_process(false)
		continue_indicator.visible = (_current_node.get_node_kind() == &"speech")
		return
	# 各节点的行为
	match _current_node.get_node_kind():
		&"speech":
			if action == &"combat_interact":
				DialogueRunner.advance()
		&"choice":
			if _choice_buttons.is_empty():
				return
			# 用 move_* 做选项导航（暂复用，无独立 ui_up/down）
			# 主键盘 W/S 默认在 move_up / move_down，但 InputContext.Dialogue 不放行 move_*
			# 此处先用 combat_interact 顺序滚动选项作为兜底（按 E 滚动选项）
			# 复杂导航留给鼠标点击 + 后续 InputAction 扩展
			if action == &"combat_interact":
				if _choice_buttons.size() == 1:
					DialogueRunner.select_choice(0)


func _on_choice_button_pressed(index: int) -> void:
	DialogueRunner.select_choice(index)


# ─────────────────────────────────────────────────────────────
# 工具
# ─────────────────────────────────────────────────────────────

func _resolve(s: String) -> String:
	# 通过 DialogueRunner 单例做插值
	if DialogueRunner != null and DialogueRunner.has_method(&"resolve_text"):
		return DialogueRunner.resolve_text(s)
	return s


func _pull_configs() -> void:
	# R-Core：ConfigCenter 走 class_name 强类型直访（has_method 防御已无必要）
	_dlg_cfg = ConfigCenter.get_dialogue_config()
	_portraits_cfg = ConfigCenter.get_portraits_config()
	if _dlg_cfg != null:
		_typewriter_speed = _dlg_cfg.typewriter_chars_per_second


func _get_enter_seconds() -> float:
	return 0.18  # 默认 S 档；后续接 UIDurations 资源


func _get_exit_seconds() -> float:
	return 0.18
