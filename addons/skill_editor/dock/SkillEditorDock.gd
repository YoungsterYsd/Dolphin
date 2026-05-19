@tool
## Skill Editor 主 Dock（M7.4）。
##
## 布局（用户决策 q5=A）：
##   [Toolbar]  ──新建 / 打开 / 保存 / Duration 输入框 / 当前文件名──
##   [HSplit]
##     [Left]   轨道列表 + Add Animation Track / Add Event Track 按钮
##     [Center] TimelineView（自绘时间轴 + 关键帧）
##     [Right]  TrackInspector（按选中 keyframe 类型动态切换 form）
##
## 资源持有：[member current_timeline] 是当前编辑的 [SkillTimeline]，可以为 null（空载状态）。
##
## R-LOG-01 例外说明：本目录下的 @tool 脚本运行在编辑器进程，
## 无法访问 GameLogger（因依赖运行时 Autoload）。M7 阶段编辑器内的调试输出统一用原生 print()。
class_name SkillEditorDock
extends Control

@onready var _toolbar_label: Label = %ToolbarLabel
@onready var _duration_spin: SpinBox = %DurationSpin
@onready var _btn_new: Button = %BtnNew
@onready var _btn_open: Button = %BtnOpen
@onready var _btn_save: Button = %BtnSave
@onready var _btn_play: Button = %BtnPlay
@onready var _btn_pause: Button = %BtnPause
@onready var _btn_reset: Button = %BtnReset
@onready var _loop_check: CheckBox = %LoopCheck
@onready var _btn_add_anim: Button = %BtnAddAnimTrack
@onready var _btn_add_event: Button = %BtnAddEventTrack
@onready var _track_list: ItemList = %TrackList
@onready var _timeline_view: Control = %TimelineView
@onready var _inspector_root: VBoxContainer = %InspectorRoot
@onready var _empty_hint: Label = %EmptyHint
# M7.7 预览舞台 + 工具栏
@onready var _preview_stage: Control = %PreviewStage
@onready var _mute_check: CheckBox = %MuteCheck
@onready var _btn_zoom_in: Button = %BtnZoomIn
@onready var _btn_zoom_out: Button = %BtnZoomOut
@onready var _btn_cam_reset: Button = %BtnCamReset
@onready var _show_hitbox_band_check: CheckBox = %ShowHitboxBandCheck

var _editor_interface: EditorInterface = null
var _undo_redo = null  # EditorUndoRedoManager（避免类型限定，跨 Godot 版本兼容）

var current_timeline: SkillTimeline = null
var selected_track_index: int = -1
var selected_keyframe_index: int = -1


func _ready() -> void:
	_btn_new.pressed.connect(_on_new_pressed)
	_btn_open.pressed.connect(_on_open_pressed)
	_btn_save.pressed.connect(_on_save_pressed)
	_btn_add_anim.pressed.connect(_on_add_anim_pressed)
	_btn_add_event.pressed.connect(_on_add_event_pressed)
	_track_list.item_selected.connect(_on_track_selected)
	_duration_spin.value_changed.connect(_on_duration_changed)

	# M7.6 预览
	_btn_play.pressed.connect(_on_play_pressed)
	_btn_pause.pressed.connect(_on_pause_pressed)
	_btn_reset.pressed.connect(_on_reset_pressed)
	_loop_check.toggled.connect(_on_loop_toggled)

	# M7.7 预览工具栏
	_mute_check.toggled.connect(_on_mute_toggled)
	_btn_zoom_in.pressed.connect(func() -> void: _adjust_preview_zoom(1.25))
	_btn_zoom_out.pressed.connect(func() -> void: _adjust_preview_zoom(0.8))
	_btn_cam_reset.pressed.connect(_on_cam_reset_pressed)
	_show_hitbox_band_check.toggled.connect(_on_show_hitbox_band_toggled)
	# 同步初始勾选
	if _preview_stage != null and _preview_stage.has_method(&"is_muted"):
		_mute_check.button_pressed = bool(_preview_stage.call(&"is_muted"))

	# PreviewStage HitStop 反馈：让 TimelineView 暂停游标
	if _preview_stage != null:
		if _preview_stage.has_signal(&"playhead_pause_requested"):
			_preview_stage.connect(&"playhead_pause_requested", _on_playhead_pause_requested)
		if _preview_stage.has_signal(&"sprite_frames_changed"):
			_preview_stage.connect(&"sprite_frames_changed", _on_sprite_frames_changed)

	# TimelineView 信号
	if _timeline_view.has_signal(&"keyframe_selected"):
		_timeline_view.connect(&"keyframe_selected", _on_keyframe_selected)
	if _timeline_view.has_signal(&"timeline_modified"):
		_timeline_view.connect(&"timeline_modified", _refresh_track_list)
	if _timeline_view.has_signal(&"keyframe_previewed"):
		_timeline_view.connect(&"keyframe_previewed", _on_keyframe_previewed)
	if _timeline_view.has_signal(&"preview_finished"):
		_timeline_view.connect(&"preview_finished", _on_preview_finished)
	# M7.7：标尺拖动 → 同步 PreviewStage（让动画跟随但不触发音效）
	if _timeline_view.has_signal(&"playhead_scrubbed"):
		_timeline_view.connect(&"playhead_scrubbed", _on_playhead_scrubbed)

	_refresh_ui()


# M7.7：Dock 范围内空格 toggle play/pause（即便焦点不在 TimelineView 上也生效）
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke: InputEventKey = event
		if ke.keycode == KEY_SPACE:
			# 避免在 LineEdit / SpinBox / TextEdit 等输入控件上抢按键
			var focused: Control = get_viewport().gui_get_focus_owner()
			if focused != null and (focused is LineEdit or focused is TextEdit or focused is SpinBox):
				return
			if _timeline_view != null and _timeline_view.has_method(&"toggle_play"):
				_timeline_view.call(&"toggle_play")
				accept_event()


# ─────────────────────────────────────────────────────────────
# 由 plugin.gd 注入
# ─────────────────────────────────────────────────────────────

func _inject_editor_interface(ei: EditorInterface, undo_redo) -> void:
	_editor_interface = ei
	_undo_redo = undo_redo
	if _timeline_view != null and _timeline_view.has_method(&"set_undo_redo"):
		_timeline_view.call(&"set_undo_redo", undo_redo)


# ─────────────────────────────────────────────────────────────
# 公开 API（plugin.gd._edit 调用）
# ─────────────────────────────────────────────────────────────

func open_timeline(timeline: SkillTimeline) -> void:
	current_timeline = timeline
	selected_track_index = -1
	selected_keyframe_index = -1
	_refresh_ui()


# ─────────────────────────────────────────────────────────────
# 工具栏
# ─────────────────────────────────────────────────────────────

func _on_new_pressed() -> void:
	current_timeline = SkillTimeline.new()
	current_timeline.skill_id = &"new_skill"
	current_timeline.duration = 1.0
	selected_track_index = -1
	selected_keyframe_index = -1
	_refresh_ui()


func _on_open_pressed() -> void:
	# 让用户从 FileSystem 双击 .tres 触发；此处仅打开 FileDialog 供主动选择
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.tres ; SkillTimeline"])
	dlg.current_dir = "res://Data/Skills/Timelines"
	dlg.file_selected.connect(func(path: String) -> void:
		var res: Resource = load(path)
		if res is SkillTimeline:
			open_timeline(res as SkillTimeline)
		dlg.queue_free()
	)
	get_tree().root.add_child(dlg)
	dlg.popup_centered_ratio(0.6)


func _on_save_pressed() -> void:
	if current_timeline == null:
		return
	if current_timeline.resource_path.is_empty():
		# 弹保存对话框
		var dlg := EditorFileDialog.new()
		dlg.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		dlg.access = EditorFileDialog.ACCESS_RESOURCES
		dlg.filters = PackedStringArray(["*.tres ; SkillTimeline"])
		dlg.current_dir = "res://Data/Skills/Timelines"
		dlg.current_file = "Timeline_%s.tres" % String(current_timeline.skill_id)
		dlg.file_selected.connect(func(path: String) -> void:
			ResourceSaver.save(current_timeline, path)
			current_timeline.take_over_path(path)
			_refresh_ui()
			dlg.queue_free()
		)
		get_tree().root.add_child(dlg)
		dlg.popup_centered_ratio(0.6)
	else:
		ResourceSaver.save(current_timeline)
		_refresh_ui()


func _on_duration_changed(v: float) -> void:
	if current_timeline == null:
		return
	current_timeline.duration = v
	if _timeline_view != null and _timeline_view.has_method(&"set_timeline"):
		_timeline_view.call(&"set_timeline", current_timeline)


# ─────────────────────────────────────────────────────────────
# 轨道列表
# ─────────────────────────────────────────────────────────────

func _on_add_anim_pressed() -> void:
	if current_timeline == null:
		return
	var tr := AnimationTrack.new()
	tr.track_name = "Animation Track %d" % current_timeline.tracks.size()
	current_timeline.tracks.append(tr)
	_refresh_track_list()


func _on_add_event_pressed() -> void:
	if current_timeline == null:
		return
	var tr := EventTrack.new()
	tr.track_name = "Event Track %d" % current_timeline.tracks.size()
	current_timeline.tracks.append(tr)
	_refresh_track_list()


func _on_track_selected(idx: int) -> void:
	selected_track_index = idx
	selected_keyframe_index = -1
	_refresh_inspector()


# ─────────────────────────────────────────────────────────────
# M7.6 预览
# ─────────────────────────────────────────────────────────────

func _on_play_pressed() -> void:
	if _timeline_view != null and _timeline_view.has_method(&"play_preview"):
		_timeline_view.call(&"play_preview")
		print("[SkillEditor] preview started")


func _on_pause_pressed() -> void:
	if _timeline_view != null and _timeline_view.has_method(&"pause_preview"):
		_timeline_view.call(&"pause_preview")
		print("[SkillEditor] preview paused")


func _on_reset_pressed() -> void:
	if _timeline_view != null and _timeline_view.has_method(&"reset_preview"):
		_timeline_view.call(&"reset_preview")
	if _preview_stage != null and _preview_stage.has_method(&"reset_preview"):
		_preview_stage.call(&"reset_preview")
	print("[SkillEditor] preview reset")


func _on_loop_toggled(v: bool) -> void:
	if _timeline_view != null and _timeline_view.has_method(&"set_loop"):
		_timeline_view.call(&"set_loop", v)


func _on_mute_toggled(v: bool) -> void:
	if _preview_stage != null and _preview_stage.has_method(&"set_mute"):
		_preview_stage.call(&"set_mute", v)


func _adjust_preview_zoom(factor: float) -> void:
	if _preview_stage == null:
		return
	# 直接通过节点动态调整 Camera2D zoom（PreviewStage 内部会持久化的话另做；此处运行期不持久化以减少写盘）
	var sub_vp: SubViewport = _preview_stage.get_node_or_null(^"SubViewportContainer/SubViewport") as SubViewport
	if sub_vp == null:
		# 兼容 PreviewStage 内部按 add_child 而非命名，直接遍历找 Camera2D
		for c in _preview_stage.get_children():
			if c is SubViewportContainer:
				sub_vp = (c as SubViewportContainer).get_child(0) as SubViewport
				break
	if sub_vp == null:
		return
	var cam: Camera2D = null
	for n in sub_vp.get_children():
		if n is Camera2D:
			cam = n as Camera2D
			break
	if cam == null:
		return
	cam.zoom *= factor
	cam.zoom = cam.zoom.clamp(Vector2(0.25, 0.25), Vector2(4.0, 4.0))


func _on_cam_reset_pressed() -> void:
	if _preview_stage != null and _preview_stage.has_method(&"reset_preview"):
		_preview_stage.call(&"reset_preview")
	# 重置缩放到 1
	var sub_vp: SubViewport = null
	for c in _preview_stage.get_children():
		if c is SubViewportContainer:
			sub_vp = (c as SubViewportContainer).get_child(0) as SubViewport
			break
	if sub_vp == null:
		return
	for n in sub_vp.get_children():
		if n is Camera2D:
			(n as Camera2D).zoom = Vector2.ONE


func _on_show_hitbox_band_toggled(v: bool) -> void:
	if _timeline_view != null and _timeline_view.has_method(&"set_show_hitbox_band"):
		_timeline_view.call(&"set_show_hitbox_band", v)


func _on_playhead_pause_requested(duration_ms: float) -> void:
	if _timeline_view != null and _timeline_view.has_method(&"pause_playhead_for"):
		_timeline_view.call(&"pause_playhead_for", duration_ms)


# M7.7：标尺被拖动时，让 PreviewStage 的角色显示"当前时间应该处于的动画"
# 不触发音效/震屏/VFX/HitStop（避免拖动时反复鸣响），仅同步动画姿态。
func _on_playhead_scrubbed(time_sec: float) -> void:
	if current_timeline == null or _preview_stage == null:
		return
	# 从所有 AnimationTrack 里找到 time <= time_sec 的最后一个 AnimationKeyframe
	var latest_anim_kf: AnimationKeyframe = null
	var latest_anim_t: float = -1.0
	for tr in current_timeline.tracks:
		if not (tr is AnimationTrack):
			continue
		for kf in (tr as AnimationTrack).keyframes:
			if kf == null:
				continue
			if kf.time <= time_sec and kf.time > latest_anim_t:
				latest_anim_t = kf.time
				latest_anim_kf = kf
	if latest_anim_kf != null and _preview_stage.has_method(&"handle_keyframe"):
		_preview_stage.call(&"handle_keyframe", latest_anim_kf)


func _on_sprite_frames_changed(_path: String) -> void:
	# 仅刷新 toolbar label（Inspector 不需要）
	_refresh_ui()


func _on_keyframe_previewed(track_idx: int, kf_idx: int, kf: SkillKeyframe) -> void:
	# 路由到 PreviewStage 真实预览（M7.7）
	if _preview_stage != null and _preview_stage.has_method(&"handle_keyframe"):
		_preview_stage.call(&"handle_keyframe", kf)
	# Console 日志保留（便于排错）
	if kf is AnimationKeyframe:
		print("[SkillEditor preview] @%.2fs anim '%s'" % [kf.time, (kf as AnimationKeyframe).anim_name])
	elif kf is EventKeyframe:
		var ekf := kf as EventKeyframe
		print("[SkillEditor preview] @%.2fs event kind=%s payload=%s" % [kf.time, ekf.kind, ekf.payload])


func _on_preview_finished() -> void:
	print("[SkillEditor] preview finished")


# ─────────────────────────────────────────────────────────────
# 时间轴 → Inspector
# ─────────────────────────────────────────────────────────────

func _on_keyframe_selected(track_idx: int, kf_idx: int) -> void:
	selected_track_index = track_idx
	selected_keyframe_index = kf_idx
	if track_idx >= 0 and track_idx < _track_list.item_count:
		_track_list.select(track_idx)
	_refresh_inspector()


# ─────────────────────────────────────────────────────────────
# UI 刷新
# ─────────────────────────────────────────────────────────────

func _refresh_ui() -> void:
	var has_timeline: bool = current_timeline != null
	_empty_hint.visible = not has_timeline
	_btn_save.disabled = not has_timeline
	_btn_add_anim.disabled = not has_timeline
	_btn_add_event.disabled = not has_timeline
	_btn_play.disabled = not has_timeline
	_btn_pause.disabled = not has_timeline
	_btn_reset.disabled = not has_timeline
	_loop_check.disabled = not has_timeline
	_duration_spin.editable = has_timeline

	if has_timeline:
		_toolbar_label.text = "%s  (skill_id: %s)" % [
			current_timeline.resource_path if not current_timeline.resource_path.is_empty() else "<unsaved>",
			String(current_timeline.skill_id),
		]
		_duration_spin.value = current_timeline.duration
		if _timeline_view != null and _timeline_view.has_method(&"set_timeline"):
			_timeline_view.call(&"set_timeline", current_timeline)
	else:
		_toolbar_label.text = "—"

	_refresh_track_list()
	_refresh_inspector()


func _refresh_track_list() -> void:
	_track_list.clear()
	if current_timeline == null:
		return
	for i in range(current_timeline.tracks.size()):
		var tr: SkillTrack = current_timeline.tracks[i]
		var label: String = "?"
		if tr is AnimationTrack:
			label = "[Anim] %s (%d kfs)" % [tr.track_name, (tr as AnimationTrack).keyframes.size()]
		elif tr is EventTrack:
			label = "[Event] %s (%d kfs)" % [tr.track_name, (tr as EventTrack).keyframes.size()]
		_track_list.add_item(label)
	# 同步 TimelineView
	if _timeline_view != null and _timeline_view.has_method(&"set_timeline"):
		_timeline_view.call(&"set_timeline", current_timeline)


func _refresh_inspector() -> void:
	# 清空旧子节点
	for child in _inspector_root.get_children():
		child.queue_free()

	if current_timeline == null:
		return

	# 顶部：技能 id 编辑
	var id_label := Label.new()
	id_label.text = "skill_id"
	_inspector_root.add_child(id_label)
	var id_edit := LineEdit.new()
	id_edit.text = String(current_timeline.skill_id)
	id_edit.text_submitted.connect(func(s: String) -> void:
		current_timeline.skill_id = StringName(s)
		_refresh_ui()
	)
	_inspector_root.add_child(id_edit)
	_inspector_root.add_child(HSeparator.new())

	# 选中轨道时显示轨道信息
	if selected_track_index >= 0 and selected_track_index < current_timeline.tracks.size():
		var tr: SkillTrack = current_timeline.tracks[selected_track_index]
		var name_label := Label.new()
		name_label.text = "Track Name"
		_inspector_root.add_child(name_label)
		var name_edit := LineEdit.new()
		name_edit.text = tr.track_name
		name_edit.text_submitted.connect(func(s: String) -> void:
			tr.track_name = s
			_refresh_track_list()
		)
		_inspector_root.add_child(name_edit)

		var del_btn := Button.new()
		del_btn.text = "Remove Track"
		del_btn.pressed.connect(func() -> void:
			current_timeline.tracks.remove_at(selected_track_index)
			selected_track_index = -1
			_refresh_track_list()
			_refresh_inspector()
		)
		_inspector_root.add_child(del_btn)
		_inspector_root.add_child(HSeparator.new())

	# M7.5 时实装：选中关键帧 → 按类型动态加载 form
	if selected_track_index >= 0 and selected_keyframe_index >= 0:
		var tr2: SkillTrack = current_timeline.tracks[selected_track_index]
		var kfs: Array = tr2.get_keyframes()
		if selected_keyframe_index < kfs.size():
			var kf: SkillKeyframe = kfs[selected_keyframe_index]
			_inspector_root.add_child(_build_keyframe_form(kf))


func _build_keyframe_form(kf: SkillKeyframe) -> Control:
	var box := VBoxContainer.new()
	# time
	var time_lbl := Label.new()
	time_lbl.text = "time (s)"
	box.add_child(time_lbl)
	var time_spin := SpinBox.new()
	time_spin.min_value = 0.0
	time_spin.max_value = 60.0
	time_spin.step = 0.01
	time_spin.value = kf.time
	time_spin.value_changed.connect(func(v: float) -> void:
		kf.time = v
		_refresh_track_list()
	)
	box.add_child(time_spin)

	if kf is AnimationKeyframe:
		var akf: AnimationKeyframe = kf
		var lbl := Label.new()
		lbl.text = "anim_name"
		box.add_child(lbl)
		var le := LineEdit.new()
		le.text = String(akf.anim_name)
		le.text_changed.connect(func(s: String) -> void: akf.anim_name = StringName(s))
		box.add_child(le)
		var loop_cb := CheckBox.new()
		loop_cb.text = "loop"
		loop_cb.button_pressed = akf.loop
		loop_cb.toggled.connect(func(v: bool) -> void: akf.loop = v)
		box.add_child(loop_cb)
	elif kf is EventKeyframe:
		var ekf: EventKeyframe = kf
		var lbl := Label.new()
		lbl.text = "kind"
		box.add_child(lbl)
		var opt := OptionButton.new()
		var all_kinds: Array[StringName] = SkillEventKind.all()
		var current_idx: int = 0
		for i in range(all_kinds.size()):
			opt.add_item(String(all_kinds[i]))
			if all_kinds[i] == ekf.kind:
				current_idx = i
		opt.select(current_idx)
		opt.item_selected.connect(func(i: int) -> void:
			ekf.kind = all_kinds[i]
			_refresh_inspector()  # 切换 kind 后重建 form
		)
		box.add_child(opt)
		# payload：M7.5 实装时按 kind 弹具体 form；M7.4 阶段先用 JSON 文本编辑
		var pl_lbl := Label.new()
		pl_lbl.text = "payload (JSON)"
		box.add_child(pl_lbl)
		var pl_edit := TextEdit.new()
		pl_edit.text = JSON.stringify(ekf.payload, "  ")
		pl_edit.custom_minimum_size = Vector2(0, 120)
		pl_edit.text_changed.connect(func() -> void:
			var parsed = JSON.parse_string(pl_edit.text)
			if parsed is Dictionary:
				ekf.payload = parsed
		)
		box.add_child(pl_edit)
	return box
