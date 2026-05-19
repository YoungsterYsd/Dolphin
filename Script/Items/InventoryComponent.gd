## 背包组件。
##
## 槽位数固定（max_slots），每槽可堆叠（受 ItemDefinition.max_stack 限制）。
## API：add(item, count) / remove(slot, count) / use(slot)
##
## 信号：通过 EventBus.inventory_changed 广播变化。
class_name InventoryComponent
extends Node

@export var max_slots: int = 16

## 槽位列表。每个元素：{ "item": ItemDefinition, "count": int } 或 null（空槽）。
var slots: Array = []

## 持有者节点（一般是 BaseCharacter，自动取 parent）。
var owner_character: Node = null


func _ready() -> void:
	owner_character = get_parent()
	slots.resize(max_slots)
	for i in range(max_slots):
		slots[i] = null


## 添加 count 个 item，返回成功添加的数量（可能少于 count，背包满）。
func add(item: ItemDefinition, count: int = 1) -> int:
	if item == null or count <= 0:
		return 0
	var remaining: int = count
	# 先填已有同 item 槽
	for i in range(max_slots):
		if remaining <= 0:
			break
		var s = slots[i]
		if s != null and s.item.item_id == item.item_id and s.count < item.max_stack:
			var fill: int = mini(item.max_stack - s.count, remaining)
			s.count += fill
			remaining -= fill
	# 再放空槽
	for i in range(max_slots):
		if remaining <= 0:
			break
		if slots[i] == null:
			var fill: int = mini(item.max_stack, remaining)
			slots[i] = {"item": item, "count": fill}
			remaining -= fill
	var added: int = count - remaining
	if added > 0:
		EventBus.inventory_changed.emit(owner_character)
		GameLogger.info("Items", "[%s] +%d %s" % [owner_character.name if owner_character else "?", added, item.get_display_name()])
	return added


## 移除指定槽位 count 个，返回实际移除数量。
func remove(slot_index: int, count: int = 1) -> int:
	if slot_index < 0 or slot_index >= max_slots:
		return 0
	var s = slots[slot_index]
	if s == null:
		return 0
	var removed: int = mini(count, s.count)
	s.count -= removed
	if s.count <= 0:
		slots[slot_index] = null
	EventBus.inventory_changed.emit(owner_character)
	return removed


## 使用槽位中的物品。返回是否成功使用（消耗品消耗 1 个；装备调用 EquipmentComponent.equip）。
func use(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= max_slots:
		return false
	var s = slots[slot_index]
	if s == null:
		return false
	var item: ItemDefinition = s.item

	if item is ConsumableDefinition:
		return _use_consumable(slot_index, item as ConsumableDefinition)
	if item is EquipmentDefinition:
		return _use_equipment(slot_index, item as EquipmentDefinition)
	GameLogger.warn("Items", "use: unknown item type: %s" % item.get_display_name())
	return false


func _use_consumable(slot_index: int, item: ConsumableDefinition) -> bool:
	if item.effect == null or owner_character == null:
		return false
	var asc := _get_owner_asc()
	if asc == null:
		return false
	asc.apply_effect_to(asc, item.effect, owner_character)
	GameLogger.info("Items", "[%s] used %s" % [owner_character.name, item.get_display_name()])
	remove(slot_index, 1)
	return true


func _use_equipment(slot_index: int, item: EquipmentDefinition) -> bool:
	if owner_character == null:
		return false
	var equip_comp: EquipmentComponent = owner_character.get_node_or_null("EquipmentComponent") as EquipmentComponent
	if equip_comp == null:
		GameLogger.warn("Items", "no EquipmentComponent on %s" % owner_character.name)
		return false
	var ok: bool = equip_comp.equip(item)
	if ok:
		remove(slot_index, 1)
	return ok


func _get_owner_asc() -> AbilitySystemComponent:
	if owner_character == null:
		return null
	if owner_character.has_method("get") and "asc" in owner_character:
		return owner_character.asc as AbilitySystemComponent
	return owner_character.get_node_or_null("AbilitySystemComponent") as AbilitySystemComponent
