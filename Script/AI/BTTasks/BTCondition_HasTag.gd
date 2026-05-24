## 检测自身 ASC 是否持有某 GameplayTag。
##
## 语义：通用 tag 判定（眩晕、嘲讽、buff 状态等扩展用）。
##
## 通过 [member AbilitySystemComponent.has_tag] 走父匹配（has_tag(&"state.buff") 含
## state.buff.haste 时返回 true）。
##
## LimboAI 改造（迁移自旧 BTCondition_HasTag）：
##   - 也可改用 LimboAI 内置 [BTCheckAgentProperty]，但保留本类便于策划在 TaskPalette 直观看到 tag 名
@tool
extends BTCondition


@export var tag: StringName = &""


func _generate_name() -> String:
	if tag == &"":
		return "HasTag (unset)"
	return "HasTag: %s" % tag


func _tick(_delta: float) -> Status:
	if tag == &"":
		return FAILURE
	if agent == null:
		return FAILURE
	var asc: Node = agent.get(&"asc") if "asc" in agent else null
	if asc == null or not asc.has_method(&"has_tag"):
		return FAILURE
	return SUCCESS if asc.call(&"has_tag", tag) else FAILURE
