## 对话图（Resource）。
##
## 一份内存对象 = 一段完整对话；由 [DialogueGraphFactory] 从 Dialogue.csv 构造。
##
## **数据驱动**（M12）：节点存储为扁平数组（[member nodes]），通过 [member start_node_id] 指定入口；
## 节点间通过 [member DialogueNode.next_links] / [member ChoiceOption.next_id] 引用 node_id 互相跳转。
class_name DialogueGraph
extends Resource

## 全局唯一图 id（CSV 主键 [code]Dialogue.id[/code]）。
@export var graph_id: int = 0

## 入口节点 id（必须存在于 [member nodes] 中；通常是 sub_id 最小的节点）。
@export var start_node_id: int = 0

## 节点列表（按 sub_id 升序）。
@export var nodes: Array[DialogueNode] = []


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 按 node_id 查找节点；找不到返回 null。
func get_node_by_id(id: int) -> DialogueNode:
	for n in nodes:
		if n != null and n.node_id == id:
			return n
	return null


## 节点总数（debug）。
func size() -> int:
	return nodes.size()
