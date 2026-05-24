## 检测自身 HP 比例是否低于阈值。
##
## 语义：「检测自身血量」。
##
## 通过 agent.asc.get_attribute(&"health") / get_attribute(&"max_health") 读 HP。
## 缺失 ASC 时返回 FAILURE。
##
## LimboAI 改造（迁移自旧 BTCondition_SelfHealthBelow）。
@tool
extends BTCondition


## 比例阈值（0.0 ~ 1.0）。HP/MaxHP < ratio 时返回 SUCCESS。
@export_range(0.0, 1.0, 0.01) var ratio: float = 0.3


func _generate_name() -> String:
	return "HP < %d%%" % int(ratio * 100.0)


func _tick(_delta: float) -> Status:
	if agent == null:
		return FAILURE
	var asc: Node = agent.get(&"asc") if "asc" in agent else null
	if asc == null or not asc.has_method(&"get_attribute"):
		return FAILURE
	var hp: float = asc.call(&"get_attribute", &"health", -1.0)
	var max_hp: float = asc.call(&"get_attribute", &"max_health", 0.0)
	if max_hp <= 0.0 or hp < 0.0:
		return FAILURE
	return SUCCESS if (hp / max_hp) < ratio else FAILURE
