@tool
## Skill Editor 主 Dock。
##
## 布局：
##   [Toolbar]  ──新建 / 打开 / 保存 / Duration / 当前文件名 / 播放控制 / 显示选项 / 预览相机控制──
##   [HSplit]
##     [Left]   TrackListView（自绘轨道名列表）+ Add Animation/Event Track 按钮
##     [Center] TimelineView（自绘时间轴 + 关键帧）
##     [Right]  Inspector（按选中 keyframe 类型动态切换 form）
##   3D 预览：独立 Window（点 "🖥 Open 3D Preview" 弹出）
##
## 资源持有：[member current_timeline] 是当前编辑的 [SkillTimeline]，可为 null（空载状态）。
##
## R-LOG-01 例外：本目录下的 @tool 脚本运行在编辑器进程，无法访问 GameLogger（依赖运行时 Autoload），
## 编辑器内调试输出统一用原生 print()。
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
@onready var _btn_add_track: MenuButton = %BtnAddTrack
@onready var _btn_add_anim: Button = %BtnAddAnimTrack
@onready var _btn_add_event: Button = %BtnAddEventTrack
@onready var _track_list: TrackListView = %TrackList
@onready var _timeline_view: Control = %TimelineView
@onready var _inspector_root: VBoxContainer = %InspectorRoot
@onready var _empty_hint: Label = %EmptyHint
# 预览：默认内嵌 PreviewSlot（PanelContainer），可点 BtnPopOut 弹到独立 Window。
@onready var _preview_slot: PanelContainer = %PreviewSlot
@onready var _btn_pop_out: Button = %BtnPopOut
@onready var _mute_check: CheckBox = %MuteCheck
@onready var _btn_zoom_in: Button = %BtnZoomIn
@onready var _btn_zoom_out: Button = %BtnZoomOut
@onready var _btn_cam_reset: Button = %BtnCamReset
@onready var _show_hitbox_band_check: CheckBox = %ShowHitboxBandCheck
@onready var _btn_preview_window: Button = %BtnPreviewWindow  # 已废弃，仍持引用避免报错

const PREVIEW_SCENE_PATH := "res://addons/skill_editor/dock/preview/PreviewScene.tscn"
const PREVIEW_WINDOW_SCRIPT := "res://addons/skill_editor/dock/preview/PreviewWindow.gd"

# PreviewStage3D 实例：默认内嵌 _preview_slot；Pop Out 时被 reparent 到 PreviewWindow，
# 取消 Pop Out 时再 reparent 回 _preview_slot。是否处于 Pop Out 状态由 _preview_window != null 判断。
var _preview_stage: PreviewStage3D = null
var _preview_window: SkillEditorPreviewWindow = null

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
	# 合并入口：MenuButton 弹两项菜单（保留旧按钮做兼容，但 .tscn 已隐藏）
	if _btn_add_track != null:
		var pm: PopupMenu = _btn_add_track.get_popup()
		pm.clear()
		pm.add_item("+ Animation Track", 0)
		pm.add_item("+ Event Track", 1)
		pm.id_pressed.connect(func(id: int) -> void:
			if id == 0:
				_on_add_anim_pressed()
			elif id == 1:
				_on_add_event_pressed()
		)
	# TrackListView 自绘版用 track_selected 信号
	if _track_list != null and _track_list.has_signal(&"track_selected"):
		_track_list.connect(&"track_selected", _on_track_selected)
	_duration_spin.value_changed.connect(_on_duration_changed)

	# 播放控制
	_btn_play.pressed.connect(_on_play_pressed)
	_btn_pause.pressed.connect(_on_pause_pressed)
	_btn_reset.pressed.connect(_on_reset_pressed)
	_loop_check.toggled.connect(_on_loop_toggled)

	# 显示选项 / 预览相机
	_mute_check.toggled.connect(_on_mute_toggled)
	_btn_zoom_in.pressed.connect(func() -> void: _adjust_preview_zoom(1.25))
	_btn_zoom_out.pressed.connect(func() -> void: _adjust_preview_zoom(0.8))
	_btn_cam_reset.pressed.connect(_on_cam_reset_pressed)
	_show_hitbox_band_check.toggled.connect(_on_show_hitbox_band_toggled)

	# 预览：默认内嵌进 PreviewSlot
	_ensure_preview_stage_embedded()
	# Pop Out 按钮：在内嵌 / 独立窗口之间切换
	if _btn_pop_out != null:
		_btn_pop_out.pressed.connect(_on_pop_out_pressed)
	# 旧"Open 3D Preview"按钮已隐藏；连接同样指向 Pop Out（以防按钮被外部触发）
	if _btn_preview_window != null:
		_btn_preview_window.pressed.connect(_on_pop_out_pressed)

	# TimelineView 信号
	if _timeline_view.has_signal(&"keyframe_selected"):
		_timeline_view.connect(&"keyframe_selected", _on_keyframe_selected)
	if _timeline_view.has_signal(&"timeline_modified"):
		_timeline_view.connect(&"timeline_modified", _refresh_track_list)
	if _timeline_view.has_signal(&"keyframe_previewed"):
		_timeline_view.connect(&"keyframe_previewed", _on_keyframe_previewed)
	if _timeline_view.has_signal(&"preview_finished"):
		_timeline_view.connect(&"preview_finished", _on_preview_finished)
	# 标尺拖动 → 同步 PreviewStage（让动画跟随但不触发音效）
	if _timeline_view.has_signal(&"playhead_scrubbed"):
		_timeline_view.connect(&"playhead_scrubbed", _on_playhead_scrubbed)

	_refresh_ui()


# Dock 范围内空格 toggle play/pause（即便焦点不在 TimelineView 上也生效）
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
	# 默认在首帧（time=0）插一个 AnimationKeyframe；anim_name 取当前 SpriteFrames 的第一个动画
	var kf := AnimationKeyframe.new()
	kf.time = 0.0
	var first_anim: StringName = _pick_first_available_anim_name()
	if first_anim != &"":
		kf.anim_name = first_anim
	tr.keyframes.append(kf)
	current_timeline.tracks.append(tr)
	# 自动选中新增的轨道（让 Inspector 直接显示，新关键帧也方便用户继续编辑）
	selected_track_index = current_timeline.tracks.size() - 1
	selected_keyframe_index = -1
	_refresh_track_list()
	_refresh_inspector()


# 从当前 PreviewStage 的 SpriteFrames 里取"第一个"动画名（按字母排序）。
# 没有 SpriteFrames 或动画列表为空时返回空 StringName。
func _pick_first_available_anim_name() -> StringName:
	if _preview_stage == null or not is_instance_valid(_preview_stage) \
			or not _preview_stage.has_method(&"get_sprite_frames"):
		return &""
	var sf: Variant = _preview_stage.call(&"get_sprite_frames")
	if not (sf is SpriteFrames):
		return &""
	var names: PackedStringArray = (sf as SpriteFrames).get_animation_names()
	if names.size() == 0:
		return &""
	# get_animation_names() 已按字母排序，直接取第 0 项
	return StringName(names[0])


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
# 预览
# ─────────────────────────────────────────────────────────────

func _on_play_pressed() -> void:
	if _timeline_view != null and _timeline_view.has_method(&"play_preview"):
		_timeline_view.call(&"play_preview")
		# Scrub 后 sprite 被 pause 过，按 Play 时恢复自动推进
		if _preview_stage != null and _preview_stage.has_method(&"resume_animation"):
			_preview_stage.call(&"resume_animation")
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
	if _preview_stage.has_method(&"cam_zoom"):
		_preview_stage.call(&"cam_zoom", factor)


func _on_cam_reset_pressed() -> void:
	if _preview_stage == null:
		return
	if _preview_stage.has_method(&"cam_reset"):
		_preview_stage.call(&"cam_reset")
	if _preview_stage.has_method(&"reset_preview"):
		_preview_stage.call(&"reset_preview")


func _on_show_hitbox_band_toggled(v: bool) -> void:
	if _timeline_view != null and _timeline_view.has_method(&"set_show_hitbox_band"):
		_timeline_view.call(&"set_show_hitbox_band", v)


func _on_playhead_pause_requested(duration_ms: float) -> void:
	if _timeline_view != null and _timeline_view.has_method(&"pause_playhead_for"):
		_timeline_view.call(&"pause_playhead_for", duration_ms)


# 标尺被拖动时，让 PreviewStage 的角色显示"当前时间应该处于的动画与帧"。
# 不触发音效 / 震屏 / VFX / HitStop（避免拖动时反复鸣响），仅同步动画姿态。
# D 任务：除了切到正确动画外，还按 (time - anim_start) 把 sprite 暂停在精确帧。
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
	if latest_anim_kf == null:
		return
	# 优先调精确帧采样（PreviewStage3D / PreviewWindow 都暴露 sample_animation_at）
	var offset: float = max(0.0, time_sec - latest_anim_t)
	if _preview_stage.has_method(&"sample_animation_at"):
		_preview_stage.call(&"sample_animation_at", latest_anim_kf.anim_name, offset)
	elif _preview_stage.has_method(&"handle_keyframe"):
		# 老接口兜底：只切动画不定位帧
		_preview_stage.call(&"handle_keyframe", latest_anim_kf)


func _on_sprite_frames_changed(_path: String) -> void:
	# 刷新 toolbar label + 把新 SpriteFrames 注入 TimelineView，让动画色条按真实长度显示
	_sync_preview_sprite_frames_to_timeline()
	_refresh_ui()


# 把 PreviewStage 的 SpriteFrames 注入 TimelineView（C 任务：动画色条用）。
# PreviewStage 未创建时直接传 null，TimelineView 内部会回退到 manual_length。
func _sync_preview_sprite_frames_to_timeline() -> void:
	if _timeline_view == null or not _timeline_view.has_method(&"set_preview_sprite_frames"):
		return
	var sf: SpriteFrames = null
	if _preview_stage != null and is_instance_valid(_preview_stage) and _preview_stage.has_method(&"get_sprite_frames"):
		sf = _preview_stage.get_sprite_frames()
	# 兜底：从 PreviewStageConfig.last_sprite_frames_path 取（PreviewStage 还没初始化时）
	if sf == null:
		var cfg: Resource = load("res://Data/Config/PreviewStageConfig.tres")
		if cfg is PreviewStageConfig and not (cfg as PreviewStageConfig).last_sprite_frames_path.is_empty():
			var loaded: Resource = load((cfg as PreviewStageConfig).last_sprite_frames_path)
			if loaded is SpriteFrames:
				sf = loaded as SpriteFrames
	_timeline_view.call(&"set_preview_sprite_frames", sf)


func _on_keyframe_previewed(track_idx: int, kf_idx: int, kf: SkillKeyframe) -> void:
	# 路由到 PreviewStage 真实预览
	if _preview_stage != null and _preview_stage.has_method(&"handle_keyframe"):
		_preview_stage.call(&"handle_keyframe", kf)
	# Console 日志保留（便于排错）
	if kf is AnimationKeyframe:
		print("[SkillEditor preview] @%.2fs anim '%s'" % [kf.time, (kf as AnimationKeyframe).anim_name])
	elif kf is EventKeyframe:
		var ekf := kf as EventKeyframe
		print("[SkillEditor preview] @%.2fs event kind=%s payload=%s" % [kf.time, ekf.kind, ekf.payload])


func _on_preview_finished() -> void:
	# Timeline 播放结束（非 loop）时让预览角色停下来，避免 SpriteFrames.loop=true 的动画
	# 在 timeline 结束后仍独自循环（视觉上"timeline 已停但角色还在动"）。
	if _preview_stage != null and _preview_stage.has_method(&"stop_animation"):
		_preview_stage.call(&"stop_animation")
	print("[SkillEditor] preview finished")


# ─────────────────────────────────────────────────────────────
# 时间轴 → Inspector
# ─────────────────────────────────────────────────────────────

func _on_keyframe_selected(track_idx: int, kf_idx: int) -> void:
	selected_track_index = track_idx
	selected_keyframe_index = kf_idx
	if _track_list != null and _track_list.has_method(&"set_selected"):
		_track_list.set_selected(track_idx)
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
	if _btn_add_track != null:
		_btn_add_track.disabled = not has_timeline
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
	_sync_preview_sprite_frames_to_timeline()


func _refresh_track_list() -> void:
	# TrackListView 自绘版：直接 set_timeline 后刷新即可
	if _track_list != null and _track_list.has_method(&"set_timeline"):
		_track_list.set_timeline(current_timeline)
		# 维持选中状态
		if _track_list.has_method(&"set_selected"):
			_track_list.set_selected(selected_track_index)
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

	# 选中关键帧 → 按类型动态加载 form
	if selected_track_index >= 0 and selected_keyframe_index >= 0:
		var tr2: SkillTrack = current_timeline.tracks[selected_track_index]
		var kfs: Array = tr2.get_keyframes()
		if selected_keyframe_index < kfs.size():
			var kf: SkillKeyframe = kfs[selected_keyframe_index]
			# on_modified：结构变了（如 EventKind 切换），需要重建整个 form
			var on_modified := func() -> void:
				_refresh_track_list()
				_refresh_inspector()
			# on_data_changed：仅数据变更（高频字段如 anim_name 连续输入），只刷新 timeline 视图，
			# 不重建 form 以保留 LineEdit 焦点
			var on_data_changed := func() -> void:
				_refresh_track_list()
			# 提供当前 PreviewStage 的 SpriteFrames，让 AnimationKeyframe form 列出可用动画名
			var sf_provider := func() -> Variant:
				if _preview_stage != null and is_instance_valid(_preview_stage) \
						and _preview_stage.has_method(&"get_sprite_frames"):
					return _preview_stage.call(&"get_sprite_frames")
				return null
			_inspector_root.add_child(KeyframeFormBuilder.build(kf, on_modified, sf_provider, on_data_changed))


func _build_keyframe_form(kf: SkillKeyframe) -> Control:
	# 兼容入口：所有调用统一走 [KeyframeFormBuilder]。
	var sf_provider := func() -> Variant:
		if _preview_stage != null and is_instance_valid(_preview_stage) \
				and _preview_stage.has_method(&"get_sprite_frames"):
			return _preview_stage.call(&"get_sprite_frames")
		return null
	var on_modified := func() -> void:
		_refresh_track_list()
		_refresh_inspector()
	var on_data_changed := func() -> void:
		_refresh_track_list()
	return KeyframeFormBuilder.build(kf, on_modified, sf_provider, on_data_changed)


# ─────────────────────────────────────────────────────────────
# 独立 3D 预览窗口
# ─────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────
# 预览：内嵌 / Pop Out
# ─────────────────────────────────────────────────────────────

# 在 Dock 启动时把 PreviewScene.tscn 实例化并挂到 PreviewSlot（默认形态）。
func _ensure_preview_stage_embedded() -> void:
	if _preview_stage != null and is_instance_valid(_preview_stage):
		# 已存在；若当前不在 PreviewSlot 下（被 Pop Out），则先 reparent 回来
		if _preview_slot != null and _preview_stage.get_parent() != _preview_slot:
			_reparent_to(_preview_stage, _preview_slot)
		return
	var ps: PackedScene = load(PREVIEW_SCENE_PATH) as PackedScene
	if ps == null:
		push_error("[SkillEditor] PreviewScene.tscn not found at %s" % PREVIEW_SCENE_PATH)
		return
	var stage: PreviewStage3D = ps.instantiate() as PreviewStage3D
	if stage == null:
		push_error("[SkillEditor] PreviewScene root is not PreviewStage3D")
		return
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _preview_slot != null:
		_preview_slot.add_child(stage)
	else:
		add_child(stage)
	_preview_stage = stage
	# 信号桥接
	if stage.has_signal(&"playhead_pause_requested"):
		stage.playhead_pause_requested.connect(_on_playhead_pause_requested)
	if stage.has_signal(&"sprite_frames_changed"):
		stage.sprite_frames_changed.connect(_on_sprite_frames_changed)
	# 同步 mute 初始勾选
	if _preview_stage.has_method(&"is_muted"):
		_mute_check.button_pressed = bool(_preview_stage.call(&"is_muted"))
	# 把 SpriteFrames 注入 TimelineView，色条立即生效
	_sync_preview_sprite_frames_to_timeline()


# Pop Out 按钮：在「内嵌 PreviewSlot」与「独立 Window」之间切换。
# 共享同一个 PreviewStage3D 实例（reparent），保留 SpriteFrames / 配置 / 角色姿态状态。
func _on_pop_out_pressed() -> void:
	if _preview_stage == null:
		_ensure_preview_stage_embedded()
		if _preview_stage == null:
			return
	if _preview_window != null and is_instance_valid(_preview_window) and _preview_window.visible:
		# 当前在 Pop Out 状态 → 还原内嵌
		_dock_back_preview()
	else:
		# 内嵌 → Pop Out
		_pop_out_preview()


func _pop_out_preview() -> void:
	if _preview_stage == null:
		return
	# 创建（或复用）独立 Window
	if _preview_window == null or not is_instance_valid(_preview_window):
		var script_res: Script = load(PREVIEW_WINDOW_SCRIPT) as Script
		if script_res == null:
			push_error("[SkillEditor] PreviewWindow script not found at %s" % PREVIEW_WINDOW_SCRIPT)
			return
		var win: SkillEditorPreviewWindow = script_res.new()
		# 关键：传入 false 让 Window 不自动 _build 内嵌 stage（我们要 reparent 自己的）
		win.set_meta(&"external_stage", true)
		var attach_to: Node = self
		if _editor_interface != null:
			var base_ctrl := _editor_interface.get_base_control()
			if base_ctrl != null:
				attach_to = base_ctrl
		attach_to.add_child(win)
		_preview_window = win
		# Window 关闭 → 收回内嵌
		if win.has_signal(&"dock_back_requested"):
			win.connect(&"dock_back_requested", _dock_back_preview)
	# 把 stage reparent 到 Window
	var host: Node = _preview_window.get_stage_host()
	if host == null:
		host = _preview_window
	_reparent_to(_preview_stage, host)
	if not _preview_window.visible:
		_preview_window.popup_centered()
	if _btn_pop_out != null:
		_btn_pop_out.text = "🪟 Dock"
		_btn_pop_out.tooltip_text = "把预览收回 Dock 内嵌面板"


func _dock_back_preview() -> void:
	if _preview_stage == null or _preview_slot == null:
		return
	_reparent_to(_preview_stage, _preview_slot)
	if _preview_window != null and is_instance_valid(_preview_window):
		_preview_window.hide()
	if _btn_pop_out != null:
		_btn_pop_out.text = "🪟 Pop"
		_btn_pop_out.tooltip_text = "把预览弹到独立窗口（再次点击恢复内嵌）"


# 安全 reparent：先 remove_child，再 add_child；保留 visible/size_flags。
func _reparent_to(node: Control, new_parent: Node) -> void:
	if node == null or new_parent == null:
		return
	var old_parent: Node = node.get_parent()
	if old_parent == new_parent:
		return
	if old_parent != null:
		old_parent.remove_child(node)
	new_parent.add_child(node)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL

