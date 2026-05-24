## 任务追踪 widget（M12 重写）。
##
## 订阅 EventBus 的新 quest_step_* 信号渲染 (quest_id, sub_id) 串行步骤；
## 同 quest_id 同时只有 1 个 active 步骤，HUD 显示其 Name + Desc + 进度。
##
## 信号订阅：
##   - [signal EventBus.quest_step_started] → 显示新条目
##   - [signal EventBus.quest_step_progress] → 刷新 N/M
##   - [signal EventBus.quest_step_pending_deliver] → 提示"回到 NPC 处汇报"
##   - [signal EventBus.quest_step_completed] → 标记 ✓ 完成 + 短暂淡出（接下来会有新 step_started）
##   - [signal EventBus.quest_series_completed] → Banner / 大提示
##   - [signal EventBus.quest_abandoned] → 立即移除
class_name QuestTrackerWidget
extends BaseWidget

@export var fade_complete_seconds: float = 1.5  # 步骤完成后淡出（短，因为下一 sub 立即接上）

@onready var vbox: VBoxContainer = $VBox

# (quest_id, sub_id) 字符串 → {root, title, progress}
var _entries: Dictionary = {}


func _ready() -> void:
	super._ready()
	EventBus.quest_step_started.connect(_on_step_started)
	EventBus.quest_step_progress.connect(_on_step_progress)
	EventBus.quest_step_pending_deliver.connect(_on_step_pending_deliver)
	EventBus.quest_step_completed.connect(_on_step_completed)
	EventBus.quest_series_completed.connect(_on_series_completed)
	EventBus.quest_abandoned.connect(_on_abandoned)


# ─────────────────────────────────────────────────────────────
# 信号处理
# ─────────────────────────────────────────────────────────────

func _on_step_started(quest_id: int, sub_id: int) -> void:
	var step: Dictionary = ConfigCenter.get_quest_step(quest_id, sub_id)
	var name_str: String = CsvLoader.as_string(step, "Name", "Quest %d.%d" % [quest_id, sub_id])
	var desc: String = CsvLoader.as_string(step, "Desc", "")
	# 创建条目
	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 2)
	vbox.add_child(root)
	var lbl_title := Label.new()
	lbl_title.text = "● " + name_str
	lbl_title.add_theme_font_size_override(&"font_size", 14)
	lbl_title.add_theme_color_override(&"font_color", Color(1, 0.85, 0.4, 1))
	root.add_child(lbl_title)
	var lbl_progress := Label.new()
	lbl_progress.text = "  · %s" % desc
	lbl_progress.add_theme_font_size_override(&"font_size", 12)
	root.add_child(lbl_progress)
	_entries[_key(quest_id, sub_id)] = {
		&"root": root,
		&"title": lbl_title,
		&"progress": lbl_progress,
		&"desc": desc,
	}
	EventBus.hud_toast_requested.emit("接受任务：%s" % name_str, 2.5)


func _on_step_progress(quest_id: int, sub_id: int, current: int, target: int) -> void:
	var key: String = _key(quest_id, sub_id)
	var entry: Dictionary = _entries.get(key, {})
	if entry.is_empty():
		# 容错：信号晚到时自动建条目
		_on_step_started(quest_id, sub_id)
		entry = _entries.get(key, {})
		if entry.is_empty():
			return
	var lbl: Label = entry.get(&"progress")
	if lbl == null or not is_instance_valid(lbl):
		return
	var desc: String = entry.get(&"desc", "")
	lbl.text = "  · %s: %d/%d" % [desc, current, target]
	if current >= target:
		lbl.add_theme_color_override(&"font_color", Color(0.6, 1.0, 0.6, 1))


func _on_step_pending_deliver(quest_id: int, sub_id: int) -> void:
	var key: String = _key(quest_id, sub_id)
	var entry: Dictionary = _entries.get(key, {})
	if entry.is_empty():
		return
	var lbl: Label = entry.get(&"progress")
	if lbl != null and is_instance_valid(lbl):
		lbl.text += "  → 回去汇报"
		lbl.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.3, 1))
	EventBus.hud_toast_requested.emit("目标达成：回去汇报", 2.5)


func _on_step_completed(quest_id: int, sub_id: int) -> void:
	var key: String = _key(quest_id, sub_id)
	var entry: Dictionary = _entries.get(key, {})
	if entry.is_empty():
		return
	var lbl_title: Label = entry.get(&"title")
	if is_instance_valid(lbl_title):
		lbl_title.text = "✔ " + lbl_title.text.trim_prefix("● ")
		lbl_title.add_theme_color_override(&"font_color", Color(0.6, 1.0, 0.6, 1))
	var root: Node = entry.get(&"root")
	var t := create_tween()
	t.tween_interval(fade_complete_seconds)
	t.tween_property(root, ^"modulate:a", 0.0, 0.4)
	t.tween_callback(_free_entry.bind(key, root))


func _on_series_completed(quest_id: int) -> void:
	EventBus.hud_toast_requested.emit("任务系列完成（q=%d）" % quest_id, 3.0)


func _on_abandoned(quest_id: int) -> void:
	# 移除该 quest_id 的所有条目
	var prefix: String = "q%d." % quest_id
	for key in _entries.keys():
		if (key as String).begins_with(prefix):
			var entry: Dictionary = _entries[key]
			var root: Node = entry.get(&"root")
			if is_instance_valid(root):
				root.queue_free()
			_entries.erase(key)


# ─────────────────────────────────────────────────────────────
# 工具
# ─────────────────────────────────────────────────────────────

func _free_entry(key: String, root: Node) -> void:
	if is_instance_valid(root):
		root.queue_free()
	_entries.erase(key)


static func _key(quest_id: int, sub_id: int) -> String:
	return "q%d.s%d" % [quest_id, sub_id]
