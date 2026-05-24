## HUD 管理器（Autoload 单例）。
##
## 职责：
##   1) **自动**实例化 [code]Scenes/UI/HUD_Main.tscn[/code]，挂到 /root（与 Autoload 同级），
##      跨场景持久存在，关卡切换 / reload_current_scene 时不重建
##   2) 注册其下的 8 层 CanvasLayer 与 7 个 Slot
##   3) 应用每层的 [HUDLayerPolicy]（输入 / 暂停 / 可见性 / 栈深度 / 入退场）
##   4) 提供 push_widget / pop_widget / get_top_widget / clear_layer API（栈式管理）
##   5) **自动**加载 [code]Data/Config/HUDLayout_Default.tres[/code] 作为默认布局
##      （业务侧只需在需要切换布局时调 [method UIExtensionSubsystem.reload_layout]）
##
## 业务侧无需主动调 [method setup]：HUDManager._ready 已通过 call_deferred 自动完成。
## 仅在特殊场景（如单元测试）需手动调用时才显式 setup()。
##
## 与 [UIExtensionSubsystem] 的分工：
##   - HUDManager 管「层」与「层内的栈」
##   - UIExtensionSubsystem 管「Slot 上的常驻 widget 注册表」
##
## R-EVENT-01：所有 push/pop 同步 emit [signal EventBus.hud_widget_pushed/popped]。
extends Node

# ─────────────────────────────────────────────────────────────
# 常量
# ─────────────────────────────────────────────────────────────

## 8 层 layer_id（顺序与 HUD_Main.tscn 子节点对齐）。
const LAYER_IDS: Array[StringName] = [
	&"L0_World", &"L1_Game", &"L2_GameMenu", &"L3_Menu",
	&"L4_Modal", &"L5_Notification", &"L6_Loading", &"L7_Debug",
]

## 7 个 Slot tag（位于 L1_Game 层下）。
const SLOT_TAGS: Array[StringName] = [
	&"TopLeft", &"TopCenter", &"TopRight",
	&"BottomLeft", &"BottomCenter", &"BottomRight",
	&"Center",
]

## HUD 主场景资源路径。
const HUD_MAIN_SCENE_PATH: String = "res://Scenes/UI/HUD_Main.tscn"

## 默认布局资源路径（HUDManager._ready 自动加载，找不到时跳过）。
const DEFAULT_LAYOUT_PATH: String = "res://Data/Config/HUDLayout_Default.tres"


# ─────────────────────────────────────────────────────────────
# 内部状态
# ─────────────────────────────────────────────────────────────

## HUD_Main 实例（场景树中实际节点）。
var _hud_main: Node = null

## layer_id -> CanvasLayer 节点
var _layers: Dictionary = {}

## layer_id -> Array[Control]   （栈管理）
var _stacks: Dictionary = {}

## layer_id -> HUDLayerPolicy
var _policies: Dictionary = {}

## slot_tag -> Control（Slot 容器节点，位于 L1_Game 层下）
var _slots: Dictionary = {}

## 是否已 setup（防止重复挂载）
var _is_setup: bool = false


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameLogger.info("UI", "HUDManager autoload ready")
	# 延后到一帧后挂载 HUD_Main：
	# - 此时 SceneTree.root 已完成初始化
	# - 此时 UIExtensionSubsystem._ready 也已完成（Autoload 顺序由 project.godot 保证）
	# - 业务关卡的 _ready 还没跑，UIExtensionSubsystem.reload_layout 时 Slot 已就绪
	call_deferred(&"_auto_setup")


## Autoload 启动后自动调，无需业务侧介入。
## 业务侧若要切换布局，只调 [method UIExtensionSubsystem.reload_layout]。
func _auto_setup() -> void:
	setup()
	_load_default_layout()


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 实例化 HUD_Main 并挂到场景树根，扫描层与槽位。
## **业务侧通常不需要主动调用** —— Autoload 启动时已自动完成。
## 重复调用安全：第二次调用直接返回。
func setup(parent: Node = null) -> void:
	if _is_setup:
		return
	if parent == null:
		parent = Engine.get_main_loop().root
	# 实例化 HUD_Main
	if not ResourceLoader.exists(HUD_MAIN_SCENE_PATH):
		GameLogger.error("UI", "HUD_Main not found: %s" % HUD_MAIN_SCENE_PATH)
		return
	var scene: PackedScene = load(HUD_MAIN_SCENE_PATH)
	_hud_main = scene.instantiate()
	# 挂到 /root（与 Autoload 同级，跨场景持久）
	parent.add_child(_hud_main)
	# 扫描层与 Slot
	_scan_layers()
	_scan_slots()
	_apply_policies()
	_is_setup = true
	# 订阅 SettingsManager 即时应用 hud/* 配置（M11 HUD 收尾）
	_subscribe_settings()
	_apply_hud_settings()
	GameLogger.info("UI", "HUDManager setup ok (layers=%d slots=%d, persistent under /root)" \
		% [_layers.size(), _slots.size()])


# ─────────────────────────────────────────────────────────────
# SettingsManager 联动（M11 HUD 收尾）
# ─────────────────────────────────────────────────────────────

func _subscribe_settings() -> void:
	var sm: Node = Engine.get_main_loop().root.get_node_or_null(^"SettingsManager")
	if sm == null:
		return
	if sm.has_signal(&"setting_changed") and not sm.setting_changed.is_connected(_on_setting_changed):
		sm.setting_changed.connect(_on_setting_changed)


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	# 任意 hud/* 变化都重应用一次（粒度无所谓，HUD 不是热路径）
	if key == &"hud_opacity" or key == &"debug_overlay_visible":
		_apply_hud_settings()


## 应用 SettingsManager 中的 HUD 配置到对应层。
func _apply_hud_settings() -> void:
	var sm: Node = Engine.get_main_loop().root.get_node_or_null(^"SettingsManager")
	if sm == null:
		return
	# hud_opacity → L1_Game / L0_HUDBackground 共同的视觉透明度
	var opacity: float = float(sm.get(&"hud_opacity"))
	for layer_id in [&"L0_HUDBackground", &"L1_Game"]:
		var layer: Node = _layers.get(layer_id)
		if layer != null and layer is CanvasLayer:
			# CanvasLayer 没有 modulate；把 opacity 应用到所有子 Control
			for child in layer.get_children():
				if child is CanvasItem:
					(child as CanvasItem).modulate.a = opacity
	# debug_overlay_visible → L7_Debug 层 visible
	var dbg_visible: bool = bool(sm.get(&"debug_overlay_visible"))
	var dbg: Node = _layers.get(&"L7_Debug")
	if dbg != null and dbg is CanvasLayer:
		(dbg as CanvasLayer).visible = dbg_visible


## 加载默认布局到 UIExtensionSubsystem。
## 业务侧若要切布局，应调 [method UIExtensionSubsystem.reload_layout]，不要再调本函数。
func _load_default_layout() -> void:
	if not ResourceLoader.exists(DEFAULT_LAYOUT_PATH):
		GameLogger.info("UI", "default layout not found, skip: %s" % DEFAULT_LAYOUT_PATH)
		return
	var layout: Resource = load(DEFAULT_LAYOUT_PATH)
	var ues: Node = Engine.get_main_loop().root.get_node_or_null(^"UIExtensionSubsystem")
	if ues == null:
		GameLogger.warn("UI", "UIExtensionSubsystem not found, skip default layout")
		return
	ues.reload_layout(layout)





## push 一个 widget 到指定层的栈顶。
## 若该层未启用栈（policy.enable_stack=false），仍可 push（行为 = 直接 add_child）。
##
## **重复 push 容错**：若 widget 已是 layer 的子节点（场景里静态预挂或之前已 push 过），
## 则跳过 add_child 直接推入栈，避免 "node already has a parent" 报错。
func push_widget(layer_id: StringName, widget: Control) -> void:
	if widget == null:
		return
	var layer: Node = _layers.get(layer_id)
	if layer == null:
		GameLogger.warn("UI", "push_widget: layer not found %s" % layer_id)
		return
	# 栈深度上限保护
	var stack: Array = _stacks.get(layer_id, [])
	var policy: HUDLayerPolicy = _policies.get(layer_id)
	if policy != null and policy.enable_stack and policy.max_stack_size > 0:
		if stack.size() >= policy.max_stack_size:
			GameLogger.warn("UI", "push_widget: layer %s stack full (%d)" % [layer_id, policy.max_stack_size])
			return
	# 若已在栈中（静态节点重复 open 等场景）→ 跳过，不重复推入
	if widget in stack:
		GameLogger.info("UI", "push_widget: %s already in %s stack, skip" % [_widget_tag(widget), layer_id])
		return
	# 上一栈顶失焦（栈管理）
	if policy != null and policy.enable_stack and stack.size() > 0:
		var prev: Control = stack[stack.size() - 1]
		if is_instance_valid(prev):
			prev.set_process_input(false)
			prev.set_process_unhandled_input(false)
	# 推入：仅当 widget 还没挂在 layer 下时才 add_child
	if widget.get_parent() != layer:
		layer.add_child(widget)
	stack.append(widget)
	_stacks[layer_id] = stack
	EventBus.hud_widget_pushed.emit(layer_id, widget)
	GameLogger.info("UI", "push %s -> %s (depth=%d)" % [_widget_tag(widget), layer_id, stack.size()])


## pop 指定层的栈顶 widget（触发其 close）。
##
## **生命周期约定**：本方法统一调用 [BaseWidget.close]，由 widget 的
## [BaseWidget.persistent] 字段决定节点命运（true = 保留 / false = queue_free）。
## 调用方无需关心销毁时机。
##
## 若栈为空返回 null。
func pop_widget(layer_id: StringName) -> Control:
	var stack: Array = _stacks.get(layer_id, [])
	if stack.is_empty():
		return null
	var top: Control = stack.pop_back()
	_stacks[layer_id] = stack
	# 新栈顶恢复输入
	var policy: HUDLayerPolicy = _policies.get(layer_id)
	if policy != null and policy.enable_stack and not stack.is_empty():
		var new_top: Control = stack[stack.size() - 1]
		if is_instance_valid(new_top):
			new_top.set_process_input(true)
			new_top.set_process_unhandled_input(true)
	EventBus.hud_widget_popped.emit(layer_id, top)
	GameLogger.info("UI", "pop %s <- %s (depth=%d)" % [_widget_tag(top), layer_id, stack.size()])
	# 触发关闭
	if is_instance_valid(top):
		if top.has_method("close"):
			top.close()  # BaseWidget.close 内部 await 退场动画后 queue_free
		else:
			top.queue_free()
	return top


## 获取指定层栈顶 widget（不弹出）。
func get_top_widget(layer_id: StringName) -> Control:
	var stack: Array = _stacks.get(layer_id, [])
	if stack.is_empty():
		return null
	return stack[stack.size() - 1] as Control


## 清空指定层的所有 widget（按 LIFO 顺序 pop 全部）。
func clear_layer(layer_id: StringName) -> void:
	while not (_stacks.get(layer_id, []) as Array).is_empty():
		pop_widget(layer_id)


## 获取层的栈深度（debug / Layer 切换前预检）。
func get_stack_size(layer_id: StringName) -> int:
	return (_stacks.get(layer_id, []) as Array).size()


## 获取 Slot 容器节点（UIExtensionSubsystem 用）。
func get_slot(slot_tag: StringName) -> Control:
	return _slots.get(slot_tag) as Control


## 获取层节点（HUDStateMachine / 调试用）。
func get_layer(layer_id: StringName) -> Node:
	return _layers.get(layer_id) as Node


## 是否已 setup（外部状态机依赖）。
func is_setup() -> bool:
	return _is_setup


# ─────────────────────────────────────────────────────────────
# 内部：扫描 / 应用策略
# ─────────────────────────────────────────────────────────────

func _scan_layers() -> void:
	if _hud_main == null:
		return
	for layer_id in LAYER_IDS:
		var node := _hud_main.get_node_or_null(NodePath(String(layer_id)))
		if node == null:
			GameLogger.warn("UI", "layer node not found in HUD_Main: %s" % layer_id)
			continue
		_layers[layer_id] = node
		_stacks[layer_id] = []


func _scan_slots() -> void:
	# Slot 都挂在 L1_Game 层下（命名严格匹配 SLOT_TAGS）
	var l1: Node = _layers.get(&"L1_Game")
	if l1 == null:
		return
	for tag in SLOT_TAGS:
		var slot := l1.get_node_or_null(NodePath(String(tag)))
		if slot == null:
			GameLogger.warn("UI", "slot not found in L1_Game: %s" % tag)
			continue
		_slots[tag] = slot


## 把每层的 HUDLayerPolicy（如已配置在 _hud_main 的元数据）应用到 CanvasLayer。
## 若没有显式 policy，则按层 id 应用一份合理默认。
func _apply_policies() -> void:
	for layer_id in LAYER_IDS:
		var node: Node = _layers.get(layer_id)
		if node == null:
			continue
		var policy: HUDLayerPolicy = _make_default_policy(layer_id)
		_policies[layer_id] = policy
		# 应用到 CanvasLayer
		if node is CanvasLayer:
			var cl: CanvasLayer = node as CanvasLayer
			cl.layer = policy.canvas_layer_index
			cl.visible = policy.visible_default
			cl.follow_viewport_enabled = policy.follow_camera
		# 应用 process_mode
		match policy.pause_policy:
			HUDLayerPolicy.PausePolicy.ALWAYS:
				node.process_mode = Node.PROCESS_MODE_ALWAYS
			HUDLayerPolicy.PausePolicy.PAUSABLE:
				node.process_mode = Node.PROCESS_MODE_PAUSABLE
			HUDLayerPolicy.PausePolicy.WHEN_PAUSED:
				node.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
			_:
				node.process_mode = Node.PROCESS_MODE_INHERIT
		# debug_only：非调试构建自动隐藏
		if policy.debug_only and not OS.is_debug_build():
			if node is CanvasLayer:
				(node as CanvasLayer).visible = false


## 各层的默认策略（不依赖外部 .tres，保证 Phase 1 即可工作）。
func _make_default_policy(layer_id: StringName) -> HUDLayerPolicy:
	var p := HUDLayerPolicy.new()
	p.layer_id = layer_id
	p.display_name = String(layer_id)
	match layer_id:
		&"L0_World":
			p.canvas_layer_index = 0
			p.input_mode = HUDLayerPolicy.InputMode.PASS
			p.pause_policy = HUDLayerPolicy.PausePolicy.PAUSABLE
			p.follow_camera = true
		&"L1_Game":
			p.canvas_layer_index = 1
			p.input_mode = HUDLayerPolicy.InputMode.PASS
			p.pause_policy = HUDLayerPolicy.PausePolicy.PAUSABLE
		&"L2_GameMenu":
			p.canvas_layer_index = 2
			p.input_mode = HUDLayerPolicy.InputMode.BLOCK
			p.pause_policy = HUDLayerPolicy.PausePolicy.PAUSABLE
			p.enable_stack = true
		&"L3_Menu":
			p.canvas_layer_index = 3
			p.input_mode = HUDLayerPolicy.InputMode.BLOCK
			p.pause_policy = HUDLayerPolicy.PausePolicy.ALWAYS
			p.enable_stack = true
		&"L4_Modal":
			p.canvas_layer_index = 4
			p.input_mode = HUDLayerPolicy.InputMode.BLOCK
			p.pause_policy = HUDLayerPolicy.PausePolicy.ALWAYS
			p.enable_stack = true
		&"L5_Notification":
			p.canvas_layer_index = 5
			p.input_mode = HUDLayerPolicy.InputMode.PASS
			p.pause_policy = HUDLayerPolicy.PausePolicy.ALWAYS
		&"L6_Loading":
			p.canvas_layer_index = 6
			p.input_mode = HUDLayerPolicy.InputMode.BLOCK
			p.pause_policy = HUDLayerPolicy.PausePolicy.ALWAYS
		&"L7_Debug":
			p.canvas_layer_index = 99
			p.input_mode = HUDLayerPolicy.InputMode.PASS
			p.pause_policy = HUDLayerPolicy.PausePolicy.ALWAYS
			p.debug_only = true
	return p


func _widget_tag(widget: Control) -> String:
	if widget == null:
		return "<null>"
	if widget is BaseWidget and (widget as BaseWidget).widget_id != &"":
		return String((widget as BaseWidget).widget_id)
	return widget.name
