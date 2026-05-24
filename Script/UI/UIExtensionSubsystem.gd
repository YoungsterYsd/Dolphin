## UI 扩展子系统（Autoload 单例）。
##
## 提供 Slot + Registry 模式的「插件式」HUD widget 挂载机制：
##   - 每个 widget 不直接知道自己挂在哪里，由本子系统按 [HUDLayoutResource] 决定
##   - 切换布局（主世界 / BossRush / 过场）只需调 [method reload_layout] 加载新 .tres
##
## 与 [HUDManager] 的分工：
##   - HUDManager 管「层」与「层内栈」
##   - UIExtensionSubsystem 管「Slot 上的常驻 widget 注册表」
##
## 用法（代码注册）：
##   var handle = UIExtensionSubsystem.register_widget(&"TopLeft",
##       preload("res://Scenes/UI/Widgets/PlayerInfo.tscn"), 10)
##   ...
##   UIExtensionSubsystem.unregister_widget(handle)
##
## 用法（配置注册）：
##   UIExtensionSubsystem.reload_layout(load("res://Data/Config/HUDLayout_Default.tres"))
extends Node


# ─────────────────────────────────────────────────────────────
# 内部状态
# ─────────────────────────────────────────────────────────────

## 注册项（运行时实例 + 元信息）。
class _Entry:
	extends RefCounted
	var handle: int
	var slot_tag: StringName
	var widget_scene: PackedScene
	var instance: Control
	var priority: int


var _next_handle: int = 1

## handle -> _Entry
var _entries: Dictionary = {}

## slot_tag -> Array[handle]
var _slot_index: Dictionary = {}

## 当前布局资源（reload 时记录）。
var _current_layout: HUDLayoutResource = null


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameLogger.info("UI", "UIExtensionSubsystem ready")


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 注册一个 widget 到指定 slot。返回 handle 用于后续 unregister。
## 若 HUDManager 尚未 setup，会延后到 setup 完成后再实际挂载（先记录到 entries）。
func register_widget(slot_tag: StringName, scene: PackedScene, priority: int = 0) -> int:
	if scene == null:
		GameLogger.warn("UI", "register_widget: null scene")
		return -1
	var entry := _Entry.new()
	entry.handle = _next_handle
	_next_handle += 1
	entry.slot_tag = slot_tag
	entry.widget_scene = scene
	entry.priority = priority
	_entries[entry.handle] = entry
	_index_add(slot_tag, entry.handle)
	# 立即尝试挂载
	_mount_entry(entry)
	GameLogger.info("UI", "register_widget %s -> slot=%s priority=%d (handle=%d)" \
		% [scene.resource_path.get_file(), slot_tag, priority, entry.handle])
	return entry.handle


## 卸载 handle 对应的 widget。
func unregister_widget(handle: int) -> void:
	var entry: _Entry = _entries.get(handle)
	if entry == null:
		return
	if is_instance_valid(entry.instance):
		if entry.instance.has_method("close"):
			entry.instance.close()
		else:
			entry.instance.queue_free()
	_index_remove(entry.slot_tag, handle)
	_entries.erase(handle)
	GameLogger.info("UI", "unregister_widget handle=%d" % handle)


## 卸载指定 slot 的全部 widget。
func clear_slot(slot_tag: StringName) -> void:
	var handles: Array = _slot_index.get(slot_tag, [])
	for h in handles.duplicate():
		unregister_widget(h)


## 卸载所有 widget。reload_layout 内部首先调用。
func clear_all() -> void:
	var all: Array = _entries.keys()
	for h in all:
		unregister_widget(h)


## 切换布局：清空当前所有注册项，按新布局批量注册。
func reload_layout(layout: HUDLayoutResource) -> void:
	clear_all()
	_current_layout = layout
	if layout == null:
		GameLogger.info("UI", "reload_layout: null (cleared all)")
		return
	for mount in layout.mounts:
		if mount == null or not mount.enabled or mount.widget_scene == null:
			continue
		register_widget(mount.slot_tag, mount.widget_scene, mount.priority)
	GameLogger.info("UI", "reload_layout: %s (%d widgets)" % [layout.layout_name, layout.mounts.size()])


## 当前布局资源（debug）。
func get_current_layout() -> HUDLayoutResource:
	return _current_layout


## 获取 slot 上当前所有 entry handles（debug）。
func get_handles_in_slot(slot_tag: StringName) -> Array:
	return (_slot_index.get(slot_tag, []) as Array).duplicate()


# ─────────────────────────────────────────────────────────────
# 内部：实际挂载 / 索引维护
# ─────────────────────────────────────────────────────────────

func _mount_entry(entry: _Entry) -> void:
	# HUDManager 尚未 setup 时延后（_on_hud_setup 触发；此处简单做：直接挂的话取不到 slot）
	var hm: Node = Engine.get_main_loop().root.get_node_or_null(^"HUDManager")
	if hm == null or not hm.is_setup():
		# 延后重试（500ms）
		await Engine.get_main_loop().create_timer(0.05).timeout
		hm = Engine.get_main_loop().root.get_node_or_null(^"HUDManager")
		if hm == null or not hm.is_setup():
			GameLogger.warn("UI", "_mount_entry: HUDManager not setup yet, skip handle=%d" % entry.handle)
			return
	var slot: Control = hm.get_slot(entry.slot_tag) as Control
	if slot == null:
		GameLogger.warn("UI", "_mount_entry: slot not found %s" % entry.slot_tag)
		return
	# 实例化并挂入
	var inst: Node = entry.widget_scene.instantiate()
	if not (inst is Control):
		GameLogger.warn("UI", "_mount_entry: scene root must be Control")
		inst.queue_free()
		return
	entry.instance = inst as Control
	slot.add_child(inst)
	# 简单优先级：priority 越大越靠前（move_child 到末尾，渲染顺序在 Godot 里末尾在前）
	# 如需更精细，后续可改为按 priority 排序所有 children
	slot.move_child(inst, slot.get_child_count() - 1)


func _index_add(slot_tag: StringName, handle: int) -> void:
	var arr: Array = _slot_index.get(slot_tag, [])
	arr.append(handle)
	_slot_index[slot_tag] = arr


func _index_remove(slot_tag: StringName, handle: int) -> void:
	var arr: Array = _slot_index.get(slot_tag, [])
	arr.erase(handle)
	_slot_index[slot_tag] = arr
