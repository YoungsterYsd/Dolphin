## 选项节点（Resource）。
##
## 玩家从 [member choices] 中选一个；选项不满足 condition_expr 时不显示。
## [DialogueRunner] 会先过滤再 emit [signal EventBus.dialogue_choice_presented]。
class_name ChoiceNode
extends DialogueNode

## 提示文字（可空；UI 在选项列表上方显示）。
@export_multiline var prompt: String = ""

## 选项列表。
@export var choices: Array[ChoiceOption] = []


func get_node_kind() -> StringName:
	return &"choice"
