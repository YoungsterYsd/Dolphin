@tool
## 技能时间轴资源。
##
## 一份 .tres 描述一个技能的"动画 + 事件"时序。
## 由 [Ability_TimelineDriven] 引用，运行时被 [TimelinePlayer] 播放。
##
## 命名：`Data/Skills/Timelines/Timeline_<Skill>.tres`，对应 [member skill_id]。
##
## R-DATA-02：所有可调时序参数（关键帧 time / kind / payload）走资源；脚本中禁止硬编码。
class_name SkillTimeline
extends Resource

## 技能 id（与 [DamageNode] 查表的 skill_id 对应；通常等于 Ability.ability_id）。
@export var skill_id: StringName = &""

## 总时长（秒）。Player 推进到 duration 时结束。
@export var duration: float = 1.0

## 轨道列表（AnimationTrack / EventTrack 混合）。
@export var tracks: Array[SkillTrack] = []


## 取所有轨道按 [member SkillKeyframe.time] 合并的有序关键帧列表。
## 返回元素：`{ "time": float, "kf": SkillKeyframe, "track": SkillTrack }`。
##
## TimelinePlayer 调度时使用：单次合并 + 用 fired index 推进，避免每帧 O(N) 扫描。
func collect_sorted_keyframes() -> Array:
	var out: Array = []
	for tr in tracks:
		if tr == null or not tr.enabled:
			continue
		for kf in tr.get_keyframes():
			if kf == null:
				continue
			out.append({"time": kf.time, "kf": kf, "track": tr})
	out.sort_custom(func(a, b): return a["time"] < b["time"])
	return out


## 编辑器渲染辅助：取某轨道的关键帧数组（避开外部跨脚本调用 placeholder 问题）。
## track_idx 越界返回空数组。
func get_track_keyframes(track_idx: int) -> Array:
	if track_idx < 0 or track_idx >= tracks.size():
		return []
	var tr: SkillTrack = tracks[track_idx]
	if tr == null:
		return []
	return tr.get_keyframes()


## 编辑器渲染辅助：取某轨道的类型常量（KIND_ANIMATION / KIND_EVENT）。
## track_idx 越界返回空 StringName。
func get_track_kind(track_idx: int) -> StringName:
	if track_idx < 0 or track_idx >= tracks.size():
		return &""
	var tr: SkillTrack = tracks[track_idx]
	if tr == null:
		return &""
	return tr.get_track_kind()
