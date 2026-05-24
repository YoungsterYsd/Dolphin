@tool
## Inspector 表单构造器。
##
## 按 [SkillKeyframe] 的具体子类型与 [EventKeyframe.kind] 渲染对应的 typed form，
## 替代旧版"裸 JSON TextEdit"。返回的 Control 由 [SkillEditorDock] 挂到 InspectorRoot。
##
## 设计：
##   - 全部 build_* 是静态函数；表单字段改动后调 on_modified.call() 通知 Dock 刷新。
##   - payload 是 [Dictionary]，所有 setter 直接 in-place 改 kf.payload[key] = v，无需 copy。
##   - 字段命名严格对齐 [EventKeyframe] 类注释里 payload 约定（与 EventTrackHandler 保持一致）。
##
## R-LOG-01 例外：编辑器进程，沿用 print。
class_name KeyframeFormBuilder
extends RefCounted


## 入口：根据 kf 类型分派。
##
## on_modified 语义 = "结构变了，请重建本 form"。EventKind 切换、auto_length 勾选这种会重建 form 的字段会触发它；
## 而 anim_name / payload 字段等"高频连续输入"会用 on_data_changed（默认与 on_modified 一致），
## 调用方可以传不同的 callable 让 LineEdit 等控件在每次按键时只刷新 timeline 色条而不破坏焦点。
##
## sprite_frames_provider 可选：用来在 AnimationKeyframe 的 anim_name 编辑控件中列出
## 当前 SpriteFrames 已有的动画名，方便用户从下拉里选；不传则只显示纯 LineEdit。
static func build(
		kf: SkillKeyframe,
		on_modified: Callable,
		sprite_frames_provider: Callable = Callable(),
		on_data_changed: Callable = Callable()) -> Control:
	if not on_data_changed.is_valid():
		on_data_changed = on_modified
	if kf == null:
		return _label("(null keyframe)")
	if kf is AnimationKeyframe:
		return _build_animation(kf as AnimationKeyframe, on_modified, sprite_frames_provider, on_data_changed)
	if kf is EventKeyframe:
		return _build_event(kf as EventKeyframe, on_modified)
	return _label("(unknown keyframe type)")


# ─────────────────────────────────────────────────────────────
# Animation keyframe
# ─────────────────────────────────────────────────────────────

static func _build_animation(
		kf: AnimationKeyframe,
		on_modified: Callable,
		sprite_frames_provider: Callable,
		on_data_changed: Callable) -> Control:
	var box := _vbox()
	box.add_child(_section_title("Animation Keyframe"))
	box.add_child(_field_time(kf, on_data_changed))

	# 取当前 SpriteFrames 内已有的动画名（用于下拉）
	var anim_names: PackedStringArray = _collect_anim_names(sprite_frames_provider)

	# anim_name 编辑布局：
	#   ┌────────────────────────────────┬─────────────┐
	#   │ LineEdit（手输 / 主输入框）   │ OptionButton │
	#   └────────────────────────────────┴─────────────┘
	# - LineEdit text_changed 只写 kf.anim_name + on_data_changed（不重建 form，焦点保留 → 支持连续输入）
	# - OptionButton 选某项 → 写 LineEdit + 写 kf.anim_name + on_data_changed
	box.add_child(_label("anim_name"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var le := LineEdit.new()
	le.text = String(kf.anim_name)
	le.placeholder_text = "e.g. attack_1"
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(s: String) -> void:
		kf.anim_name = StringName(s)
		_safe_call(on_data_changed)
	)
	row.add_child(le)

	if anim_names.size() > 0:
		var opt := OptionButton.new()
		opt.text = "▼"
		opt.tooltip_text = "选择当前 SpriteFrames 中已有的动画"
		# 直接把动画名作为下拉项（不再有占位项）
		for i in range(anim_names.size()):
			opt.add_item(anim_names[i])
		# 初始 selected：若当前 anim_name 命中下拉项则选中对应索引；否则不选中（=-1，OptionButton 显示"▼"）
		var initial_idx: int = -1
		var current: String = String(kf.anim_name)
		for i in range(anim_names.size()):
			if String(anim_names[i]) == current:
				initial_idx = i
				break
		if initial_idx >= 0:
			opt.select(initial_idx)
		opt.item_selected.connect(func(i: int) -> void:
			if i < 0 or i >= anim_names.size():
				return
			var picked: String = anim_names[i]
			kf.anim_name = StringName(picked)
			le.text = picked
			_safe_call(on_data_changed)
		)
		row.add_child(opt)

	box.add_child(row)

	if anim_names.size() == 0:
		var hint := _label("(没有可用 SpriteFrames，请在预览面板拖入或点 Browse)")
		hint.modulate = Color(1, 1, 1, 0.55)
		box.add_child(hint)

	# loop
	var loop_cb := CheckBox.new()
	loop_cb.text = "loop"
	loop_cb.button_pressed = kf.loop
	loop_cb.toggled.connect(func(v: bool) -> void:
		kf.loop = v
		_safe_call(on_data_changed)
	)
	box.add_child(loop_cb)

	# auto_length / manual_length（C 任务引入；编辑器侧色条长度，与运行时无关）
	var auto_cb := CheckBox.new()
	auto_cb.text = "auto length (从 SpriteFrames 推算)"
	auto_cb.button_pressed = kf.auto_length
	auto_cb.toggled.connect(func(v: bool) -> void:
		kf.auto_length = v
		_safe_call(on_data_changed)
	)
	box.add_child(auto_cb)

	box.add_child(_label("manual length (s) · auto 关闭时生效"))
	var ml := SpinBox.new()
	ml.min_value = 0.0
	ml.max_value = 30.0
	ml.step = 0.01
	ml.value = kf.manual_length
	ml.value_changed.connect(func(v: float) -> void:
		kf.manual_length = v
		_safe_call(on_data_changed)
	)
	box.add_child(ml)

	return box


# 从 sprite_frames_provider（Callable -> SpriteFrames or null）取所有动画名（按字母排序）。
static func _collect_anim_names(provider: Callable) -> PackedStringArray:
	var out := PackedStringArray()
	if not provider.is_valid():
		return out
	var sf_var: Variant = provider.call()
	if not (sf_var is SpriteFrames):
		return out
	var sf: SpriteFrames = sf_var as SpriteFrames
	var names: PackedStringArray = sf.get_animation_names()
	# get_animation_names() 已按字母排序，但保险一遍
	var sorted: Array = []
	for n in names:
		sorted.append(String(n))
	sorted.sort()
	for n in sorted:
		out.append(n)
	return out


# ─────────────────────────────────────────────────────────────
# Event keyframe（按 kind 分派）
# ─────────────────────────────────────────────────────────────

static func _build_event(kf: EventKeyframe, on_modified: Callable) -> Control:
	var box := _vbox()
	box.add_child(_section_title("Event Keyframe"))
	box.add_child(_field_time(kf, on_modified))

	# Kind 下拉
	box.add_child(_label("kind"))
	var opt := OptionButton.new()
	var kinds: Array[StringName] = SkillEventKind.all()
	var current_idx: int = 0
	for i in range(kinds.size()):
		opt.add_item(String(kinds[i]))
		if kinds[i] == kf.kind:
			current_idx = i
	opt.select(current_idx)
	opt.item_selected.connect(func(i: int) -> void:
		kf.kind = kinds[i]
		# 切 kind 时清空 payload，避免脏字段；调 on_modified 让 Dock 重建整个 form。
		kf.payload = {}
		_safe_call(on_modified)
	)
	box.add_child(opt)
	box.add_child(HSeparator.new())

	# 按 kind 渲染 payload form
	match kf.kind:
		SkillEventKind.HITBOX_ENABLE:
			_build_hitbox_enable(box, kf, on_modified)
		SkillEventKind.HITBOX_DISABLE:
			_build_hitbox_disable(box, kf, on_modified)
		SkillEventKind.SFX_PLAY:
			_build_sfx_play(box, kf, on_modified)
		SkillEventKind.VFX_SPAWN:
			_build_vfx_spawn(box, kf, on_modified)
		SkillEventKind.PROJECTILE_SPAWN:
			_build_projectile_spawn(box, kf, on_modified)
		SkillEventKind.CAMERA_SHAKE:
			_build_camera_shake(box, kf, on_modified)
		SkillEventKind.HIT_STOP:
			_build_hit_stop(box, kf, on_modified)
		SkillEventKind.CUSTOM_SIGNAL:
			_build_custom_signal(box, kf, on_modified)
		_:
			box.add_child(_label("(unknown kind, raw JSON below)"))
			box.add_child(_raw_json_edit(kf, on_modified))

	# 兜底：折叠的 raw JSON（专家手动微调用）
	box.add_child(HSeparator.new())
	var raw_btn := Button.new()
	raw_btn.text = "▸ raw payload (JSON)"
	raw_btn.toggle_mode = true
	raw_btn.flat = true
	raw_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(raw_btn)
	var raw_box := _raw_json_edit(kf, on_modified)
	raw_box.visible = false
	box.add_child(raw_box)
	raw_btn.toggled.connect(func(v: bool) -> void:
		raw_box.visible = v
		raw_btn.text = ("▾ raw payload (JSON)" if v else "▸ raw payload (JSON)")
	)

	return box


# ─────────────────────────────────────────────────────────────
# 各 Kind 的具体 form
# ─────────────────────────────────────────────────────────────

static func _build_hitbox_enable(box: VBoxContainer, kf: EventKeyframe, on_modified: Callable) -> void:
	# payload: {node_path: "HitboxComponent", damage_node_index: 0}
	box.add_child(_label("node_path"))
	var le := LineEdit.new()
	le.text = String(kf.payload.get("node_path", "HitboxComponent"))
	le.placeholder_text = "HitboxComponent"
	le.text_changed.connect(func(s: String) -> void:
		kf.payload["node_path"] = s
		_safe_call(on_modified)
	)
	box.add_child(le)

	box.add_child(_label("damage_node_index · 查 SkillDamageTable[skill_id][index]"))
	var sp := SpinBox.new()
	sp.min_value = 0
	sp.max_value = 31
	sp.step = 1
	sp.value = int(kf.payload.get("damage_node_index", 0))
	sp.value_changed.connect(func(v: float) -> void:
		kf.payload["damage_node_index"] = int(v)
		_safe_call(on_modified)
	)
	box.add_child(sp)


static func _build_hitbox_disable(box: VBoxContainer, kf: EventKeyframe, on_modified: Callable) -> void:
	# payload: {node_path: "HitboxComponent"}
	box.add_child(_label("node_path"))
	var le := LineEdit.new()
	le.text = String(kf.payload.get("node_path", "HitboxComponent"))
	le.placeholder_text = "HitboxComponent"
	le.text_changed.connect(func(s: String) -> void:
		kf.payload["node_path"] = s
		_safe_call(on_modified)
	)
	box.add_child(le)


static func _build_sfx_play(box: VBoxContainer, kf: EventKeyframe, on_modified: Callable) -> void:
	# payload: {sfx_id: StringName}
	box.add_child(_label("sfx_id · 来自 SfxBindings.tres"))
	var ids: Array[StringName] = _load_sfx_ids()
	var current: String = String(kf.payload.get("sfx_id", ""))
	if ids.is_empty():
		# 兜底：让用户手输
		var le := LineEdit.new()
		le.text = current
		le.placeholder_text = "（SfxBindings 为空，手动输入）"
		le.text_changed.connect(func(s: String) -> void:
			kf.payload["sfx_id"] = StringName(s)
			_safe_call(on_modified)
		)
		box.add_child(le)
	else:
		var opt := OptionButton.new()
		var sel: int = 0
		for i in range(ids.size()):
			opt.add_item(String(ids[i]))
			if String(ids[i]) == current:
				sel = i
		# 若 current 不在列表里，追加一个保留项
		if current != "" and not _contains_string(ids, current):
			opt.add_item("%s  (missing)" % current)
			sel = opt.item_count - 1
		opt.select(sel)
		opt.item_selected.connect(func(i: int) -> void:
			var item_text: String = opt.get_item_text(i).split("  ")[0]
			kf.payload["sfx_id"] = StringName(item_text)
			_safe_call(on_modified)
		)
		box.add_child(opt)


static func _build_vfx_spawn(box: VBoxContainer, kf: EventKeyframe, on_modified: Callable) -> void:
	# payload: {vfx_scene_path: String, offset_3d: Vector3, lifetime: float}
	box.add_child(_label("vfx_scene_path · *.tscn"))
	var hb := HBoxContainer.new()
	var le := LineEdit.new()
	le.text = String(kf.payload.get("vfx_scene_path", ""))
	le.placeholder_text = "res://Content/VFX/xxx.tscn"
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(s: String) -> void:
		kf.payload["vfx_scene_path"] = s
		_safe_call(on_modified)
	)
	hb.add_child(le)
	var browse := Button.new()
	browse.text = "…"
	browse.tooltip_text = "选择 .tscn"
	browse.pressed.connect(func() -> void:
		_open_file_picker("*.tscn ; PackedScene", "res://Content/VFX",
			func(path: String) -> void:
				le.text = path
				kf.payload["vfx_scene_path"] = path
				_safe_call(on_modified))
	)
	hb.add_child(browse)
	box.add_child(hb)

	box.add_child(_label("offset_3d (x, y, z)"))
	var off: Vector3 = kf.payload.get("offset_3d", Vector3.ZERO)
	box.add_child(_vector3_edit(off, func(v: Vector3) -> void:
		kf.payload["offset_3d"] = v
		_safe_call(on_modified)))

	box.add_child(_label("lifetime (s)"))
	var sp := SpinBox.new()
	sp.min_value = 0.05
	sp.max_value = 30.0
	sp.step = 0.05
	sp.value = float(kf.payload.get("lifetime", 1.5))
	sp.value_changed.connect(func(v: float) -> void:
		kf.payload["lifetime"] = v
		_safe_call(on_modified)
	)
	box.add_child(sp)


static func _build_projectile_spawn(box: VBoxContainer, kf: EventKeyframe, on_modified: Callable) -> void:
	# payload: {projectile_id: StringName, direction: Vector3, speed: float}
	box.add_child(_label("projectile_id"))
	var le := LineEdit.new()
	le.text = String(kf.payload.get("projectile_id", ""))
	le.placeholder_text = "fireball"
	le.text_changed.connect(func(s: String) -> void:
		kf.payload["projectile_id"] = StringName(s)
		_safe_call(on_modified)
	)
	box.add_child(le)

	box.add_child(_label("direction (单位向量)"))
	var dir: Vector3 = kf.payload.get("direction", Vector3.RIGHT)
	box.add_child(_vector3_edit(dir, func(v: Vector3) -> void:
		kf.payload["direction"] = v
		_safe_call(on_modified)))

	box.add_child(_label("speed (units/s)"))
	var sp := SpinBox.new()
	sp.min_value = 0.0
	sp.max_value = 5000.0
	sp.step = 10.0
	sp.value = float(kf.payload.get("speed", 800.0))
	sp.value_changed.connect(func(v: float) -> void:
		kf.payload["speed"] = v
		_safe_call(on_modified)
	)
	box.add_child(sp)


static func _build_camera_shake(box: VBoxContainer, kf: EventKeyframe, on_modified: Callable) -> void:
	# payload: {intensity: float, duration: float}
	box.add_child(_label("intensity (px @ 2D · auto / 50 @ 3D)"))
	var sp1 := SpinBox.new()
	sp1.min_value = 0.0
	sp1.max_value = 100.0
	sp1.step = 0.5
	sp1.value = float(kf.payload.get("intensity", 4.0))
	sp1.value_changed.connect(func(v: float) -> void:
		kf.payload["intensity"] = v
		_safe_call(on_modified)
	)
	box.add_child(sp1)

	box.add_child(_label("duration (s)"))
	var sp2 := SpinBox.new()
	sp2.min_value = 0.01
	sp2.max_value = 5.0
	sp2.step = 0.01
	sp2.value = float(kf.payload.get("duration", 0.15))
	sp2.value_changed.connect(func(v: float) -> void:
		kf.payload["duration"] = v
		_safe_call(on_modified)
	)
	box.add_child(sp2)


static func _build_hit_stop(box: VBoxContainer, kf: EventKeyframe, on_modified: Callable) -> void:
	# payload: {duration_ms: float}
	box.add_child(_label("duration_ms"))
	var sp := SpinBox.new()
	sp.min_value = 0.0
	sp.max_value = 1000.0
	sp.step = 5.0
	sp.value = float(kf.payload.get("duration_ms", 80.0))
	sp.value_changed.connect(func(v: float) -> void:
		kf.payload["duration_ms"] = v
		_safe_call(on_modified)
	)
	box.add_child(sp)


static func _build_custom_signal(box: VBoxContainer, kf: EventKeyframe, on_modified: Callable) -> void:
	# payload: {signal_name: StringName, data: Dictionary}
	box.add_child(_label("signal_name"))
	var le := LineEdit.new()
	le.text = String(kf.payload.get("signal_name", ""))
	le.placeholder_text = "my_event"
	le.text_changed.connect(func(s: String) -> void:
		kf.payload["signal_name"] = StringName(s)
		_safe_call(on_modified)
	)
	box.add_child(le)

	box.add_child(_label("data (JSON)"))
	var te := TextEdit.new()
	te.text = JSON.stringify(kf.payload.get("data", {}), "  ")
	te.custom_minimum_size = Vector2(0, 100)
	te.text_changed.connect(func() -> void:
		var parsed: Variant = JSON.parse_string(te.text)
		if parsed is Dictionary:
			kf.payload["data"] = parsed
			_safe_call(on_modified)
	)
	box.add_child(te)


# ─────────────────────────────────────────────────────────────
# 公共控件辅助
# ─────────────────────────────────────────────────────────────

static func _vbox() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	return v


static func _label(s: String) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	return l


static func _section_title(s: String) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
	return l


static func _field_time(kf: SkillKeyframe, on_modified: Callable) -> Control:
	var box := _vbox()
	box.add_child(_label("time (s)"))
	var sp := SpinBox.new()
	sp.min_value = 0.0
	sp.max_value = 60.0
	sp.step = 0.01
	sp.value = kf.time
	sp.value_changed.connect(func(v: float) -> void:
		kf.time = v
		_safe_call(on_modified)
	)
	box.add_child(sp)
	return box


static func _vector3_edit(initial: Vector3, on_changed: Callable) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	var current := [initial]  # 借数组捕获引用
	for i in range(3):
		var idx: int = i
		var sp := SpinBox.new()
		sp.min_value = -10000.0
		sp.max_value = 10000.0
		sp.step = 0.1
		sp.value = (initial.x if i == 0 else (initial.y if i == 1 else initial.z))
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.value_changed.connect(func(v: float) -> void:
			var cur: Vector3 = current[0]
			match idx:
				0: cur.x = v
				1: cur.y = v
				2: cur.z = v
			current[0] = cur
			on_changed.call(cur)
		)
		hb.add_child(sp)
	return hb


static func _raw_json_edit(kf: EventKeyframe, on_modified: Callable) -> Control:
	var te := TextEdit.new()
	te.text = JSON.stringify(kf.payload, "  ")
	te.custom_minimum_size = Vector2(0, 110)
	te.text_changed.connect(func() -> void:
		var parsed: Variant = JSON.parse_string(te.text)
		if parsed is Dictionary:
			kf.payload = parsed
			_safe_call(on_modified)
	)
	return te


static func _open_file_picker(filter: String, dir: String, on_pick: Callable) -> void:
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray([filter])
	dlg.current_dir = dir
	dlg.file_selected.connect(func(path: String) -> void:
		on_pick.call(path)
		dlg.queue_free()
	)
	# 挂到 EditorInterface base control
	var ei := Engine.get_singleton(&"EditorInterface")
	if ei != null and ei.has_method(&"get_base_control"):
		ei.call(&"get_base_control").add_child(dlg)
	else:
		Engine.get_main_loop().root.add_child(dlg)
	dlg.popup_centered_ratio(0.6)


static func _load_sfx_ids() -> Array[StringName]:
	var res: Resource = load("res://Data/Config/SfxBindings.tres")
	if res is SfxBindings:
		return (res as SfxBindings).get_all_ids()
	return []


static func _contains_string(arr: Array[StringName], s: String) -> bool:
	for it in arr:
		if String(it) == s:
			return true
	return false


static func _safe_call(c: Callable) -> void:
	if c.is_valid():
		c.call()
