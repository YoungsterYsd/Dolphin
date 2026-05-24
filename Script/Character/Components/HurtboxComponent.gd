## 受击判定盒（3D）。
##
## 挂在防御方角色下，被对方的 [HitboxComponent] 命中时广播 [signal damaged]。
class_name HurtboxComponent
extends Area3D

## 收到伤害请求。amount 由攻击方传入，最终结算由 ASC + GE 完成。
signal damaged(amount: float, source: Node)


## 持有该 Hurtbox 的角色根节点（一般是 BaseCharacter）。
@export var owner_node: Node


func _ready() -> void:
	if owner_node == null:
		owner_node = get_parent()


## 由攻击方调用，传入伤害数值与来源。
func take_damage(amount: float, source: Node) -> void:
	damaged.emit(amount, source)
