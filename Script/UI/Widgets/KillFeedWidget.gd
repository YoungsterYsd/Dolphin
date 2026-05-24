## 击杀提示流。
##
## 订阅 [signal EventBus.enemy_died]：
##   - 每次击杀向上滚动一行「击杀: <名字>」
##   - 单条 [member entry_seconds] 后自动淡出移除
##   - 同屏最多 [member max_entries] 条，溢出最旧的立刻消失
##
## 名字解析顺序：
##   1) enemy.get_meta("display_name", "") 若存在
##   2) enemy.name（节点名）
##
## 不依赖任何业务类（R-HUD-02）。
class_name KillFeedWidget
extends BaseWidget

@export var entry_seconds: float = 3.0
@export var fade_seconds: float = 0.4
@export var max_entries: int = 4

@onready var vbox: VBoxContainer = $VBox


func _ready() -> void:
	super._ready()
	EventBus.enemy_died.connect(_on_enemy_died)


func _on_enemy_died(enemy: Node) -> void:
	if enemy == null:
		return
	var name_str: String = ""
	if enemy.has_meta(&"display_name"):
		name_str = String(enemy.get_meta(&"display_name", ""))
	if name_str == "":
		name_str = enemy.name
	_push_entry("击杀: %s" % name_str)


func _push_entry(text: String) -> void:
	# 溢出淘汰最旧
	while vbox.get_child_count() >= max_entries:
		var oldest: Node = vbox.get_child(0)
		if oldest != null:
			oldest.queue_free()
	# 新条目
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override(&"font_size", 18)
	lbl.modulate.a = 0.0
	vbox.add_child(lbl)
	# 渐入
	var t := create_tween()
	t.tween_property(lbl, ^"modulate:a", 1.0, fade_seconds)
	# 停留 → 渐出 → 移除
	t.tween_interval(entry_seconds)
	t.tween_property(lbl, ^"modulate:a", 0.0, fade_seconds)
	t.tween_callback(func():
		if is_instance_valid(lbl):
			lbl.queue_free()
	)
