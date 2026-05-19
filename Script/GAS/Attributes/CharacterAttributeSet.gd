## 通用角色属性集（玩家与怪物共用）。
##
## R-DATA-01：所有数值默认值仅作为编辑器入口，实际值由 .tres 配置覆盖。
class_name CharacterAttributeSet
extends AttributeSet

# 生命
@export var max_health: float = 100.0
@export var health: float = 100.0

# 法力
@export var max_mana: float = 50.0
@export var mana: float = 50.0

# 战斗
@export var attack: float = 10.0
@export var defense: float = 5.0

# 移动
@export var move_speed: float = 200.0
