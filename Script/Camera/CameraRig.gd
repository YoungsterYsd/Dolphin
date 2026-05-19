## 相机跟随 + Shake + ZoomPunch（2D 版）。
##
## 用法：放到玩家附近，[code]target[/code] 拖入要跟随的节点；M3 直接挂在玩家场景内。
## R-CHAR-01：3D 版未来作为子类（继承本类抽象基类形式）扩展。
##
## M8 升级：
##   - shake() 支持 frequency 参数（每秒重采样次数）
##   - 新增 zoom_punch(scale, duration)：相机 zoom 主动缩到指定比例再回弹，用于命中重打击感
class_name CameraRig
extends Camera2D

## 跟随目标（可在 Inspector 拖入；为空则不跟随）。
@export var target: Node2D = null

## 跟随平滑度（越大越跟手）。
@export var follow_speed: float = 8.0

## 缩放（统一 zoom）。
@export var camera_zoom: float = 2.0


# Shake 状态
var _shake_remaining: float = 0.0
var _shake_total: float = 0.0  # M8：用于按时间衰减
var _shake_intensity: float = 0.0
var _shake_frequency: float = 30.0  # M8：每秒重采样次数
var _shake_offset: Vector2 = Vector2.ZERO
var _shake_resample_timer: float = 0.0

# Zoom punch 状态（M8）
var _zoom_punch_tween: Tween = null
var _zoom_base: Vector2 = Vector2.ONE


func _ready() -> void:
	zoom = Vector2(camera_zoom, camera_zoom)
	_zoom_base = zoom
	if target != null:
		global_position = target.global_position
	# M7：订阅技能轨发出的 camera shake 请求
	EventBus.skill_event_camera_shake.connect(_on_skill_event_camera_shake)


func _physics_process(delta: float) -> void:
	# 跟随
	if target != null:
		global_position = global_position.lerp(target.global_position, clampf(follow_speed * delta, 0.0, 1.0))

	# Shake（M8：按时间衰减 + 按 frequency 重采样）
	if _shake_remaining > 0.0:
		_shake_remaining -= delta
		_shake_resample_timer -= delta
		if _shake_resample_timer <= 0.0:
			var t_ratio: float = 1.0 if _shake_total <= 0.0 else clampf(_shake_remaining / _shake_total, 0.0, 1.0)
			var amp: float = _shake_intensity * t_ratio  # 越接近结束越弱
			_shake_offset = Vector2(
				randf_range(-amp, amp),
				randf_range(-amp, amp),
			)
			offset = _shake_offset
			_shake_resample_timer = 1.0 / maxf(_shake_frequency, 1.0)
		if _shake_remaining <= 0.0:
			offset = Vector2.ZERO
			_shake_offset = Vector2.ZERO


## 触发屏幕震动。
## intensity：抖动幅度（像素）
## duration：持续时间（秒）
## frequency：每秒重采样次数（M8 新增，默认 30 Hz）
func shake(intensity: float, duration: float, frequency: float = 30.0) -> void:
	if intensity > _shake_intensity or duration > _shake_remaining:
		_shake_intensity = maxf(_shake_intensity, intensity)
		_shake_remaining = maxf(_shake_remaining, duration)
		_shake_total = _shake_remaining
		_shake_frequency = frequency
		_shake_resample_timer = 0.0


## M8：相机 zoom 缩到 base * scale，duration 后回到 base（命中重打击感）。
## scale < 1.0 时画面"被打中"放大效果；> 1.0 时拉远。
func zoom_punch(scale: float, duration: float) -> void:
	if _zoom_punch_tween != null and _zoom_punch_tween.is_valid():
		_zoom_punch_tween.kill()
	# 主动缩放
	var target_zoom: Vector2 = _zoom_base * scale
	_zoom_punch_tween = create_tween()
	_zoom_punch_tween.tween_property(self, "zoom", target_zoom, duration * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_zoom_punch_tween.tween_property(self, "zoom", _zoom_base, duration * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# 信号回调：把 EventBus 的 camera_shake 请求路由到 shake()
func _on_skill_event_camera_shake(intensity: float, duration: float, _caster: Node) -> void:
	# 从 ConfigCenter 取默认 frequency
	var freq: float = 30.0
	var cfg_node: Node = get_tree().root.get_node_or_null(^"ConfigCenter")
	if cfg_node != null:
		var hit_cfg = cfg_node.get_hit_feedback_config()
		if hit_cfg != null:
			freq = hit_cfg.default_camera_shake_frequency
	shake(intensity, duration, freq)
