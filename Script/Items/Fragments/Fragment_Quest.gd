## 任务道具 Fragment。
##
## use() 时 emit [signal EventBus.quest_item_used]，由任务系统订阅做后续判定。
## 道具本体堆叠扣 1 由通用流程负责（主表 Consumable=1 时）。
class_name Fragment_Quest
extends ItemFragment

@export var quest_id: int = 0


# ─────────────────────────────────────────────────────────────
# CSV 工厂
# ─────────────────────────────────────────────────────────────


static func from_csv_row(row: Dictionary, _source) -> ItemFragment:
	if row.is_empty():
		return null
	var f := Fragment_Quest.new()
	f.quest_id = CsvLoader.as_int(row, "Quest_ID", 0)
	return f


# ─────────────────────────────────────────────────────────────
# use 钩子
# ─────────────────────────────────────────────────────────────


func on_use(owner, instance) -> bool:
	var def_id: int = instance.def_id if instance != null else 0
	EventBus.quest_item_used.emit(def_id, quest_id, owner)
	GameLogger.info("Items", "[%s] used quest item: def_id=%d quest_id=%d" % [
		owner.name if owner != null else "?", def_id, quest_id,
	])
	return true
