## CueBindings。
##
## Cue Tag → CueBinding 注册表的容器 Resource。由 .tres 文件持久化，由 [CueManager] 启动时加载。
##
## 路径约定：[code]res://Data/Config/CueBindings.tres[/code]
##
## 编辑入口：在 Inspector 中编辑 [member bindings] 数组，每条填 [member CueBinding.cue_tag] + 各表现手段。
##
## R-DATA-02：所有 cue 的 sfx/vfx/震屏/冻帧参数均走 .tres，禁止脚本里硬编码。
class_name CueBindings
extends Resource

## Cue 绑定数组。CueManager 启动时遍历，按 [member CueBinding.cue_tag] 建立 Dictionary 索引。
##
## 注：用 Array 而非 Dictionary，是因为 Godot 4.6 Inspector 对 [code]Dictionary[StringName, Resource][/code]
## 的可视化编辑支持还不稳定；Array[CueBinding] 编辑体验更好（每条直接展开）。
@export var bindings: Array[CueBinding] = []


## 把数组转成 Dictionary[cue_tag → CueBinding]，重复 tag 后写覆盖前并 warn。
func to_dict() -> Dictionary:
	var dict: Dictionary = {}
	for b in bindings:
		if b == null:
			continue
		if b.cue_tag == &"":
			GameLogger.warn("Cue", "CueBinding with empty cue_tag, skip")
			continue
		if dict.has(b.cue_tag):
			GameLogger.warn("Cue", "Duplicate cue_tag: %s (later overrides)" % b.cue_tag)
		dict[b.cue_tag] = b
	return dict
