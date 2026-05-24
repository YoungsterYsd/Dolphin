@tool
## Skill Editor 预览独立窗口（可选 Pop Out 形态）。
##
## 默认情况下 SkillEditor 内嵌 PreviewStage3D 在 Dock 的 Preview 面板里；
## 当用户点 Pop 按钮时，由 Dock 把 stage reparent 到本 Window 的 _stage_host。
## 关闭窗口（X）会发 "dock_back_requested" 信号让 Dock 还原内嵌。
##
## 兼容老接口：当 set_meta("external_stage") = false（或未设）时，仍保留懒加载内置 stage 的旧逻辑。
class_name SkillEditorPreviewWindow
extends Window

const PREVIEW_SCENE_PATH := "res://addons/skill_editor/dock/preview/PreviewScene.tscn"

signal playhead_pause_requested(duration_ms: float)
signal sprite_frames_changed(path: String)
signal dock_back_requested()

var _stage: PreviewStage3D = null
var _stage_host: Control = null  # stage 实际挂载的容器（VBox 子控件）


func _ready() -> void:
	title = "Skill Preview (3D)"
	min_size = Vector2i(560, 420)
	size = Vector2i(720, 540)
	exclusive = false
	# 关闭时通知 Dock 回收（Dock 会 reparent 回 PreviewSlot 并 hide 本窗口）
	close_requested.connect(func() -> void:
		dock_back_requested.emit()
		hide())
	_build()


# 由 Dock 在 Pop Out 时获取 stage 挂载点（VBox 子控件，扩展 fill）。
func get_stage_host() -> Control:
	return _stage_host


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_stage_host = root

	# 仅在"非 external_stage"模式（即由 Window 自己持有 stage）下才创建内置 stage；
	# Pop Out 模式下 Dock 会负责 reparent，本 Window 不创建。
	if not (has_meta(&"external_stage") and bool(get_meta(&"external_stage"))):
		var ps: PackedScene = load(PREVIEW_SCENE_PATH) as PackedScene
		if ps != null:
			_stage = ps.instantiate() as PreviewStage3D
		if _stage != null:
			_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
			root.add_child(_stage)
			# 信号转发
			if _stage.has_signal(&"playhead_pause_requested"):
				_stage.playhead_pause_requested.connect(func(ms: float) -> void:
					playhead_pause_requested.emit(ms))
			if _stage.has_signal(&"sprite_frames_changed"):
				_stage.sprite_frames_changed.connect(func(path: String) -> void:
					sprite_frames_changed.emit(path))


# ─────────────────────────────────────────────────────────────
# 转发 API（与 PreviewStage / PreviewStage3D 同签名）
# 注意：external_stage 模式下 _stage = null，所有方法返回安全默认值。
# Dock 应直接调内嵌 stage，本 Window 仅作为容器。
# ─────────────────────────────────────────────────────────────

func handle_keyframe(kf: SkillKeyframe) -> void:
	if _stage != null:
		_stage.handle_keyframe(kf)


func reset_preview() -> void:
	if _stage != null:
		_stage.reset_preview()


func set_mute(v: bool) -> void:
	if _stage != null:
		_stage.set_mute(v)


func is_muted() -> bool:
	return _stage != null and _stage.is_muted()


func cam_zoom(factor: float) -> void:
	if _stage != null and _stage.has_method(&"cam_zoom"):
		_stage.cam_zoom(factor)


func cam_reset() -> void:
	if _stage != null and _stage.has_method(&"cam_reset"):
		_stage.cam_reset()


func get_sprite_frames() -> SpriteFrames:
	return _stage.get_sprite_frames() if _stage != null else null


func sample_animation_at(anim_name: StringName, offset_in_anim: float) -> void:
	if _stage != null:
		_stage.sample_animation_at(anim_name, offset_in_anim)


func resume_animation() -> void:
	if _stage != null:
		_stage.resume_animation()


func stop_animation() -> void:
	if _stage != null:
		_stage.stop_animation()


func get_stage() -> PreviewStage3D:
	return _stage
