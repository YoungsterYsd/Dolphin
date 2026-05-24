## GameplayEffect 资源（Resource）。
##
## 三种效果类型：
##   - INSTANT：瞬发，立即应用 modifiers，结束后立即移除（granted_tags 不附加）
##   - DURATION：持续时长，期间附加 granted_tags，到期自动移除
##   - PERIODIC：每 period 秒应用一次 modifiers，持续 duration（duration<=0 视为永久，需手动移除）
##
## Tag 三类：
##   - granted_tags：DURATION/PERIODIC 期间附加到目标 ASC 的 tag（计数引用）
##   - application_required_tags：目标必须持有这些 tag 才能应用本 GE，否则跳过
##   - application_blocked_tags：目标持有任一这些 tag 则跳过应用
##   - removed_tags：应用本 GE 时强制移除目标的某些 tag（一次性）
class_name GameplayEffect
extends Resource

enum EffectType { INSTANT, DURATION, PERIODIC }

@export var effect_type: EffectType = EffectType.INSTANT

## 修饰器列表。INSTANT 立即应用一次；PERIODIC 每周期应用一次；DURATION 仅在应用与移除时不应用 modifiers（用 tag 表达持续状态）。
@export var modifiers: Array[AttributeModifier] = []

## 持续时长（秒）。INSTANT 忽略；DURATION 必须 >0；PERIODIC 若 <=0 视为永久。
@export var duration: float = 0.0

## 周期（秒）。仅 PERIODIC 使用，需 >0。
@export var period: float = 1.0

## 应用期间附加到目标 ASC 的 tag（DURATION/PERIODIC 生效；INSTANT 忽略）。
@export var granted_tags: Array[StringName] = []

## 目标必须持有这些 tag（按父匹配）才能应用。
@export var application_required_tags: Array[StringName] = []

## 目标持有任一这些 tag（按父匹配）则不应用。
@export var application_blocked_tags: Array[StringName] = []

## 应用时强制移除目标的这些 tag（按父匹配清除所有匹配，一次性）。
@export var removed_tags: Array[StringName] = []

## DURATION/PERIODIC 效果存活期间触发的"持续 cue"。
##
## 由 [AbilitySystemComponent] 在 [code]_attach_active[/code] 时通过 [code]GameInstance.cue_manager.add_active_cue[/code]
## 启动；在 [code]_detach_active[/code] 时通过 [code]remove_active_cue[/code] 停止。
## 例：[code]GE_Burning_3s.cue_tags_while_active = [&"Cue.Buff.Burning.Active"][/code]
##
## 注：本字段仅 DURATION/PERIODIC 生效；INSTANT 类型应在 DamagePipeline 第 13 步直接调
## [code]execute_cue(&"Cue.Damage...")[/code]，不通过本字段。
@export var cue_tags_while_active: Array[StringName] = []

## 调试名（用于日志）。可选。
@export var display_name: String = ""


func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	if resource_path.is_empty():
		return "<inline GE>"
	return resource_path.get_file().get_basename()
