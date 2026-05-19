## 装备组件。
##
## 维护三个槽位（武器/防具/饰品）。装备时立即修改 ASC 属性 + 授予 Ability；
## 卸下时反向改回属性 + 撤销 Ability。
##
## 因 GE 当前无"infinite duration"概念，M5 直接 apply Modifier 改属性,
## 卸下时构造一个反向 modifier apply 一次。
class_name EquipmentComponent
extends Node

## 当前装备：slot(int) → EquipmentDefinition
var equipped: Dictionary = {}

var owner_character: Node = null


func _ready() -> void:
	owner_character = get_parent()


## 装备一件道具。返回是否成功（同槽位已有装备会先卸下并放回背包）。
func equip(item: EquipmentDefinition) -> bool:
	if item == null or owner_character == null:
		return false
	# 同槽位已有 → 先 unequip 放回背包
	if equipped.has(item.slot):
		_unequip_internal(item.slot, true)

	var asc := _get_owner_asc()
	if asc == null:
		return false

	# 应用 modifiers（直接 set_attr，相当于 INSTANT GE）
	for m in item.attribute_modifiers:
		m.apply_to(asc.attribute_set)
	# 授予 abilities
	for ab in item.granted_abilities:
		if ab != null:
			asc.grant_ability(ab)

	equipped[item.slot] = item
	EventBus.equipment_changed.emit(owner_character, item.slot)
	GameLogger.info("Items", "[%s] equipped %s (slot=%d)" % [owner_character.name, item.get_display_name(), item.slot])
	return true


## 卸下指定槽位装备，返回是否成功（成功则装备被放回背包）。
func unequip(slot: int) -> bool:
	return _unequip_internal(slot, true)


## 内部卸下逻辑。put_back_to_inventory=false 时仅卸下不放回（同槽替换时用）。
func _unequip_internal(slot: int, put_back_to_inventory: bool) -> bool:
	if not equipped.has(slot):
		return false
	var item: EquipmentDefinition = equipped[slot]
	var asc := _get_owner_asc()
	if asc != null:
		# 反向 modifiers
		for m in item.attribute_modifiers:
			_apply_inverse_modifier(asc.attribute_set, m)
		# 撤销 abilities
		for ab in item.granted_abilities:
			if ab != null:
				asc.revoke_ability(ab.ability_id)

	equipped.erase(slot)
	EventBus.equipment_changed.emit(owner_character, slot)
	GameLogger.info("Items", "[%s] unequipped %s" % [owner_character.name, item.get_display_name()])

	# 放回背包
	if put_back_to_inventory:
		var inv: InventoryComponent = owner_character.get_node_or_null("InventoryComponent") as InventoryComponent
		if inv != null:
			inv.add(item, 1)
	return true


## 反向 apply 一个 Modifier。
func _apply_inverse_modifier(attrs: AttributeSet, m: AttributeModifier) -> void:
	match m.op:
		AttributeModifier.Op.ADD:
			attrs.add_to_attr(m.attribute, -m.magnitude)
		AttributeModifier.Op.MULTIPLY:
			# 反向乘法：除以 magnitude（避免除 0）
			if absf(m.magnitude) > 0.0001:
				attrs.set_attr(m.attribute, attrs.get_attr(m.attribute) / m.magnitude)
		AttributeModifier.Op.OVERRIDE:
			# OVERRIDE 无法反推；warning 提示
			GameLogger.warn("Items", "OVERRIDE modifier on equipment cannot be reversed: %s" % m.attribute)


func _get_owner_asc() -> AbilitySystemComponent:
	if owner_character == null:
		return null
	if "asc" in owner_character:
		return owner_character.asc as AbilitySystemComponent
	return owner_character.get_node_or_null("AbilitySystemComponent") as AbilitySystemComponent
