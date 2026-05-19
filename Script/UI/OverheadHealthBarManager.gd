## 头顶血条管理器（M8 引入）。
##
## 挂在 HUD 根 Control 下；监听 [signal EventBus.enemy_spawned] / [signal EventBus.enemy_died]
## 自动维护每个敌人头顶的 [EnemyOverheadHealthBar]。
##
## 对 Boss 不挂头顶血条（Boss 用顶部 [LayeredBossHealthBar]）。
class_name OverheadHealthBarManager
extends Control

const BOSS_CATEGORY: StringName = &"boss"

var _bars: Dictionary = {}  # Node(enemy) -> EnemyOverheadHealthBar
var _cfg: HealthBarConfig = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pull_config()
	if EventBus.has_signal(&"enemy_spawned"):
		EventBus.enemy_spawned.connect(_on_enemy_spawned)
	if EventBus.has_signal(&"enemy_died"):
		EventBus.enemy_died.connect(_on_enemy_died)


# ─────────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────────

func _on_enemy_spawned(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if _bars.has(enemy):
		return  # 重复 spawn 信号忽略
	# 跳过 Boss（Boss 用专门血条）
	if _is_boss(enemy):
		return
	# 找 ASC
	var asc: AbilitySystemComponent = _find_asc(enemy)
	if asc == null:
		return
	# 创建血条
	var bar := EnemyOverheadHealthBar.new()
	add_child(bar)
	var is_elite: bool = _is_elite(enemy)
	bar.bind_to(enemy, asc, _cfg, is_elite)
	_bars[enemy] = bar


func _on_enemy_died(enemy: Node) -> void:
	if not _bars.has(enemy):
		return
	var bar: EnemyOverheadHealthBar = _bars[enemy]
	_bars.erase(enemy)
	# 延迟 free（让 bar 隐藏动画播完）
	if is_instance_valid(bar):
		bar.queue_free()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _pull_config() -> void:
	var cfg_node: Node = get_tree().root.get_node_or_null(^"ConfigCenter")
	if cfg_node != null:
		_cfg = cfg_node.get_health_bar_config()
	if _cfg == null:
		_cfg = HealthBarConfig.new()


func _find_asc(enemy: Node) -> AbilitySystemComponent:
	var direct: Node = enemy.get_node_or_null(^"AbilitySystemComponent")
	if direct is AbilitySystemComponent:
		return direct
	return null


func _is_boss(enemy: Node) -> bool:
	# 看 CharacterInstanceEntry.category 或节点是否在 boss 组
	if enemy.is_in_group(BOSS_CATEGORY):
		return true
	# 通过 entity_id 查 CharacterInstanceEntry.category（enum 值 2 = BOSS）
	var def: CharacterInstanceEntry = _get_entry(enemy)
	if def != null and def.category == CharacterInstanceEntry.Category.BOSS:
		return true
	return false


func _is_elite(enemy: Node) -> bool:
	var def: CharacterInstanceEntry = _get_entry(enemy)
	if def != null and def.category == CharacterInstanceEntry.Category.ELITE:
		return true
	return false


func _get_entry(enemy: Node) -> CharacterInstanceEntry:
	if enemy == null:
		return null
	if not ("entity_id" in enemy):
		return null
	var eid: StringName = enemy.entity_id
	if eid == &"":
		return null
	var cfg_node: Node = get_tree().root.get_node_or_null(^"ConfigCenter")
	if cfg_node == null:
		return null
	return cfg_node.get_character_def(eid)
