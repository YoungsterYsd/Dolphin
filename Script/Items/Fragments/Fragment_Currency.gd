## 货币 Fragment。
##
## 拦截入库流程（[method intercepts_inventory_add] 返回 true），
## 货币不进背包网格，改路由到 CurrencyManager（Phase 2 实装；当前阶段仅日志占位）。
class_name Fragment_Currency
extends ItemFragment

## HUD 货币栏 / 飘字提示用图标路径。
@export var icon_on_tip: String = ""


# ─────────────────────────────────────────────────────────────
# CSV 工厂
# ─────────────────────────────────────────────────────────────


static func from_csv_row(row: Dictionary, _source) -> ItemFragment:
	if row.is_empty():
		return null
	var f := Fragment_Currency.new()
	f.icon_on_tip = CsvLoader.as_string(row, "Icon_On_Tip", "")
	return f


# ─────────────────────────────────────────────────────────────
# 入库拦截
# ─────────────────────────────────────────────────────────────


func intercepts_inventory_add(_def, _count: int) -> bool:
	return true


func handle_inventory_add(_owner, def, count: int) -> int:
	# 路由到 GameInstance.currency_manager（挂在 GameInstance 子节点；R-ARCH-02）。
	# 货币不进背包网格，只更新货币账户 + 广播 EventBus.currency_changed。
	var cm: CurrencyManager = GameInstance.currency_manager
	if cm == null:
		GameLogger.warn("Items", "CurrencyManager not ready, currency [%d] %s += %d will be lost" % [
			def.item_id, def.display_name, count,
		])
		return count
	cm.add(def.item_id, count)
	return count


# ─────────────────────────────────────────────────────────────
# use 阻断
# ─────────────────────────────────────────────────────────────


## 货币不响应 use（即使 InventoryComponent.use 误触也阻断 consume）。
func on_use(_owner, _instance) -> bool:
	return false
