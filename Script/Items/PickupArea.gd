## 地面拾取区（M5）。
##
## 玩家进入 Area2D 范围 → 自动加进玩家背包，自身销毁。
## item 通过 .tres 拖入。M5 不做按 E 拾取，简化为接触即拾取。
class_name PickupArea
extends Area2D

@export var item: ItemDefinition = null
@export var count: int = 1


func _ready() -> void:
	# 与玩家 Hurtbox（layer=2）相互检测：
	# PickupArea collision_layer 任意（一般 32），collision_mask 包含 2（玩家 hurtbox）
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _on_body_entered(body: Node) -> void:
	_try_pickup(body)


func _on_area_entered(area: Area2D) -> void:
	if area is HurtboxComponent and area.owner_node != null:
		_try_pickup(area.owner_node)


func _try_pickup(picker: Node) -> void:
	if item == null or picker == null:
		return
	if not picker.is_in_group(&"player"):
		return
	var inv: InventoryComponent = picker.get_node_or_null("InventoryComponent") as InventoryComponent
	if inv == null:
		return
	var added: int = inv.add(item, count)
	if added > 0:
		queue_free()
