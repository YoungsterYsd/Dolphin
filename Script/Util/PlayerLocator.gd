## 玩家定位工具（静态）。
##
## 用于消除项目内多处重复的"通过 group &\"player\" 查找首个节点 + 取 ASC + 取 TagContainer"代码。
##
## 使用：
## [codeblock]
## # Node 上下文（推荐）：
## var p := PlayerLocator.find_player(self)
## var asc := PlayerLocator.find_player_asc(self)
## var tags := PlayerLocator.find_player_tags(self)
##
## # RefCounted / Handler 上下文（无 self.get_tree()）：
## var p := PlayerLocator.find_player_global()
## [/codeblock]
##
## 设计原则：
## - 失败返回 null（玩家死亡 / 未生成 / Editor 工具脚本）；调用方决定如何处理"找不到"
## - 不打 warn 日志（让调用方按业务语义打）
## - 仅做"读取"，不修改场景树
class_name PlayerLocator
extends RefCounted


# ─────────────────────────────────────────────────────────────
# Node 上下文（推荐：拿 SceneTree 更可靠）
# ─────────────────────────────────────────────────────────────

## 在 caller 所在的 SceneTree 中查找首个 [PlayerCharacter]。找不到返回 null。
static func find_player(caller: Node) -> PlayerCharacter:
	if caller == null:
		return null
	var tree := caller.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"player") as PlayerCharacter


## 取玩家 ASC。找不到（玩家未生成 / asc 字段为 null）返回 null。
static func find_player_asc(caller: Node) -> AbilitySystemComponent:
	var p := find_player(caller)
	if p == null:
		return null
	return p.asc


## 取玩家 [GameplayTagContainer]（ASC.tags）。找不到返回 null。
static func find_player_tags(caller: Node) -> GameplayTagContainer:
	var asc := find_player_asc(caller)
	if asc == null:
		return null
	return asc.tags


# ─────────────────────────────────────────────────────────────
# RefCounted / 无 Node 上下文（Handler / Tool 类用）
# ─────────────────────────────────────────────────────────────

## 全局查找玩家（无 caller 上下文，走 Engine.get_main_loop）。
##
## 仅在 RefCounted（如 Dialogue Handler）等无 Node 持有 SceneTree 的场景使用。
## 普通 Node 节点请优先用 [method find_player]。
static func find_player_global() -> PlayerCharacter:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"player") as PlayerCharacter


## 全局取玩家 ASC（无 Node 上下文）。
static func find_player_asc_global() -> AbilitySystemComponent:
	var p := find_player_global()
	if p == null:
		return null
	return p.asc


## 全局取玩家 TagContainer（无 Node 上下文）。
static func find_player_tags_global() -> GameplayTagContainer:
	var asc := find_player_asc_global()
	if asc == null:
		return null
	return asc.tags
