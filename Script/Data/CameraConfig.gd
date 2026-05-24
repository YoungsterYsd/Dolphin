## 相机配置。
##
## 俯视角 3D 相机参数集中存放（R-DATA-02）。
## CameraRig._ready 启动时从 ConfigCenter.get_camera_config() 取值；改 .tres 立即生效。
class_name CameraConfig
extends Resource

## 俯角（度）。负值看向地面（八方旅人风格 ≈ -55°）。
@export_range(-90.0, 0.0, 1.0) var pitch_deg: float = -55.0

## 相机距离（SpringArm3D length，米）。
@export_range(1.0, 30.0, 0.5) var distance: float = 8.0

## 视场角（度）。
@export_range(20.0, 100.0, 1.0) var fov_deg: float = 45.0

## 跟随平滑度（越大越跟手；0=瞬移）。
@export_range(0.0, 30.0, 0.1) var follow_smoothing: float = 8.0

## Shake 强度倍数（默认 1.0；调大可放大所有 shake 事件）。
@export_range(0.0, 5.0, 0.1) var shake_intensity_multiplier: float = 1.0

## Y 轴相机偏移（看向 target.position + Vector3(0, target_y_offset, 0)）。
@export var target_y_offset: float = 0.5

## 是否启用正交相机（true 时距离/角度仍生效，但用 ProjectionMode.ORTHOGONAL；HD-2D 风更扁平）。
@export var use_orthogonal: bool = false

## 正交模式 size（仅 use_orthogonal=true 时生效）。
@export_range(1.0, 30.0, 0.5) var orthogonal_size: float = 10.0
