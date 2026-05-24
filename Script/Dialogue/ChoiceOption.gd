## 玩家选项（Resource）。
##
## 由 [ChoiceNode] 持有。运行时按 [member cond_id] 过滤：
##   - 不满足 → 该选项**不显示**（不灰显，避免暴露剧情）
class_name ChoiceOption
extends Resource

## 按钮文本（支持 {var:x} / {tag:x} / {player_name} 占位符）。
@export var text: String = ""

## 显示条件（[code]Condition.id[/code]；<=0 = 始终显示，由 [ConditionEvaluator] 求值）。
@export var cond_id: int = 0

## 选中后跳转的目标节点 id（[code]Dialogue.sub_id[/code]）。
@export var next_id: int = 0
