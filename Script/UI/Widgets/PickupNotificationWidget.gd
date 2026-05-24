## 拾取提示。
##
## 订阅两路信号：
##   - [signal EventBus.pickup_displayed]（item_id: StringName, qty: int）：业务侧手动 emit
##   - [signal EventBus.item_added]（owner: Node, def: ItemDefinition, added: int）：道具系统 Phase 1 自动 emit
##
## 右下条目堆叠 [member entry_seconds] 秒后淡出。
## 同屏最多 [member max_entries] 条。
##
## 文本格式：「+%d %s」（例如 +5 金币）
##
## 注：同一次拾取可能两个信号都触发；业务侧自行决定是否 emit pickup_displayed。
##     当前 PickupArea 只 emit item_added（自动），未 emit pickup_displayed。
class_name PickupNotificationWidget
extends BaseWidget

@export var max_entries: int = 6
@export var entry_seconds: float = 5.0
@export var fade_seconds: float = 0.4

@onready var vbox: VBoxContainer = $VBox


func _ready() -> void:
	super._ready()
	EventBus.pickup_displayed.connect(_on_pickup)
	EventBus.item_added.connect(_on_item_added)


func _on_pickup(item_id: StringName, qty: int) -> void:
	_push_entry("+%d %s" % [qty, String(item_id)], Color.WHITE)


func _on_item_added(_owner: Node, def: ItemDefinition, added: int) -> void:
	if def == null or added <= 0:
		return
	# 用品质色染色（与背包槽边框颜色一致）
	var color := Color.WHITE
	var rarity: int = def.get_rarity()
	if rarity >= 1:
		var style: Dictionary = AffixFormatter.rarity_style(rarity)
		color = style.get("color", Color.WHITE)
	_push_entry("+%d %s" % [added, def.get_display_name()], color)


func _push_entry(text: String, color: Color) -> void:
	# 溢出淘汰最旧
	while vbox.get_child_count() >= max_entries:
		var oldest: Node = vbox.get_child(0)
		if oldest != null:
			oldest.queue_free()
	# 新条目
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override(&"font_size", 16)
	lbl.add_theme_color_override(&"font_color", color)
	lbl.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override(&"outline_size", 4)
	lbl.modulate.a = 0.0
	vbox.add_child(lbl)
	# 渐入 → 停留 → 渐出 → 移除
	var t := create_tween()
	t.tween_property(lbl, ^"modulate:a", 1.0, fade_seconds)
	t.tween_interval(entry_seconds)
	t.tween_property(lbl, ^"modulate:a", 0.0, fade_seconds)
	t.tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free()
	)
