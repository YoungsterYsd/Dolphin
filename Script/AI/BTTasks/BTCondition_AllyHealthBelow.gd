## 检测同组（友军）HP 比例是否低于阈值。
##
## 语义：「检测其他怪物血量」。
##
## [member ally_group] 默认为 [code]&"enemy"[/code]（与 EnemyCharacter add_to_group 对齐）。
## 自身会从匹配列表中排除。
##
## [member mode]：
##   - [code]ANY[/code]：任一友军 HP 比例 < ratio 即 SUCCESS
##   - [code]AVG[/code]：所有友军 HP 平均比例 < ratio 即 SUCCESS
##
## LimboAI 改造（迁移自旧 BTCondition_AllyHealthBelow）。
@tool
extends BTCondition


enum Mode {
	ANY,
	AVG,
}


## 友军组名。
@export var ally_group: StringName = &"enemy"

## 比例阈值。
@export_range(0.0, 1.0, 0.01) var ratio: float = 0.3

## 判定模式。
@export var mode: Mode = Mode.ANY

## 是否把自己也算进友军（一般 false）。
@export var include_self: bool = false


func _generate_name() -> String:
	var mode_str: String = "ANY" if mode == Mode.ANY else "AVG"
	return "Ally(%s) HP %s < %d%%" % [ally_group, mode_str, int(ratio * 100.0)]


func _tick(_delta: float) -> Status:
	if agent == null or not agent.is_inside_tree():
		return FAILURE
	var allies: Array = agent.get_tree().get_nodes_in_group(ally_group)
	if allies.is_empty():
		return FAILURE

	var sum: float = 0.0
	var count: int = 0
	for ally in allies:
		if ally == null:
			continue
		if not include_self and ally == agent:
			continue
		var ally_asc: Variant = ally.get(&"asc") if "asc" in ally else null
		if ally_asc == null or not ally_asc.has_method(&"get_attribute"):
			continue
		var hp: float = ally_asc.call(&"get_attribute", &"health", -1.0)
		var max_hp: float = ally_asc.call(&"get_attribute", &"max_health", 0.0)
		if max_hp <= 0.0 or hp < 0.0:
			continue
		var r: float = hp / max_hp
		if mode == Mode.ANY:
			if r < ratio:
				return SUCCESS
		else:
			sum += r
			count += 1
	if mode == Mode.AVG:
		if count == 0:
			return FAILURE
		return SUCCESS if (sum / float(count)) < ratio else FAILURE
	return FAILURE  # ANY 没找到符合
