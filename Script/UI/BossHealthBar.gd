## Boss 顶部血条（M5 引入，M8 升级为分层 + ghost 追条）。
##
## 监听 EventBus.attribute_changed（boss 的 health）+ boss_phase_changed（阶段变化高亮）。
## M8 新增：
##   - **主血条**（红，快速下降到当前值）
##   - **ghost 追条**（黄，延迟 `boss_ghost_chase_delay` 秒后以 `boss_ghost_chase_speed` HP/s 追赶）
##   - **分段视觉**：按 `boss_layer_step` HP 横向切分，每段画一条短分隔线
##
## 参数全部走 [HealthBarConfig]（R-DATA-02）。
class_name BossHealthBar
extends Control

@export var boss: Node = null

@onready var bar: ProgressBar = $Bar  # 主血条（红，立即跟随真实值）
@onready var name_label: Label = $NameLabel
@onready var phase_label: Label = $PhaseLabel

# M8：ghost 追条（代码创建，半透明叠加在主条上方）
var _ghost_bar: ProgressBar = null
var _layer_overlay: Control = null  # 自绘分段线

var _cfg: HealthBarConfig = null

# 追条状态
var _target_hp: float = 0.0   # 主条目标（= 当前实际 hp）
var _ghost_hp: float = 0.0    # ghost 当前显示
var _ghost_delay_timer: float = 0.0  # 距离上次伤害的时间


func _ready() -> void:
	_pull_config()
	_build_ghost_and_overlay()
	# 信号无条件连接，回调内判断 boss 引用是否匹配
	EventBus.attribute_changed.connect(_on_attr)
	EventBus.boss_phase_changed.connect(_on_phase)
	EventBus.enemy_died.connect(_on_died)
	visible = (boss != null)
	if boss != null:
		_setup()
	set_process(true)


func _process(delta: float) -> void:
	if _ghost_bar == null:
		return
	# Ghost 追赶逻辑
	if _ghost_hp > _target_hp:
		_ghost_delay_timer += delta
		if _cfg != null and _ghost_delay_timer >= _cfg.boss_ghost_chase_delay:
			var speed: float = _cfg.boss_ghost_chase_speed
			_ghost_hp = max(_target_hp, _ghost_hp - speed * delta)
			_ghost_bar.value = _ghost_hp
	elif _ghost_hp < _target_hp:
		# 治疗：ghost 立即跟上
		_ghost_hp = _target_hp
		_ghost_bar.value = _ghost_hp


# ─────────────────────────────────────────────────────────────
# 公开 API（保留 M5 签名）
# ─────────────────────────────────────────────────────────────

func bind_boss(b: Node) -> void:
	boss = b
	visible = true
	_setup()
	GameLogger.info("UI", "BossHealthBar bind_boss=%s" % b.name)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _pull_config() -> void:
	var cfg_node: Node = get_tree().root.get_node_or_null(^"ConfigCenter")
	if cfg_node != null:
		_cfg = cfg_node.get_health_bar_config()
	if _cfg == null:
		_cfg = HealthBarConfig.new()


func _build_ghost_and_overlay() -> void:
	if bar == null:
		return
	# Ghost：作为主条的兄弟节点，叠在下层（先 add_child）
	_ghost_bar = ProgressBar.new()
	_ghost_bar.show_percentage = false
	_ghost_bar.modulate = _cfg.boss_ghost_color
	# 同样的 anchor / offset
	_ghost_bar.size_flags_horizontal = bar.size_flags_horizontal
	bar.get_parent().add_child(_ghost_bar)
	bar.get_parent().move_child(_ghost_bar, bar.get_index())  # 移到 bar 前面（叠下层）
	_ghost_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 复制 bar 的位置（直接用 bar 同样的 rect）
	_ghost_bar.global_position = bar.global_position
	_ghost_bar.size = bar.size
	# 把主条调红色
	bar.modulate = _cfg.boss_main_color

	# 分段叠加层：覆盖在主条之上画分隔线
	_layer_overlay = Control.new()
	_layer_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_layer_overlay)
	_layer_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer_overlay.draw.connect(_draw_layer_lines)


func _setup() -> void:
	if boss == null:
		return
	name_label.text = boss.name
	var asc: AbilitySystemComponent = boss.get_node_or_null("AbilitySystemComponent") as AbilitySystemComponent
	if asc != null and asc.attribute_set != null:
		var max_hp: float = asc.attribute_set.get_attr(&"max_health")
		var cur_hp: float = asc.attribute_set.get_attr(&"health")
		bar.max_value = max_hp
		bar.value = cur_hp
		if _ghost_bar != null:
			_ghost_bar.max_value = max_hp
			_ghost_bar.value = cur_hp
		_target_hp = cur_hp
		_ghost_hp = cur_hp
	phase_label.text = "Phase 0"
	if _layer_overlay != null:
		_layer_overlay.queue_redraw()


func _draw_layer_lines() -> void:
	if _cfg == null or _layer_overlay == null or bar == null:
		return
	var max_hp: float = bar.max_value
	if max_hp <= 0.0:
		return
	var step: int = _cfg.boss_layer_step
	if step <= 0:
		return
	var w: float = _layer_overlay.size.x
	var h: float = _layer_overlay.size.y
	var hp: float = float(step)
	var line_color := Color(0.05, 0.05, 0.05, 0.9)
	while hp < max_hp:
		var x: float = (hp / max_hp) * w
		_layer_overlay.draw_line(Vector2(x, 0), Vector2(x, h), line_color, 2.0)
		hp += float(step)


# ─────────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────────

func _on_attr(owner_node: Node, attr_name: StringName, _old: float, new: float) -> void:
	if boss == null or owner_node != boss:
		return
	if attr_name == &"health":
		bar.value = new
		_target_hp = new
		_ghost_delay_timer = 0.0  # 重置追条延迟
	elif attr_name == &"max_health":
		bar.max_value = new
		if _ghost_bar != null:
			_ghost_bar.max_value = new
		if _layer_overlay != null:
			_layer_overlay.queue_redraw()


func _on_phase(b: Node, phase: int) -> void:
	if b != boss:
		return
	phase_label.text = "Phase %d" % phase


func _on_died(b: Node) -> void:
	if b == boss:
		visible = false
