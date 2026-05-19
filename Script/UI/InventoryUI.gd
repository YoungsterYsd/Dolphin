## 背包 UI（M5）。
##
## 显示玩家背包：4x4 网格，每格显示道具名 + 数量；点击使用/装备。
## 装备区显示三槽位（武器/防具/饰品），点击空槽无效，点击有装备则卸下。
##
## 默认隐藏，由 PauseMenu 或 InventoryToggle 控制 visibility。
class_name InventoryUI
extends Control

@export var inventory: InventoryComponent = null
@export var equipment: EquipmentComponent = null

@onready var grid: GridContainer = $Panel/Margin/VBox/InvGrid
@onready var weapon_label: Label = $Panel/Margin/VBox/EquipRow/WeaponSlot/Label
@onready var armor_label: Label = $Panel/Margin/VBox/EquipRow/ArmorSlot/Label
@onready var accessory_label: Label = $Panel/Margin/VBox/EquipRow/AccessorySlot/Label

var _slot_buttons: Array[Button] = []


func _ready() -> void:
	# 创建 16 个槽按钮
	for i in range(16):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 72)
		btn.text = ""
		btn.pressed.connect(_on_slot_pressed.bind(i))
		grid.add_child(btn)
		_slot_buttons.append(btn)

	# 装备槽按钮
	($Panel/Margin/VBox/EquipRow/WeaponSlot as Button).pressed.connect(_on_equip_slot_pressed.bind(EquipmentDefinition.Slot.WEAPON))
	($Panel/Margin/VBox/EquipRow/ArmorSlot as Button).pressed.connect(_on_equip_slot_pressed.bind(EquipmentDefinition.Slot.ARMOR))
	($Panel/Margin/VBox/EquipRow/AccessorySlot as Button).pressed.connect(_on_equip_slot_pressed.bind(EquipmentDefinition.Slot.ACCESSORY))

	EventBus.inventory_changed.connect(_on_changed)
	EventBus.equipment_changed.connect(_on_equip_changed)
	_refresh()


func _refresh() -> void:
	if inventory == null:
		return
	for i in range(_slot_buttons.size()):
		var s = inventory.slots[i] if i < inventory.slots.size() else null
		var btn := _slot_buttons[i]
		if s == null:
			btn.text = "—"
			btn.disabled = true
		else:
			btn.text = "%s\nx%d" % [s.item.get_display_name(), s.count]
			btn.disabled = false
	_refresh_equipment()


func _refresh_equipment() -> void:
	if equipment == null:
		return
	weapon_label.text = _equip_text(EquipmentDefinition.Slot.WEAPON)
	armor_label.text = _equip_text(EquipmentDefinition.Slot.ARMOR)
	accessory_label.text = _equip_text(EquipmentDefinition.Slot.ACCESSORY)


func _equip_text(slot: int) -> String:
	if equipment == null or not equipment.equipped.has(slot):
		return "（空）"
	return (equipment.equipped[slot] as EquipmentDefinition).get_display_name()


func _on_slot_pressed(slot_index: int) -> void:
	if inventory == null:
		return
	inventory.use(slot_index)


func _on_equip_slot_pressed(slot: int) -> void:
	if equipment == null:
		return
	equipment.unequip(slot)


func _on_changed(_owner) -> void:
	_refresh()


func _on_equip_changed(_owner, _slot) -> void:
	_refresh_equipment()
