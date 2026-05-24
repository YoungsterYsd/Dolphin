## 命中反馈配置。
##
## 集中存放战斗手感参数，符合 R-DATA-02（数据驱动优先）。
## ConfigCenter.get_hit_feedback_config() 提供访问；改 tres 立即生效（reload_all）。
class_name HitFeedbackConfig
extends Resource

# === 屏幕震动 ===
@export var default_camera_shake_intensity: float = 4.0
@export var default_camera_shake_duration: float = 0.15
@export var default_camera_shake_frequency: float = 30.0

# === 冻帧 ===
@export var default_hit_stop_ms: float = 80.0

# === 闪白 ===
@export var default_flash_color: Color = Color.WHITE
@export var default_flash_duration: float = 0.08

# === Camera Zoom Punch ===
@export var default_zoom_punch_scale: float = 0.92  # 主动缩到该 zoom，再回 1.0
@export var default_zoom_punch_duration: float = 0.12

# === 伤害飘字 ===
@export var damage_popup_normal_color: Color = Color.WHITE
@export var damage_popup_crit_color: Color = Color(1.0, 0.55, 0.2)
@export var damage_popup_heal_color: Color = Color(0.4, 0.95, 0.45)
## 普通格挡灰色（dmg ×block_damage_reduction 减伤后落地）。
@export var damage_popup_block_color: Color = Color(0.7, 0.7, 0.7)
## 完美格挡银色（不显数值，显"完美格挡"文字）。
@export var damage_popup_perfect_block_color: Color = Color(0.85, 0.9, 1.0)
@export var damage_popup_font_size: int = 18
@export var damage_popup_crit_font_size: int = 26
@export var damage_popup_drift_distance: float = 40.0  # 向上飘多少像素
@export var damage_popup_horizontal_jitter: float = 16.0  # 左右随机偏移
@export var damage_popup_lifetime: float = 0.6
@export var damage_popup_pool_initial_size: int = 20
