## 道具运行时实例（Resource）。
##
## 装备 / 有词条 / 有耐久 / 有任何运行时状态的物品都需要 Instance。
## 简单堆叠物品（如药水）可以无 Instance 直接走 def + count。
##
## **持久化字段**（[member def_id] + [member stat_tags]）足够 SaveGame 还原；
## def 通过 ConfigCenter 反查（不持久化对象引用）。
##
## 关键工厂方法：
##   - [method create_new]：新获取物品时（**触发 on_instance_created 钩子 → 滚字等**）
##   - [method from_save]：读档还原（**不触发钩子**，直接用 saved stat_tags）
class_name ItemInstance
extends Resource

@export var def_id: int = 0
@export var stat_tags: Dictionary = {}


## 取关联的 ItemDefinition。
func get_def() -> ItemDefinition:
	var d: ItemDefinition = ConfigCenter.get_item_def(def_id)
	assert(d != null, "ItemInstance.get_def: def_id=%d not found in ConfigCenter" % def_id)
	return d


# ─────────────────────────────────────────────────────────────
# 工厂
# ─────────────────────────────────────────────────────────────


## 新获取物品时调用。会逐个触发 def.fragments[*].on_instance_created。
##
## 例如 Fragment_Equip 在该钩子里滚字写入 stat_tags["affix_mods"]。
static func create_new(def: ItemDefinition) -> ItemInstance:
	assert(def != null, "ItemInstance.create_new: def is null")
	var inst := ItemInstance.new()
	inst.def_id = def.item_id
	for f in def.fragments:
		f.on_instance_created(inst)
	return inst


## 从存档还原。不触发 on_instance_created（直接用存档 stat_tags）。
static func from_save(saved_def_id: int, saved_stat_tags: Dictionary) -> ItemInstance:
	var inst := ItemInstance.new()
	inst.def_id = saved_def_id
	inst.stat_tags = saved_stat_tags.duplicate(true)
	return inst


# ─────────────────────────────────────────────────────────────
# stat_tags 便利访问
# ─────────────────────────────────────────────────────────────


func get_stat(key: StringName, default_value: Variant = 0) -> Variant:
	return stat_tags.get(key, default_value)


func set_stat(key: StringName, value: Variant) -> void:
	stat_tags[key] = value


func add_stat(key: StringName, delta: int) -> void:
	stat_tags[key] = int(stat_tags.get(key, 0)) + delta


func has_stat(key: StringName) -> bool:
	return stat_tags.has(key)
