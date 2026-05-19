## 消耗品（药水等）。
##
## 使用时对持有者 ASC 应用 effect。一般是 INSTANT GE。
class_name ConsumableDefinition
extends ItemDefinition

## 使用时施加的效果。
@export var effect: GameplayEffect = null
