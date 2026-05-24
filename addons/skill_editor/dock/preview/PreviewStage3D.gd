@tool
## 编辑器内嵌技能预览舞台 · 3D 版（基于 PreviewScene.tscn）。
##
## 与历史"代码动态构建 SubViewport+Camera"方案不同，本版本所有节点都在 PreviewScene.tscn 里
## 静态布置好；脚本通过 `%unique_name` 直接引用，避免 @tool 启动时序导致的"viewport size=0
## / 相机未 current / 渲染空白"等问题。
##
## 使用方式：Dock 直接 [code]load("PreviewScene.tscn").instantiate()[/code]，挂到 PreviewSlot 即可。
##
## 关键帧路由：handle_keyframe(kf) 由 SkillEditorDock 在 keyframe_previewed 时转发。
##   · AnimationKeyframe → 切动画
##   · EventKeyframe.SFX_PLAY → 播 AudioStream
##   · EventKeyframe.CAMERA_SHAKE → Tween 抖 Camera3D
##   · EventKeyframe.HIT_STOP → emit playhead_pause_requested(ms)
##   · EventKeyframe.VFX_SPAWN → instantiate payload.vfx_scene_path 到 VfxLayer
##   · 其它 Kind → 仅打印
##
## 配置：[PreviewStageConfig.tres]。
## R-LOG-01 例外：编辑器进程，沿用 print / push_error。
class_name PreviewStage3D
extends VBoxContainer

const CONFIG_PATH: String = "res://Data/Config/PreviewStageConfig.tres"

signal playhead_pause_requested(duration_ms: float)
signal sprite_frames_changed(path: String)

# === 节点引用（来自 PreviewScene.tscn 的 unique_name 节点）===
@onready var _hint_label: Label = %HintLabel
@onready var _browse_btn: Button = %BrowseBtn
@onready var _viewport_container: SubViewportContainer = %ViewportContainer
@onready var _viewport: SubViewport = %Viewport
@onready var _sprite: AnimatedSprite3D = %Sprite
@onready var _vfx_layer: Node3D = %VfxLayer
@onready var _camera: Camera3D = %Camera
@onready var _spring_arm: SpringArm3D = %SpringArm
@onready var _audio: AudioStreamPlayer = %AudioPlayer

# === 配置 ===
var _config: PreviewStageConfig = null

# === 抖动状态 ===
var _shake_tween: Tween = null

# 相机 zoom（缓存，与 SpringArm.spring_length 同步）
# 默认 8.0 m 与 main_scene 的 CameraConfig.distance 一致；
# _ready 时会用场景里的实际值覆盖，所以只是兜底。
var _cam_distance_default: float = 8.0
var _cam_distance: float = 8.0


func _ready() -> void:
	_load_config()
	# 显式接收事件（拖拽 SpriteFrames 时 _can_drop_data / _drop_data 才会被调用）
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 缓存初始相机距离（场景里写死 2.4，但允许配置覆盖）
	if _spring_arm != null:
		_cam_distance_default = _spring_arm.spring_length
		_cam_distance = _cam_distance_default
	# 浏览按钮
	if _browse_btn != null and not _browse_btn.pressed.is_connected(_on_browse_sprite_frames_pressed):
		_browse_btn.pressed.connect(_on_browse_sprite_frames_pressed)
	# 应用持久化配置（last_sprite_frames_path）
	_apply_config_to_view()


# ─────────────────────────────────────────────────────────────
# 公开 API（被 SkillEditorDock / PreviewWindow 转发调用）
# ─────────────────────────────────────────────────────────────

func handle_keyframe(kf: SkillKeyframe) -> void:
	if kf == null:
		return
	if kf is AnimationKeyframe:
		_play_animation(kf as AnimationKeyframe)
	elif kf is EventKeyframe:
		_handle_event(kf as EventKeyframe)


func reset_preview() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		_shake_tween = null
	if _camera != null:
		_camera.position = Vector3.ZERO  # SpringArm 子节点偏移
	if _vfx_layer != null:
		for c in _vfx_layer.get_children():
			c.queue_free()
	if _audio != null and _audio.playing:
		_audio.stop()
	if _sprite != null:
		_sprite.stop()


func set_mute(v: bool) -> void:
	if _config == null:
		return
	_config.mute_audio = v
	_save_config()


func is_muted() -> bool:
	return _config != null and _config.mute_audio


# 相机 zoom（被 Dock 工具栏的 Zoom +/- 调用）
func cam_zoom(factor: float) -> void:
	if _spring_arm == null:
		return
	_cam_distance = clampf(_cam_distance / factor, 1.0, 30.0)
	_spring_arm.spring_length = _cam_distance


func cam_reset() -> void:
	if _spring_arm == null:
		return
	_cam_distance = _cam_distance_default
	_spring_arm.spring_length = _cam_distance


# 当前预览角色使用的 SpriteFrames（TimelineView 计算动画色条长度用）；可能为 null。
func get_sprite_frames() -> SpriteFrames:
	return _sprite.sprite_frames if _sprite != null else null


# 让外部（Dock · D 任务的 Scrub）按 anim 起始时间 + 偏移，把 sprite 暂停在指定帧上。
# offset_in_anim 单位秒，<0 视为 0；超过该 anim 总长时停在末帧。
func sample_animation_at(anim_name: StringName, offset_in_anim: float) -> void:
	if _sprite == null or _sprite.sprite_frames == null or anim_name == &"":
		return
	if not _sprite.sprite_frames.has_animation(anim_name):
		return
	var fps: float = _sprite.sprite_frames.get_animation_speed(anim_name)
	var frames: int = _sprite.sprite_frames.get_frame_count(anim_name)
	if fps <= 0.0001 or frames <= 0:
		return
	var off: float = max(0.0, offset_in_anim)
	var idx: int = int(off * fps)
	if idx >= frames:
		idx = frames - 1
	if _sprite.animation != anim_name:
		_sprite.play(anim_name)
	_sprite.pause()
	_sprite.frame = idx


# 被 [method sample_animation_at] 暂停的 sprite，在用户按 Play 时恢复自动推进。
func resume_animation() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var cur: StringName = _sprite.animation
	if cur != &"" and _sprite.sprite_frames.has_animation(cur):
		_sprite.play(cur)


# Timeline 播放结束（非循环模式）时由 Dock 调用：暂停 sprite 防止 SpriteFrames.loop=true
# 的动画在 timeline 结束后还独自循环。
func stop_animation() -> void:
	if _sprite == null:
		return
	_sprite.pause()


# ─────────────────────────────────────────────────────────────
# Browse 按钮 + 拖拽接收
# ─────────────────────────────────────────────────────────────

func _on_browse_sprite_frames_pressed() -> void:
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray(["*.tres ; SpriteFrames"])
	dlg.current_dir = "res://Content/Sprites"
	dlg.file_selected.connect(func(path: String) -> void:
		var res: Resource = load(path)
		if res is SpriteFrames:
			_apply_sprite_frames(res as SpriteFrames, path)
			if _config != null:
				_config.last_sprite_frames_path = path
				_save_config()
			sprite_frames_changed.emit(path)
		else:
			push_warning("[PreviewStage3D] selected file is not SpriteFrames: %s" % path)
		dlg.queue_free()
	)
	# 挂到 EditorInterface base control 而非 self，避免 popup 被 Window 裁掉
	var ei: Object = Engine.get_singleton(&"EditorInterface")
	if ei != null and ei.has_method(&"get_base_control"):
		var base_ctrl: Node = ei.call(&"get_base_control") as Node
		if base_ctrl != null:
			base_ctrl.add_child(dlg)
		else:
			Engine.get_main_loop().root.add_child(dlg)
	else:
		Engine.get_main_loop().root.add_child(dlg)
	dlg.popup_centered_ratio(0.6)


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return _extract_sprite_frames_from_drop(data).has(&"sf")


func _drop_data(_pos: Vector2, data: Variant) -> void:
	var info: Dictionary = _extract_sprite_frames_from_drop(data)
	if info.is_empty():
		return
	_apply_sprite_frames(info["sf"], info["path"])
	if _config != null:
		_config.last_sprite_frames_path = info["path"]
		_save_config()
	sprite_frames_changed.emit(String(info["path"]))


func _extract_sprite_frames_from_drop(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var d: Dictionary = data
	if d.get("type", "") == "files":
		var files: PackedStringArray = d.get("files", PackedStringArray())
		for f in files:
			var res: Resource = load(f)
			if res is SpriteFrames:
				return {"sf": res, "path": f}
		return {}
	if d.get("type", "") == "resource":
		var res2: Resource = d.get("resource", null)
		if res2 is SpriteFrames:
			return {"sf": res2, "path": res2.resource_path}
	return {}


func _apply_sprite_frames(sf: SpriteFrames, path: String) -> void:
	if _sprite == null:
		return
	_sprite.sprite_frames = sf
	if _hint_label != null:
		_hint_label.text = "Preview (3D)  ·  %s" % path.get_file()


# ─────────────────────────────────────────────────────────────
# 关键帧处理
# ─────────────────────────────────────────────────────────────

func _play_animation(kf: AnimationKeyframe) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		print("[PreviewStage3D] no sprite_frames; click Browse or drag SpriteFrames.tres")
		return
	var name_str: StringName = kf.anim_name
	if name_str == &"":
		return
	if not _sprite.sprite_frames.has_animation(name_str):
		print("[PreviewStage3D] anim '%s' not in SpriteFrames" % name_str)
		return
	_sprite.sprite_frames.set_animation_loop(name_str, kf.loop)
	_sprite.play(name_str)


func _handle_event(kf: EventKeyframe) -> void:
	match kf.kind:
		SkillEventKind.SFX_PLAY:
			_handle_sfx_play(kf.payload)
		SkillEventKind.CAMERA_SHAKE:
			_handle_camera_shake(kf.payload)
		SkillEventKind.HIT_STOP:
			_handle_hit_stop(kf.payload)
		SkillEventKind.VFX_SPAWN:
			_handle_vfx_spawn(kf.payload)
		_:
			print("[PreviewStage3D] event kind=%s payload=%s (no visual preview)" % [kf.kind, kf.payload])


func _handle_sfx_play(payload: Dictionary) -> void:
	if _audio == null or (_config != null and _config.mute_audio):
		return
	var stream: AudioStream = null
	var sfx_id: StringName = StringName(str(payload.get("sfx_id", "")))
	if sfx_id != &"":
		var bindings_res: Resource = load("res://Data/Config/SfxBindings.tres")
		if bindings_res is SfxBindings:
			stream = (bindings_res as SfxBindings).get_stream(sfx_id)
	if stream == null:
		print("[PreviewStage3D] sfx_play: sfx_id='%s' not bound" % sfx_id)
		return
	_audio.stream = stream
	_audio.play()


func _handle_camera_shake(payload: Dictionary) -> void:
	if _camera == null:
		return
	var intensity: float = float(payload.get("intensity", 4.0))
	var duration: float = float(payload.get("duration", 0.15))
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps: int = max(2, _config.camera_shake_steps if _config != null else 4)
	var step_time: float = duration / float(steps)
	# 单位换算：2D intensity 是像素；3D 量纲是米，约 / 50
	var amp_unit: float = intensity / 50.0
	for i in range(steps):
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0).normalized()
		var amp: float = amp_unit * (1.0 - float(i) / float(steps))
		_shake_tween.tween_property(_camera, "position", dir * amp, step_time * 0.5)
	_shake_tween.tween_property(_camera, "position", Vector3.ZERO, step_time * 0.5)


func _handle_hit_stop(payload: Dictionary) -> void:
	var ms: float = float(payload.get("duration_ms", 80.0))
	playhead_pause_requested.emit(ms)


func _handle_vfx_spawn(payload: Dictionary) -> void:
	var path: String = String(payload.get("vfx_scene_path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		print("[PreviewStage3D] vfx_spawn: invalid scene path '%s'" % path)
		return
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return
	var inst: Node = ps.instantiate()
	if inst is Node3D:
		var off: Vector3 = payload.get("offset_3d", Vector3.ZERO)
		(inst as Node3D).position = Vector3(0.0, 0.6, 0.0) + off
	_vfx_layer.add_child(inst)
	var lifetime: float = float(payload.get("lifetime", _config.default_vfx_lifetime if _config != null else 1.5))
	var t := get_tree().create_timer(lifetime)
	t.timeout.connect(func() -> void:
		if is_instance_valid(inst):
			inst.queue_free()
	)


# ─────────────────────────────────────────────────────────────
# 配置读写
# ─────────────────────────────────────────────────────────────

func _load_config() -> void:
	var res: Resource = load(CONFIG_PATH)
	if res is PreviewStageConfig:
		_config = res as PreviewStageConfig
	else:
		_config = PreviewStageConfig.new()


func _apply_config_to_view() -> void:
	if _config == null or _sprite == null:
		return
	if not _config.last_sprite_frames_path.is_empty():
		var res: Resource = load(_config.last_sprite_frames_path)
		if res is SpriteFrames:
			_apply_sprite_frames(res as SpriteFrames, _config.last_sprite_frames_path)


func _save_config() -> void:
	if _config == null or _config.resource_path.is_empty():
		return
	ResourceSaver.save(_config, _config.resource_path)
