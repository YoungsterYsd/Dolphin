## 对话节点基类（Resource）。
##
## 子类：[SpeechNode]（说话）/ [ChoiceNode]（选项）。
## 子类必须覆写 [method get_node_kind] 返回标识符（运行时 [DialogueRunner._enter_node] 用 match 分发）。
##
## **M12 简化**：所有 effect_kind / payload 概念已移除；任务接取/交付等业务由各业务系统
## 订阅 [signal EventBus.dialogue_ended] 自行处理（A1 决策：对话纯解耦）。
class_name DialogueNode
extends Resource

## 节点 id（CSV 子主键 [code]Dialogue.sub_id[/code]）。同一 graph 内唯一。
@export var node_id: int = 0

## 出边列表。SpeechNode 通常 0~多条；ChoiceNode 通常不用（由 ChoiceOption.next_id 决定）。
@export var next_links: Array[NextLink] = []


## 子类必须覆写：返回节点种类标识。
## 约定值：&"speech" / &"choice"。
func get_node_kind() -> StringName:
	return &"unknown"
