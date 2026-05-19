@tool
## 时间轴可视化（M7.4 框架，M7.5 充实交互，M7.6 加预览游标，M7.7 加内嵌真预览 + 标尺拖拽 + 空格快捷键）。
## 渲染：
##   - 顶部时间刻度（按 _ruler_step 秒一格）
##   - 每条轨道一行，行间分隔
##   - 关键帧渲染为彩色菱形（动画绿 / 事件橙；选中红边框）
##   - 当前游标（垂直黄线）
##
## 交互（M7.5 + M7.7）：
##   - 左键单击关键帧 → 选中（emit keyframe_selected）
##   - 左键拖拽关键帧 → 修改 time，吸附 _snap_step
##   - 右键空白处 → 弹菜单"添加关键帧"
##   - Delete 键 → 删除选中关键帧
##   - **空格 → toggle Play/Pause**（M7.7 新增）
##   - **左键按住标尺区（顶部 22px）→ 拖动 playhead**（M7.7 新增）
##
## 预览（M7.6）：
##   - 通过 [method play_preview] / [method pause_preview] / [method reset_preview] 由 Dock 调用
##   - _process(delta) 时推进 _playhead_time
##   - 触发到关键帧时 emit [signal keyframe_previewed]（Dock 路由到 PreviewStage 真实预览）
class_name TimelineView
extends Control

signal keyframe_selected(track_idx: int, kf_idx: int)
signal timeline_modified()
signal keyframe_previewed(track_idx: int, kf_idx: int, kf: SkillKeyframe)
signal preview_finished()
## M7.7：标尺拖拽改变 playhead 时通知 Dock（用于刷新工具栏 Play/Pause 按钮的显示）
signal playhead_scrubbed(time_sec: float)

# === 视觉常量（R-DATA-02：M8 时如要调优可拆到 Config，但这是编辑器 UI 范围，符合 R-DATA-02 例外条款） ===
const ROW_HEIGHT: float = 32.0
const RULER_HEIGHT: float = 22.0
const LEFT_PADDING: float = 8.0
const RIGHT_PADDING: float = 16.0
const KEYFRAME_RADIUS: float = 7.0
const COLOR_RULER_BG := Color(0.18, 0.20, 0.24, 1.0)
const COLOR_RULER_TICK := Color(0.55, 0.58, 0.62, 1.0)
const COLOR_ROW_ALT := Color(0.13, 0.14, 0.17, 1.0)
const COLOR_ROW_GRID := Color(0.25, 0.27, 0.30, 0.6)
const COLOR_KF_ANIM := Color(0.40, 0.85, 0.45, 1.0)
const COLOR_KF_EVENT := Color(0.95, 0.65, 0.30, 1.0)
const COLOR_KF_SELECTED_BORDER := Color(1.0, 0.30, 0.30, 1.0)
const COLOR_PLAYHEAD := Color(1.0, 0.90, 0.20, 0.85)

var _timeline: SkillTimeline = null
var _undo_redo = null

# 选中状态
var _selected_track: int = -1
var _selected_kf: int = -1

# 拖拽
var _dragging: bool = false
var _drag_track_idx: int = -1
var _drag_kf_idx: int = -1
var _drag_offset_x: float = 0.0

# M7.7：标尺拖拽 playhead
var _scrubbing: bool = false

# 吸附（秒）
const _snap_step: float = 0.01
# 时间刻度密度
const _ruler_step: float = 0.1

# === M7.6 预览状态 ===
var _playhead_time: float = 0.0
var _playing: bool = false
var _loop: bool = false
# 已触发关键帧索引集合（在 _sorted_kfs 数组里的下标）
var _fired_set: Dictionary = {}
var _sorted_kfs_cache: Array = []
var _sorted_kfs_dirty: bool = true

# === M7.7 hit_stop 暂停 ===
var _pause_remaining: float = 0.0  # 秒，>0 时游标暂停推进

# === M7.7 hitbox 区间色带 ===
var _show_hitbox_band: bool = true
var _hitbox_band_color: Color = Color(1.0, 0.25, 0.25, 0.18)


func _ready() -> void:
	# 让 Control 接收输入与重绘
	mouse_filter = MOUSE_FILTER_STOP
	set_process(true)
	# 加载 PreviewStageConfig 的 hitbox 区间显示配置
	var cfg_res: Resource = load("res://Data/Config/PreviewStageConfig.tres")
	if cfg_res != null and cfg_res is PreviewStageConfig:
		_show_hitbox_band = (cfg_res as PreviewStageConfig).show_hitbox_band
		_hitbox_band_color = (cfg_res as PreviewStageConfig).hitbox_band_color


# M7.7：标尺区显示拖手 cursor，提示用户可拖动
func _get_cursor_shape(pos: Vector2) -> int:
	if pos.y <= RULER_HEIGHT:
		return Control.CURSOR_HSIZE
	return Control.CURSOR_ARROW


func _process(delta: float) -> void:
	if not _playing or _timeline == null:
		return
	# M7.7：HitStop 暂停优先
	if _pause_remaining > 0.0:
		_pause_remaining -= delta
		queue_redraw()
		return
	_playhead_time += delta
	_consume_keyframes_until(_playhead_time)
	if _playhead_time >= _timeline.duration:
		if _loop:
			_playhead_time = 0.0
			_fired_set.clear()
		else:
			_playing = false
			_playhead_time = _timeline.duration
			preview_finished.emit()
	queue_redraw()


# === M7.6 预览 API（Dock 调用） ===

func play_preview() -> void:
	if _timeline == null:
		return
	if _playhead_time >= _timeline.duration:
		_playhead_time = 0.0
		_fired_set.clear()
	_sorted_kfs_dirty = true
	_pause_remaining = 0.0
	_playing = true


func pause_preview() -> void:
	_playing = false


func reset_preview() -> void:
	_playing = false
	_playhead_time = 0.0
	_pause_remaining = 0.0
	_fired_set.clear()
	queue_redraw()


func set_loop(v: bool) -> void:
	_loop = v


# M7.7：HitStop 路由进来，让游标暂停 N 毫秒
func pause_playhead_for(duration_ms: float) -> void:
	_pause_remaining = max(_pause_remaining, duration_ms / 1000.0)


# M7.7：工具栏 Hitbox Band 开关
func set_show_hitbox_band(v: bool) -> void:
	_show_hitbox_band = v
	queue_redraw()


func is_playing() -> bool:
	return _playing


func get_playhead_time() -> float:
	return _playhead_time


# M7.7：空格快捷键调用
func toggle_play() -> void:
	if _timeline == null:
		return
	if _playing:
		pause_preview()
	else:
		play_preview()


# M7.7：拖动标尺/外部代码定位 playhead
func seek_to(t: float) -> void:
	if _timeline == null:
		return
	t = clampf(t, 0.0, _timeline.duration)
	_playhead_time = t
	_pause_remaining = 0.0
	# 重建已触发集合：把 t 之前的关键帧标记为已触发，避免回放重复
	if _sorted_kfs_dirty:
		_sorted_kfs_cache = _timeline.collect_sorted_keyframes()
		_sorted_kfs_dirty = false
	_fired_set.clear()
	for i in range(_sorted_kfs_cache.size()):
		var item: Dictionary = _sorted_kfs_cache[i]
		if float(item["time"]) < t - 0.0001:
			_fired_set[i] = true
		else:
			break
	queue_redraw()
	playhead_scrubbed.emit(_playhead_time)


func _consume_keyframes_until(t: float) -> void:
	if _sorted_kfs_dirty:
		_sorted_kfs_cache = _timeline.collect_sorted_keyframes()
		_sorted_kfs_dirty = false
	for i in range(_sorted_kfs_cache.size()):
		if _fired_set.has(i):
			continue
		var item: Dictionary = _sorted_kfs_cache[i]
		if float(item["time"]) <= t:
			_fired_set[i] = true
			# 找到 track / kf 索引（线性查找；预览阶段量小可接受）
			var tr: SkillTrack = item["track"]
			var kf: SkillKeyframe = item["kf"]
			var track_idx: int = _timeline.tracks.find(tr)
			# 通过 SkillTimeline.get_track_keyframes 调（编辑器内 self-call 走真实 GDScript，避免 placeholder）
			var kf_idx: int = _timeline.get_track_keyframes(track_idx).find(kf)
			keyframe_previewed.emit(track_idx, kf_idx, kf)
		else:
			break


func set_timeline(t: SkillTimeline) -> void:
	_timeline = t
	_sorted_kfs_dirty = true
	_fired_set.clear()
	_playhead_time = 0.0
	_playing = false
	queue_redraw()


func set_undo_redo(undo_redo) -> void:
	_undo_redo = undo_redo


# ─────────────────────────────────────────────────────────────
# 渲染
# ─────────────────────────────────────────────────────────────

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if _timeline == null or _timeline.duration <= 0.0:
		return

	# 标尺
	draw_rect(Rect2(0, 0, w, RULER_HEIGHT), COLOR_RULER_BG, true)
	var t_total: float = _timeline.duration
	var t: float = 0.0
	while t <= t_total + 0.0001:
		var px: float = _time_to_x(t)
		draw_line(Vector2(px, 0), Vector2(px, RULER_HEIGHT), COLOR_RULER_TICK, 1.0)
		# 整数秒额外加粗
		if abs(t - round(t)) < 0.001:
			draw_string(get_theme_default_font(), Vector2(px + 2, RULER_HEIGHT - 4), "%.1fs" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_RULER_TICK)
		t += _ruler_step

	# 行
	var tracks: Array[SkillTrack] = _timeline.tracks
	for i in range(tracks.size()):
		var y: float = RULER_HEIGHT + i * ROW_HEIGHT
		# 隔行底色
		if i % 2 == 0:
			draw_rect(Rect2(0, y, w, ROW_HEIGHT), COLOR_ROW_ALT, true)
		# 分隔线
		draw_line(Vector2(0, y + ROW_HEIGHT), Vector2(w, y + ROW_HEIGHT), COLOR_ROW_GRID, 1.0)
		# 关键帧（通过 SkillTimeline.get_track_keyframes 取，避免编辑器中跨脚本调 placeholder 失败）
		var tr: SkillTrack = tracks[i]
		var kfs: Array = _timeline.get_track_keyframes(i)
		var is_anim: bool = (_timeline.get_track_kind(i) == SkillTrack.KIND_ANIMATION)

		# M7.7：事件轨上的 hitbox enable/disable 区间渲染为半透明红色色带
		if _show_hitbox_band and not is_anim:
			_draw_hitbox_bands(kfs, y)

		for j in range(kfs.size()):
			var kf: SkillKeyframe = kfs[j]
			if kf == null:
				continue
			var kx: float = _time_to_x(kf.time)
			var ky: float = y + ROW_HEIGHT * 0.5
			var color: Color = COLOR_KF_ANIM if is_anim else COLOR_KF_EVENT
			_draw_diamond(Vector2(kx, ky), KEYFRAME_RADIUS, color)
			if i == _selected_track and j == _selected_kf:
				_draw_diamond_border(Vector2(kx, ky), KEYFRAME_RADIUS + 2.0, COLOR_KF_SELECTED_BORDER, 2.0)

	# Playhead（M7.6 预览游标）
	var px: float = _time_to_x(_playhead_time)
	draw_line(Vector2(px, 0), Vector2(px, h), COLOR_PLAYHEAD, 2.0)
	# 顶部三角标记
	var triangle := PackedVector2Array([
		Vector2(px - 6, 0),
		Vector2(px + 6, 0),
		Vector2(px, 8),
	])
	draw_colored_polygon(triangle, COLOR_PLAYHEAD)
	# 时间数字
	draw_string(get_theme_default_font(), Vector2(px + 8, 14), "%.2fs" % _playhead_time, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_PLAYHEAD)


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
	])
	draw_colored_polygon(pts, color)


func _draw_diamond_border(center: Vector2, radius: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius, 0),
		center + Vector2(0, -radius),
	])
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], color, width)


# M7.7：把事件轨上 HITBOX_ENABLE → HITBOX_DISABLE 的区间渲染为半透明红色色带
func _draw_hitbox_bands(kfs: Array, y: float) -> void:
	# 收集时间排好序的 hitbox 事件
	var events: Array = []  # [{time, is_enable}]
	for kf in kfs:
		if kf == null or not (kf is EventKeyframe):
			continue
		var ek: EventKeyframe = kf
		if ek.kind == SkillEventKind.HITBOX_ENABLE:
			events.append({"time": ek.time, "enable": true})
		elif ek.kind == SkillEventKind.HITBOX_DISABLE:
			events.append({"time": ek.time, "enable": false})
	events.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	# 逐对 enable→disable 配对画色带（容忍单边：enable 后没 disable，则延伸到 timeline 末尾）
	var pending_enable_t: float = -1.0
	for ev in events:
		var t: float = float(ev["time"])
		if ev["enable"]:
			if pending_enable_t < 0.0:
				pending_enable_t = t
		else:
			if pending_enable_t >= 0.0:
				_fill_band(pending_enable_t, t, y)
				pending_enable_t = -1.0
	if pending_enable_t >= 0.0 and _timeline != null:
		_fill_band(pending_enable_t, _timeline.duration, y)


func _fill_band(t_start: float, t_end: float, y: float) -> void:
	if t_end <= t_start:
		return
	var x1: float = _time_to_x(t_start)
	var x2: float = _time_to_x(t_end)
	draw_rect(Rect2(x1, y + 2.0, x2 - x1, ROW_HEIGHT - 4.0), _hitbox_band_color, true)


# ─────────────────────────────────────────────────────────────
# 输入（M7.5 充实）
# ─────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if _timeline == null:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# M7.7：标尺区（顶部 RULER_HEIGHT 像素）按下 → 启动 scrubbing
				if mb.position.y <= RULER_HEIGHT:
					_scrubbing = true
					seek_to(_x_to_time(mb.position.x))
					grab_focus()
					accept_event()
					return
				var hit: Dictionary = _hit_test_keyframe(mb.position)
				if not hit.is_empty():
					_selected_track = hit["track"]
					_selected_kf = hit["kf"]
					_dragging = true
					_drag_track_idx = _selected_track
					_drag_kf_idx = _selected_kf
					_drag_offset_x = mb.position.x - _time_to_x(_get_kf(hit["track"], hit["kf"]).time)
					keyframe_selected.emit(_selected_track, _selected_kf)
					queue_redraw()
				else:
					_selected_track = -1
					_selected_kf = -1
					queue_redraw()
				grab_focus()  # M7.7：点击轨道时获取焦点，让空格能被收到
			else:
				if _scrubbing:
					_scrubbing = false
					accept_event()
					return
				if _dragging:
					_dragging = false
					timeline_modified.emit()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_show_context_menu(mb.position)

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		# M7.7：scrubbing 中 → 跟随鼠标更新 playhead
		if _scrubbing:
			seek_to(_x_to_time(mm.position.x))
			accept_event()
			return
		if _dragging:
			var kf: SkillKeyframe = _get_kf(_drag_track_idx, _drag_kf_idx)
			if kf != null:
				var new_x: float = mm.position.x - _drag_offset_x
				var new_t: float = _x_to_time(new_x)
				new_t = clampf(new_t, 0.0, _timeline.duration)
				# 吸附
				new_t = round(new_t / _snap_step) * _snap_step
				kf.time = new_t
				queue_redraw()

	elif event is InputEventKey:
		var ke: InputEventKey = event
		if ke.pressed and not ke.echo:
			# M7.7：空格 toggle play/pause
			if ke.keycode == KEY_SPACE:
				toggle_play()
				accept_event()
				return
			if ke.keycode == KEY_DELETE:
				_delete_selected_keyframe()


func _hit_test_keyframe(pos: Vector2) -> Dictionary:
	if _timeline == null:
		return {}
	var tracks: Array[SkillTrack] = _timeline.tracks
	for i in range(tracks.size()):
		var y: float = RULER_HEIGHT + i * ROW_HEIGHT + ROW_HEIGHT * 0.5
		if abs(pos.y - y) > KEYFRAME_RADIUS + 2.0:
			continue
		var kfs: Array = _timeline.get_track_keyframes(i)
		for j in range(kfs.size()):
			var kf: SkillKeyframe = kfs[j]
			if kf == null:
				continue
			var kx: float = _time_to_x(kf.time)
			if abs(pos.x - kx) <= KEYFRAME_RADIUS + 2.0:
				return {"track": i, "kf": j}
	return {}


func _show_context_menu(pos: Vector2) -> void:
	if _timeline == null:
		return
	# 找到 pos 落在第几行
	var row: int = int((pos.y - RULER_HEIGHT) / ROW_HEIGHT)
	if row < 0 or row >= _timeline.tracks.size():
		return
	var tr: SkillTrack = _timeline.tracks[row]
	var time_at_pos: float = clampf(_x_to_time(pos.x), 0.0, _timeline.duration)
	time_at_pos = round(time_at_pos / _snap_step) * _snap_step

	var menu := PopupMenu.new()
	add_child(menu)

	if tr is AnimationTrack:
		menu.add_item("Add Animation Keyframe @%.2fs" % time_at_pos, 0)
	elif tr is EventTrack:
		# 8 种 Kind 各自一个菜单项
		var all_kinds: Array[StringName] = SkillEventKind.all()
		for i in range(all_kinds.size()):
			menu.add_item("Add Event [%s] @%.2fs" % [all_kinds[i], time_at_pos], i)

	menu.id_pressed.connect(func(id: int) -> void:
		if tr is AnimationTrack:
			var nkf := AnimationKeyframe.new()
			nkf.time = time_at_pos
			(tr as AnimationTrack).keyframes.append(nkf)
		elif tr is EventTrack:
			var nkf2 := EventKeyframe.new()
			nkf2.time = time_at_pos
			var kinds: Array[StringName] = SkillEventKind.all()
			if id >= 0 and id < kinds.size():
				nkf2.kind = kinds[id]
			(tr as EventTrack).keyframes.append(nkf2)
		_sorted_kfs_dirty = true
		queue_redraw()
		timeline_modified.emit()
		menu.queue_free()
	)
	menu.position = global_position + pos
	menu.popup()


func _delete_selected_keyframe() -> void:
	if _timeline == null:
		return
	if _selected_track < 0 or _selected_kf < 0:
		return
	var tr: SkillTrack = _timeline.tracks[_selected_track]
	if tr is AnimationTrack:
		(tr as AnimationTrack).keyframes.remove_at(_selected_kf)
	elif tr is EventTrack:
		(tr as EventTrack).keyframes.remove_at(_selected_kf)
	_selected_kf = -1
	_sorted_kfs_dirty = true
	queue_redraw()
	timeline_modified.emit()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _time_to_x(t: float) -> float:
	if _timeline == null or _timeline.duration <= 0.0:
		return LEFT_PADDING
	var avail: float = size.x - LEFT_PADDING - RIGHT_PADDING
	return LEFT_PADDING + (t / _timeline.duration) * avail


func _x_to_time(x: float) -> float:
	if _timeline == null or _timeline.duration <= 0.0:
		return 0.0
	var avail: float = size.x - LEFT_PADDING - RIGHT_PADDING
	if avail <= 0.0:
		return 0.0
	return (x - LEFT_PADDING) / avail * _timeline.duration


func _get_kf(track_idx: int, kf_idx: int) -> SkillKeyframe:
	if _timeline == null:
		return null
	if track_idx < 0 or track_idx >= _timeline.tracks.size():
		return null
	var tr: SkillTrack = _timeline.tracks[track_idx]
	var kfs: Array = tr.get_keyframes()
	if kf_idx < 0 or kf_idx >= kfs.size():
		return null
	return kfs[kf_idx]
