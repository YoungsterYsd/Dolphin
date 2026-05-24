## AttributeDebugWidget（D2.E 新增，调试 UI）。
##
## F1 切换显示当前玩家的所有 AttributeSet 字段（HealthSet 11 + PrimaryAttributeSet 21 + CombatSet 2 = 34 字段）。
## 实时刷新（每物理帧重读 + 订阅 [signal EventBus.attribute_changed] 即时更新）。
##
## 挂载：HUDLayer 下，自动 ALWAYS process_mode（暂停期间也能查属性）。
##
## R-DATA-02 例外：本 widget 是开发期调试工具，所有 ASCII 文本格式硬编码合规。
class_name AttributeDebugWidget
extends Control

## 当前观察的玩家（默认从 group "player" 取第一个）。
var _player: Node = null
var _label: Label = null

## 是否显示中（F1 切换）。
var _is_visible: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 锚定右上角
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	custom_minimum_size = Vector2(280, 0)
	position.x -= 290
	position.y += 10

	# 半透明黑底 + Label
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_label = Label.new()
	# 用 anchor + offset 替代 position + size 减法（避免 size 未初始化时直接 -=）
	_label.anchor_left = 0.0
	_label.anchor_top = 0.0
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 8.0
	_label.offset_top = 8.0
	_label.offset_right = -8.0
	_label.offset_bottom = -8.0
	_label.add_theme_font_size_override(&"font_size", 11)
	_label.add_theme_color_override(&"font_color", Color(0.85, 0.95, 1.0))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 2)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_label)

	visible = false

	# 订阅属性变化（实时刷新）
	EventBus.attribute_changed.connect(_on_attribute_changed)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_toggle()


func _process(_delta: float) -> void:
	if _is_visible:
		_refresh()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _toggle() -> void:
	_is_visible = not _is_visible
	visible = _is_visible
	if _is_visible:
		_resolve_player()
		_refresh()


func _resolve_player() -> void:
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			_player = players[0]


func _on_attribute_changed(_owner_node: Node, _attr_name: StringName, _old: float, _new: float) -> void:
	# 仅在显示时刷新（_process 已经每帧刷一次，这里是边沿刷新冗余保护）
	if _is_visible:
		_refresh()


func _refresh() -> void:
	_resolve_player()
	if _player == null:
		_label.text = "[F1] No player found in group 'player'"
		return
	var asc: Node = null
	if &"asc" in _player:
		asc = _player.get(&"asc")
	if asc == null:
		_label.text = "[F1] Player has no ASC"
		return

	var lines: PackedStringArray = []
	lines.append("[F1] %s · attrs=%d sets" % [_player.name, asc.attribute_sets.size()])
	lines.append("─────────────────")

	for s in asc.attribute_sets:
		if s == null:
			continue
		var set_name: String = s.get_class()
		if s.get_script() != null and s.get_script().get_global_name() != &"":
			set_name = String(s.get_script().get_global_name())
		lines.append("【%s】" % set_name)
		# 遍历所有 @export 数值属性
		for prop in s.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_STORAGE):
				continue
			var pname: String = prop.name
			if pname == "resource_local_to_scene" or pname == "resource_path" or pname == "resource_name" or pname.begins_with("script") or pname.begins_with("metadata"):
				continue
			if prop.type != TYPE_FLOAT and prop.type != TYPE_INT:
				continue
			var val: Variant = s.get(pname)
			lines.append("  %-22s = %.2f" % [pname, float(val)])
		lines.append("")

	# 当前激活的 GameplayTag（前 8 个，避免太长）
	if &"tags" in asc:
		var tags = asc.get(&"tags")
		if tags != null and tags.has_method(&"get_explicit_tags"):
			var tag_list: Array = tags.get_explicit_tags()
			if not tag_list.is_empty():
				lines.append("【Tags】 %s" % str(tag_list).substr(0, 200))

	_label.text = "\n".join(lines)
