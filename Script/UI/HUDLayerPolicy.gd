## HUD 层级策略（Resource）。
##
## 描述一层 HUD（CanvasLayer 维度）的可见性 / 输入策略 / 暂停策略 / 栈管理 / 入退场动画。
## 由 [HUDManager] 加载并应用到对应 CanvasLayer。
##
## 一份 .tres 描述一个层；项目共 8 份（L0~L7）。
##
## 策划案对应：05 文档 §3.1 单层规则 + 8 层定义。
class_name HUDLayerPolicy
extends Resource

## 输入策略枚举（与 [BaseWidget.InputMode] 对齐）。
enum InputMode { PASS, ABSORB, BLOCK }

## 暂停策略枚举（与 [BaseWidget.PausePolicy] 对齐）。
enum PausePolicy { INHERIT, ALWAYS, PAUSABLE, WHEN_PAUSED }


# ─────────────────────────────────────────────────────────────
# 字段
# ─────────────────────────────────────────────────────────────

## 层 id。建议 L0_World / L1_Game / L2_GameMenu / L3_Menu / L4_Modal / L5_Notification / L6_Loading / L7_Debug。
@export var layer_id: StringName = &""

## 调试 / 编辑器显示用。
@export var display_name: String = ""

## CanvasLayer 的 layer 字段。Z 越大越靠前。L0=0 / L1=1 / ... / L7=99。
@export var canvas_layer_index: int = 1

## 默认是否可见。
@export var visible_default: bool = true

## 输入策略。
@export var input_mode: InputMode = InputMode.PASS

## 暂停策略。
@export var pause_policy: PausePolicy = PausePolicy.PAUSABLE

## 是否启用栈管理（仅 L2 / L3 / L4 建议开）。
@export var enable_stack: bool = false

## 栈最大深度（0 = 不限制）。
@export var max_stack_size: int = 0

## 层级整体入场时长档（XS / S / M / L 等，由 UIDurations 解析；空字符串 = 不播）。
@export var fade_in_tag: StringName = &""

## 层级整体退场时长档。
@export var fade_out_tag: StringName = &""

## 仅 L0 World HUD 设 true（CanvasLayer.follow_viewport_enabled）。
@export var follow_camera: bool = false

## 仅 L7 Debug 设 true（非调试构建自动隐藏）。
@export var debug_only: bool = false
