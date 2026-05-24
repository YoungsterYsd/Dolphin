## 货币管理器（GameInstance 子节点）。
##
## 数据驱动：货币种类来自 Excel `Items` 表中含 [Fragment_Currency] 的行，
## 本类不硬编码任何 `gold` / `exp` 字段。新增货币 = 改配表 + 在 UI 多挂一个 [CurrencyBarWidget]，
## 不改本类一行代码（OCP）。
##
## **职责（SRP）**：
##   - 持有 `currency_id(int) → amount(int)` 字典
##   - 提供 add / get / try_spend 三个统一入口
##   - 任何余额变更 → 广播 [signal EventBus.currency_changed]
##
## **不负责**：UI 显示、飘字、音效（由 EventBus 订阅方各自实现）。
##
## **接入**：在 [GameInstance._setup_skill_subsystems] 同款模式下被实例化为子节点；
## 业务侧通过 `GameInstance.currency_manager.xxx()` 调用。
##
## **R-ARCH-02**：不增 Autoload；挂 GameInstance 子节点。
## **R-ARCH-04**：跨模块状态变更走 EventBus 广播，不反向 get_node。
class_name CurrencyManager
extends Node

# 内部数据：currency_id(int) → amount(int)。
# 不暴露字典本身（封装），只通过 API 访问。
var _balances: Dictionary = {}


# ─────────────────────────────────────────────────────────────
# 查询
# ─────────────────────────────────────────────────────────────


## 查询某种货币当前持有量。不存在的货币返回 0。
func get_amount(currency_id: int) -> int:
	return int(_balances.get(currency_id, 0))


## 是否至少持有 `amount` 个 currency_id。
func has_at_least(currency_id: int, amount: int) -> bool:
	if amount <= 0:
		return true
	return get_amount(currency_id) >= amount


## 返回所有持有量大于 0 的货币 id 列表（UI 遍历用）。
func get_all_currency_ids() -> Array[int]:
	var result: Array[int] = []
	for k in _balances.keys():
		if int(_balances[k]) > 0:
			result.append(int(k))
	return result


# ─────────────────────────────────────────────────────────────
# 增减（统一入口；都走 _set_amount → 都广播一次）
# ─────────────────────────────────────────────────────────────


## 增加货币。amount<=0 静默忽略（与 InventoryComponent 风格一致）。
## 返回新余额。
func add(currency_id: int, amount: int) -> int:
	if amount <= 0:
		return get_amount(currency_id)
	var new_amount: int = get_amount(currency_id) + amount
	_set_amount(currency_id, new_amount)
	return new_amount


## 尝试消费货币。不足返回 false 不改账户；成功返回 true 并广播。
func try_spend(currency_id: int, amount: int) -> bool:
	if amount <= 0:
		return true
	var current: int = get_amount(currency_id)
	if current < amount:
		return false
	_set_amount(currency_id, current - amount)
	return true


# ─────────────────────────────────────────────────────────────
# 存档钩子（D5 SaveSystem 落地后接入；当前为空 stub）
# ─────────────────────────────────────────────────────────────


## 序列化为 Dictionary（存档用）。返回 _balances 浅拷贝。
func to_dict() -> Dictionary:
	return _balances.duplicate()


## 从 Dictionary 恢复（读档用）。逐项触发 currency_changed 让 UI 自动刷新。
func from_dict(data: Dictionary) -> void:
	_balances.clear()
	for k in data.keys():
		var cid: int = int(k)
		var amt: int = int(data[k])
		_set_amount(cid, amt)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────


## 写入余额并广播。所有变更必须走本方法（保证一定发信号）。
func _set_amount(currency_id: int, new_amount: int) -> void:
	new_amount = maxi(new_amount, 0)
	_balances[currency_id] = new_amount
	GameLogger.info("Items", "Currency [%d] = %d" % [currency_id, new_amount])
	EventBus.currency_changed.emit(currency_id, new_amount)
