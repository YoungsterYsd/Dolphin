## 背包 UI（升级版：货币 + 装备 + 拖拽 + 右键/双击 + 拖出丢弃）。
##
## **布局**：标题（含 × 关闭按钮）/ 装备区 (3 槽) / 货币区 (N 槽) / 道具网格 (4x4)。
##
## **交互（用户决策 2026-05-24）**：
##   - 右键单击 / 双击道具格 → 使用（装备类经 Fragment_Equip.on_use 自动 equip）
##   - 右键单击 / 双击装备槽 → 卸下回背包
##   - 左键拖道具 → 背包内换位置 / 装到装备槽（同 fe.slot 才能放）
##   - 左键拖装备 → 卸下到指定背包格（目标空槽才允许）
##   - 左键拖出本面板（Panel 矩形之外）→ 丢弃，仅发 [signal EventBus.item_dropped]
##   - × 按钮 / Esc / I 键 → 关闭
##
## **R-HUD-02**：本类不直接 cast 业务对象，与 InventoryComponent / EquipmentComponent
## 的接触面只通过它们的公开 API（add_instance / move / use / equip / unequip / remove）。
##
## **R-ARCH-04**：跨模块状态变更走 EventBus；本类不主动 emit inventory_changed
## （由组件自身 emit），只 emit item_dropped。
class_name InventoryUI
extends BaseWidget

const _SlotControlScript = preload("res://Script/UI/Widgets/InventorySlotControl.gd")

@export var inventory: InventoryComponent = null
@export var equipment: EquipmentComponent = null

@onready var _panel: PanelContainer = $Panel
@onready var _grid: GridContainer = $Panel/Margin/VBox/InvGrid
@onready var _equip_row: HBoxContainer = $Panel/Margin/VBox/EquipRow
@onready var _currency_row: HBoxContainer = $Panel/Margin/VBox/CurrencyRow
@onready var _close_btn: Button = $Panel/Margin/VBox/TitleRow/CloseBtn

# 槽位 Control 数组
var _inv_slots: Array = []        # 16 个 KIND_INV
var _equip_slots: Dictionary = {} # Fragment_Equip.Slot → KIND_EQUIP InventorySlotControl
var _currency_slots: Dictionary = {} # currency_id(int) → KIND_CURRENCY InventorySlotControl

var _is_open: bool = false


func _ready() -> void:
	super._ready()
	# Esc 关闭时本 UI 仍要响应 → ALWAYS（避免 HUDStateMachine 暂停游戏树时无法关闭）
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# 装备槽（3 个）：WEAPON / ARMOR / SHOES
	_create_equip_slot(Fragment_Equip.Slot.WEAPON, "武器")
	_create_equip_slot(Fragment_Equip.Slot.ARMOR, "防具")
	_create_equip_slot(Fragment_Equip.Slot.SHOES, "鞋子")

	# 道具网格（16 个）
	for i in range(16):
		var s: InventorySlotControl = _SlotControlScript.new()
		s.kind = InventorySlotControl.KIND_INV
		s.index = i
		s.owner_ui = self
		_grid.add_child(s)
		_inv_slots.append(s)

	# 关闭按钮
	_close_btn.pressed.connect(_on_close_pressed)

	# 信号订阅
	EventBus.inventory_changed.connect(_on_inv_changed)
	EventBus.equipment_changed.connect(_on_equip_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.item_added.connect(_on_item_added)

	_refresh_all()


func _create_equip_slot(slot: int, label_hint: String) -> void:
	var s: InventorySlotControl = _SlotControlScript.new()
	s.kind = InventorySlotControl.KIND_EQUIP
	s.index = slot
	s.owner_ui = self
	s.tooltip_text = label_hint + "（空）"
	_equip_row.add_child(s)
	_equip_slots[slot] = s


# ─────────────────────────────────────────────────────────────
# 打开 / 关闭 API（保留原契约）
# ─────────────────────────────────────────────────────────────


# ─────────────────────────────────────────────────────────────
# 打开 / 关闭 API
# ─────────────────────────────────────────────────────────────
#
# 设计说明：
#   InventoryUI 在 .tscn 中以 persistent=true + visible=false 静态预挂在关卡 HUDLayer 下。
#   open/close 走 HUDManager 栈：push_widget 检测到节点已在 layer 下会跳过 reparent；
#   pop_widget 调 BaseWidget.close() → persistent 分支只 hide 不 free，节点可反复 toggle。


## 打开背包 UI。push 到 L2_GameMenu 栈 + HUD 状态切 PANEL_OPEN。
func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	_refresh_all()
	# 接 HUDManager 栈（重复 push 会被 push_widget 内部去重）
	var hm: Node = Engine.get_main_loop().root.get_node_or_null(^"HUDManager")
	if hm != null and hm.has_method(&"push_widget"):
		var layer: Node = hm.call(&"get_layer", &"L2_GameMenu")
		if layer != null and get_parent() != layer:
			reparent(layer, false)
			if layer is CanvasLayer:
				(layer as CanvasLayer).visible = true
		hm.call(&"push_widget", &"L2_GameMenu", self)
	# 切 HUD 状态 → PANEL_OPEN（自动屏蔽战斗按键）
	if HUDStateMachine != null and HUDStateMachine.has_method(&"change_state"):
		HUDStateMachine.change_state(HUDStateMachine.State.PANEL_OPEN)
	GameLogger.info("UI", "InventoryUI opened")


## 关闭背包 UI。pop 栈（触发 BaseWidget.close → persistent=true 仅 hide 不 free）+ HUD 状态切回 GAMEPLAY。
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	# 切回 GAMEPLAY（恢复战斗按键）
	if HUDStateMachine != null and HUDStateMachine.has_method(&"change_state"):
		HUDStateMachine.change_state(HUDStateMachine.State.GAMEPLAY)
	# 通过栈管理统一关闭：HUDManager.pop_widget → BaseWidget.close → persistent 分支隐藏
	var hm: Node = Engine.get_main_loop().root.get_node_or_null(^"HUDManager")
	if hm != null and hm.has_method(&"pop_widget"):
		hm.call(&"pop_widget", &"L2_GameMenu")
	else:
		# fallback：HUDManager 不可用时仍能正常关
		visible = false
	GameLogger.info("UI", "InventoryUI closed")


## 切换打开/关闭。供 Tab / I 键调用。
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


## 当前是否打开。
func is_open() -> bool:
	return _is_open


## Esc / I 关闭背包。
func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"ui_panel_build"):
		close()
		get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	close()


# ─────────────────────────────────────────────────────────────
# 刷新
# ─────────────────────────────────────────────────────────────


## 公开刷新入口（供外部如 test_arena 在赋值 inventory/equipment 后触发刷新）。
func refresh_all() -> void:
	_refresh_all()


func _refresh_all() -> void:
	_refresh_inv()
	_refresh_equipment()
	_refresh_currency()


func _refresh_inv() -> void:
	if inventory == null:
		return
	for i in range(_inv_slots.size()):
		var s: InventorySlotControl = _inv_slots[i]
		var slot_data = inventory.slots[i] if i < inventory.slots.size() else null
		if slot_data == null:
			s.clear_display()
		else:
			var def: ItemDefinition = slot_data.def
			var count: int = slot_data.count
			var label_text: String = "" if slot_data.instance != null else str(count)
			s.set_display(_load_icon(def.icon_path), label_text, _build_tooltip(def, slot_data.instance))
			s.set_rarity(def.get_rarity())


func _refresh_equipment() -> void:
	if equipment == null:
		return
	for slot_id in _equip_slots.keys():
		var s: InventorySlotControl = _equip_slots[slot_id]
		if equipment.equipped.has(slot_id):
			var inst: ItemInstance = equipment.equipped[slot_id]
			var def: ItemDefinition = inst.get_def()
			s.set_display(_load_icon(def.icon_path), "", _build_tooltip(def, inst))
			s.set_rarity(def.get_rarity())
		else:
			s.clear_display()
			s.tooltip_text = _equip_empty_tip(slot_id)


func _equip_empty_tip(slot_id: int) -> String:
	match slot_id:
		Fragment_Equip.Slot.WEAPON: return "武器（空）"
		Fragment_Equip.Slot.ARMOR:  return "防具（空）"
		Fragment_Equip.Slot.SHOES:  return "鞋子（空）"
		_: return "（空）"


func _refresh_currency() -> void:
	# 数据驱动：拿 GameInstance.currency_manager 当前所有持有的货币 → 没格子就建一个
	var cm: CurrencyManager = GameInstance.currency_manager
	if cm == null:
		return
	for cid in cm.get_all_currency_ids():
		_ensure_currency_slot(cid)
	# 刷新所有已建格子
	for cid in _currency_slots.keys():
		var s: InventorySlotControl = _currency_slots[cid]
		var amount: int = cm.get_amount(cid)
		var def: ItemDefinition = ConfigCenter.get_item_def(cid)
		var icon: Texture2D = null
		var name_str: String = "Currency#%d" % cid
		if def != null:
			name_str = def.get_display_name()
			icon = _load_icon(def.icon_path)
		s.set_display(icon, str(amount), "%s: %d" % [name_str, amount])


func _ensure_currency_slot(cid: int) -> void:
	if _currency_slots.has(cid):
		return
	var s: InventorySlotControl = _SlotControlScript.new()
	s.kind = InventorySlotControl.KIND_CURRENCY
	s.index = cid
	s.owner_ui = self
	_currency_row.add_child(s)
	_currency_slots[cid] = s


# ─────────────────────────────────────────────────────────────
# 拖拽策略 + 处理（被 InventorySlotControl 回调）
# ─────────────────────────────────────────────────────────────


## 是否允许从 src 拖到 dst。
func can_drop(src_kind: StringName, src_index: int, dst_kind: StringName, dst_index: int) -> bool:
	# inv → inv：永远允许（move 内部会处理交换/合并；拒绝空槽源）
	if src_kind == InventorySlotControl.KIND_INV and dst_kind == InventorySlotControl.KIND_INV:
		if inventory == null:
			return false
		return inventory.slots[src_index] != null

	# inv → equip：检查源是否是装备类 + slot 类型匹配
	if src_kind == InventorySlotControl.KIND_INV and dst_kind == InventorySlotControl.KIND_EQUIP:
		if inventory == null:
			return false
		var sd = inventory.slots[src_index]
		if sd == null or sd.instance == null:
			return false
		var fe: Fragment_Equip = sd.def.find_fragment(Fragment_Equip) as Fragment_Equip
		return fe != null and fe.slot == dst_index

	# equip → inv：仅当目标是空槽（避免和原有"放回第一空槽"语义冲突）
	if src_kind == InventorySlotControl.KIND_EQUIP and dst_kind == InventorySlotControl.KIND_INV:
		if inventory == null or equipment == null:
			return false
		if not equipment.equipped.has(src_index):
			return false
		return inventory.slots[dst_index] == null

	# equip → equip / 含 currency：禁止
	return false


## 执行 drop。本方法不做合法性检查（can_drop 已过）。
func on_drop(src_kind: StringName, src_index: int, dst_kind: StringName, dst_index: int) -> void:
	if src_kind == InventorySlotControl.KIND_INV and dst_kind == InventorySlotControl.KIND_INV:
		inventory.move(src_index, dst_index)
		return

	if src_kind == InventorySlotControl.KIND_INV and dst_kind == InventorySlotControl.KIND_EQUIP:
		var sd = inventory.slots[src_index]
		if sd == null or sd.instance == null:
			return
		# 关键步骤：先把背包源槽清空，再 equip。
		# 因为 EquipmentComponent.equip 内部会把原装备 add_instance(...) 放入第一空槽，
		# 如果不先清，可能会回到 src_index 之后的位置；先 remove(src_index, 1) 让 src_index
		# 成为第一空槽，旧装备就自然落到玩家拖出的那个位置（视觉直觉一致）。
		var inst: ItemInstance = sd.instance
		inventory.remove(src_index, 1)
		equipment.equip(inst)
		return

	if src_kind == InventorySlotControl.KIND_EQUIP and dst_kind == InventorySlotControl.KIND_INV:
		# 装备槽 → 背包指定空槽
		# 当前 EquipmentComponent.unequip 走 inv.add_instance(第一空槽)；
		# 为了精确落到 dst_index：先 unequip 走标准路径，再 move 到目标位置。
		var inst2: ItemInstance = equipment.equipped[src_index]
		var def: ItemDefinition = inst2.get_def()
		equipment.unequip(src_index)
		# 找回放置后的位置（应在第一个空槽，但用 def 反查更稳）
		var landed_idx: int = inventory.find_first_by_def(def)
		if landed_idx >= 0 and landed_idx != dst_index:
			inventory.move(landed_idx, dst_index)


# ─────────────────────────────────────────────────────────────
# 使用 / 卸下（右键 + 双击 走这里）
# ─────────────────────────────────────────────────────────────


func on_use_inv(slot_index: int) -> void:
	if inventory == null:
		return
	inventory.use(slot_index)


func on_unequip(slot_id: int) -> void:
	if equipment == null:
		return
	equipment.unequip(slot_id)


# ─────────────────────────────────────────────────────────────
# 拖出面板 = 丢弃
# ─────────────────────────────────────────────────────────────


# 监听全局 drag end：在 _process 中轮询 viewport.gui_is_dragging()
# 转换为 drag-start / drag-end 事件；drag-end 时若鼠标不在 Panel 矩形内 → 丢弃。
# （Godot 4 的 _get_drag_data 没有"拖起源信息"的全局访问入口，所以由各
# InventorySlotControl 在 _get_drag_data 时回调本类 register_drag_source 注册。）
var _drag_source_kind: StringName = &""
var _drag_source_index: int = -1
var _drag_active: bool = false


func _process(_delta: float) -> void:
	if not _is_open:
		return
	var dragging: bool = get_viewport().gui_is_dragging()
	# 进入拖拽
	if dragging and not _drag_active:
		_drag_active = true
	# 退出拖拽
	elif not dragging and _drag_active:
		_drag_active = false
		_check_drop_outside()


## 由 InventorySlotControl._get_drag_data 在拖起时调用，记录源信息。
func register_drag_source(kind: StringName, index: int) -> void:
	_drag_source_kind = kind
	_drag_source_index = index


func _check_drop_outside() -> void:
	var src_kind: StringName = _drag_source_kind
	var src_index: int = _drag_source_index
	# 重置（无论是否丢弃，避免下次拖拽残留）
	_drag_source_kind = &""
	_drag_source_index = -1
	if src_kind == &"" or src_index < 0:
		return
	var mouse_global: Vector2 = get_viewport().get_mouse_position()
	var panel_rect: Rect2 = _panel.get_global_rect()
	if panel_rect.has_point(mouse_global):
		return  # 在面板内：drop 已由 _drop_data 处理（或落空回弹）
	_drop_outside(src_kind, src_index)


func _drop_outside(src_kind: StringName, src_index: int) -> void:
	# 只对背包格子允许丢弃；装备槽拖出不丢弃（避免误丢宝贵装备，需先卸下）
	if src_kind != InventorySlotControl.KIND_INV:
		GameLogger.info("UI", "InventoryUI: drop-outside ignored for kind=%s" % String(src_kind))
		return
	if inventory == null:
		return
	var sd = inventory.slots[src_index]
	if sd == null:
		return
	var def: ItemDefinition = sd.def
	var count: int = sd.count
	var inst: ItemInstance = sd.instance
	# 移除 + 广播 item_dropped
	inventory.remove(src_index, count)
	EventBus.item_dropped.emit(inventory.owner_character, def, count, inst)
	GameLogger.info("UI", "InventoryUI: dropped %s x%d (slot=%d)" % [
		def.get_display_name(), count, src_index,
	])


# ─────────────────────────────────────────────────────────────
# 图标加载 / Tooltip
# ─────────────────────────────────────────────────────────────


func _load_icon(icon_path: String) -> Texture2D:
	if icon_path.is_empty():
		return null
	if not ResourceLoader.exists(icon_path):
		GameLogger.warn("UI", "InventoryUI: icon not found: %s" % icon_path)
		return null
	return load(icon_path) as Texture2D


func _build_tooltip(def: ItemDefinition, instance: ItemInstance) -> String:
	var lines: Array[String] = []
	# 品质标签前缀（白 / 绿 / 蓝 / 紫 / 橙 / 红）
	var rarity: int = def.get_rarity()
	if rarity >= 1:
		var style: Dictionary = AffixFormatter.rarity_style(rarity)
		lines.append("[%s] %s" % [style.get("label", ""), def.get_display_name()])
	else:
		lines.append(def.get_display_name())
	if not def.description.is_empty():
		lines.append(def.description)
	if instance != null:
		var mods: Array = instance.stat_tags.get(&"affix_mods", [])
		if not mods.is_empty():
			lines.append(AffixFormatter.format_mods_block_plain(mods))
	return "\n".join(lines)


# ─────────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────────


func _on_inv_changed(_owner) -> void:
	_refresh_inv()


func _on_equip_changed(_owner, _slot) -> void:
	_refresh_equipment()


func _on_currency_changed(currency_id: int, _new_amount: int) -> void:
	_ensure_currency_slot(currency_id)
	_refresh_currency()


func _on_item_added(_owner, _def, _count) -> void:
	# item_added 时 inventory_changed 也会发；这里留空避免重复刷新
	pass
