## 装备 Fragment。
##
## 持有装备槽位 + 主/副词条池配置；在 ItemInstance.create_new 期触发滚字
## 并把结果写入 [code]instance.stat_tags["affix_mods"][/code]（永久绑定）。
##
## 装备/卸下时由 EquipmentComponent 直接读 stat_tags["affix_mods"] rebuild GE，**不再滚字**。
class_name Fragment_Equip
extends ItemFragment

enum Slot { WEAPON, ARMOR, SHOES }

const STAT_KEY_AFFIX_MODS: StringName = &"affix_mods"

@export var slot: Slot = Slot.WEAPON
@export var num_main: int = 0
@export var affix_plan_main: int = 0
@export var num_sub: int = 0
@export var affix_plan_sub: int = 0


# ─────────────────────────────────────────────────────────────
# CSV 工厂
# ─────────────────────────────────────────────────────────────


static func from_csv_row(row: Dictionary, _source) -> ItemFragment:
	if row.is_empty():
		return null
	var f := Fragment_Equip.new()
	f.slot = _parse_slot(CsvLoader.as_string(row, "Slot", "Weapon"))
	f.num_main = CsvLoader.as_int(row, "num_main", 0)
	f.affix_plan_main = CsvLoader.as_int(row, "affix_plan_main", 0)
	f.num_sub = CsvLoader.as_int(row, "num_sub", 0)
	f.affix_plan_sub = CsvLoader.as_int(row, "affix_plan_sub", 0)
	return f


static func _parse_slot(s: String) -> Slot:
	match s.to_lower():
		"weapon": return Slot.WEAPON
		"armor":  return Slot.ARMOR
		"shoes":  return Slot.SHOES
	push_warning("Fragment_Equip: unknown slot '%s', fallback to WEAPON" % s)
	return Slot.WEAPON


# ─────────────────────────────────────────────────────────────
# 滚字钩子（ItemInstance.create_new 触发）
# ─────────────────────────────────────────────────────────────


func on_instance_created(instance: ItemInstance) -> void:
	var mods_main: Array = AffixRoller.roll_to_dicts(affix_plan_main, num_main)
	var mods_sub: Array = AffixRoller.roll_to_dicts(affix_plan_sub, num_sub)
	var all_mods: Array = mods_main + mods_sub
	instance.stat_tags[STAT_KEY_AFFIX_MODS] = all_mods
	GameLogger.info("Items", "Fragment_Equip rolled: item_id=%d main=%d sub=%d total=%d" % [
		instance.def_id, mods_main.size(), mods_sub.size(), all_mods.size(),
	])
	for m in all_mods:
		GameLogger.info("Items", "  affix: %s %s %.3f" % [m["attribute"], m["op"], m["magnitude"]])


# ─────────────────────────────────────────────────────────────
# 装备：use 即装备
# ─────────────────────────────────────────────────────────────


## 装备类的 on_use → 调 EquipmentComponent.equip。
## 不消耗本体（装备不该被 use 流程扣堆叠；返回 true 但 def.consumable 应为 false）。
func on_use(owner, instance) -> bool:
	if instance == null:
		return true
	var ec: EquipmentComponent = NodeFinder.find_first_child_of_type(owner, EquipmentComponent) as EquipmentComponent
	if ec == null:
		GameLogger.warn("Items", "Fragment_Equip.on_use: no EquipmentComponent on %s" % owner.name)
		return true
	ec.equip(instance)
	return true
