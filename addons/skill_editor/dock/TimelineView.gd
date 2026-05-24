@tool
## 时间轴可视化。
## 渲染：
##   - 顶部时间刻度（按 _ruler_step 秒一格）
##   - 每条轨道一行，行间分隔
##   - 关键帧渲染为彩色菱形（动画绿 / 事件橙；选中红边框）
##   - 当前游标（垂直黄线）
##
## 交互：
##   - 左键单击关键帧 → 选中（emit keyframe_selected）
##   - 左键拖拽关键帧 → 修改 time，吸附 _snap_step
##   - 右键空白处 → 弹菜单"添加关键帧"
##   - Delete → 删除选中关键帧
##   - 空格 → toggle Play/Pause
##   - 左键按住标尺区（顶部 22px）→ 拖动 playhead
##
## 预览：
##   - 通过 [method play_preview] / [method pause_preview] / [method reset_preview] 由 Dock 调用
##   - _process(delta) 时推进 _playhead_time
##   - 触发到关键帧时 emit [signal keyframe_previewed]（Dock 路由到 PreviewStage 真实预览）
class_name TimelineView
extends Control

signal keyframe_selected(track_idx: int, kf_idx: int)
signal timeline_modified()
signal keyframe_previewed(track_idx: int, kf_idx: int, kf: SkillKeyframe)
signal preview_finished()
## 标尺拖拽改变 playhead 时通知 Dock（用于刷新工具栏 Play/Pause 按钮的显示）
signal playhead_scrubbed(time_sec: float)

# === 视觉常量（编辑器 UI 内部值，无需走 R-DATA-02 配置）===
const ROW_HEIGHT: float = 32.0
const RULER_HEIGHT: float = 28.0
const LEFT_PADDING: float = 8.0
const RIGHT_PADDING: float = 16.0
const KEYFRAME_RADIUS: float = 7.0
const COLOR_RULER_BG := Color(0.18, 0.20, 0.24, 1.0)
const COLOR_RULER_TICK := Color(0.55, 0.58, 0.62, 1.0)
const COLOR_ROW_ALT := Color(0.13, 0.14, 0.17, 1.0)
const COLOR_ROW_GRID := Color(0.25, 0.27, 0.30, 0.6)
const COLOR_KF_ANIM := Color(0.40, 0.85, 0.45, 1.0)
const COLOR_KF_ANIM_REGION := Color(0.40, 0.85, 0.45, 0.32)
const COLOR_KF_ANIM_REGION_BORDER := Color(0.40, 0.85, 0.45, 0.85)
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

# 标尺拖拽 playhead
var _scrubbing: bool = false

# 吸附（秒）
# 拖拽吸附最小步长（秒）；用 _get_snap_step() 动态返回 frame_step 或 0.01
const _snap_step: float = 0.01


# 拖拽时实际吸附步长：有帧对齐基准就吸附到帧，否则 0.01s。
func _get_snap_step() -> float:
	var fs: float = _get_frame_step_seconds()
	return fs if fs > 0.0001 else _snap_step
# 时间刻度密度（已废弃；改用 _pick_ruler_step 自适应）
const _ruler_step: float = 0.1


# 根据 pixels_per_second 返回合适的 ruler 步长（秒）。
# - 优先按"动画帧步长"对齐（_get_frame_step_seconds 取当前 timeline 第一条 AnimationKeyframe 引用的 anim 的 fps）；
#   找到 frame_step 后选 frame_step×N（N ∈ 1/2/5/10/20/...）使每刻度间距 ≈ 50px。
# - 找不到帧步长（无 SpriteFrames / 无 AnimationKeyframe）时回退到 1·2·5×10ⁿ 经典算法。
func _pick_ruler_step(pps: float) -> float:
	if pps <= 0.0001:
		return 1.0
	var target_px: float = 50.0
	var raw: float = target_px / pps
	# 模式 1：按帧对齐
	var frame_step: float = _get_frame_step_seconds()
	if frame_step > 0.0001:
		# 选 frame_step × N（N 从 1·2·5·10·20·50... 序列里挑）让间距 ≥ target_px
		var n_raw: float = raw / frame_step
		var n_exp10: float = pow(10.0, floor(log(maxf(n_raw, 1.0)) / log(10.0)))
		var n_mant: float = n_raw / n_exp10
		var n_nice: float
		if n_mant <= 1.0:
			n_nice = 1.0
		elif n_mant <= 2.0:
			n_nice = 2.0
		elif n_mant <= 5.0:
			n_nice = 5.0
		else:
			n_nice = 10.0
		return frame_step * n_nice * n_exp10
	# 模式 2：经典 1/2/5×10^n
	var exp10: float = pow(10.0, floor(log(raw) / log(10.0)))
	var mantissa: float = raw / exp10
	var nice: float
	if mantissa <= 1.0:
		nice = 1.0
	elif mantissa <= 2.0:
		nice = 2.0
	elif mantissa <= 5.0:
		nice = 5.0
	else:
		nice = 10.0
	return nice * exp10


# 取"当前 timeline 中第一条 AnimationKeyframe 引用的 anim 的 fps"对应的帧时长（秒）。
# 找不到合理 fps 时返回 0（让 _pick_ruler_step 回退）。
func _get_frame_step_seconds() -> float:
	if _timeline == null or _preview_sprite_frames == null:
		return 0.0
	for tr in _timeline.tracks:
		if not (tr is AnimationTrack):
			continue
		for kf in (tr as AnimationTrack).keyframes:
			if kf == null:
				continue
			var name_str: StringName = (kf as AnimationKeyframe).anim_name
			if name_str == &"":
				continue
			if not _preview_sprite_frames.has_animation(name_str):
				continue
			var fps: float = _preview_sprite_frames.get_animation_speed(name_str)
			if fps > 0.0001:
				return 1.0 / fps
	return 0.0

# === 预览状态 ===
var _playhead_time: float = 0.0
var _playing: bool = false
var _loop: bool = false
# 已触发关键帧索引集合（在 _sorted_kfs 数组里的下标）
var _fired_set: Dictionary = {}
var _sorted_kfs_cache: Array = []
var _sorted_kfs_dirty: bool = true

# === HitStop 暂停 ===
var _pause_remaining: float = 0.0  # 秒，>0 时游标暂停推进

# === Hitbox 区间色带 ===
var _show_hitbox_band: bool = true
var _hitbox_band_color: Color = Color(1.0, 0.25, 0.25, 0.18)

# === 缩放 / 横向滚动 ===
# pixels_per_second：每秒占多少像素。<=0 表示用"自适应"（fit-to-width）。
# 用户 Ctrl+滚轮调节后变成具体值；reset_view 后回到 -1（fit）。
var _pixels_per_second: float = -1.0
var _scroll_x: float = 0.0
const _ZOOM_STEP: float = 1.2          # 每次滚轮缩放系数
const _MIN_PPS: float = 20.0           # 最小像素/秒
const _MAX_PPS: float = 4000.0         # 最大像素/秒

# === 动画色条 ===
# 用于按 anim_name 推算 frame_count / fps，进而画出"该关键帧覆盖 [t, t+length]"色条。
# 来自 PreviewStage3D._sprite.sprite_frames（Dock 在 _refresh 时注入）。
var _preview_sprite_frames: SpriteFrames = null


func _ready() -> void:
	# 让 Control 接收输入与重绘
	mouse_filter = MOUSE_FILTER_STOP
	# 启用 clip：任何 draw 都不会溢出控件边界（防止缩放后 playhead/关键帧画到 TrackList 上）
	clip_contents = true
	set_process(true)
	# 加载 PreviewStageConfig 的 hitbox 区间显示配置
	var cfg_res: Resource = load("res://Data/Config/PreviewStageConfig.tres")
	if cfg_res != null and cfg_res is PreviewStageConfig:
		_show_hitbox_band = (cfg_res as PreviewStageConfig).show_hitbox_band
		_hitbox_band_color = (cfg_res as PreviewStageConfig).hitbox_band_color


# 标尺区显示拖手 cursor，提示用户可拖动
func _get_cursor_shape(pos: Vector2) -> int:
	if pos.y <= RULER_HEIGHT:
		return Control.CURSOR_HSIZE
	return Control.CURSOR_ARROW


func _process(delta: float) -> void:
	if not _playing or _timeline == null:
		return
	# HitStop 暂停优先
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


# === 预览 API（Dock 调用） ===

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


# HitStop 路由进来，让游标暂停 N 毫秒
func pause_playhead_for(duration_ms: float) -> void:
	_pause_remaining = max(_pause_remaining, duration_ms / 1000.0)


# 工具栏 Hitbox Band 开关
func set_show_hitbox_band(v: bool) -> void:
	_show_hitbox_band = v
	queue_redraw()


func is_playing() -> bool:
	return _playing


func get_playhead_time() -> float:
	return _playhead_time


# 空格快捷键调用
func toggle_play() -> void:
	if _timeline == null:
		return
	if _playing:
		pause_preview()
	else:
		play_preview()


# 拖动标尺 / 外部代码定位 playhead
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
	# 切换 timeline 自动 fit-to-width
	_pixels_per_second = -1.0
	_scroll_x = 0.0
	queue_redraw()


func set_undo_redo(undo_redo) -> void:
	_undo_redo = undo_redo


# 重置视图：恢复 fit-to-width 自适应缩放，滚动归零（按键 F / Dock 工具栏可调）
func reset_view() -> void:
	_pixels_per_second = -1.0
	_scroll_x = 0.0
	queue_redraw()


# 以鼠标 x 为锚点缩放：保持鼠标处时间点固定不变。
# factor > 1 放大；factor < 1 缩小。
func _zoom_at(anchor_x: float, factor: float) -> void:
	var t_anchor: float = _x_to_time(anchor_x)
	var pps_old: float = _get_effective_pps()
	var pps_new: float = clampf(pps_old * factor, _MIN_PPS, _MAX_PPS)
	if abs(pps_new - pps_old) < 0.001:
		return
	_pixels_per_second = pps_new
	# 调整 scroll，让 t_anchor 在屏幕上的 x 不变：
	# new_x(t_anchor) = LEFT_PADDING + t_anchor * pps_new - new_scroll == anchor_x
	_scroll_x = LEFT_PADDING + t_anchor * pps_new - anchor_x
	_clamp_scroll()
	queue_redraw()


# 横向滚动 API（暴露给将来可能加的 HScrollBar）
func set_scroll_x(v: float) -> void:
	_scroll_x = v
	_clamp_scroll()
	queue_redraw()


func get_scroll_x() -> float:
	return _scroll_x


func get_pixels_per_second() -> float:
	return _get_effective_pps()


# Dock 注入：当 PreviewStage 加载/切换 SpriteFrames 时同步过来，让动画色条显示真实长度。
func set_preview_sprite_frames(sf: SpriteFrames) -> void:
	_preview_sprite_frames = sf
	queue_redraw()


# 推算某 AnimationKeyframe 在编辑器侧的色条长度（秒）。
# - auto_length=true 且 SpriteFrames 中存在该动画 → frame_count / fps
# - 否则取 manual_length
# - 最终再被"下一个 AnimationKeyframe.time" 截断（在 _draw 内做）
func _calc_anim_length(kf: AnimationKeyframe) -> float:
	if kf == null:
		return 0.0
	if kf.auto_length and _preview_sprite_frames != null:
		var name_str: StringName = kf.anim_name
		if name_str != &"" and _preview_sprite_frames.has_animation(name_str):
			var frames: int = _preview_sprite_frames.get_frame_count(name_str)
			var fps: float = _preview_sprite_frames.get_animation_speed(name_str)
			if frames > 0 and fps > 0.0001:
				var loop_anim: bool = _preview_sprite_frames.get_animation_loop(name_str)
				var raw_len: float = float(frames) / fps
				# 循环动画在编辑器侧最多画 1 个周期，避免无限延伸
				return raw_len if not loop_anim else raw_len
	return max(0.0, kf.manual_length)


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
	# 自适应步长：让相邻刻度像素间隔接近 50px
	var pps: float = _get_effective_pps()
	var step: float = _pick_ruler_step(pps)
	var frame_step: float = _get_frame_step_seconds()
	var frame_aligned: bool = frame_step > 0.0001 and abs(step / frame_step - round(step / frame_step)) < 0.001
	# 仅画当前可见区间
	var t_left: float = max(0.0, _x_to_time(0.0))
	var t_right: float = min(t_total + 0.0001, _x_to_time(w))
	var t_start: float = floor(t_left / step) * step
	var t: float = t_start
	while t <= t_right:
		var px: float = _time_to_x(t)
		draw_line(Vector2(px, 0), Vector2(px, RULER_HEIGHT), COLOR_RULER_TICK, 1.0)
		# 当 step 是整秒倍数时所有刻度都标；否则仅整秒标
		var should_label: bool = step >= 1.0 or abs(t - round(t)) < step * 0.5
		if should_label:
			var label_str: String
			if frame_aligned:
				# 帧对齐模式：显示 "0.20s · f12"（秒 + 帧序号）
				var frame_idx: int = int(round(t / frame_step))
				label_str = "%.2fs·f%d" % [t, frame_idx]
			else:
				var fmt: String = "%.0fs" if step >= 1.0 else ("%.1fs" if step >= 0.1 else "%.2fs")
				label_str = fmt % t
			draw_string(get_theme_default_font(), Vector2(px + 2, RULER_HEIGHT - 4), label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_RULER_TICK)
		t += step

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

		# 事件轨上的 hitbox enable/disable 区间渲染为半透明红色色带
		if _show_hitbox_band and not is_anim:
			_draw_hitbox_bands(kfs, y)

		# 动画轨：先画"持续色条"（每个 AnimationKeyframe 对应一段 [t, t+length]，被下一帧截断）
		if is_anim:
			_draw_anim_regions(kfs, y)

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

	# Playhead 预览游标：x 落在控件可视范围外（缩放/横向滚动后）就不画，避免溢出
	var px: float = _time_to_x(_playhead_time)
	if px >= -8.0 and px <= w + 8.0:
		draw_line(Vector2(px, 0), Vector2(px, h), COLOR_PLAYHEAD, 2.0)
		# 顶部三角标记
		var triangle := PackedVector2Array([
			Vector2(px - 6, 0),
			Vector2(px + 6, 0),
			Vector2(px, 8),
		])
		draw_colored_polygon(triangle, COLOR_PLAYHEAD)
		# 时间数字（避免靠近右边时被截断 → 自动改对齐到左侧）
		var label_x: float = px + 8.0
		var label_align: int = HORIZONTAL_ALIGNMENT_LEFT
		if label_x + 40.0 > w:
			label_x = px - 8.0
			label_align = HORIZONTAL_ALIGNMENT_RIGHT
		draw_string(get_theme_default_font(), Vector2(label_x, 14), "%.2fs" % _playhead_time, label_align, -1, 11, COLOR_PLAYHEAD)
	else:
		# 在屏幕外的话给一个边缘指示器，提示用户 playhead 在哪边
		var indicator_x: float = 4.0 if px < 0 else w - 4.0
		draw_line(Vector2(indicator_x, RULER_HEIGHT + 2.0), Vector2(indicator_x, h - 2.0), Color(COLOR_PLAYHEAD, 0.45), 1.0)


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


# 把事件轨上 HITBOX_ENABLE → HITBOX_DISABLE 的区间渲染为半透明红色色带
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


# 动画轨色条：每个 AnimationKeyframe 占据 [time, time+length]，被下一关键帧的 time 截断；
# 触达 timeline.duration 时也截断。颜色用半透绿色 + 上下边框。
func _draw_anim_regions(kfs: Array, y: float) -> void:
	if _timeline == null:
		return
	# 先把动画关键帧按 time 升序拷贝（保留索引，便于将来选中态联动）
	var anim_kfs: Array = []
	for kf in kfs:
		if kf is AnimationKeyframe:
			anim_kfs.append(kf)
	anim_kfs.sort_custom(func(a, b) -> bool: return float(a.time) < float(b.time))
	for i in range(anim_kfs.size()):
		var akf: AnimationKeyframe = anim_kfs[i]
		var t_start: float = akf.time
		var raw_len: float = _calc_anim_length(akf)
		if raw_len <= 0.0:
			continue
		var t_end: float = t_start + raw_len
		# 截断：到下一动画关键帧
		if i + 1 < anim_kfs.size():
			t_end = min(t_end, float(anim_kfs[i + 1].time))
		# 截断：到 timeline 末尾
		t_end = min(t_end, _timeline.duration)
		if t_end <= t_start:
			continue
		var x1: float = _time_to_x(t_start)
		var x2: float = _time_to_x(t_end)
		var rect := Rect2(x1, y + 4.0, max(2.0, x2 - x1), ROW_HEIGHT - 10.0)
		draw_rect(rect, COLOR_KF_ANIM_REGION, true)
		# 顶/底边框，加强存在感
		draw_line(Vector2(rect.position.x, rect.position.y),
			Vector2(rect.position.x + rect.size.x, rect.position.y),
			COLOR_KF_ANIM_REGION_BORDER, 1.0)
		draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y),
			Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),
			COLOR_KF_ANIM_REGION_BORDER, 1.0)
		# 名称标签（色条内左上角；空间够时才画）
		if rect.size.x > 32.0:
			draw_string(get_theme_default_font(),
				Vector2(rect.position.x + 4.0, rect.position.y + rect.size.y - 4.0),
				String(akf.anim_name) if akf.anim_name != &"" else "<unnamed>",
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6.0, 10,
				COLOR_KF_ANIM_REGION_BORDER)


# ─────────────────────────────────────────────────────────────
# 输入
# ─────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if _timeline == null:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		# 滚轮：Ctrl+滚 = 缩放（以鼠标处时间为锚点）；普通滚轮/Shift+滚轮 = 横向平移
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if mb.ctrl_pressed:
				var factor: float = _ZOOM_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / _ZOOM_STEP)
				_zoom_at(mb.position.x, factor)
			else:
				var dx: float = -60.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 60.0
				_scroll_x += dx
				_clamp_scroll()
				queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# 标尺区（顶部 RULER_HEIGHT 像素）按下 → 启动 scrubbing
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
				grab_focus()  # 点击轨道时获取焦点，让空格能被收到
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
		# 中键拖（按下 + motion 处理）：用 _scrubbing 之外的 flag 占位会复杂，平移走 Shift+滚轮即可

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		# scrubbing 中 → 跟随鼠标更新 playhead
		if _scrubbing:
			seek_to(_x_to_time(mm.position.x))
			accept_event()
			return
		# 中键按住拖动 → 横向平移
		if (mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			_scroll_x -= mm.relative.x
			_clamp_scroll()
			queue_redraw()
			accept_event()
			return
		if _dragging:
			var kf: SkillKeyframe = _get_kf(_drag_track_idx, _drag_kf_idx)
			if kf != null:
				var new_x: float = mm.position.x - _drag_offset_x
				var new_t: float = _x_to_time(new_x)
				new_t = clampf(new_t, 0.0, _timeline.duration)
				# 吸附
				new_t = round(new_t / _get_snap_step()) * _get_snap_step()
				kf.time = new_t
				queue_redraw()

	elif event is InputEventKey:
		var ke: InputEventKey = event
		if ke.pressed and not ke.echo:
			# 空格 toggle play/pause
			if ke.keycode == KEY_SPACE:
				toggle_play()
				accept_event()
				return
			if ke.keycode == KEY_DELETE:
				_delete_selected_keyframe()
			# F = Fit-to-width（重置缩放与滚动）
			if ke.keycode == KEY_F:
				reset_view()
				accept_event()


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
	time_at_pos = round(time_at_pos / _get_snap_step()) * _get_snap_step()

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
	var pps: float = _get_effective_pps()
	return LEFT_PADDING + t * pps - _scroll_x


func _x_to_time(x: float) -> float:
	if _timeline == null or _timeline.duration <= 0.0:
		return 0.0
	var pps: float = _get_effective_pps()
	if pps <= 0.0001:
		return 0.0
	return (x - LEFT_PADDING + _scroll_x) / pps


# 当前实际使用的 pixels_per_second：
# - 用户主动设置（>0）→ 用户值
# - 否则按"timeline 占满当前可用宽度"自适应
func _get_effective_pps() -> float:
	if _pixels_per_second > 0.0:
		return _pixels_per_second
	if _timeline == null or _timeline.duration <= 0.0:
		return _MIN_PPS
	var avail: float = max(1.0, size.x - LEFT_PADDING - RIGHT_PADDING)
	return avail / _timeline.duration


# Content 总宽（按 pps 计算）。用于钳制 _scroll_x。
func _get_content_width() -> float:
	if _timeline == null:
		return 0.0
	return _get_effective_pps() * _timeline.duration + LEFT_PADDING + RIGHT_PADDING


func _clamp_scroll() -> void:
	var max_scroll: float = max(0.0, _get_content_width() - size.x)
	_scroll_x = clampf(_scroll_x, 0.0, max_scroll)


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
