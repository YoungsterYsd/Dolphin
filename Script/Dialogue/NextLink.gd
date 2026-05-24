## 对话节点出边（Resource）。
##
## 每个 [DialogueNode] 拥有 0~N 条 NextLink；运行时按数组顺序求值 [member cond_id]，
## 选第一条满足条件的 next_id 推进。cond_id<=0 视为"无条件通过"。
class_name NextLink
extends Resource

## 目标节点 id（[code]Dialogue.sub_id[/code]，必须在同一 [DialogueGraph.nodes] 中存在）。
@export var next_id: int = 0

## 显示条件（[code]Condition.id[/code]；<=0 = 无条件，由 [ConditionEvaluator] 求值）。
@export var cond_id: int = 0
