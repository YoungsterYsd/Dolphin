## 全局 GameplayTag 注册表（Resource）。
##
## 单例资源，启动时由 [GameInstance] 加载 [code]res://Data/Tags/GameplayTags.tres[/code]。
## 业务代码使用未注册 tag 时由 [GameLogger] 报 warning（宽松模式，参见 R-GAS-01）。
class_name GameplayTagRegistry
extends Resource

## 已注册的 tag 列表（编辑器可编辑）。
@export var tags: Array[StringName] = []


## 是否已注册某 tag（精确匹配）。
func is_registered(tag: StringName) -> bool:
	return tag in tags


## 取所有已注册 tag 的副本。
func get_all() -> Array[StringName]:
	return tags.duplicate()


## 取某 parent 的全部直接/间接子 tag（含自身可选）。
func get_children(parent: StringName, include_self: bool = false) -> Array[StringName]:
	var result: Array[StringName] = []
	for t in tags:
		if t == parent:
			if include_self:
				result.append(t)
		elif GameplayTag.matches(t, parent):
			result.append(t)
	return result


## 校验入参 tag，未注册时打 warning（不中断）。
## 返回 tag 是否合法（已注册）。
func validate(tag: StringName, context: String = "") -> bool:
	if is_registered(tag):
		return true
	var ctx := " (%s)" % context if not context.is_empty() else ""
	GameLogger.warn("GAS", "tag not registered: %s%s" % [tag, ctx])
	return false
