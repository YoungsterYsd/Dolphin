## UI 颜色 token 集（Resource）。
##
## 集中管理 HUD 所有「语义化颜色」，避免每个 widget 硬编码 Color(1,0,0)。
## 加新颜色 → 改本资源 .tres 即可全局生效（R-HUD-03 / R-DATA-02）。
##
## 与 [HealthBarConfig] / [HitFeedbackConfig] 的分工：
##   - HealthBarConfig / HitFeedbackConfig 管「特定模块的视觉参数」（血条尺寸、popup 字号等）
##   - UIColorTokens 管「跨模块共用的语义颜色」（暴击红 / 治疗绿 / 警告黄）
##
## Phase 2：仅定义最小集，挂起具体颜色值；Phase 3 各 widget 接入时按需扩展。
class_name UIColorTokens
extends Resource

# ─────────────────────────────────────────────────────────────
# 战斗
# ─────────────────────────────────────────────────────────────

@export var damage_normal: Color = Color(1.0, 0.95, 0.6)
@export var damage_crit: Color = Color(1.0, 0.5, 0.2)
@export var damage_heal: Color = Color(0.3, 1.0, 0.4)
@export var damage_miss: Color = Color(0.7, 0.7, 0.7)

# ─────────────────────────────────────────────────────────────
# 属性条
# ─────────────────────────────────────────────────────────────

@export var hp_bar_fill: Color = Color(0.85, 0.15, 0.15)
@export var hp_bar_low: Color = Color(1.0, 0.3, 0.0)        # 低血警告
@export var mp_bar_fill: Color = Color(0.25, 0.45, 0.95)
@export var xp_bar_fill: Color = Color(1.0, 0.85, 0.2)

# ─────────────────────────────────────────────────────────────
# 状态
# ─────────────────────────────────────────────────────────────

@export var buff_positive: Color = Color(0.3, 0.9, 0.4)
@export var buff_negative: Color = Color(0.9, 0.3, 0.3)
@export var warning: Color = Color(1.0, 0.7, 0.0)
@export var danger: Color = Color(1.0, 0.1, 0.1)

# ─────────────────────────────────────────────────────────────
# UI 基础
# ─────────────────────────────────────────────────────────────

@export var ui_text_primary: Color = Color(1.0, 1.0, 1.0)
@export var ui_text_secondary: Color = Color(0.75, 0.75, 0.75)
@export var ui_text_disabled: Color = Color(0.5, 0.5, 0.5)
@export var ui_panel_bg: Color = Color(0.1, 0.1, 0.1, 0.85)
@export var ui_panel_border: Color = Color(0.3, 0.3, 0.3, 1.0)
@export var ui_focus_outline: Color = Color(1.0, 0.85, 0.2)
