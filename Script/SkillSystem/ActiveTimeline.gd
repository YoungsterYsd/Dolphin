## 一次播放实例。由 [SkillTimelinePlayerHost] 在 `play()` 时创建，每物理帧推进 elapsed。
##
## 核心算法：构造时把所有轨道的关键帧合并按 time 升序，运行时维护 `_next_index`，
## 每帧 advance 期间消费 `[_next_index, n)` 中所有 time ≤ elapsed 的关键帧，避免每帧 O(N)。
##
## 不持有 Node，纯逻辑容器；由 Host 维护引用。
class_name ActiveTimeline
extends RefCounted

var timeline: SkillTimeline = null
var caster: Node = null  # 施法者节点（一般为 BaseCharacter）
var target: Node = null  # 可选目标
var handle_id: int = 0
var elapsed: float = 0.0
var finished: bool = false

# 已合并并按 time 升序的关键帧列表，元素：{time, kf, track}
var _sorted_kfs: Array = []
# 下一个待触发关键帧索引
var _next_index: int = 0


func init(p_timeline: SkillTimeline, p_caster: Node, p_target: Node, p_handle_id: int) -> void:
	timeline = p_timeline
	caster = p_caster
	target = p_target
	handle_id = p_handle_id
	elapsed = 0.0
	finished = false
	_next_index = 0
	if timeline != null:
		_sorted_kfs = timeline.collect_sorted_keyframes()
	else:
		_sorted_kfs = []


## 推进 delta 秒。返回本次推进期间需要触发的关键帧列表（元素同 _sorted_kfs 项）。
## 同时维护 finished 标志（elapsed >= duration 即结束）。
func advance(delta: float) -> Array:
	if finished or timeline == null:
		return []
	elapsed += delta
	var to_fire: Array = []
	while _next_index < _sorted_kfs.size():
		var item = _sorted_kfs[_next_index]
		if float(item["time"]) > elapsed:
			break
		to_fire.append(item)
		_next_index += 1
	if elapsed >= timeline.duration:
		finished = true
	return to_fire


## 主动终止：把剩余未触发关键帧丢弃，标记 finished。
## 不调用 disable hitbox 等清理动作 —— 由 Host 决定如何收尾。
func mark_terminated() -> void:
	finished = true
	_next_index = _sorted_kfs.size()
