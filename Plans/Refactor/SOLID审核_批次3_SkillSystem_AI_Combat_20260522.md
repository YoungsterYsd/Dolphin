# SOLID 审核 · 批次 3：SkillSystem + AI + Combat（L1 速扫）

> 审核日期：2026-05-22
> 范围：`Script/SkillSystem/`（16）、`Script/AI/`（8）、`Script/Combat/`（1），共 **25 个 .gd**
> 严重级：🔴 Error / 🟡 Warning / 🟢 Note

---

## SkillSystem

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| ActiveTimeline.gd | 60 | 🟢 | RefCounted 纯逻辑容器，SRP 干净；`_sorted_kfs` 元素是无类型 Dictionary（魔字符串 "time"/"kf"/"track"） | 抽 inner class `KeyframeEntry` 或 const 常量 key |
| DamageNode.gd | 26 | 🟢 | 资源定义类，纯数据，零问题 | — |
| HitDamageResolver.gd | 106 | 🟡 | (1) ConfigCenter 弱类型查找 + null 静默 return（违反 R-CODE-01）；(2) `_find_asc` 鸭子链 `&"asc" in node` / 节点名硬查 / `has_method(&"get_asc")` 三段兜底 | (1) 缺失 assert；(2) 复用 BaseCharacter.asc 强类型，删 has_method 分支 |
| HitStopHost.gd | 56 | 🟢 | 职责单一、注释清晰 | — |
| SkillDamageTable.gd | 43 | 🟢 | 纯资源 | — |
| SkillEventKind.gd | 51 | 🟢 | 常量集中、is_valid/all() 工具方法到位 | 加 "请勿 new" 注释（已有），保留 |
| SkillKeyframe.gd | 13 | 🟢 | 极简基类，零问题 | — |
| SkillTimeline.gd | 60 | 🟢 | 资源定义清晰；`collect_sorted_keyframes` 每次重新合并+排序，轻微浪费 | 缓存合并结果（低优） |
| SkillTimelinePlayerHost.gd | 135 | 🟡 | (1) 对 BaseCharacter 类型耦合 + 取 `.hitbox` 字段（违反 R-CHAR-01）；(2) meta 清理逻辑与 EventTrackHandler 重复 | (1) 用 NodeFinder 类型查找；(2) meta 清理抽 `EventTrackHandler.clear_skill_meta(caster)` 静态方法 |
| SkillTrack.gd | 30 | 🟢 | 用 `GameLogger.error` + 默认值代替 abstract，可接受 | 改 `assert(false, "...")` 让违约直接崩 |
| Keyframes/AnimationKeyframe.gd | 21 | 🟢 | 纯资源 | — |
| Keyframes/EventKeyframe.gd | 26 | 🟡 | `payload: Dictionary` 全 kind 共用一个无 schema 字段 | 长期：拆 8 个子类带强类型字段；短期保留 |
| TrackHandlers/AnimationTrackHandler.gd | 27 | 🟡 | (1) `caster.get_node_or_null(^"AnimationComponent")` 硬编码节点名；(2) `has_method(&"play")` 防御静态可知 API | (1) 改 NodeFinder；(2) 删 has_method |
| TrackHandlers/EventTrackHandler.gd | 120 | 🟡 | (1) 对 BaseCharacter 类型耦合；(2) `caster.set_meta/get_meta` 充当跨函数共享状态总线（隐式契约） | (1) NodeFinder；(2) 中期抽 `SkillExecutionContext` per-active 上下文对象 |
| Tracks/AnimationTrack.gd | 20 | 🟢 | 极简实现，零问题 | — |
| Tracks/EventTrack.gd | 21 | 🟢 | 极简实现，零问题 | — |

---

## AI

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| AIController.gd | 102 | 🟢 | `enemy: Node` 弱类型（应 EnemyCharacter）；`current_state.state_name` 三元简写但 enemy 字段类型未声明 | `var enemy: EnemyCharacter` 强类型化 |
| AIState.gd | 39 | 🟢 | 抽象基类设计干净 | — |
| BossAI.gd | 73 | 🟡 | (1) Character 重构已自我订阅 ✓；(2) 直接读写 `enemy.move_comp.max_speed` + `set_meta("base_speed")` 字符串状态总线；(3) 阶段配置数组应迁 .tres | (1) 已合规；(2) `_base_speed` 改本类 var；(3) 阶段配置进 `BossPhaseConfig.tres`；(4) MoveComponent 暴露 `set_speed_mult` 公共 API |
| States/AIState_Attack.gd | 64 | 🟡 | (1) `&"enemy_basic_attack"` 硬编码 ability_id；(2) `_set_facing` 在 State 直接操 sprite（SoC + R-CHAR-03 适用） | (1) ability_id 改 EnemyCharacter @export；(2) 调 `enemy.visual.set_facing(dir)` |
| States/AIState_Chase.gd | 30 | 🟢 | `detect_range * 1.5` 中 1.5 是脱离倍率魔数 | 加 `@export var leash_mult: float = 1.5` |
| States/AIState_Dead.gd | 53 | 🟡 | (1) `FADE_DURATION: float = 0.5` 硬编码；(2) State 直接遍历 `enemy.get_children()` 操作三类视觉 modulate；(3) 兼容 2D `CanvasItem` 路径与 R-CHAR-02 不一致 | (1) 0.5 迁配置；(2) 抽 `VisualComponent.set_alpha(a)` API；(3) 删 CanvasItem 分支 |
| States/AIState_Hit.gd | 26 | 🟢 | 极简 | — |
| States/AIState_Idle.gd | 21 | 🟢 | 极简 | — |

---

## Combat

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| CombatStateService.gd | 122 | 🔴 | (1) `asc.call(&"_detach_active", h)` —— **越权调用 ASC 私有方法**，与 BlockComponent 已修复的反模式同形（ASC 已有公共 `remove_effects_with_granted_tag` 不用！）；(2) 玩家 ASC 缺失静默降级；(3) `EventBus.has_signal(&"damage_dealt_v2")` 防御静态信号；(4) `COMBAT_ACTIVE_DURATION = 5.0` / `COMBAT_AGGRO_RADIUS = 8.0` 硬编码 | (1) **必改**：换成 `asc.remove_effects_with_granted_tag(&"State.Combat.Active")`；(2) 玩家 ASC 缺失 → assert；(3) 删 has_signal；(4) 5.0/8.0 迁 `CombatStateConfig.tres` |

---

## 批次小结

**Top 5 严重文件**：
1. **CombatStateService.gd 🔴** — 唯一 Error 级。包含 6 类问题，含已修复反模式遗漏；改造一次借力 ASC 公共 API
2. **HitDamageResolver.gd 🟡** — `_find_asc` 三段兜底 + ConfigCenter null 静默 return
3. **AIState_Dead.gd 🟡** — 内嵌三类视觉分支 + 0.5 秒硬编码 + 残留 2D 路径
4. **BossAI.gd 🟡** — 自我订阅已修对 ✓，但直写 MoveComponent + 字符串状态总线
5. **EventTrackHandler.gd 🟡** — `caster.set_meta` 当跨函数 implicit context

**跨文件共性**：
- **C1 · ConfigCenter 弱类型访问 4+ 处**：HitDamageResolver / CombatStateService / 间接共 4 处；与全局 C1 同根
- **C2 · BaseCharacter 类型耦合 + 取聚合字段**：SkillTimelinePlayerHost / EventTrackHandler / AnimationTrackHandler / AIState_* 普遍存在；建议改 NodeFinder
- **C3 · assert / 兜底失衡**：与 Character 模块经验完全同型
- **C4 · State / Handler 直接操作宿主表现层**：AIState_Attack / AIState_Dead / EventTrackHandler 跨层访问表现/物理
- **C5 · meta 当跨函数状态总线**：EventTrackHandler.META_* × HitDamageResolver × SkillTimelinePlayerHost 三处共享 caster.set_meta 链

**与 GAS / Character 接口耦合**：
- **GAS**：CombatStateService 仍用 `_detach_active` ✗（应改 `remove_effects_with_granted_tag`）；其它 ASC 调用合规
- **Character**：所有 SkillSystem 假设 `caster is BaseCharacter` 取 `.hitbox / .anim_comp` 强类型耦合，应改 NodeFinder
- **EventBus**：BossAI 自我订阅 ✓；CombatStateService emit `combat_state_changed` 唯一发射源 ✓

**待用户确认项**：
- **U1**：`SkillSystem/TrackHandlers/` 目录命名 vs 用户提示词写的 `EventHandlers/` 不一致；保持现状还是改名？
- **U2**：EventKeyframe.payload 是否拆 8 个强类型子类？.tres 资源迁移工作量大
- **U3**：CombatStateService 5s/8m 是否进配置表？这俩值与 GE_CombatActive 形成系统耦合
- **U4**：AIState_Attack 是否调 VisualComponent.set_facing()，还是改 emit `EventBus.ai_facing_requested`？前者简单后者更解耦
- **U5**：BossAI 阶段配置 .tres 是 per-Boss 还是全局一份？
