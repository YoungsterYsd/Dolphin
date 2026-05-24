## 背包组件（Phase 1 Fragment 架构版本）。
##
## 槽位数固定（max_slots），每槽：
##   - 简单堆叠物品（药水、任务道具）：[code]{def, instance: null, count}[/code]
##   - 装备 / 有词条物品：[code]{def, instance: ItemInstance, count: 1}[/code]（每件独立 instance）
##
## **双入口**：
##   - [method add_by_id]：新获取（**触发 fragment.on_instance_created → 滚字**）
##   - [method add_instance]：放回已存在 instance（卸下回背包 / 读档恢复，**不滚字**）
##
## **use 路由**：通过 fragment.on_use 钩子驱动，本类不写 if-else 链（OCP）。
##
## 信号：通过 EventBus.inventory_changed / item_added 广播。
class_name InventoryComponent
extends Node

@export var max_slots: int = 16

## 槽位列表。每个元素：
## [code]{ "def": ItemDefinition, "instance": ItemInstance|null, "count": int }[/code]
## 或 null（空槽）。
var slots: Array = []

## 持有者角色（强类型；R-CHAR-01）。
var owner_character: BaseCharacter = null


func _ready() -> void:
	# R-CODE-01：父节点必须是 BaseCharacter
	owner_character = get_parent() as BaseCharacter
	assert(owner_character != null,
		"InventoryComponent: parent must be BaseCharacter, got %s" % str(get_parent()))
	slots.resize(max_slots)
	for i in range(max_slots):
		slots[i] = null


# ─────────────────────────────────────────────────────────────
# 添加 API（双入口）
# ─────────────────────────────────────────────────────────────


## 入口 1：按 def_id 加新物品。装备类会触发 ItemInstance.create_new → 滚字。
##
## 拾取 / 商店购买 / 任务奖励 / 调试命令走这里。
## 返回成功添加的数量。
func add_by_id(def_id: int, count: int = 1) -> int:
	var def: ItemDefinition = ConfigCenter.get_item_def(def_id)
	assert(def != null, "InventoryComponent.add_by_id: def_id=%d not found" % def_id)
	return _add_internal(def, count)


## 入口 2：放回已存在的 instance（**不重新滚字**，词条/状态保留）。
##
## 卸下装备 / 读档恢复走这里。
func add_instance(instance: ItemInstance) -> int:
	assert(instance != null, "InventoryComponent.add_instance: null instance")
	return _add_existing_instance(instance)


# ─────────────────────────────────────────────────────────────
# 移除 / 使用
# ─────────────────────────────────────────────────────────────


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


## 移动 / 交换 / 合并两槽位内容（仅供 UI 拖拽使用）。
##
## **行为规则**：
##   - to 槽为空 → from 内容平移到 to（from 变空）
##   - to 非空，且双方 def 相同且都是堆叠类（instance==null）→ 合并堆叠
##     （受 max_stack 约束；溢出留在 from 槽；若已满则回退到交换）
##   - 其他情况（含装备类 instance!=null） → 交换两槽内容
##
## **设计约束**：
##   - 不调用任何 fragment 钩子（位置整理无业务语义，符合 SRP）
##   - 不修改 instance 内容（词条原样保留）
##   - 装备类天然走交换分支（instance!=null 不参与合并条件）
##
## 成功返回 true 并发 [signal EventBus.inventory_changed]；
## 失败（index 越界 / from==to / from 空槽）返回 false 不发信号。
func move(from: int, to: int) -> bool:
	if from < 0 or from >= max_slots or to < 0 or to >= max_slots:
		return false
	if from == to:
		return false
	var src = slots[from]
	if src == null:
		return false  # 空槽不允许做源
	var dst = slots[to]

	# 同 def + 都是堆叠类 → 合并
	if dst != null and dst.def == src.def and src.instance == null and dst.instance == null:
		var max_stack: int = src.def.get_max_stack()
		if max_stack > 0 and dst.count < max_stack:
			var fill: int = mini(max_stack - dst.count, src.count)
			if fill > 0:
				dst.count += fill
				src.count -= fill
				if src.count <= 0:
					slots[from] = null
				EventBus.inventory_changed.emit(owner_character)
				return true
		# 已满：回退到交换分支

	# 普通交换 / 平移
	slots[to] = src
	slots[from] = dst
	EventBus.inventory_changed.emit(owner_character)
	return true


## 使用槽位中的物品。所有具体行为由 fragment.on_use 钩子决定。
##
## 通用消耗规则：所有 fragment.on_use 都返回 true 且 def.consumable=true → 扣 1 个堆叠。
func use(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= max_slots:
		return false
	var s = slots[slot_index]
	if s == null:
		return false
	var def: ItemDefinition = s.def
	var instance: ItemInstance = s.instance

	# 让所有 Fragment 决定使用行为
	# 任一 Fragment 返回 false → 阻断后续 consume
	var allow_consume := true
	for f in def.fragments:
		var ok: bool = f.on_use(owner_character, instance)
		if not ok:
			allow_consume = false

	# 通用消耗逻辑（Consumable=1 → 扣 1 个堆叠）
	if allow_consume and def.consumable:
		remove(slot_index, 1)
	return true


# ─────────────────────────────────────────────────────────────
# 查询
# ─────────────────────────────────────────────────────────────


## 找第一个空槽位 index，无空槽返回 -1。
func _find_empty_slot() -> int:
	for i in range(max_slots):
		if slots[i] == null:
			return i
	return -1


## 找第一个含指定 def 的槽位 index。
func find_first_by_def(def: ItemDefinition) -> int:
	for i in range(max_slots):
		var s = slots[i]
		if s != null and s.def == def:
			return i
	return -1


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────


func _add_internal(def: ItemDefinition, count: int) -> int:
	if def == null or count <= 0:
		return 0

	# 询问 Fragment：是否拦截入库？（Currency 路由到 CurrencyManager 等）
	for f in def.fragments:
		if f.intercepts_inventory_add(def, count):
			var consumed: int = f.handle_inventory_add(owner_character, def, count)
			# 拦截路径不发 inventory_changed（背包未变），只发 item_added（HUD 飘字订阅）
			if consumed > 0:
				EventBus.item_added.emit(owner_character, def, consumed)
			return consumed

	# 装备类（每件独立 instance）→ count 强制 1，每件占独立槽，**进入背包时滚字**
	if def.has_fragment(Fragment_Equip):
		return _add_unique_equip(def, count)

	# 简单堆叠类（药水/任务道具/材料）→ instance=null 节省内存
	return _add_stackable(def, count)


func _add_unique_equip(def: ItemDefinition, count: int) -> int:
	var added: int = 0
	for i in count:
		var slot_idx: int = _find_empty_slot()
		if slot_idx == -1:
			break
		var inst := ItemInstance.create_new(def)  # ★ 滚字在这里发生（Fragment_Equip.on_instance_created）
		slots[slot_idx] = {"def": def, "instance": inst, "count": 1}
		added += 1
	if added > 0:
		EventBus.inventory_changed.emit(owner_character)
		EventBus.item_added.emit(owner_character, def, added)
	return added


func _add_stackable(def: ItemDefinition, count: int) -> int:
	var max_stack: int = def.get_max_stack()
	if max_stack <= 0:
		# Stack=0 但又没 Fragment_Currency 拦截 → 配置错误（应在 Excel 修正）
		GameLogger.warn("Items", "Item %d has Stack=0 but not intercepted by any fragment" % def.item_id)
		return 0
	var remaining: int = count
	# 先填已有同 def 槽
	for i in range(max_slots):
		if remaining <= 0:
			break
		var s = slots[i]
		if s != null and s.def == def and s.instance == null and s.count < max_stack:
			var fill: int = mini(max_stack - s.count, remaining)
			s.count += fill
			remaining -= fill
	# 再放空槽
	for i in range(max_slots):
		if remaining <= 0:
			break
		if slots[i] == null:
			var fill: int = mini(max_stack, remaining)
			slots[i] = {"def": def, "instance": null, "count": fill}
			remaining -= fill
	var added: int = count - remaining
	if added > 0:
		EventBus.inventory_changed.emit(owner_character)
		EventBus.item_added.emit(owner_character, def, added)
	return added


func _add_existing_instance(instance: ItemInstance) -> int:
	var def: ItemDefinition = instance.get_def()
	var slot_idx: int = _find_empty_slot()
	if slot_idx == -1:
		return 0
	slots[slot_idx] = {"def": def, "instance": instance, "count": 1}
	EventBus.inventory_changed.emit(owner_character)
	return 1
