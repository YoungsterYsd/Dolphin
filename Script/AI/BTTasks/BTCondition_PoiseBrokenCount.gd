## 检测怪物自身被破韧次数。
##
## 语义：「怪物破韧次数」。
##
## 数据来源：[EnemyCharacter.poise_broken_count] / [EnemyCharacter._poise_broken_history]。
##
## 滑动窗口（[member window_sec] > 0）：只数最近 [member window_sec] 秒内的破韧次数。
## window_sec = 0 时取全程累计。
##
## 操作符：
##   - [code]GTE[/code]：count >= [member count]
##   - [code]LT[/code]：count < [member count]
##
## [member reset_on_match]：命中时是否清零（仅 GTE 模式有意义；用于"满足条件后重新计数"）。
##
## LimboAI 改造（迁移自旧 BTCondition_PoiseBrokenCount）。
@tool
extends BTCondition


enum Op {
	GTE,
	LT,
}


@export var op: Op = Op.GTE

## 比较的次数阈值。
@export_range(0, 100, 1) var count: int = 3

## 滑动窗口（秒）。0 = 全程累计。
@export var window_sec: float = 0.0

## 命中时是否清零。仅 GTE 模式有意义。
@export var reset_on_match: bool = false


func _generate_name() -> String:
	var op_str: String = ">=" if op == Op.GTE else "<"
	if window_sec > 0.0:
		return "PoiseBrk %s %d in %.1fs%s" % [op_str, count, window_sec, " (reset)" if reset_on_match else ""]
	return "PoiseBrk %s %d%s" % [op_str, count, " (reset)" if reset_on_match else ""]


func _tick(_delta: float) -> Status:
	if agent == null:
		return FAILURE

	var current_count: int = 0
	if window_sec > 0.0:
		# 滑动窗口：从 _poise_broken_history 数最近 window_sec 内的时间戳
		if not "_poise_broken_history" in agent:
			return FAILURE
		var history: Array = agent.get(&"_poise_broken_history")
		var now_ms: int = Time.get_ticks_msec()
		var window_ms: int = int(window_sec * 1000.0)
		for ts in history:
			if (now_ms - int(ts)) <= window_ms:
				current_count += 1
	else:
		# 全程累计
		if not "poise_broken_count" in agent:
			return FAILURE
		current_count = int(agent.get(&"poise_broken_count"))

	var ok: bool = false
	match op:
		Op.GTE:
			ok = current_count >= count
		Op.LT:
			ok = current_count < count

	# 命中后清零
	if ok and reset_on_match and op == Op.GTE:
		if window_sec > 0.0:
			var history2: Array = agent.get(&"_poise_broken_history")
			var now_ms2: int = Time.get_ticks_msec()
			var window_ms2: int = int(window_sec * 1000.0)
			var keep: Array = []
			for ts in history2:
				if (now_ms2 - int(ts)) > window_ms2:
					keep.append(ts)
			agent.set(&"_poise_broken_history", keep)
		else:
			agent.set(&"poise_broken_count", 0)

	return SUCCESS if ok else FAILURE
