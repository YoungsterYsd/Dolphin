## 对话图工厂（静态工具，CSV → DialogueGraph 内存对象）。
##
## 输入：graph_id（[code]Dialogue.id[/code]）
## 输出：[DialogueGraph]（含 SpeechNode / ChoiceNode 节点数组 + start_node_id）
##
## **构图规则**（与 Dialogue.csv 字段一一对应）：
##   - 每行 sub_id≥1 = 一个节点
##   - **无 Branch** → SpeechNode；自动跳到 sub_id+1（用 NextLink 表达，无 sub_id+1 则结束）
##   - **有 Branch** → ChoiceNode；Branch_Text/Branch_ID/Branch_Cond 三列等长，依次组装 ChoiceOption
##   - start_node_id = 最小的 sub_id≥1 的节点
##
## **设计要点**（SOLID）：
##   - SRP：仅做"CSV → 内存图"转换；不读 csv（委托 ConfigCenter）、不渲染、不发信号
##   - DRY：与 [LootRoller] 同模式（静态工具 + 简单纯函数）
##
## **失败语义**（R-CODE-01）：
##   - graph_id 在 csv 不存在 → 返回 null（业务侧 warn）
##   - Branch_Text / Branch_ID 长度不等 → assert 崩（配置错误）
##
## 静态工具类，请勿 new。
class_name DialogueGraphFactory
extends RefCounted


## 主入口：构造一段对话图。找不到 graph_id → null。
static func build(graph_id: int) -> DialogueGraph:
	if graph_id <= 0:
		return null
	var rows: Array = ConfigCenter.get_dialogue_nodes(graph_id)
	if rows.is_empty():
		GameLogger.warn("Dialogue", "DialogueGraphFactory.build: graph_id=%d not found / empty" % graph_id)
		return null

	# 收集有效节点行（sub_id≥1；sub_id=0/留空是工具的"主行"占位，跳过）
	var valid_rows: Array = []
	for r in rows:
		var sub_id: int = int(r.get("sub_id", 0))
		if sub_id >= 1:
			valid_rows.append(r)
	if valid_rows.is_empty():
		GameLogger.warn("Dialogue", "DialogueGraphFactory.build: graph_id=%d has no nodes" % graph_id)
		return null

	# 按 sub_id 升序（DRY：CsvLoader 的 sub_entries 已按 sub_id 升序，保险再排一次）
	valid_rows.sort_custom(func(a, b): return int(a.get("sub_id", 0)) < int(b.get("sub_id", 0)))

	var graph: DialogueGraph = DialogueGraph.new()
	graph.graph_id = graph_id
	graph.start_node_id = int(valid_rows[0].get("sub_id", 1))

	# 构造节点
	var sub_ids: Array[int] = []
	for r in valid_rows:
		sub_ids.append(int(r.get("sub_id", 0)))

	for i in range(valid_rows.size()):
		var r: Dictionary = valid_rows[i]
		var node: DialogueNode = _build_node(r, graph_id, sub_ids, i)
		if node != null:
			graph.nodes.append(node)

	return graph


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────


## 单节点构造：依据是否含 Branch 字段选择 SpeechNode / ChoiceNode。
##
## [param r]：当前行 dict
## [param graph_id]：仅用于错误日志定位
## [param sub_ids]：本 graph 全部节点 sub_id 升序数组（用于推断"自动下一节点"）
## [param idx]：当前行在 sub_ids 中的索引
static func _build_node(r: Dictionary, graph_id: int, sub_ids: Array[int], idx: int) -> DialogueNode:
	var sub_id: int = int(r.get("sub_id", 0))
	var branch_texts: Array = CsvLoader.as_list_string(r, "Branch_Text")
	var branch_ids: Array = CsvLoader.as_list_int(r, "Branch_ID")

	if branch_ids.is_empty():
		# SpeechNode：无分支，自动接下一节点（NextLink）
		var sn: SpeechNode = SpeechNode.new()
		sn.node_id = sub_id
		sn.text = String(r.get("Text", ""))
		# 自动 NextLink：下一个 sub_id（如果存在）
		if idx + 1 < sub_ids.size():
			var nl: NextLink = NextLink.new()
			nl.next_id = sub_ids[idx + 1]
			nl.cond_id = 0
			sn.next_links = [nl]
		return sn

	# ChoiceNode：有分支
	var branch_conds: Array = CsvLoader.as_list_int(r, "Branch_Cond")
	# 长度对齐校验（R-CODE-01）
	assert(branch_texts.size() == branch_ids.size(),
		"DialogueGraphFactory: graph=%d sub_id=%d Branch_Text/ID 长度不等 (%d vs %d)" % [
			graph_id, sub_id, branch_texts.size(), branch_ids.size()])

	var cn: ChoiceNode = ChoiceNode.new()
	cn.node_id = sub_id
	cn.prompt = String(r.get("Text", ""))
	for i in range(branch_ids.size()):
		var co: ChoiceOption = ChoiceOption.new()
		co.text = String(branch_texts[i]) if i < branch_texts.size() else ""
		co.next_id = int(branch_ids[i])
		co.cond_id = int(branch_conds[i]) if i < branch_conds.size() else 0
		cn.choices.append(co)
	return cn
