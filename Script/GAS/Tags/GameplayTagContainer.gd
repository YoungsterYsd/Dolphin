## GameplayTag 运行时容器（计数引用）。
##
## 设计要点：
##   - 计数引用：同一 tag 多次 add_tag 计数 +1，remove_tag 计数 -1，归零才真正移除。
##   - 父子匹配：has_tag 默认走父匹配；exact=true 时走精确匹配。
##   - 信号：tag_added / tag_removed 仅在"真正添加（0→1）"或"真正移除（1→0）"时发出。
##
## 注：本类是普通 RefCounted，由 AbilitySystemComponent 持有。
class_name GameplayTagContainer
extends RefCounted

signal tag_added(tag: StringName)
signal tag_removed(tag: StringName)

var _counts: Dictionary = {}


## 添加一个 tag，引用计数 +1。返回是否触发"真正添加"（0→1）。
func add_tag(tag: StringName) -> bool:
	var prev: int = _counts.get(tag, 0)
	_counts[tag] = prev + 1
	if prev == 0:
		tag_added.emit(tag)
		return true
	return false


## 移除一个 tag，引用计数 -1。返回是否触发"真正移除"（1→0）。
func remove_tag(tag: StringName) -> bool:
	var prev: int = _counts.get(tag, 0)
	if prev <= 0:
		return false
	if prev == 1:
		_counts.erase(tag)
		tag_removed.emit(tag)
		return true
	_counts[tag] = prev - 1
	return false


## 强制移除某 tag（计数清零），不论计数多少。返回是否原本存在。
func force_remove(tag: StringName) -> bool:
	if _counts.has(tag):
		_counts.erase(tag)
		tag_removed.emit(tag)
		return true
	return false


## 强制移除所有匹配 query 的 tag（含父子匹配）。返回被移除数量。
## 用于 Cleanse 类 GE：force_remove_matching(&"state") 会清掉所有 state.* tag。
func force_remove_matching(query: StringName) -> int:
	var to_remove: Array[StringName] = []
	for t in _counts.keys():
		if GameplayTag.matches(t, query):
			to_remove.append(t)
	for t in to_remove:
		_counts.erase(t)
		tag_removed.emit(t)
	return to_remove.size()


## 是否持有某 tag。默认走父匹配（has_tag(&"state.buff") 在含 state.buff.haste 时返回 true）。
## exact=true 仅精确匹配。
func has_tag(tag: StringName, exact: bool = false) -> bool:
	if exact:
		return _counts.has(tag)
	for t in _counts.keys():
		if GameplayTag.matches(t, tag):
			return true
	return false


## 是否持有 tags 中任意一个（按 has_tag 语义）。
func has_any(tags: Array, exact: bool = false) -> bool:
	for t in tags:
		if has_tag(t, exact):
			return true
	return false


## 是否持有 tags 中全部（按 has_tag 语义）。
func has_all(tags: Array, exact: bool = false) -> bool:
	for t in tags:
		if not has_tag(t, exact):
			return false
	return true


## 取某 tag 的引用计数（精确匹配）。
func get_count(tag: StringName) -> int:
	return _counts.get(tag, 0)


## 取所有显式 tag（仅返回精确添加过的，不展开父）。
func get_explicit_tags() -> Array[StringName]:
	var result: Array[StringName] = []
	for t in _counts.keys():
		result.append(t)
	return result


## 调试输出。
func dump() -> String:
	var parts: PackedStringArray = []
	for t in _counts.keys():
		parts.append("%s(%d)" % [t, _counts[t]])
	return "[" + ", ".join(parts) + "]"
