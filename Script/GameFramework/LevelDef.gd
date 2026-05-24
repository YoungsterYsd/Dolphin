## 关卡定义（Resource）。
##
## LevelManager 通过 .tres 加载，含场景 / BGM / 出生点 / 加载提示等。
class_name LevelDef
extends Resource

## 关卡 ID（全局唯一；用于持久化、对话引用）。
@export var level_id: StringName = &""

## 玩家可见的关卡名（如 "村庄"、"BossRoom 01"）。会被 AreaNameBannerWidget 显示。
@export var display_name: String = ""

## 主场景资源。
@export var scene: PackedScene = null

## 关卡 BGM（null 则保持当前不切）。
@export var bgm: AudioStream = null

## 是否为 Boss 房（HUD 据此决定是否显示 BossHealthBar / 切 BossRush 布局）。
@export var is_boss_room: bool = false

## 玩家出生点 Marker 名（场景内必须存在 [LevelSpawnMarker] 节点且 [member spawn_id] 匹配；
## 空字符串则不主动定位，玩家保留当前 transform）。
@export var spawn_marker_id: StringName = &""

## 加载界面副文本（提示语 / 章节描述）。空字符串 → 默认显示「正在加载…」。
@export var loading_tip: String = ""

## fade out 持续时间（秒）。
@export var fade_out_seconds: float = 0.35

## fade in 持续时间（秒）。
@export var fade_in_seconds: float = 0.35

## fade 颜色（默认黑）。可改为白屏（雪山 / 教堂场景）。
@export var fade_color: Color = Color.BLACK


## 关卡启动时自动接取的任务系列 id 列表（M12；A3 决策）。
##
## [LevelManager] 在 [signal EventBus.level_changed] 之后调 [QuestSystem.bulk_accept]，
## 让对应任务进入 sub_id=1 active 状态。
##
## 例：[code]init_quest_ids = [1, 5][/code] 意为关卡启动时同时开启 quest_id=1 和 quest_id=5 的系列。
@export var init_quest_ids: PackedInt32Array = PackedInt32Array()
