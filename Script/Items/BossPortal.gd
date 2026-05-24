## Boss 房传送门（3D） — **@deprecated 2026-05-23**。
##
## ⚠️ 本类与 [LevelTransitionArea] 功能 95% 重叠。新场景请直接使用 [LevelTransitionArea]
## （后者支持 require_interact 双模式 + 更完整的 input prompt 流程）。
##
## 保留本类仅用于已存在场景的向后兼容；启动时会 push_warning 提醒迁移。
## 计划：批次 5 / 6 期间将所有引用 BossPortal 的场景迁到 LevelTransitionArea，然后删除本类。
class_name BossPortal
extends Area3D


@export var target_level: LevelDef = null

## 备用：以路径加载 LevelDef.tres，规避循环 ext_resource。
## target_level 为 null 时使用本路径运行时加载。
@export var target_level_path: String = ""


func _ready() -> void:
	push_warning("BossPortal at %s is deprecated, please migrate to LevelTransitionArea" % str(get_path()))
	body_entered.connect(_on_entered)
	area_entered.connect(_on_area)


func _on_entered(body: Node) -> void:
	_try_enter(body)


func _on_area(area: Area3D) -> void:
	if area is HurtboxComponent and area.owner_node != null:
		_try_enter(area.owner_node)


func _try_enter(picker: Node) -> void:
	if picker == null or not picker.is_in_group(&"player"):
		return
	var level: LevelDef = target_level
	if level == null and target_level_path != "":
		if ResourceLoader.exists(target_level_path):
			level = load(target_level_path) as LevelDef
	# level 缺失 = 配置 bug（target_level 和 target_level_path 都没填）
	assert(level != null, "BossPortal at %s: both target_level and target_level_path are empty" % str(get_path()))
	GameLogger.info("Level", "Player entered portal -> %s" % level.level_id)
	LevelManager.load_level(level)
