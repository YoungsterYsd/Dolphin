## GE 常驻挂载 Fragment（Granted Effect）。
##
## 装备时挂载一组 GameplayEffect（一般是 Duration=Infinite 的 buff），卸下时移除。
## 用于"装备特殊额外效果"接口（如吸血戒指、反伤盾、光环 buff）。
##
## 对应 Frag_GE.csv（1:N，全子行：每条 sub_id 一个 GE_Path）。
##
## **关键约定**：每个 GE 资源**必须有自己的 granted_tags**（至少 1 个），
## 用于 unequip 时通过 [code]asc.remove_effects_with_granted_tag[/code] 反查并撤销。
class_name Fragment_GE
extends ItemFragment

## 启动期 preload 的 GameplayEffect 资源数组。
@export var ge_resources: Array[GameplayEffect] = []


# ─────────────────────────────────────────────────────────────
# CSV 工厂（preload GameplayEffect）
# ─────────────────────────────────────────────────────────────


static func from_csv_row(row: Dictionary, _source) -> ItemFragment:
	if row.is_empty():
		return null
	var f := Fragment_GE.new()
	var subs: Array = row.get("sub_entries", [])
	for s in subs:
		var path: String = CsvLoader.as_string(s, "GE_Path", "")
		if path.is_empty():
			continue
		assert(ResourceLoader.exists(path), "Fragment_GE: GE_Path not exists: %s" % path)
		var ge: GameplayEffect = load(path) as GameplayEffect
		assert(ge != null, "Fragment_GE: failed to load GameplayEffect at %s" % path)
		f.ge_resources.append(ge)
	return f


# ─────────────────────────────────────────────────────────────
# 装备 / 卸下钩子
# ─────────────────────────────────────────────────────────────


func on_equipped(owner, _instance) -> void:
	var asc: AbilitySystemComponent = owner.asc
	if asc == null:
		GameLogger.warn("Items", "Fragment_GE.on_equipped: %s has no asc" % owner.name)
		return
	for ge in ge_resources:
		asc.apply_effect_to(asc, ge, owner)
		GameLogger.info("Items", "[%s] apply granted GE: %s" % [owner.name, ge.get_display_name()])


func on_unequipped(owner, _instance) -> void:
	var asc: AbilitySystemComponent = owner.asc
	if asc == null:
		return
	# 通过每个 GE 的 granted_tags[0] 反查并撤销
	for ge in ge_resources:
		if ge.granted_tags.is_empty():
			GameLogger.warn("Items", "Fragment_GE.on_unequipped: %s has no granted_tags, cannot revoke" % ge.get_display_name())
			continue
		var removed: int = asc.remove_effects_with_granted_tag(ge.granted_tags[0])
		GameLogger.info("Items", "[%s] revoke granted GE: %s (removed=%d)" % [
			owner.name, ge.get_display_name(), removed,
		])
