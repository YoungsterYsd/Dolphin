## 光照配置。
##
## 主光 + 环境光 + 雾，参数全部走配置（R-DATA-02）。
class_name LightingConfig
extends Resource

# === DirectionalLight3D ===
@export var main_light_color: Color = Color(1.0, 0.95, 0.85)
@export_range(0.0, 16.0, 0.1) var main_light_energy: float = 1.2
## 主光朝向：欧拉角（度），默认 -45° pitch + 30° yaw 模拟黄昏
@export var main_light_rotation_deg: Vector3 = Vector3(-45.0, 30.0, 0.0)
@export var shadow_enabled: bool = true

# === Environment 环境光 ===
@export var ambient_color: Color = Color(0.5, 0.55, 0.65)
@export_range(0.0, 4.0, 0.05) var ambient_energy: float = 0.3
@export var sky_horizon_color: Color = Color(0.6, 0.65, 0.75)
@export var sky_top_color: Color = Color(0.4, 0.5, 0.7)

# === Fog ===
@export var fog_enabled: bool = true
@export_range(0.0, 0.05, 0.001) var fog_density: float = 0.005
@export var fog_light_color: Color = Color(0.7, 0.8, 0.9)
