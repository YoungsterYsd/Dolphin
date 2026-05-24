## 装备组件（Phase 1 Fragment 架构版本）。
##
## 维护槽位 → ItemInstance 映射（[member equipped]）。
## 装备/卸下 = 词条 GE 应用/撤销 + 触发所有 fragment 的 on_equipped/on_unequipped 钩子。
##
## **关键不变性**：词条已在 InventoryComponent.add_by_id 时滚定（[code]instance.stat_tags["affix_mods"][/code]），
## 本组件 equip/unequip **永不滚字**——只读取 stat_tags rebuild GameplayEffect。
##
## R-ARCH-04：跨模块状态变更走 ASC API + EventBus；不反向 get_node 兄弟组件。
class_name EquipmentComponent
extends Node

const STAT_KEY_AFFIX_MODS: StringName = &"affix_mods"

## 当前装备：[code]Slot(int) → ItemInstance[/code]。
## Slot 取值见 [Fragment_Equip.Slot]。
var equipped: Dictionary = {}

## 持有者角色（强类型；R-CHAR-01）。
var owner_character: BaseCharacter = null


func _ready() -> void:
	owner_character = get_parent() as BaseCharacter
	assert(owner_character != null,
		"EquipmentComponent: parent must be BaseCharacter, got %s" % str(get_parent()))


# ─────────────────────────────────────────────────────────────
# 装备 / 卸下
# ─────────────────────────────────────────────────────────────


## 装备一件 instance（词条已固定，不滚字）。
##
## 同槽位已有装备 → 先 unequip 放回背包再装新。
## 返回是否成功。
func equip(instance: ItemInstance) -> bool:
	assert(instance != null, "EquipmentComponent.equip: null instance")
	var def: ItemDefinition = instance.get_def()
	var fe: Fragment_Equip = def.find_fragment(Fragment_Equip) as Fragment_Equip
	assert(fe != null, "EquipmentComponent.equip: item %d has no Fragment_Equip" % def.item_id)
	assert(instance.stat_tags.has(STAT_KEY_AFFIX_MODS),
		"EquipmentComponent.equip: instance missing affix_mods (forgot to call ItemInstance.create_new?)")

	# 同槽位已有 → 先 unequip 放回背包
	if equipped.has(fe.slot):
		_unequip_internal(fe.slot, true)

	# 1. 词条 GE 挂载（这块逻辑只与 Fragment_Equip 相关，保留在 EquipmentComponent）
	_apply_affix_ge(def, instance)

	# 2. 触发所有 fragment 的 on_equipped 钩子（GA/GE 自处理）
	for f in def.fragments:
		f.on_equipped(owner_character, instance)

	equipped[fe.slot] = instance
	EventBus.equipment_changed.emit(owner_character, fe.slot)
	GameLogger.info("Items", "[%s] equipped %s (slot=%d)" % [
		owner_character.name, def.get_display_name(), fe.slot,
	])
	return true


## 卸下指定槽位装备，instance 放回背包（仍带原词条）。
func unequip(slot: int) -> bool:
	return _unequip_internal(slot, true)


# ─────────────────────────────────────────────────────────────
# 查询
# ─────────────────────────────────────────────────────────────


func get_equipped(slot: int) -> ItemInstance:
	return equipped.get(slot, null)


func is_slot_occupied(slot: int) -> bool:
	return equipped.has(slot)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────


func _unequip_internal(slot: int, put_back_to_inventory: bool) -> bool:
	if not equipped.has(slot):
		return false
	var instance: ItemInstance = equipped[slot]
	var def: ItemDefinition = instance.get_def()
	var asc: AbilitySystemComponent = owner_character.asc

	# 1. 撤销词条 GE（按 equip_tag 反查 active_effect）
	if asc != null:
		var equip_tag: StringName = _make_equip_tag(def.item_id)
		asc.remove_effects_with_granted_tag(equip_tag)

	# 2. 触发所有 fragment 的 on_unequipped 钩子（GA/GE 自撤销）
	for f in def.fragments:
		f.on_unequipped(owner_character, instance)

	equipped.erase(slot)
	EventBus.equipment_changed.emit(owner_character, slot)
	GameLogger.info("Items", "[%s] unequipped %s (slot=%d)" % [
		owner_character.name, def.get_display_name(), slot,
	])

	# 3. 放回背包（instance 仍带原词条）
	if put_back_to_inventory:
		var inv: InventoryComponent = NodeFinder.find_first_child_of_type(owner_character, InventoryComponent) as InventoryComponent
		if inv != null:
			inv.add_instance(instance)
	return true


## 构造 Duration=Infinite 临时 GE 挂载词条加成。
func _apply_affix_ge(def: ItemDefinition, instance: ItemInstance) -> void:
	var asc: AbilitySystemComponent = owner_character.asc
	if asc == null:
		GameLogger.warn("Items", "EquipmentComponent: %s has no asc" % owner_character.name)
		return
	var mods_dicts: Array = instance.stat_tags.get(STAT_KEY_AFFIX_MODS, [])
	if mods_dicts.is_empty():
		return
	var mods: Array[AttributeModifier] = AffixRoller.dicts_to_modifiers(mods_dicts)
	var ge := GameplayEffect.new()
	ge.effect_type = GameplayEffect.EffectType.DURATION
	ge.duration = -1.0  # 无限（卸下时通过 granted_tag 反查并撤销）
	ge.modifiers = mods
	ge.granted_tags = [_make_equip_tag(def.item_id)]
	ge.display_name = "EquipAffix_%d" % def.item_id
	asc.apply_effect_to(asc, ge, owner_character)


## equip_tag 命名约定：[code]equip.<item_id>[/code]
static func _make_equip_tag(item_id: int) -> StringName:
	return StringName("equip.%d" % item_id)
