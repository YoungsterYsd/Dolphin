## GA 授予 Fragment（Granted Ability）。
##
## 装备时临时学到一组 GA，卸下时撤销。
## 对应 Frag_GA.csv（1:N，全子行：每条 sub_id 一个 GA_Path）。
##
## **关键**：CSV 加载期 preload [Ability] 资源到 [member abilities]，运行时零 IO。
class_name Fragment_GA
extends ItemFragment

## 启动期 preload 的 Ability 资源数组。
@export var abilities: Array[Ability] = []


# ─────────────────────────────────────────────────────────────
# CSV 工厂（preload Ability）
# ─────────────────────────────────────────────────────────────


static func from_csv_row(row: Dictionary, _source) -> ItemFragment:
	if row.is_empty():
		return null
	var f := Fragment_GA.new()
	var subs: Array = row.get("sub_entries", [])
	for s in subs:
		var path: String = CsvLoader.as_string(s, "GA_Path", "")
		if path.is_empty():
			continue
		assert(ResourceLoader.exists(path), "Fragment_GA: GA_Path not exists: %s" % path)
		var ab: Ability = load(path) as Ability
		assert(ab != null, "Fragment_GA: failed to load Ability at %s" % path)
		f.abilities.append(ab)
	return f


# ─────────────────────────────────────────────────────────────
# 装备 / 卸下钩子
# ─────────────────────────────────────────────────────────────


func on_equipped(owner, _instance) -> void:
	var asc: AbilitySystemComponent = owner.asc
	if asc == null:
		GameLogger.warn("Items", "Fragment_GA.on_equipped: %s has no asc" % owner.name)
		return
	for ab in abilities:
		asc.grant_ability(ab)
		GameLogger.info("Items", "[%s] grant GA: %s" % [owner.name, ab.ability_id])


func on_unequipped(owner, _instance) -> void:
	var asc: AbilitySystemComponent = owner.asc
	if asc == null:
		return
	for ab in abilities:
		asc.revoke_ability(ab.ability_id)
		GameLogger.info("Items", "[%s] revoke GA: %s" % [owner.name, ab.ability_id])
