## NPC 对话服务（静态工具）。
##
## 职责：玩家与 NPC 互动时，**决定该弹什么菜单 / 进入哪段对话**。
##
## **决策流程**（A6 决策：NPC ↔ 对话包多对一）：
##   1. 读 NPC_Data.csv 取该 NPC 的 Diapack_ID
##   2. 读 NPC_Diapack.csv 取该 diapack 全部子项（选项菜单）
##   3. 用 [ConditionEvaluator] 过滤 Condition 不满足的子项
##   4. 命中数量决策：
##      - 0 个 → [method resolve_entry] 返回 0（业务侧静默关闭，不打开对话）
##      - 1 个 → 直接返回该 Dialogue_ID（**自动跳过菜单**，进入对话）
##      - ≥2 个 → 返回 -1（业务侧调 [method get_visible_options] 取选项菜单数据自行渲染）
##
## **设计要点**（SOLID）：
##   - SRP：仅做"NPC → 该弹什么菜单"决策；不发信号、不操作 UI、不开对话
##   - DRY：所有 NPC 互动入口（NPCActor / GM 命令 / 远程触发）共用本服务
##   - DIP：调用方传 npc_id；本服务不知道是谁在调用
##
## 静态工具类，请勿 new。
class_name NPCDialogueService
extends RefCounted

## 决策结果常量（[method resolve_entry] 返回值的特殊含义）。
const RESULT_NONE: int = 0     # 无可见选项，静默关闭
const RESULT_MENU: int = -1    # 多个可见选项，业务侧应显示菜单


## 解析进入入口。返回值含义：
##   - >0：直接进入此 graph_id（自动跳过菜单）
##   - 0：[constant RESULT_NONE]，静默关闭（业务侧不打开对话）
##   - -1：[constant RESULT_MENU]，业务侧应调 [method get_visible_options] 渲染菜单
static func resolve_entry(npc_id: int) -> int:
	var visible: Array = get_visible_options(npc_id)
	if visible.is_empty():
		return RESULT_NONE
	if visible.size() == 1:
		return int(visible[0].get("Dialogue_ID", 0))
	return RESULT_MENU


## 取所有可见的 Diapack 选项（已过滤 Condition；按 sub_id 升序）。
##
## 返回 [code]Array[Dictionary][/code]，元素 dict 包含：
##   - [code]sub_id[/code]: int  选项序号
##   - [code]Talk_Text[/code]: String  按钮文字
##   - [code]Dialogue_ID[/code]: int  跳转目标 graph_id
##   - [code]Condition[/code]: int  原始 cond_id（已通过；UI 一般不再用）
static func get_visible_options(npc_id: int) -> Array:
	if npc_id <= 0:
		return []
	var npc_def: Dictionary = ConfigCenter.get_npc_def(npc_id)
	if npc_def.is_empty():
		GameLogger.warn("NPC", "NPCDialogueService: npc_id=%d not in NPC_Data.csv" % npc_id)
		return []
	var diapack_id: int = CsvLoader.as_int(npc_def, "Diapack_ID", 0)
	if diapack_id <= 0:
		return []
	var entries: Array = ConfigCenter.get_diapack_entries(diapack_id)
	var visible: Array = []
	for e in entries:
		# 跳过工具的"主行"占位（sub_id 留空 / 0）
		var sub_id: int = int(e.get("sub_id", 0))
		if sub_id < 1:
			continue
		var cond_id: int = CsvLoader.as_int(e, "Condition", 0)
		if not ConditionEvaluator.eval(cond_id):
			continue
		visible.append(e)
	return visible


## 取 NPC 显示名（HUD/对话头像用）。找不到返回空字符串。
static func get_npc_name(npc_id: int) -> String:
	var def: Dictionary = ConfigCenter.get_npc_def(npc_id)
	if def.is_empty():
		return ""
	return CsvLoader.as_string(def, "Name", "")


## 取 NPC 的对话半身像路径（[code]Talk_Show[/code] 列）。找不到返回空字符串。
static func get_npc_portrait(npc_id: int) -> String:
	var def: Dictionary = ConfigCenter.get_npc_def(npc_id)
	if def.is_empty():
		return ""
	return CsvLoader.as_string(def, "Talk_Show", "")
