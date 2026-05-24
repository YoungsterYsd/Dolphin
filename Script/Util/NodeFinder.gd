## 节点查找工具（静态）。
##
## 用于消除项目内多处重复的"在子树中找首个某类型节点"代码。
##
## 使用：
## [codeblock]
## var sprite := NodeFinder.find_first_of_type(self, SpriteBase3D) as SpriteBase3D
## var anim := NodeFinder.find_first_of_type(self, AnimatedSprite3D) as AnimatedSprite3D
## [/codeblock]
##
## 设计原则：
## - 失败返回 null（不抛异常、不打 warn）；调用方决定如何处理"找不到"
## - 仅做"读取"，不修改节点树
class_name NodeFinder
extends RefCounted


## 在 root 子树中深度优先查找首个 type 类型的节点。root 自身也算入候选。
##
## type 必须是 Object 或 Script（GDScript 的 [code]is[/code] 操作符支持的类型）。
## 找不到返回 null。
static func find_first_of_type(root: Node, type) -> Node:
	if root == null:
		return null
	if is_instance_of(root, type):
		return root
	for child in root.get_children():
		var found := find_first_of_type(child, type)
		if found != null:
			return found
	return null


## 在 root 直接子节点中查找首个 type 类型的节点（不递归子树）。
static func find_first_child_of_type(root: Node, type) -> Node:
	if root == null:
		return null
	for child in root.get_children():
		if is_instance_of(child, type):
			return child
	return null


## 收集 root 子树中所有 type 类型的节点。
static func find_all_of_type(root: Node, type) -> Array:
	var result: Array = []
	if root == null:
		return result
	_collect_of_type(root, type, result)
	return result


static func _collect_of_type(node: Node, type, out: Array) -> void:
	if is_instance_of(node, type):
		out.append(node)
	for child in node.get_children():
		_collect_of_type(child, type, out)
