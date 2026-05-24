@tool
## 自绘的 Track 名称列表。
##
## 与 [TimelineView] 共享 ROW_HEIGHT / RULER_HEIGHT 常量，确保左右两侧每条 track 的
## "行起点 / 行高"严格对齐。
##
## 渲染：
##   - 顶部 RULER_HEIGHT 留空（与 TimelineView 内部画 ruler 的高度一致，左右第 0 行 y 完全相同）
##   - 每条 track 一行，高 ROW_HEIGHT
##   - 显示 track.kind 图标占位 + track 名称（无名时显示 "<unnamed>"）
##   - 选中行带高亮底色 + 左侧色条（动画绿 / 事件橙）
##
## 交互：
##   - 左键单击行 → 选中（emit track_selected）
class_name TrackListView
extends Control

signal track_selected(track_idx: int)

# === 与 TimelineView 同步的尺寸常量 ===
const ROW_HEIGHT: float = TimelineView.ROW_HEIGHT
const RULER_HEIGHT: float = TimelineView.RULER_HEIGHT
const LEFT_PADDING: float = 8.0
const RIGHT_PADDING: float = 8.0
const COLOR_BG := Color(0.13, 0.14, 0.17, 1.0)
const COLOR_ROW_ALT := Color(0.16, 0.17, 0.20, 1.0)
const COLOR_ROW_SELECTED := Color(0.32, 0.42, 0.65, 0.55)
const COLOR_LINE := Color(0.25, 0.27, 0.30, 0.6)
const COLOR_RULER_BG := Color(0.18, 0.20, 0.24, 1.0)
const COLOR_NAME := Color(0.85, 0.88, 0.92, 1.0)
const COLOR_NAME_DIM := Color(0.55, 0.58, 0.62, 1.0)
const COLOR_TAG_ANIM := Color(0.40, 0.85, 0.45, 1.0)
const COLOR_TAG_EVENT := Color(0.95, 0.65, 0.30, 1.0)

var _timeline: SkillTimeline = null
var _selected: int = -1


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(120, 0)


func set_timeline(t: SkillTimeline) -> void:
	_timeline = t
	_selected = -1
	queue_redraw()


func set_selected(idx: int) -> void:
	if idx == _selected:
		return
	_selected = idx
	queue_redraw()


func get_selected() -> int:
	return _selected


# ─────────────────────────────────────────────────────────────
# 渲染
# ─────────────────────────────────────────────────────────────

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	# 整体背景
	draw_rect(Rect2(0, 0, w, h), COLOR_BG, true)
	# 顶部 ruler 占位（与 TimelineView 内部 ruler 高度严格一致 → 第 0 条 track 屏幕 y 对齐）
	draw_rect(Rect2(0, 0, w, RULER_HEIGHT), COLOR_RULER_BG, true)
	draw_line(Vector2(0, RULER_HEIGHT), Vector2(w, RULER_HEIGHT), COLOR_LINE, 1.0)

	if _timeline == null:
		return
	var tracks: Array[SkillTrack] = _timeline.tracks
	var font := get_theme_default_font()
	var font_size: int = 12

	for i in range(tracks.size()):
		var y: float = RULER_HEIGHT + i * ROW_HEIGHT
		# 隔行底色（与 TimelineView 一致：偶数行高亮）
		if i % 2 == 0:
			draw_rect(Rect2(0, y, w, ROW_HEIGHT), COLOR_ROW_ALT, true)
		# 选中高亮
		if i == _selected:
			draw_rect(Rect2(0, y, w, ROW_HEIGHT), COLOR_ROW_SELECTED, true)
		# 分隔线
		draw_line(Vector2(0, y + ROW_HEIGHT), Vector2(w, y + ROW_HEIGHT), COLOR_LINE, 1.0)

		# 左侧色条（4px）：动画绿 / 事件橙
		var is_anim: bool = (_timeline.get_track_kind(i) == SkillTrack.KIND_ANIMATION)
		var tag_color: Color = COLOR_TAG_ANIM if is_anim else COLOR_TAG_EVENT
		draw_rect(Rect2(0, y + 3.0, 4.0, ROW_HEIGHT - 6.0), tag_color, true)

		# track 名（带 kind 前缀）
		var tr: SkillTrack = tracks[i]
		var name_text: String = ""
		if tr != null and "track_name" in tr and String(tr.track_name) != "":
			name_text = String(tr.track_name)
		else:
			name_text = "<unnamed>" if tr == null else "<%s>" % ("Anim" if is_anim else "Event")
		var prefix: String = "🎞 " if is_anim else "⚡ "
		var label: String = prefix + name_text

		var text_pos := Vector2(LEFT_PADDING + 6.0, y + ROW_HEIGHT * 0.5 + font_size * 0.35)
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, w - LEFT_PADDING - RIGHT_PADDING - 6.0, font_size, COLOR_NAME)


# ─────────────────────────────────────────────────────────────
# 输入
# ─────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if _timeline == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# ruler 区不响应（与 TimelineView 一致 —— 那里点击 ruler 是 scrub）
			if mb.position.y < RULER_HEIGHT:
				return
			var idx: int = int((mb.position.y - RULER_HEIGHT) / ROW_HEIGHT)
			if idx < 0 or idx >= _timeline.tracks.size():
				return
			set_selected(idx)
			track_selected.emit(idx)
			grab_focus()
			accept_event()
