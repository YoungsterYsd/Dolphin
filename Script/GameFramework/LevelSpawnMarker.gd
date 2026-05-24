## 关卡出生点标记（Marker3D 派生）。
##
## 用法：
##   - 在关卡场景内放一个 [LevelSpawnMarker] 节点
##   - 设置 [member spawn_id]（如 &"main_entrance" / &"from_boss" / &"checkpoint_1"）
##   - LevelManager 切场景时按 [LevelDef.spawn_marker_id] 找到匹配 Marker，把玩家 teleport 到此处
##   - 同关卡可有多个 Marker；不同入口（村→副本东门 / 副本→村南门）配不同 spawn_id
##
## 设计：纯 Marker3D 子类 + add_to_group("level_spawn")，方便 LevelManager 用 group 查找。
class_name LevelSpawnMarker
extends Marker3D


## 出生点 ID。同一场景内应唯一。
@export var spawn_id: StringName = &"default"


func _ready() -> void:
	add_to_group(&"level_spawn")
