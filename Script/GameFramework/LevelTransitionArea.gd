## 通用关卡传送门（Area3D）。
##
## 替代 [BossPortal] 的"特殊化关卡入口"——任意场景任意位置都可放置。
## 玩家踩进时调 [LevelManager.load_level]。
##
## 配置：
##   - target_level: LevelDef.tres
##   - require_interact: 是否需要按 G 才触发（false=接触即触发）
##   - prompt_text: 按 G 模式下的提示文本
class_name LevelTransitionArea
extends Area3D


## 目标关卡定义。两种配置方式（二选一）：
##   1. **target_level**: 直接拖 LevelDef.tres（推荐场景内 inspector 配置）
##   2. **target_level_path**: String 形式，运行时 load（用于规避循环引用：当目标场景与本场景互相引用时）
@export var target_level: LevelDef = null

## 备用：以路径形式配置 LevelDef.tres（避免循环 ext_resource）。
## 当 target_level 为 null 时使用此路径运行时加载。
@export var target_level_path: String = ""

## 是否需要玩家按 G 才传送（true 时实现 [InteractableTarget] 风格交互）。
## false（默认）= 触碰即传送（旧 BossPortal 行为）。
@export var require_interact: bool = false

## 按 G 模式的提示文本。
@export var prompt_text: String = "[G] 进入"

## 显示名（提示用）。
@export var display_name: String = "传送门"


# Internal — 玩家是否在范围内（require_interact 模式用）
var _player_in_range: Node = null


func _ready() -> void:
	add_to_group(&"level_transition")
	if require_interact:
		add_to_group(&"interactable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)


# ─────────────────────────────────────────────────────────────
# Area 信号
# ─────────────────────────────────────────────────────────────

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player"):
		return
	if require_interact:
		_player_in_range = body
		EventBus.interaction_target_entered.emit(self)
	else:
		_trigger(body)


func _on_body_exited(body: Node) -> void:
	if body != _player_in_range:
		return
	_player_in_range = null
	if require_interact:
		EventBus.interaction_target_left.emit(self)


func _on_area_entered(area: Area3D) -> void:
	# 兼容老的 HurtboxComponent 路径（未来可移除）
	if area is HurtboxComponent and area.owner_node != null:
		var owner: Node = area.owner_node
		if not owner.is_in_group(&"player"):
			return
		if not require_interact:
			_trigger(owner)


# ─────────────────────────────────────────────────────────────
# InteractableTarget 接口（require_interact 时由 PlayerCharacter 调用）
# ─────────────────────────────────────────────────────────────

func interact(player: Node) -> void:
	_trigger(player)


func is_interactable() -> bool:
	return require_interact and _player_in_range != null


func get_prompt_anchor() -> Vector3:
	return global_position + Vector3.UP * 1.5


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _trigger(_player: Node) -> void:
	var level: LevelDef = target_level
	if level == null and target_level_path != "":
		if ResourceLoader.exists(target_level_path):
			level = load(target_level_path) as LevelDef
	# R-CODE-01：target_level / target_level_path 都没填是配置 bug
	assert(level != null,
		"%s: both target_level and target_level_path are empty/invalid" % name)
	GameLogger.info("Level", "Player entered transition -> %s" % level.level_id)
	# R-ARCH-03：LevelManager 是 Autoload，直访
	LevelManager.load_level(level)
