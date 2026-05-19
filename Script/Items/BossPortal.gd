## Boss 房传送门（M5）。
##
## 玩家踩进时通过 LevelManager.load_level 切到指定 Boss 关卡。
class_name BossPortal
extends Area2D

@export var target_level: LevelDef = null


func _ready() -> void:
	body_entered.connect(_on_entered)
	area_entered.connect(_on_area)


func _on_entered(body: Node) -> void:
	_try_enter(body)


func _on_area(area: Area2D) -> void:
	if area is HurtboxComponent and area.owner_node != null:
		_try_enter(area.owner_node)


func _try_enter(picker: Node) -> void:
	if target_level == null or picker == null or not picker.is_in_group(&"player"):
		return
	GameLogger.info("Level", "Player entered portal -> %s" % target_level.level_id)
	LevelManager.load_level(target_level)
