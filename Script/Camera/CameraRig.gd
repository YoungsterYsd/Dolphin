## 相机跟随 + Shake + ZoomPunch（3D 俯视角）。
##
## 节点结构（自动构建，无需手动放置）：
##   CameraRig (Node3D)
##     └─ SpringArm3D（rotation.x = pitch；spring_length = distance；shape 用作碰撞）
##           └─ Camera3D（current=true，fov 来自 CameraConfig）
##
## R-CHAR-01：保留对外 API `shake / zoom_punch`，与 2D 期签名一致；
##   2D 期 zoom 概念在 3D 期改为 "fov 收缩"（zoom_punch 主动缩 fov 再恢复）。
##
## R-DATA-02：所有相机参数走 CameraConfig.tres，运行期改值需要 reload_from_config()。
class_name CameraRig
extends Node3D

## 跟随目标（Node3D）。
@export var target: Node3D = null

# 子节点（_ready 时构建）
var _spring_arm: SpringArm3D = null
var _camera: Camera3D = null

# 配置
var _cfg: CameraConfig = null

# Shake 状态
var _shake_remaining: float = 0.0
var _shake_total: float = 0.0
var _shake_intensity: float = 0.0
var _shake_frequency: float = 30.0
var _shake_resample_timer: float = 0.0

# Zoom punch 状态
var _zoom_punch_tween: Tween = null
var _fov_base: float = 45.0


func _ready() -> void:
	_pull_config()
	_build_3d_camera()
	# 初始位置贴 target
	if target != null:
		global_position = _target_world_pos()
	# 订阅技能轨发出的 camera shake 请求
	EventBus.skill_event_camera_shake.connect(_on_skill_event_camera_shake)


func _physics_process(delta: float) -> void:
	# 跟随
	if target != null and _cfg != null:
		var t_pos: Vector3 = _target_world_pos()
		var smooth: float = clampf(_cfg.follow_smoothing * delta, 0.0, 1.0)
		# 平滑度 0 时直接跟，否则 lerp
		if _cfg.follow_smoothing <= 0.0:
			global_position = t_pos
		else:
			global_position = global_position.lerp(t_pos, smooth)

	# Shake：按时间衰减 + 按 frequency 重采样
	if _shake_remaining > 0.0:
		_shake_remaining -= delta
		_shake_resample_timer -= delta
		if _shake_resample_timer <= 0.0 and _spring_arm != null:
			var t_ratio: float = 1.0 if _shake_total <= 0.0 else clampf(_shake_remaining / _shake_total, 0.0, 1.0)
			var amp: float = _shake_intensity * t_ratio * 0.02  # 单位换算：2D 期是像素，3D 期是米；除以 50 量纲
			# 摄像机在 SpringArm3D 上抖动 X/Y（屏幕空间近似）
			_spring_arm.position = Vector3(
				randf_range(-amp, amp),
				randf_range(-amp, amp),
				0.0,
			)
			_shake_resample_timer = 1.0 / maxf(_shake_frequency, 1.0)
		if _shake_remaining <= 0.0:
			if _spring_arm != null:
				_spring_arm.position = Vector3.ZERO


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

func shake(intensity: float, duration: float, frequency: float = 30.0) -> void:
	# 应用配置中的强度倍数
	var mul: float = _cfg.shake_intensity_multiplier if _cfg != null else 1.0
	if intensity * mul > _shake_intensity or duration > _shake_remaining:
		_shake_intensity = maxf(_shake_intensity, intensity * mul)
		_shake_remaining = maxf(_shake_remaining, duration)
		_shake_total = _shake_remaining
		_shake_frequency = frequency
		_shake_resample_timer = 0.0


## 3D 期 zoom punch 改为 fov 收缩 → 命中放大效果（fov 减小相当于变焦推近）。
## scale < 1.0 → fov 缩小到 base * scale，duration 后回 base。
func zoom_punch(scale: float, duration: float) -> void:
	if _camera == null:
		return
	if _zoom_punch_tween != null and _zoom_punch_tween.is_valid():
		_zoom_punch_tween.kill()
	var target_fov: float = _fov_base * scale
	_zoom_punch_tween = create_tween()
	_zoom_punch_tween.tween_property(_camera, "fov", target_fov, duration * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_zoom_punch_tween.tween_property(_camera, "fov", _fov_base, duration * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 从 ConfigCenter 重新加载相机参数（运行时调试用）。
func reload_from_config() -> void:
	_pull_config()
	_apply_config_to_camera()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _pull_config() -> void:
	# R-Core：ConfigCenter 走 class_name 强类型直访
	_cfg = ConfigCenter.get_camera_config()


func _build_3d_camera() -> void:
	_spring_arm = SpringArm3D.new()
	_spring_arm.name = "SpringArm3D"
	_spring_arm.collision_mask = 0  # 默认不碰撞墙壁；项目需要墙体推近时再开
	add_child(_spring_arm)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	_spring_arm.add_child(_camera)
	# 应用配置
	_apply_config_to_camera()


func _apply_config_to_camera() -> void:
	if _spring_arm == null or _camera == null or _cfg == null:
		return
	# pitch 在 SpringArm3D 上：rotation_degrees.x = pitch（向下俯视为负）
	_spring_arm.rotation_degrees = Vector3(_cfg.pitch_deg, 0.0, 0.0)
	_spring_arm.spring_length = _cfg.distance
	# fov 在 Camera3D
	_camera.fov = _cfg.fov_deg
	_fov_base = _cfg.fov_deg
	# 正交模式
	if _cfg.use_orthogonal:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = _cfg.orthogonal_size
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE


func _target_world_pos() -> Vector3:
	if target == null:
		return global_position
	return target.global_position + Vector3(0.0, _cfg.target_y_offset if _cfg != null else 0.5, 0.0)


# 信号回调
func _on_skill_event_camera_shake(intensity: float, duration: float, _caster: Node) -> void:
	# R-Core：ConfigCenter 走 class_name 强类型直访
	var freq: float = ConfigCenter.get_hit_feedback_config().default_camera_shake_frequency
	shake(intensity, duration, freq)
