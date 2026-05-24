## 头顶血条管理器。
##
## 挂在 HUD 根 Control 下；监听 [signal EventBus.enemy_spawned] / [signal EventBus.enemy_died]
## 自动维护每个敌人头顶的 [EnemyOverheadHealthBar]。Boss 不挂头顶血条（用 [LayeredBossHealthBar]）。
##
## R-Excel 重构（2026-05-23）：Boss/Elite 判定优先看 Node groups（"boss" / "elite"），
## 兜底走 [code]ConfigCenter.is_boss(kind, data_id)[/code] 查 Monster_Data.type
## （唯一数据来源，按用户决策 Q3）。
class_name OverheadHealthBarManager
extends BaseWidget

const BOSS_GROUP: StringName = &"boss"
const ELITE_GROUP: StringName = &"elite"

var _bars: Dictionary = {}  # Node(enemy) -> EnemyOverheadHealthBar
var _cfg: HealthBarConfig = null


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pull_config()
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	EventBus.enemy_died.connect(_on_enemy_died)
	# 兜底：本节点 _ready 早于/晚于 EnemyCharacter._ready 都可能发生（场景树顺序敏感），
	# 主动扫描一次 "enemy" 组里已存在的实例，避免错过 enemy_spawned 信号。
	call_deferred(&"_register_existing_enemies")


# ─────────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────────

func _on_enemy_spawned(enemy: Node) -> void:
	_register_enemy(enemy)


func _on_enemy_died(enemy: Node) -> void:
	if not _bars.has(enemy):
		return
	var bar: EnemyOverheadHealthBar = _bars[enemy]
	_bars.erase(enemy)
	# 延迟 free（让 bar 隐藏动画播完）
	if is_instance_valid(bar):
		bar.queue_free()


# ─────────────────────────────────────────────────────────────
# 注册逻辑
# ─────────────────────────────────────────────────────────────

func _register_existing_enemies() -> void:
	if not is_inside_tree():
		return
	for enemy in get_tree().get_nodes_in_group(&"enemy"):
		_register_enemy(enemy)


func _register_enemy(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if _bars.has(enemy):
		return  # 重复信号或重复扫描忽略
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


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _pull_config() -> void:
	# R-Core：ConfigCenter 走 class_name 强类型直访
	_cfg = ConfigCenter.get_health_bar_config()


func _find_asc(enemy: Node) -> AbilitySystemComponent:
	var direct: Node = enemy.get_node_or_null(^"AbilitySystemComponent")
	if direct is AbilitySystemComponent:
		return direct
	return null


func _is_boss(enemy: Node) -> bool:
	# 优先看 group（BossAI 或场景手动加进去的）
	if enemy.is_in_group(BOSS_GROUP):
		return true
	# 兜底：通过 (kind, data_id) 查 Monster_Data.type
	var kind_id: Vector2i = _get_kind_data_id(enemy)
	if kind_id == Vector2i.ZERO:
		return false
	return ConfigCenter.is_boss(kind_id.x, kind_id.y)


func _is_elite(enemy: Node) -> bool:
	if enemy.is_in_group(ELITE_GROUP):
		return true
	var kind_id: Vector2i = _get_kind_data_id(enemy)
	if kind_id == Vector2i.ZERO:
		return false
	return ConfigCenter.is_elite(kind_id.x, kind_id.y)


## 从 enemy 节点取 (kind, data_id)。失败返回 [code]Vector2i.ZERO[/code]（视为非法）。
func _get_kind_data_id(enemy: Node) -> Vector2i:
	if enemy == null:
		return Vector2i.ZERO
	if not ("kind" in enemy) or not ("data_id" in enemy):
		return Vector2i.ZERO
	var did: int = int(enemy.data_id)
	if did <= 0:
		return Vector2i.ZERO
	return Vector2i(int(enemy.kind), did)
