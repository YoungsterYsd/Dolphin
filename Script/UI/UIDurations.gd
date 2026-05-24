## UI 动画时长档（Resource）。
##
## 策划案规定 4 档时长（XS / S / M / L），具体毫秒由本资源决定，
## 所有 HUD widget 的入场 / 退场 / 数值变化 / 状态变化 / 强调 动画时长必须取自本表，
## 禁止硬编码毫秒数（R-HUD-03）。
##
## 用法：
##   var d := UIDurations.get_seconds(&"S")  # 0.18
##   tween.tween_property(self, "modulate:a", 1.0, d)
##
## 数值挂起原则：当前给出业界常见缺省值；项目落地后通过 Tween 试验调整。
## 「减少动画」开关开启后，[method get_seconds] 返回 0.0（动画即时完成）。
class_name UIDurations
extends Resource

# ─────────────────────────────────────────────────────────────
# 时长档（毫秒）。修改本资源后所有 HUD 动画自动跟随。
# ─────────────────────────────────────────────────────────────

@export_range(0, 1000, 1, "suffix:ms") var xs_ms: int = 80   ## 极小元素：状态切换、按钮 hover/pressed。
@export_range(0, 1000, 1, "suffix:ms") var s_ms:  int = 180  ## 小元素：Toast 淡入、按钮反馈、单 widget 入场。
@export_range(0, 1000, 1, "suffix:ms") var m_ms:  int = 320  ## 中等：面板淡入、数值变化插值、双层条追赶。
@export_range(0, 1000, 1, "suffix:ms") var l_ms:  int = 600  ## 大元素：章节卡、Boss 出场、全屏过渡。

## 「退场动画时长 = 入场 × 该系数」（策划案 §5.1 规则）。
@export_range(0.1, 1.0, 0.05) var exit_ratio: float = 0.7

## 「减少动画」开关：开启后所有 [method get_seconds] 返回 0。
## 与 SettingsManager 的 hud/reduce_motion 项绑定。
@export var reduce_motion: bool = false


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 按档名取秒数。tag 接受 &"XS" / &"S" / &"M" / &"L"（大小写不敏感），其他值回退到 S。
func get_seconds(tag: StringName) -> float:
	if reduce_motion:
		return 0.0
	var key: String = String(tag).to_upper()
	match key:
		"XS": return xs_ms / 1000.0
		"S":  return s_ms / 1000.0
		"M":  return m_ms / 1000.0
		"L":  return l_ms / 1000.0
		_:    return s_ms / 1000.0


## 按档名取退场秒数（= 入场 × exit_ratio）。
func get_exit_seconds(tag: StringName) -> float:
	if reduce_motion:
		return 0.0
	return get_seconds(tag) * exit_ratio


## 直接取毫秒（供日志 / Debug 层显示）。
func get_ms(tag: StringName) -> int:
	if reduce_motion:
		return 0
	var key: String = String(tag).to_upper()
	match key:
		"XS": return xs_ms
		"S":  return s_ms
		"M":  return m_ms
		"L":  return l_ms
		_:    return s_ms
