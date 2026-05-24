## 地面拾取区（3D）。
##
## 玩家进入 Area3D 范围 → 自动加进玩家背包，自身销毁。
## 简化为接触即拾取（无需按键）。
##
## **配置方式**（Phase 1 重构后只走 def_id；ItemDefinition .tres 字段已废弃）：
##   - `item_def_id`：CSV `Item_Data` 主键（如 5 = 测试装备）
##   - `count`：堆叠数；装备 / Currency 类内部会按 Fragment 决定行为
##
## 走 [method InventoryComponent.add_by_id]：
##   - 装备类自动 [code]ItemInstance.create_new[/code] → 滚字
##   - Currency 类被 [code]Fragment_Currency.intercepts_inventory_add[/code] 拦截入 CurrencyManager
class_name PickupArea
extends Area3D

@export var item_def_id: int = 0
@export var count: int = 1


func _ready() -> void:
	# 与玩家 Hurtbox（layer=2）相互检测：
	# PickupArea collision_layer 任意（一般 32），collision_mask 包含 2（玩家 hurtbox）
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _on_body_entered(body: Node) -> void:
	_try_pickup(body)


func _on_area_entered(area: Area3D) -> void:
	if area is HurtboxComponent and area.owner_node != null:
		_try_pickup(area.owner_node)


func _try_pickup(picker: Node) -> void:
	# R-CODE-01：item_def_id <= 0 是配置 bug（场景里没填 id）
	assert(item_def_id > 0, "PickupArea: item_def_id<=0 at %s (forgot to set in editor?)" % str(get_path()))
	if picker == null or not picker.is_in_group(&"player"):
		return
	# R-CHAR-01：用 NodeFinder 强类型查找
	var inv: InventoryComponent = NodeFinder.find_first_child_of_type(picker, InventoryComponent) as InventoryComponent
	if inv == null:
		return
	var added: int = inv.add_by_id(item_def_id, count)
	if added > 0:
		queue_free()
