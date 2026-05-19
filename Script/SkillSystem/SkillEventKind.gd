@tool
## 技能事件 Kind 常量集合（M7 统一来源）。
##
## 所有 [EventKeyframe.kind] 字段必须使用这里的常量，禁止散落字符串字面量（R-DATA-02）。
## 由 [SkillTimelinePlayerHost] 在事件触发时按 kind 分派路由。
##
## 8 种 Kind 分两组：
##   - **直管类**（Player 内部直接处理，不走 EventBus）：HITBOX_ENABLE / HITBOX_DISABLE
##   - **广播类**（emit EventBus 信号让各 Manager 订阅，R-EVENT-01 合规）：
##     SFX_PLAY / VFX_SPAWN / PROJECTILE_SPAWN / CAMERA_SHAKE / HIT_STOP / CUSTOM_SIGNAL
##
## 静态常量类，请勿 new。
class_name SkillEventKind
extends RefCounted

# === 直管类 ===
const HITBOX_ENABLE: StringName = &"hitbox_enable"
const HITBOX_DISABLE: StringName = &"hitbox_disable"

# === 广播类 ===
const SFX_PLAY: StringName = &"sfx_play"
const VFX_SPAWN: StringName = &"vfx_spawn"
const PROJECTILE_SPAWN: StringName = &"projectile_spawn"
const CAMERA_SHAKE: StringName = &"camera_shake"
const HIT_STOP: StringName = &"hit_stop"
const CUSTOM_SIGNAL: StringName = &"custom_signal"


## 所有合法 Kind 列表（用于 Editor 下拉框 / 校验）。
static func all() -> Array[StringName]:
	return [
		HITBOX_ENABLE,
		HITBOX_DISABLE,
		SFX_PLAY,
		VFX_SPAWN,
		PROJECTILE_SPAWN,
		CAMERA_SHAKE,
		HIT_STOP,
		CUSTOM_SIGNAL,
	]


## 校验 kind 是否合法。
static func is_valid(kind: StringName) -> bool:
	return kind in all()


## 是否为直管类（不走 EventBus）。
static func is_direct(kind: StringName) -> bool:
	return kind == HITBOX_ENABLE or kind == HITBOX_DISABLE
