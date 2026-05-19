## 关卡定义（Resource，M5）。
##
## LevelManager 通过 .tres 加载，含场景 / BGM / Boss 引用 / 是否为 BossRoom。
class_name LevelDef
extends Resource

@export var level_id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene = null
@export var bgm: AudioStream = null
@export var is_boss_room: bool = false
