## Buff / Debuff 列表（统一显示，按净值染色区分）。
##
## 订阅：
##   - [signal EventBus.effect_applied]   → 添加条目
##   - [signal EventBus.effect_removed]   → 移除条目
## 仅显示 [code]target[/code] 在 "player" group 中、且 effect.duration > 0 的持续型效果。
##
## 区分 Buff / Debuff：根据 GameplayEffect.modifiers 的净值正负染色
##   - 总值 > 0 → 偏暖色（buff）
##   - 总值 ≤ 0 → 偏冷色（debuff）
## 注：GameplayEffect 没有显式 category 字段，按净值是临时方案。
## **前置依赖**：建议给 GameplayEffect 加 `category: enum {BUFF, DEBUFF, NEUTRAL}` 字段后再拆 Buff/Debuff 两个 widget。
##
## 同屏最多 [member max_entries] 条，溢出最旧的立刻消失。
class_name BuffListWidget
extends BaseWidget

@export var max_entries: int = 10

@onready var hbox: HBoxContainer = $HBox

# effect.resource_path -> Label（条目节点）
var _entries: Dictionary = {}


func _ready() -> void:
	super._ready()
	EventBus.effect_applied.connect(_on_applied)
	EventBus.effect_removed.connect(_on_removed)


# ─────────────────────────────────────────────────────────────
# 信号
# ─────────────────────────────────────────────────────────────

func _on_applied(target: Node, effect: Resource, _source: Node) -> void:
	if target == null or not target.is_in_group(&"player"):
		return
	if effect == null:
		return
	var ge: GameplayEffect = effect as GameplayEffect
	if ge == null or ge.duration <= 0.0:
		return
	# 溢出淘汰最旧
	while _entries.size() >= max_entries and not _entries.is_empty():
		var oldest_key: Variant = _entries.keys()[0]
		_remove_entry(oldest_key)
	# 加新条目
	var key: Variant = _effect_key(ge)
	if _entries.has(key):
		# 重复添加：刷新文本与计时
		_remove_entry(key)
	var lbl := Label.new()
	lbl.add_theme_font_size_override(&"font_size", 14)
	lbl.modulate = _color_for(ge)
	lbl.text = _format_text(ge)
	hbox.add_child(lbl)
	_entries[key] = lbl
	# 如果是 DURATION，启动倒计时；PERIODIC duration<=0 表示永久不倒计时
	if ge.duration > 0.0:
		var t := create_tween()
		t.tween_interval(ge.duration)
		t.tween_callback(func():
			if is_instance_valid(lbl):
				_remove_entry(key)
		)


func _on_removed(target: Node, effect: Resource) -> void:
	if target == null or not target.is_in_group(&"player"):
		return
	if effect == null:
		return
	var ge: GameplayEffect = effect as GameplayEffect
	if ge == null:
		return
	_remove_entry(_effect_key(ge))


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _effect_key(ge: GameplayEffect) -> Variant:
	# 用 resource_path 作为 key（同一 GE 资源的不同实例算同一条）
	if ge.resource_path != "":
		return ge.resource_path
	return ge.get_instance_id()


func _remove_entry(key: Variant) -> void:
	var lbl: Label = _entries.get(key)
	if lbl != null and is_instance_valid(lbl):
		lbl.queue_free()
	_entries.erase(key)


func _format_text(ge: GameplayEffect) -> String:
	var name_str: String = ge.display_name if ge.display_name != "" else ge.resource_path.get_file().get_basename()
	if ge.duration > 0.0:
		return "[%s %.0fs]" % [name_str, ge.duration]
	return "[%s]" % name_str


func _color_for(ge: GameplayEffect) -> Color:
	# 按 modifiers 净值正负染色（临时方案）
	var net_sum: float = 0.0
	for m in ge.modifiers:
		if m == null:
			continue
		if m.has_method(&"get_magnitude"):
			net_sum += float(m.call(&"get_magnitude"))
		elif m.get(&"magnitude") != null:
			net_sum += float(m.get(&"magnitude"))
	if net_sum > 0.001:
		return Color(0.5, 1.0, 0.5)   # 偏绿（增益）
	if net_sum < -0.001:
		return Color(1.0, 0.5, 0.5)   # 偏红（减益）
	return Color(1.0, 1.0, 0.5)       # 黄（中性）
