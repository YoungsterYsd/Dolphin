@tool
## 编辑器内嵌技能预览舞台（M7.7）。
##
## 功能合集（避免组件爆炸，集中在本脚本管理）：
##   - SubViewport 渲染：AnimatedSprite2D 角色 + Camera2D + VfxLayer
##   - 拖拽接收：把 SpriteFrames.tres 拖到本控件即应用到预览角色（用户决策 q1=C）
##   - 关键帧路由：handle_keyframe(kf) 由 SkillEditorDock 在 keyframe_previewed 时转发
##     · AnimationKeyframe → 切动画
##     · EventKeyframe.SFX_PLAY → 播 AudioStream（路径走 payload.sfx_path 或后续 SfxBank）
##     · EventKeyframe.CAMERA_SHAKE → Tween 抖 Camera2D
##     · EventKeyframe.HIT_STOP → emit playhead_pause_requested(ms)，由 TimelineView 实现暂停
##     · EventKeyframe.VFX_SPAWN → instantiate payload.vfx_scene_path 到 VfxLayer
##     · 其它 Kind → 仅打印（PROJECTILE / CUSTOM 编辑器内不预览）
##
## 配置：[PreviewStageConfig.tres]（R-DATA-02 合规）。
##
## R-LOG-01 例外：编辑器进程，沿用 print / push_error，不依赖 GameLogger Autoload。
## R-EVENT-01 例外：编辑器内不 emit 真实 EventBus 信号；本控件向 Dock 抛本地信号。
class_name PreviewStage
extends Control

const CONFIG_PATH: String = "res://Data/Config/PreviewStageConfig.tres"

## 顶部由 Dock 监听：当 HitStop 事件触发时让 TimelineView 暂停游标 N 毫秒。
signal playhead_pause_requested(duration_ms: float)
## SpriteFrames 拖入后通知 Dock（用于刷新 Inspector 顶部状态文字等）。
signal sprite_frames_changed(path: String)

# === 节点引用 ===
var _viewport_container: SubViewportContainer = null
var _viewport: SubViewport = null
var _sprite: AnimatedSprite2D = null
var _camera: Camera2D = null
var _vfx_layer: Node2D = null
var _audio: AudioStreamPlayer = null
var _hint_label: Label = null

# === 配置 ===
var _config: PreviewStageConfig = null

# === 抖动状态 ===
var _shake_tween: Tween = null


func _ready() -> void:
	_load_config()
	_build_view()
	_apply_config_to_view()
	# 默认大小
	custom_minimum_size = Vector2(0, _config.viewport_size.y + 24)


# ─────────────────────────────────────────────────────────────
# 公开 API（Dock 调用）
# ─────────────────────────────────────────────────────────────

func handle_keyframe(kf: SkillKeyframe) -> void:
	if kf == null:
		return
	if kf is AnimationKeyframe:
		_play_animation(kf as AnimationKeyframe)
	elif kf is EventKeyframe:
		_handle_event(kf as EventKeyframe)


func reset_preview() -> void:
	# 停所有特效 / 抖动 / 音效（Reset 按钮调用）
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
		_shake_tween = null
	if _camera != null:
		_camera.offset = Vector2.ZERO
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


# ─────────────────────────────────────────────────────────────
# 视图构建
# ─────────────────────────────────────────────────────────────

func _build_view() -> void:
	# 顶部提示标签
	_hint_label = Label.new()
	_hint_label.text = "Preview Stage  ·  drag a SpriteFrames.tres here to set preview character"
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	add_child(_hint_label)

	# SubViewportContainer
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = false
	_viewport_container.custom_minimum_size = _config.viewport_size
	_viewport_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = _config.viewport_size
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_viewport)

	# 背景棋盘（一个简单 ColorRect 即可分辨预览区域）
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.13)
	bg.size = Vector2(_config.viewport_size)
	_viewport.add_child(bg)

	# 角色
	_sprite = AnimatedSprite2D.new()
	_sprite.position = Vector2(_config.viewport_size) * 0.5
	_viewport.add_child(_sprite)

	# 相机
	_camera = Camera2D.new()
	_camera.position = Vector2(_config.viewport_size) * 0.5
	_camera.zoom = Vector2(_config.camera_zoom, _config.camera_zoom)
	_camera.enabled = true
	# 不调 make_current()：SubViewport 内只有一个 Camera2D，Godot 会自动选为当前相机
	_viewport.add_child(_camera)

	# VFX 容器
	_vfx_layer = Node2D.new()
	_vfx_layer.name = "VfxLayer"
	_viewport.add_child(_vfx_layer)

	# 音频播放器（Dock 持有，不进 SubViewport）
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"Master"
	add_child(_audio)


func _apply_config_to_view() -> void:
	if _config == null:
		return
	# 恢复 SpriteFrames
	if not _config.last_sprite_frames_path.is_empty():
		var res: Resource = load(_config.last_sprite_frames_path)
		if res is SpriteFrames:
			_apply_sprite_frames(res as SpriteFrames, _config.last_sprite_frames_path)


# ─────────────────────────────────────────────────────────────
# 拖拽接收 SpriteFrames（用户决策 q1=C）
# ─────────────────────────────────────────────────────────────

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return _extract_sprite_frames_from_drop(data) != null


func _drop_data(_pos: Vector2, data: Variant) -> void:
	var info: Dictionary = _extract_sprite_frames_from_drop(data)
	if info.is_empty():
		return
	_apply_sprite_frames(info["sf"], info["path"])
	# 持久化
	if _config != null:
		_config.last_sprite_frames_path = info["path"]
		_save_config()
	sprite_frames_changed.emit(String(info["path"]))


func _extract_sprite_frames_from_drop(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var d: Dictionary = data
	# Godot Editor 资源拖拽 type=files 或 resource
	if d.get("type", "") == "files":
		var files: PackedStringArray = d.get("files", PackedStringArray())
		for f in files:
			var res: Resource = load(f)
			if res is SpriteFrames:
				return {"sf": res, "path": f}
			# 如果是 .tscn / 含 SpriteFrames 的资源，尝试从 PackedScene 内提取
			if res is PackedScene:
				var sf: SpriteFrames = _extract_sprite_frames_from_packed_scene(res as PackedScene)
				if sf != null:
					return {"sf": sf, "path": f}
		return {}
	if d.get("type", "") == "resource":
		var res2: Resource = d.get("resource", null)
		if res2 is SpriteFrames:
			return {"sf": res2, "path": res2.resource_path}
	return {}


func _extract_sprite_frames_from_packed_scene(ps: PackedScene) -> SpriteFrames:
	# 简单遍历 SceneState 找第一个 sprite_frames 属性
	var state := ps.get_state()
	for i in range(state.get_node_count()):
		var prop_count: int = state.get_node_property_count(i)
		for j in range(prop_count):
			var pname: String = state.get_node_property_name(i, j)
			if pname == "sprite_frames" or pname == "frames":
				var v: Variant = state.get_node_property_value(i, j)
				if v is SpriteFrames:
					return v
	return null


func _apply_sprite_frames(sf: SpriteFrames, path: String) -> void:
	if _sprite == null:
		return
	_sprite.sprite_frames = sf
	if _hint_label != null:
		_hint_label.text = "Preview Stage  ·  %s" % path.get_file()


# ─────────────────────────────────────────────────────────────
# 关键帧处理
# ─────────────────────────────────────────────────────────────

func _play_animation(kf: AnimationKeyframe) -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		print("[PreviewStage] no sprite_frames; drag a SpriteFrames.tres into preview area first")
		return
	var name_str: StringName = kf.anim_name
	if name_str == &"":
		return
	if not _sprite.sprite_frames.has_animation(name_str):
		print("[PreviewStage] anim '%s' not in SpriteFrames" % name_str)
		return
	# loop 控制写回到 SpriteFrames（编辑器内副作用，仅预览期；保存的 .tres 不会被修改）
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
			# HITBOX_ENABLE / DISABLE / PROJECTILE / CUSTOM：编辑器内仅打印
			print("[PreviewStage] event kind=%s payload=%s (no visual preview)" % [kf.kind, kf.payload])


func _handle_sfx_play(payload: Dictionary) -> void:
	if _audio == null or (_config != null and _config.mute_audio):
		return
	# M8：sfx_id 走 ConfigCenter.SfxBindings 查表（统一规则，与运行时一致）
	var stream: AudioStream = null
	var sfx_id: StringName = StringName(str(payload.get("sfx_id", "")))
	if sfx_id != &"":
		var cfg: Node = null
		if Engine.is_editor_hint() and EditorInterface != null:
			# 编辑器进程没 Autoload，直接 load
			var bindings_res: Resource = load("res://Data/Config/SfxBindings.tres")
			if bindings_res is SfxBindings:
				stream = (bindings_res as SfxBindings).get_stream(sfx_id)
		else:
			cfg = get_tree().root.get_node_or_null(^"ConfigCenter")
			if cfg != null:
				stream = cfg.get_sfx_stream(sfx_id)
	if stream == null:
		print("[PreviewStage] sfx_play: sfx_id='%s' not bound in SfxBindings.tres (payload=%s)" % [sfx_id, payload])
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
	var base: Vector2 = Vector2(_config.viewport_size) * 0.5
	for i in range(steps):
		var dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
		var amp: float = intensity * (1.0 - float(i) / float(steps))
		_shake_tween.tween_property(_camera, "offset", dir * amp, step_time * 0.5)
	_shake_tween.tween_property(_camera, "offset", Vector2.ZERO, step_time * 0.5)


func _handle_hit_stop(payload: Dictionary) -> void:
	var ms: float = float(payload.get("duration_ms", 80.0))
	# 仅暂停游标推进，不影响整个编辑器
	playhead_pause_requested.emit(ms)


func _handle_vfx_spawn(payload: Dictionary) -> void:
	var path: String = String(payload.get("vfx_scene_path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		print("[PreviewStage] vfx_spawn: invalid scene path '%s'" % path)
		return
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		return
	var inst: Node = ps.instantiate()
	# 位置：相对 viewport 中心 + payload.offset
	if inst is Node2D:
		var off: Vector2 = payload.get("offset_2d", Vector2.ZERO)
		(inst as Node2D).position = Vector2(_config.viewport_size) * 0.5 + off
	_vfx_layer.add_child(inst)
	# 自动销毁
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
		push_error("[PreviewStage] PreviewStageConfig.tres not found, using defaults")


func _save_config() -> void:
	if _config == null or _config.resource_path.is_empty():
		return
	ResourceSaver.save(_config, _config.resource_path)
