## 受击屏幕边缘红色脉冲。
##
## 订阅 [signal EventBus.damage_dealt_v2]：当 target 在 "player" group 时触发。
##   - 内部为 [ColorRect]（全屏红色，初始 a=0），用 modulate.a 做脉冲
##   - 受击时 a 从 0 → peak → 0（脉冲）
##   - 重叠受击时取消旧 tween，按当前峰值重新脉冲
##
## 注：当前用纯色全屏（视觉为整屏微红闪），后期接入 vignette 纹理时把根节点
##     换成 [TextureRect] + 带 alpha 通道的 vignette 图即可，本脚本无需改动。
##
## 因不依赖业务类，仅靠 group "player" 判定（R-HUD-02）。
class_name HitVignetteWidget
extends BaseWidget

## 脉冲峰值透明度。
@export var peak_alpha: float = 0.35

## 脉冲单次时长。
@export var pulse_seconds: float = 0.45

## 暴击额外加成倍数（is_crit=true 时 peak_alpha *= 此值）。
@export var crit_boost: float = 1.4


@onready var rect: CanvasItem = $Vignette

var _tween: Tween = null


func _ready() -> void:
	super._ready()
	rect.modulate.a = 0.0
	EventBus.damage_dealt_v2.connect(_on_damage_dealt)


func _on_damage_dealt(_source: Node, target: Node, _amount: float, _damage_node: Resource, is_crit: bool) -> void:
	if target == null or not target.is_in_group(&"player"):
		return
	var peak: float = peak_alpha * (crit_boost if is_crit else 1.0)
	peak = clampf(peak, 0.0, 1.0)
	# 取消旧 tween 重新脉冲
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(rect, ^"modulate:a", peak, pulse_seconds * 0.3)
	_tween.tween_property(rect, ^"modulate:a", 0.0, pulse_seconds * 0.7)
