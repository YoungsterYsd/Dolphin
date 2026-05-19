## 全局事件总线（Autoload 单例）。
##
## 所有跨模块全局信号集中声明在此（参见 R-EVENT-01）。
## 业务节点上的 signal 仅用于自身/父子作用域；跨模块通信一律走本类。
##
## 命名规则（R-NAME-01）：snake_case 过去式，如 [signal enemy_died]。
extends Node

# ─────────────────────────────────────────────────────────────
# 游戏状态
# ─────────────────────────────────────────────────────────────

## 顶层游戏状态发生切换。old_state/new_state 为 GameInstance.GameState 枚举值。
signal game_state_changed(old_state: int, new_state: int)


# ─────────────────────────────────────────────────────────────
# GAS · 属性 / 技能 / 效果
# ─────────────────────────────────────────────────────────────

## AttributeSet 中任一属性发生变化时广播。
## owner 为持有该 AttributeSet 的节点（一般是 ASC 所在节点）。
signal attribute_changed(owner: Node, attr_name: StringName, old_value: float, new_value: float)

## 技能成功激活。
signal ability_activated(owner: Node, ability_id: StringName)

## 技能因 cost / cd / tag 拦截而激活失败。
signal ability_activation_failed(owner: Node, ability_id: StringName, reason: String)

## 技能正常结束（无论成功命中与否）。
signal ability_ended(owner: Node, ability_id: StringName)

## GameplayEffect 应用到目标。
signal effect_applied(target: Node, effect: Resource, source: Node)

## GameplayEffect 从目标移除（含到期、被驱散）。
signal effect_removed(target: Node, effect: Resource)


# ─────────────────────────────────────────────────────────────
# 战斗
# ─────────────────────────────────────────────────────────────

## 一次伤害结算完成。amount 为最终扣血数值。
signal damage_dealt(source: Node, target: Node, amount: float, damage_type: StringName)

## M8 扩展版伤害事件：携带 DamageNode 引用 + 暴击标记，给表现层（飘字/HitFlash/VFX）订阅用。
## 注：旧 damage_dealt 信号仍保留（HitDamageResolver 也仍 emit），便于兼容；M8 表现层优先订阅本信号。
signal damage_dealt_v2(source: Node, target: Node, amount: float, damage_node: Resource, is_crit: bool)

## 玩家死亡。
signal player_died()

## 怪物死亡。
signal enemy_died(enemy: Node)

## M8 怪物生成（供 OverheadHealthBarManager 监听并自动挂血条）。
## 由 EnemyCharacter._ready 在初始化完成后 emit。
signal enemy_spawned(enemy: Node)


# ─────────────────────────────────────────────────────────────
# 关卡 / Boss
# ─────────────────────────────────────────────────────────────

## 关卡切换完成。
signal level_changed(level_id: StringName)

## 关卡通关。
signal level_completed(level_id: StringName)

## Boss 进入新阶段。
signal boss_phase_changed(boss: Node, phase: int)


# ─────────────────────────────────────────────────────────────
# UI / 物品
# ─────────────────────────────────────────────────────────────

## 背包内容变化（增删改）。
signal inventory_changed(owner: Node)

## 装备变化。
signal equipment_changed(owner: Node, slot: int)

## 通用 HUD 提示请求。
signal hud_toast_requested(text: String, duration: float)


# ─────────────────────────────────────────────────────────────
# M7 · 技能时间轴（SkillTimeline · EventTrack 派发）
# ─────────────────────────────────────────────────────────────
# 6 种"广播类"事件 Kind（SkillEventKind）通过这里转发给各 Manager 订阅；
# 2 种"直管类"（HITBOX_ENABLE/HITBOX_DISABLE）由 SkillTimelinePlayerHost 内部直接处理，不走 EventBus。
# R-EVENT-01：跨模块全局信号集中声明在此。

## 技能播放开始（一份 timeline 进入活动列表）。
signal skill_timeline_started(skill_id: StringName, caster: Node, handle_id: int)

## 技能播放结束（duration 到时间或 stop 主动终止）。
signal skill_timeline_ended(skill_id: StringName, caster: Node, handle_id: int)

## 音频播放请求（payload: {sfx_id: StringName, ...}）。AudioManager 订阅。
signal skill_event_sfx(sfx_id: StringName, caster: Node, payload: Dictionary)

## 特效生成请求（M8 时由 VFXSpawner 订阅；M7 阶段先打日志）。
signal skill_event_vfx(vfx_id: StringName, caster: Node, payload: Dictionary)

## 投掷物生成请求（M8 时由 ProjectileSpawner 订阅；M7 阶段先打日志）。
signal skill_event_projectile(projectile_id: StringName, caster: Node, payload: Dictionary)

## 屏幕震动请求。CameraRig 订阅。
signal skill_event_camera_shake(intensity: float, duration: float, caster: Node)

## 冻帧请求（duration_ms 毫秒）。HitStopHost 订阅。
signal skill_event_hit_stop(duration_ms: float, caster: Node)

## 自定义信号（业务可订阅 signal_name 做扩展）。
signal skill_event_custom(signal_name: StringName, caster: Node, data: Dictionary)


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	GameLogger.info("Core", "EventBus ready")
