## 输入上下文（Resource）。
##
## 描述「在某个 HUD 状态下，哪些 InputMap action 是允许的、哪些是禁止的」。
## 由 [InputContextManager] 维护栈结构，[InputController] 在 emit 信号前查询本资源。
##
## 用法（数据层）：
##   每份 .tres 描述一个上下文，例如：
##     - Gameplay：默认上下文，全部允许（allow_all=true）
##     - PanelOpen：仅 UI 导航与确认/取消，屏蔽所有 combat_*
##     - Modal：在 PanelOpen 基础上仅允许 confirm/cancel（inherit_from=PanelOpen，extra_allow=[confirm,cancel]）
##
## 解析顺序（[is_action_allowed] 的判定逻辑）：
##   1) 若 [member explicit_blocked] 命中 → 禁止（最高优先级）
##   2) 若 [member allow_all] = true → 允许
##   3) 若 [member explicit_allowed] 命中 → 允许
##   4) 若 [member inherit_from] 非空 → 递归询问父级
##   5) 否则 → 禁止（默认 deny）
##
## 命名（R-NAME-01）：context_id 使用 PascalCase（如 &"Gameplay" / &"PanelOpen"）。
class_name InputContext
extends Resource

## 上下文标识。每份 .tres 必填，且全局唯一。
@export var context_id: StringName = &""

## 直接允许的 action 列表（白名单）。
@export var explicit_allowed: Array[StringName] = []

## 直接禁止的 action 列表（黑名单，优先级最高）。
@export var explicit_blocked: Array[StringName] = []

## 若为 true，未在黑名单的 action 全部允许（用于 Gameplay 默认上下文）。
@export var allow_all: bool = false

## 父上下文。若本上下文未声明某 action，则向上回溯。
## 注意：避免循环引用（Manager 加载时会做一次自检）。
@export var inherit_from: InputContext = null

## 调试用显示名（不影响逻辑）。
@export var display_name: String = ""


## 查询：本上下文下指定 action 是否允许。
func is_action_allowed(action: StringName) -> bool:
	# 1) 显式黑名单优先
	if explicit_blocked.has(action):
		return false
	# 2) allow_all
	if allow_all:
		return true
	# 3) 显式白名单
	if explicit_allowed.has(action):
		return true
	# 4) 父上下文
	if inherit_from != null:
		return inherit_from.is_action_allowed(action)
	# 5) 默认禁止
	return false


## 调试输出（递归收集本上下文与所有父级的允许/禁止集合）。
func describe() -> String:
	var lines: Array[String] = []
	lines.append("[InputContext %s]" % context_id)
	lines.append("  allow_all = %s" % allow_all)
	lines.append("  allowed = %s" % str(explicit_allowed))
	lines.append("  blocked = %s" % str(explicit_blocked))
	if inherit_from != null:
		lines.append("  inherit_from = %s" % inherit_from.context_id)
	return "\n".join(lines)
