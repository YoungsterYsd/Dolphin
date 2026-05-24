## 对话系统配置（Resource）。
##
## 落库到 `Data/Manual/Config/DialogueConfig.tres`，由 DialogueWidget / DialogueRunner 读取。
## 所有视觉数值 / 时长全部走本资源；不在 .gd 硬编码（R-DLG-01）。
class_name DialogueConfig
extends Resource

## 打字机速度（字符/秒）。≤0 时关闭打字机效果，文本一次性显示。
@export var typewriter_chars_per_second: float = 40.0

## 无选项的 SpeechNode 在多少秒后自动 advance。≤0 表示不自动推进。
@export var auto_advance_after_seconds: float = -1.0

## 默认肖像 path（PortraitsConfig 找不到时兜底；空字符串 → 显示纯色占位）。
@export var default_portrait_path: String = ""

## 入场 / 退场动画时长档位（XS/S/M/L），需在 UIDurations 中有定义。
@export var enter_duration_tier: StringName = &"S"
@export var exit_duration_tier: StringName = &"S"

## 是否允许 cancel 键中断对话（部分剧情对话禁用）。
@export var allow_cancel: bool = true
