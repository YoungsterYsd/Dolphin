## 检测黑板上是否存在某一次性事件键（[code]event_*[/code]）。
##
## 语义：「事件触发型条件」—— 受击 / 破韧 / 完美格挡等瞬时事件的入口。
##
## 用法：放在 Selector 的高优先级分支前作 guard：
## [codeblock]
## Sequence
## ├── BTCondition_OnEvent(event_key=&"poise_broken", consume=true)
## └── BTAction_EnterPoiseBroken
## [/codeblock]
##
## [member consume]：
##   - false：检测但不消耗（同帧多个 leaf 都能响应）
##   - true（推荐用于"独占事件"）：检测到立即从黑板移除
##
## LimboAI 改造（迁移自旧 BTCondition_OnEvent）：
##   - LimboAI 没有"tick 末尾自动 consume_events"机制；建议高优先级独占事件分支均设 [member consume]=true
##   - 取反需求请套 [BTInvert] 装饰器
@tool
extends BTCondition


## 事件键（不带 [code]event_[/code] 前缀，自动拼接）。
##
## 例：[code]&"took_damage"[/code] → 检测黑板里 [code]&"event_took_damage"[/code]
@export var event_key: StringName = &""

## 检测后是否从黑板移除（推荐对独占事件用 true）。
@export var consume: bool = true


func _generate_name() -> String:
	return "OnEvent: %s%s" % [event_key, " (consume)" if consume else ""]


func _tick(_delta: float) -> Status:
	if event_key == &"":
		return FAILURE
	var full_key: StringName = StringName("event_" + String(event_key))
	if blackboard == null or not blackboard.has_var(full_key):
		return FAILURE
	if consume:
		blackboard.erase_var(full_key)
	return SUCCESS
