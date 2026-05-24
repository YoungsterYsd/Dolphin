## 后处理配置。
##
## DOF（景深） + SSAO + Bloom 等后处理参数。
## 由 LightingManager（或 TestArena 内 WorldEnvironment）启动时应用。
class_name PostProcessConfig
extends Resource

# === DOF（景深） ===
@export var dof_far_enabled: bool = true
@export_range(0.0, 100.0, 0.5) var dof_far_distance: float = 15.0
@export_range(0.0, 50.0, 0.5) var dof_far_transition: float = 5.0
@export_range(0.0, 1.0, 0.01) var dof_far_amount: float = 0.15

@export var dof_near_enabled: bool = false
@export_range(0.0, 50.0, 0.5) var dof_near_distance: float = 2.0
@export_range(0.0, 0.5, 0.01) var dof_near_amount: float = 0.0

# === SSAO ===
@export var ssao_enabled: bool = true
@export_range(0.0, 8.0, 0.1) var ssao_intensity: float = 2.0
@export_range(0.1, 8.0, 0.1) var ssao_radius: float = 1.5
@export_range(0.0, 1.0, 0.01) var ssao_power: float = 0.6

# === Bloom（Glow） ===
@export var bloom_enabled: bool = true
@export_range(0.0, 4.0, 0.05) var bloom_intensity: float = 0.3
@export_range(0.0, 4.0, 0.05) var bloom_threshold: float = 0.8
@export_range(0.0, 4.0, 0.05) var bloom_strength: float = 1.0

# === Tonemap ===
@export var tonemap_mode: int = 2  # 0=Linear, 1=Reinhardt, 2=Filmic, 3=ACES
@export_range(0.0, 16.0, 0.05) var tonemap_exposure: float = 1.0
@export_range(0.0, 4.0, 0.05) var tonemap_white: float = 1.0
