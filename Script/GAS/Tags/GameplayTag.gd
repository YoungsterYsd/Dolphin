## GameplayTag 静态工具类。
##
## Tag 用 [StringName] 表示，层级用 [code].[/code] 分隔，例如：
##   - [code]state.buff.haste[/code]
##   - [code]ability.skill.fireball[/code]
##   - [code]damage.type.fire[/code]
##
## 父子匹配：[code]matches("state.buff.haste", "state.buff")[/code] → true
class_name GameplayTag
extends RefCounted


## child 是否匹配 parent（child 自身或其任一祖先 == parent）。
## 严格 exact 比对请直接用 [code]a == b[/code]。
##
## 示例：
##   [code]matches(&"state.buff.haste", &"state.buff")[/code] → true
##   [code]matches(&"state.buff", &"state.buff.haste")[/code] → false
##   [code]matches(&"state.buff", &"state.buff")[/code] → true
static func matches(child: StringName, parent: StringName) -> bool:
	if child == parent:
		return true
	var c := String(child)
	var p := String(parent)
	# child 必须以 parent + "." 开头
	return c.begins_with(p + ".")


## 取父 tag。无父则返回 [code]&""[/code]。
##
## 示例：[code]get_parent(&"state.buff.haste")[/code] → [code]&"state.buff"[/code]
static func get_parent_tag(tag: StringName) -> StringName:
	var s := String(tag)
	var idx := s.rfind(".")
	if idx < 0:
		return &""
	return StringName(s.substr(0, idx))


## 切分为段。
##
## 示例：[code]split(&"state.buff.haste")[/code] → [code]["state","buff","haste"][/code]
static func split(tag: StringName) -> PackedStringArray:
	return String(tag).split(".")


## 是否为合法 tag 格式（小写字母/数字/下划线，按 [code].[/code] 分段，至少一段）。
static func is_valid_format(tag: StringName) -> bool:
	var s := String(tag)
	if s.is_empty():
		return false
	var regex := RegEx.new()
	regex.compile("^[a-z0-9_]+(\\.[a-z0-9_]+)*$")
	return regex.search(s) != null
