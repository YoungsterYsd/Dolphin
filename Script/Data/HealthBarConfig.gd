## 血条系统配置（M8 引入）。
##
## 头顶血条 + Boss 分层血条参数。
class_name HealthBarConfig
extends Resource

# === Boss 分层血条 ===
@export var boss_layer_step: int = 500
@export var boss_ghost_chase_delay: float = 0.3
@export var boss_ghost_chase_speed: float = 200.0  # HP/秒
@export var boss_main_color: Color = Color(0.85, 0.20, 0.20)
@export var boss_ghost_color: Color = Color(0.95, 0.85, 0.30)

# === 头顶血条 ===
@export var overhead_show_distance: float = 600.0  # 2D 像素 / 3D 米（在 OverheadHealthBarManager 内按场景适配）
@export var overhead_y_offset: float = -40.0  # 屏幕上 enemy 位置上方多少像素绘制
@export var overhead_bar_size: Vector2 = Vector2(48, 6)
@export var overhead_bg_color: Color = Color(0.05, 0.05, 0.05, 0.7)
@export var overhead_fill_color: Color = Color(0.85, 0.25, 0.25, 0.95)
@export var overhead_fill_color_elite: Color = Color(0.95, 0.55, 0.20, 0.95)
@export var overhead_auto_hide_when_full_seconds: float = 3.0  # 满血时多久后自动隐藏（0=始终显示）
