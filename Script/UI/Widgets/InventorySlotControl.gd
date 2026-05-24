## 背包 / 装备 / 货币 通用槽位 Control（拖拽载体）。
##
## **三种 mode**（由 [member kind] 区分）：
##   - [code]KIND_INV[/code]    背包格：可拖出 / 可放入；右键 = 使用，双击 = 使用
##   - [code]KIND_EQUIP[/code]  装备槽：可拖出（卸下到背包） / 仅接受同 fe.slot 的装备拖入
##   - [code]KIND_CURRENCY[/code] 货币条：只读，不参与拖拽（icon + 数字）
##
## **拖拽数据格式**（_get_drag_data 返回的 Dictionary）：
## [code]
##   {
##     "source_kind": &"inv" | &"equip",
##     "source_index": int,            # inv: slot 0..15; equip: Fragment_Equip.Slot
##   }
## [/code]
##
## **回调由父 InventoryUI 注入**（owner_ui 字段）；本类不直接 cast 业务对象，遵守 R-HUD-02。
class_name InventorySlotControl
extends Control

const KIND_INV: StringName = &"inv"
const KIND_EQUIP: StringName = &"equip"
const KIND_CURRENCY: StringName = &"currency"

const DOUBLE_CLICK_THRESHOLD: float = 0.35  ## 双击间隔阈值（秒）

## 槽位类型（KIND_INV / KIND_EQUIP / KIND_CURRENCY）。
@export var kind: StringName = KIND_INV

## 索引：背包 = 槽位序号(0..max_slots-1)；装备 = Fragment_Equip.Slot；货币 = currency_id。
@export var index: int = -1

## 父 InventoryUI 引用（用于回调）。在父侧 _ready 时注入。
var owner_ui: Node = null


# ─────────────────────────────────────────────────────────────
# 视觉子节点（运行时构造，无 .tscn 依赖）
# ─────────────────────────────────────────────────────────────

var _bg: Panel
var _icon: TextureRect
var _label: Label
var _highlight: Panel  # drag hover 高亮叠层

# 双击检测
var _last_click_time: float = -1.0


func _ready() -> void:
	custom_minimum_size = Vector2(72, 72)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_bg = Panel.new()
	_bg.name = "BG"
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_label = Label.new()
	_label.name = "Label"
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_top = -20
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_color_override(&"font_color", Color.WHITE)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_highlight = Panel.new()
	_highlight.name = "Highlight"
	_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.modulate = Color(1, 1, 0.4, 0.35)
	_highlight.visible = false
	add_child(_highlight)

	# 默认空槽样式（中性边框）
	set_rarity(0)


# ─────────────────────────────────────────────────────────────
# 显示 API（由父 InventoryUI 调用）
# ─────────────────────────────────────────────────────────────


## 设置图标 + 数字 + tooltip。
## icon=null 时显示空槽样式（只剩底板）。
func set_display(icon: Texture2D, label_text: String, tooltip: String) -> void:
	_icon.texture = icon
	_label.text = label_text
	tooltip_text = tooltip


## 清空显示（空槽）。
func clear_display() -> void:
	_icon.texture = null
	_label.text = ""
	tooltip_text = ""
	set_rarity(0)


## 设置品质（影响底板边框颜色）。0/1=普通(白)；2 绿 / 3 蓝 / 4 紫 / 5 橙 / 6+ 红。
##
## 调用方：父 InventoryUI 在每次 _refresh 时根据 def.get_rarity() 调本方法。
## 空槽（rarity=0）→ 透明边框 + 中性灰底板。
func set_rarity(rarity: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.14, 0.85)
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	if rarity <= 0:
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.3, 0.3, 0.35, 1)
	else:
		var style: Dictionary = AffixFormatter.rarity_style(rarity)
		var c: Color = style.get("color", Color.WHITE)
		# 高品质边框更粗
		var w: int = 1 + clamp(rarity - 1, 0, 3)
		sb.border_width_left = w
		sb.border_width_right = w
		sb.border_width_top = w
		sb.border_width_bottom = w
		sb.border_color = c
		# 高品质底板微微染色
		sb.bg_color = Color(c.r * 0.15 + 0.1, c.g * 0.15 + 0.1, c.b * 0.15 + 0.1, 0.85)
	_bg.add_theme_stylebox_override(&"panel", sb)


# ─────────────────────────────────────────────────────────────
# 拖拽：发起方
# ─────────────────────────────────────────────────────────────


func _get_drag_data(_at_position: Vector2) -> Variant:
	# 货币槽不可拖
	if kind == KIND_CURRENCY:
		return null
	# 空槽不可拖（由父侧通过 _icon.texture==null 判定）
	if _icon.texture == null:
		return null

	# 拖拽预览：复制图标
	var preview := TextureRect.new()
	preview.texture = _icon.texture
	preview.custom_minimum_size = Vector2(64, 64)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1, 1, 1, 0.85)
	var ctn := Control.new()
	ctn.add_child(preview)
	preview.position = -preview.custom_minimum_size * 0.5
	set_drag_preview(ctn)

	# 通知父 UI 注册 drag source（拖出面板 = 丢弃 流程依赖此回调）
	if owner_ui != null and owner_ui.has_method(&"register_drag_source"):
		owner_ui.call(&"register_drag_source", kind, index)

	return {
		&"source_kind": kind,
		&"source_index": index,
	}


# ─────────────────────────────────────────────────────────────
# 拖拽：接收方
# ─────────────────────────────────────────────────────────────


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if owner_ui == null or typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has(&"source_kind") or not data.has(&"source_index"):
		return false
	# 货币槽不接受
	if kind == KIND_CURRENCY:
		return false
	# 调父侧策略检查
	if owner_ui.has_method(&"can_drop"):
		var ok: bool = owner_ui.call(
			&"can_drop",
			data[&"source_kind"], int(data[&"source_index"]),
			kind, index,
		)
		_highlight.visible = ok
		return ok
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_highlight.visible = false
	if owner_ui == null:
		return
	if owner_ui.has_method(&"on_drop"):
		owner_ui.call(
			&"on_drop",
			data[&"source_kind"], int(data[&"source_index"]),
			kind, index,
		)


# ─────────────────────────────────────────────────────────────
# 鼠标输入：右键单击 / 双击 = 使用
# ─────────────────────────────────────────────────────────────


func _gui_input(event: InputEvent) -> void:
	if owner_ui == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return

	if kind == KIND_INV:
		# 右键 = 使用（不消耗双击）
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if owner_ui.has_method(&"on_use_inv"):
				owner_ui.call(&"on_use_inv", index)
			get_viewport().set_input_as_handled()
			return
		# 左键双击 = 使用
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			if owner_ui.has_method(&"on_use_inv"):
				owner_ui.call(&"on_use_inv", index)
			get_viewport().set_input_as_handled()
			return
	elif kind == KIND_EQUIP:
		# 右键 / 双击 = 卸下
		if mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click):
			if owner_ui.has_method(&"on_unequip"):
				owner_ui.call(&"on_unequip", index)
			get_viewport().set_input_as_handled()
			return


# ─────────────────────────────────────────────────────────────
# 视觉：drag 离开时清高亮
# ─────────────────────────────────────────────────────────────


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_highlight.visible = false
