## 伤害飘字池。
##
## 挂在 HUD 根 Control 下；订阅 [signal EventBus.damage_dealt_v2] 自动显示飘字。
## 池化避免每次 instantiate 的内存分配；不足时按需 grow×2。
##
## 屏幕坐标投影：
##   - 2D 场景：找当前激活 Camera2D（get_viewport().get_camera_2d()），用 unproject_position 把
##     target.global_position 转屏幕坐标。
##   - 3D 场景：找 Camera3D，用 unproject_position（API 名称一致）。
##
## R-DATA-02：所有视觉参数取自 HitFeedbackConfig；不硬编码。
## Phase 2：继承 BaseWidget；投影逻辑抽到 [WorldProjector] 静态工具。
class_name DamagePopupPool
extends BaseWidget

# === 池 ===
var _pool: Array[DamagePopup] = []
var _busy: Array[DamagePopup] = []  # 仅用于统计

# 缓存 config
var _cfg: HitFeedbackConfig = null


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pull_config()
	_build_pool()
	# D2.E：优先订阅 v3（4 样式：白/金/灰/银）；v3 不存在时 fallback 到 v2
	# 注：v3/v2 都已在 EventBus 静态声明，此处无需 has_signal 防御
	EventBus.damage_dealt_v3.connect(_on_damage_dealt_v3)


# ─────────────────────────────────────────────────────────────
# 信号回调
# ─────────────────────────────────────────────────────────────

## D2.E 新版：4 样式飘字（白/金/灰/银）。
func _on_damage_dealt_v3(_source: Node, target: Node, amount: float, is_crit: bool, is_block: bool, is_perfect_block: bool, _tags: Array) -> void:
	if target == null:
		return
	var screen_pos: Vector2 = WorldProjector.project(target, get_viewport())
	if screen_pos == Vector2.INF:
		return

	if is_perfect_block:
		# 银色"完美格挡"文字（不显数值）
		_popup_text_at_screen_pos(screen_pos, "完美格挡!", _cfg.damage_popup_perfect_block_color, _cfg.damage_popup_crit_font_size)
	elif is_crit:
		# 金色加大字号 + 数值（暴击）
		_show_popup(screen_pos, amount, _cfg.damage_popup_crit_color, _cfg.damage_popup_crit_font_size)
	elif is_block:
		# 灰色 + 数值（普通格挡）
		_show_popup(screen_pos, amount, _cfg.damage_popup_block_color, _cfg.damage_popup_font_size)
	else:
		# 白色 + 数值（普通命中）
		_show_popup(screen_pos, amount, _cfg.damage_popup_normal_color, _cfg.damage_popup_font_size)


func _on_damage_dealt_v2(_source: Node, target: Node, amount: float, _damage_node: Resource, is_crit: bool) -> void:
	if target == null:
		return
	# 投影屏幕坐标
	var screen_pos: Vector2 = WorldProjector.project(target, get_viewport())
	if screen_pos == Vector2.INF:
		return
	var color: Color = _cfg.damage_popup_crit_color if is_crit else _cfg.damage_popup_normal_color
	var font_size: int = _cfg.damage_popup_crit_font_size if is_crit else _cfg.damage_popup_font_size
	_show_popup(screen_pos, amount, color, font_size)


# ─────────────────────────────────────────────────────────────
# 公开 API（外部代码也可直接调，如治疗 / MISS / 闪避 / 经验 / 金币飘字）
# Phase 3-T10/T22：扩展为通用文字飘字池。
# ─────────────────────────────────────────────────────────────

## 治疗飘字（绿色）。
func popup_heal(target: Node, amount: float) -> void:
	_popup_text_at_target(target, "+%d" % int(round(amount)),
		_cfg.damage_popup_heal_color, _cfg.damage_popup_font_size)


## MISS（攻击未命中 / 装备影响等）。
func popup_miss(target: Node) -> void:
	_popup_text_at_target(target, "MISS",
		Color(0.7, 0.7, 0.7), _cfg.damage_popup_font_size)


## 闪避（被攻击但闪过）。
func popup_dodge(target: Node) -> void:
	_popup_text_at_target(target, "闪避",
		Color(0.6, 0.85, 1.0), _cfg.damage_popup_font_size)


## 经验飘字（黄色 +XP N）。target 一般传 Player。
func popup_xp(target: Node, amount: int) -> void:
	_popup_text_at_target(target, "+%d XP" % amount,
		Color(1.0, 0.85, 0.25), _cfg.damage_popup_font_size)


## 金币飘字（金色 +N 金）。
func popup_gold(target: Node, amount: int) -> void:
	_popup_text_at_target(target, "+%d 金" % amount,
		Color(1.0, 0.78, 0.15), _cfg.damage_popup_font_size)


## 通用文本飘字（业务侧自定义）。
func popup_text(target: Node, text_str: String, color: Color = Color.WHITE, font_size: int = 0) -> void:
	var fs: int = font_size if font_size > 0 else _cfg.damage_popup_font_size
	_popup_text_at_target(target, text_str, color, fs)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _popup_text_at_target(target: Node, text_str: String, color: Color, font_size: int) -> void:
	if target == null:
		return
	var screen_pos: Vector2 = WorldProjector.project(target, get_viewport())
	if screen_pos == Vector2.INF:
		return
	_popup_text_at_screen_pos(screen_pos, text_str, color, font_size)


## D2.E 新增：以屏幕坐标显示文本飘字（_on_damage_dealt_v3 等已投影过坐标的入口用）。
func _popup_text_at_screen_pos(screen_pos: Vector2, text_str: String, color: Color, font_size: int) -> void:
	var p: DamagePopup = _acquire()
	if p == null:
		return
	_busy.append(p)
	p.show_text(
		screen_pos + Vector2(0, _cfg.damage_popup_drift_distance * 0.2),
		text_str,
		color,
		font_size,
		_cfg.damage_popup_drift_distance,
		_cfg.damage_popup_horizontal_jitter,
		_cfg.damage_popup_lifetime,
	)


func _show_popup(screen_pos: Vector2, amount: float, color: Color, font_size: int) -> void:
	var p: DamagePopup = _acquire()
	if p == null:
		return
	_busy.append(p)
	p.show_damage(
		screen_pos + Vector2(0, _cfg.damage_popup_drift_distance * 0.2),  # 起始略偏下
		amount,
		color,
		font_size,
		_cfg.damage_popup_drift_distance,
		_cfg.damage_popup_horizontal_jitter,
		_cfg.damage_popup_lifetime,
	)


func _acquire() -> DamagePopup:
	if _pool.is_empty():
		# Grow×2
		_grow_pool(maxi(_busy.size(), 4))
	if _pool.is_empty():
		return null
	return _pool.pop_back()


func _on_recycled(p: DamagePopup) -> void:
	_busy.erase(p)
	_pool.append(p)


func _build_pool() -> void:
	var init_size: int = _cfg.damage_popup_pool_initial_size if _cfg != null else 20
	_grow_pool(init_size)


func _grow_pool(count: int) -> void:
	for i in range(count):
		var p := DamagePopup.new()
		add_child(p)
		p.recycled.connect(_on_recycled)
		_pool.append(p)


func _pull_config() -> void:
	# R-Core：ConfigCenter 走 class_name 强类型直访
	_cfg = ConfigCenter.get_hit_feedback_config()


# 注：原 _get_world_position / _project_to_screen 已抽到 WorldProjector 静态工具（Phase 2 P2-T3）
