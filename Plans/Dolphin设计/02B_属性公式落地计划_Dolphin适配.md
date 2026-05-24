# D2 属性 RPG 化 · 落地计划（02B）

> **本文定位**：将 [`02_战斗框架_属性公式_Dolphin适配.md`](./02_战斗框架_属性公式_Dolphin适配.md) 的"架构锁定 + 数值挂起"设计，按 Dolphin **当前工程现状** 拆解成可执行的 5 个阶段子里程碑（D2.A–D2.E），含差距分析、依赖关系、文件级动作清单、风险与回退、验收锚点。
> **对应里程碑**：D2（战斗框架 · 属性 RPG 化），与三期 M10–M12 **并行**。
> **预估工期**：10.2 工作日（02 文档原 D2.1–D2.11 共 6.7d + 现状差距弥补 + 数据迁移与回归 + AbilityTask 轻量钩子 + CueManager 注册表 ≈ +3.5d）
> **状态**：⬜ 未开始
> **创建日期**：2026-05-21

---

## 0. 差距分析（当前 vs 目标）

### 0.1 当前工程现状（M9 收尾后的 GAS 实现）

| 维度 | 现状 | 位置 |
|---|---|---|
| AttributeSet | **1 套** `CharacterAttributeSet`（玩家+敌人共用），7 字段：`max_health/health/max_mana/mana/attack/defense/move_speed` | `Script/GAS/Attributes/CharacterAttributeSet.gd` |
| 元属性管道 | ❌ **无**：`set_attr(health, ...)` 直接落值 + clamp，没有 `damage`/`healing` 元属性中转 | `AttributeSet.gd:20` |
| `OnOutOfHealth` 钩子 | ❌ **无**：HP 归零 → 业务侧（EnemyCharacter 等）自己判 → emit `EventBus.enemy_died` | `EventBus.gd` |
| `_pre_change_*` / `_post_apply_effect` | ❌ **无**：基类只支持"上限属性自动 clamp"，没有 hook | `AttributeSet.gd:56` |
| GameplayEffect 类型 | ✅ Instant/Duration/Periodic 三型 + tags | `GameplayEffect.gd` |
| GE 数量 | 7 个：`GE_BasicDamage` / `GE_BossMeleeDamage` / `GE_EnemyMeleeDamage` / `GE_Heal30` / `GE_Burning_3s` / `GE_Cleanse` / `GE_Stun_2s` | `Data/Effects/` |
| **SetByCaller 数据传递** | ❌ **无**：GE 的 `magnitude` 是写死字面量，技能注入需在 caller 侧 duplicate GE 改 magnitude（极不优雅） | `AttributeModifier.gd` |
| 伤害公式 | **1 步**：`HitDamageResolver` 取 `caster.attack` × `damage_node.damage_multiplier` + `extra_flat`，apply 给 target；**没有暴击 / 防穿 / 减伤 / 格挡 / 吸血** | `Script/SkillSystem/HitDamageResolver.gd` |
| 双池能量系统 | ❌ **无**（mana 字段闲置） | — |
| 格挡耐久 | ❌ **无** | — |
| WeaponInstance | ❌ **无**（D4 里程碑才做） | — |
| CombatStateService | ❌ **无** | — |
| 数据驱动入口 | ✅ ConfigCenter + AttributeGrowthTable（M6 已做），按 `entity_id+level` 解算注入 | `Script/Data/AttributeResolver.gd` |

### 0.2 目标（02 文档锁定）

| 维度 | 目标 |
|---|---|
| AttributeSet | **3 套**：HealthSet（6 字段）/ PrimaryAttributeSet（21 字段，仅玩家） / CombatSet（2 字段，玩家+敌人） |
| 元属性 | `health_damage` / `health_healing` 经 `_post_apply_effect` 反应到 `health_final` |
| Hook | `_pre_change_<attr>` / `_post_apply_effect` 钩子函数 |
| SetByCaller | `GE.set_by_caller_tags: Dictionary` 配 `apply_effect_spec(spec)` |
| GE 数量 | **9 个核心** + 派生 N 个（吸血/暴击 buff 等按需） |
| 伤害公式 | **13 步** `DamagePipeline.compute_and_apply()` 静态函数 |
| 能量 | 切换池 50（角色级）+ 大招池 100（武器级） |
| 格挡 | `block_max/regen_delay/regen_rate/regen_rate_in_combat/current` + 完美格挡 buff |
| OutOfHealth | `EventBus.out_of_health(asc)` 信号 |

### 0.3 差距清单（影响实施顺序）

| ⚠️ 差距点 | 处理策略 | 出现在哪个阶段 |
|---|---|---|
| **D2.A 必须做的基建**：`AttributeSet` 基类增加 `_pre_change_<attr>` / `_post_apply_effect` 钩子；保持 `set_attr` 兼容 | 改 `AttributeSet.gd`，加非破坏性钩子；老子类不重写 = 0 影响 | D2.A |
| **元属性管道**：现 `set_attr` 直接 clamp，无法插入"先累计再结算"语义 | 在 HealthSet 内拦截 `damage`/`healing` 字段写入 → 走 `_post_apply_effect` 反应 | D2.A |
| **SetByCaller 缺位**：`AttributeModifier.magnitude` 是 float 字面量 | `AttributeModifier` 增加 `magnitude_source: enum {LITERAL, SET_BY_CALLER}` + `set_by_caller_tag: StringName`；ASC 增加 `apply_effect_spec(spec)` 重载，spec 携带 `set_by_caller_data: Dictionary[StringName, float]` | D2.A |
| **HitDamageResolver 已是单点入口**：所有伤害都走它，替换风险低 | D2.D 用 `DamagePipeline.compute_and_apply` **完全替换** `HitDamageResolver._resolve` 内部，对外 API 不变（`HitDamageResolver` 保留为薄壳） | D2.D |
| **WeaponInstance 未实现**：02 文档 §4 把"大招池"挂武器实例 | D2.C 阶段**仅落地切换池 + 玩家级单池**作为兼容；大招池预留接口空跑（`func get_current_main_ult_energy() -> 0.0`），D4 时填实 | D2.C |
| **Boss / 普通敌人是否挂 PrimaryAttributeSet**：02 文档 §1.2 明确**只挂 HealthSet+CombatSet**；当前 Slime/Boss 共用 CharacterAttributeSet | D2.B 拆分时，Slime/Boss 的 ASC 只挂 HealthSet+CombatSet；玩家三套全挂；老的 `CharacterAttributeSet` 标记 `@deprecated` 但保留兼容 1 个版本 | D2.B |
| **AttributeGrowthTable 字段名变更**：当前是 `health/attack/defense/move_speed`；目标是 `health_max / attack_base / armor_base / move_speed_mul` | D2.B 改 `Growth_*.tres` + `AttributeResolver`；M6 路径不变，仅字段名映射 | D2.B |
| **CombatStateService 与 02 文档 §2.GE_CombatActive 关系**：HUD 已有 InCombat 概念（HUD Phase 2 接过），是否复用？ | D2.D 调研后决定：若 HUD 已有 `EventBus.combat_state_changed`，则 CombatStateService 复用同一信号；不重复造轮子 | D2.D 前置调研 |
| **HUD 升级**：3 套 27 字段 vs HUD 当前显示的 `health/mana`；技能槽 / 飘字接 `damage_dealt_v2` 含 `is_perfect_block` | HUD-D 阶段已规划接此（见 06 HUD 路线）；D2.E 验收时与 HUD 联调 | D2.E |
| **存档兼容**：D5 RunSnapshot 字段必须包含新 27 属性 | D2 里**只产新字段写法**，序列化由 D5 接管；D2.E 验收清单加一行"字段名锁定，不允许后续改名" | D2.E |

---

## 1. 阶段划分（D2.A → D2.E，10.2 工作日）

```
D2.A (2.7d) GAS 基建升级 + AbilityTask 轻量钩子 + CueManager
   │  AttributeSet 钩子 + AttributeModifier SetByCaller + ASC apply_effect_spec
   │  Ability._tick / wait_event 助手（替代 Lyra AbilityTask 体系，覆盖 Timeline 表达不了的 5%）
   │  CueManager + CueBinding 注册表 + Tag 父匹配路由（收编 6 路 EventBus 订阅）
   ▼
D2.B (2.0d) 三套 AttributeSet 拆分 + 数据迁移
   │  HealthSet / PrimaryAttributeSet / CombatSet + Growth_*.tres 字段映射 + Slime/Boss/Player 装配重排
   ▼
D2.C (1.5d) 9 GE + 8 步初始化 + 能量切换池
   │  9 个 .tres GE + BaseCharacter._wire_components 8 步 + EnergyComponent.switch_energy
   ▼
D2.D (2.5d) DamagePipeline 13 步 + 替换旧公式 + 格挡耐久
   │  Pipeline 静态类 + HitDamageResolver 改写 + BlockComponent + CombatStateService
   │  DamagePipeline 第 13 步直接发 cue_manager.execute_cue(...)（取代散点 EventBus 调用）
   ▼
D2.E (1.5d) 飘字 / HUD 联调 / 验收回归
   │  damage_dealt_v2 含 is_block/is_perfect_block + ShowDebug 27 属性 + 数据热改回归
```

---

## 2. D2.A · GAS 基建升级 + AbilityTask 轻量钩子 + CueManager（2.7d）

**目标**：把"3 套 AttributeSet + 13 步管线 + SetByCaller"所需的基础设施加到现有 GAS 里，**不引入业务回归**；同时落地两项 Lyra 借鉴而来的轻量化基建：
- **AbilityTask 轻量钩子**：仅 `_tick(asc, delta)` 虚方法 + `wait_event(asc, sig, timeout)` 助手，覆盖蓄力 / 完美格挡判定 / 等待 GameplayEvent 等 SkillTimeline 表达不了的 5% 场景，**不引入完整 Lyra Task 体系**
- **CueManager 注册表**：以 Cue Tag → CueBinding 的方式收编当前散落在 6 处的 EventBus 表现层订阅（sfx/vfx/shake/hit_stop 等），统一 One-Shot / Looping 两类 cue 生命周期；**与现有 EventBus 信号通道并存兼容**，新功能首选走 CueManager

### 2.1 GAS 基建（1.5d）

#### 2.1.1 文件级动作

| 文件 | 动作 | 要点 |
|---|---|---|
| `Script/GAS/AttributeSet.gd` | 改 | 1) `set_attr` 末尾加 `_post_apply_effect(attr_name, old, new)` 虚钩子调用；<br>2) `set_attr` 写值前调 `_pre_change_<attr_name>(value) -> float` 钩子（用 `call(method)` + `has_method` 探测，不强制子类实现）；<br>3) 新增 `func get_owner_asc() -> Node`（返回 `owner_node` 关联的 ASC 节点） |
| `Script/GAS/AttributeModifier.gd` | 改 | 1) 新增 `enum MagnitudeSource { LITERAL, SET_BY_CALLER }`；2) 新增 `@export var magnitude_source: MagnitudeSource = LITERAL` + `@export var set_by_caller_tag: StringName = &""`；3) `apply_to(attr_set, spec=null)` 增加可选 spec 参数，SET_BY_CALLER 时从 spec 取值；4) 默认参数兼容老调用 |
| `Script/GAS/GameplayEffectSpec.gd` | **新增** | RefCounted 包装类：`var ge: GameplayEffect`、`var source: Node`、`var target: Node`、`var set_by_caller_data: Dictionary[StringName, float]`；提供 `make(ge_id, source, target)` 静态构造函数（从 ConfigCenter 取 GE） |
| `Script/GAS/AbilitySystemComponent.gd` | 改 | 1) 新增 `apply_effect_spec(spec: GameplayEffectSpec) -> bool`（与 `apply_effect_to` 共存，老 API 不动）；2) `_apply_modifiers` 接收 spec 参数转给 `Modifier.apply_to`；3) 新增 `consume_block(amount: float)` 占位方法（D2.D 实装）；4) `has_tag(t)` / `add_tag(t)` / `remove_tag(t)` 透传 `tags.has_tag/add_tag/remove_tag`，让调用代码更短 |
| `Script/Core/EventBus.gd` | 改 | 新增信号：`signal out_of_health(asc: Node)`；保留旧 `enemy_died` / `player_died` 不变（D2.D 让 HealthSet `_post_apply_effect` 触发 `out_of_health`，业务侧再桥接 `enemy_died`） |

#### 2.1.2 设计要点

- **钩子约定**：用 GDScript 的 `has_method("_pre_change_" + attr)` 反射调用，**不强制每个子类都写**，没写就走 base 行为。这样老的 `CharacterAttributeSet` 0 改动。
- **SetByCaller Tag 命名**：`&"SetByCaller.Damage"` / `&"SetByCaller.Heal"` / `&"SetByCaller.Block.Consume"` 三个先建表，进入 `Data/Tags/GameplayTags.tres`。
- **GameplayEffectSpec 与现有 AttributeModifier 兼容**：`apply_effect_to(target, ge, source)` 内部转换成临时 spec 后转 `apply_effect_spec`；保证 100% 向后兼容。

### 2.2 AbilityTask 轻量钩子（0.2d）

#### 2.2.1 决策背景

Lyra 的 UAbilityTask 体系（`WaitDelay / WaitGameplayEvent / WaitInputPress / PlayMontageAndWait` 等 10+ 子类）在 Dolphin 下**与 SkillTimeline 高度重叠**：

| Lyra Task | Dolphin 现状解决方式 |
|---|---|
| WaitDelay | SkillTimeline 关键帧 time |
| PlayMontageAndWait | AnimationTrack + Ability_TimelineDriven 监听 `skill_timeline_ended` |
| WaitGameplayEvent | EventBus + Ability `connect` |
| SpawnActor + WaitHit | EventTrack `projectile_spawn` + EventBus |
| **WaitInputPress（蓄力 / 再次按键）** | ⚠️ **当前没干净的方案** |
| **WaitTargetData（完美格挡 0.3s 窗口）** | ⚠️ **当前没干净的方案** |

引入完整 Task 体系代价：≈700 行新增基建 + 概念双轨 + Skill Editor 失配 → **不划算**。

#### 2.2.2 落地方案

只给 `Ability` 基类加 2 个钩子，覆盖那 5% 死角：

```gdscript
# Script/GAS/Ability.gd 增量
## 子类可重写：每物理帧由 ASC 调用一次（仅在该 ability 处于 activation 期）。
## 用于"蓄力 / 持续判定"等 SkillTimeline 表达不了的运行时逻辑。
func _tick(_asc: Node, _delta: float) -> void:
    pass

## 助手：等待 EventBus 信号或超时（基于 Timer + 一次性 connect/disconnect）。
## 用法：var data = await ability.wait_event(asc, EventBus.damage_dealt_v2, 2.0)
##       data 为 null 表示超时。
func wait_event(asc: Node, sig: Signal, timeout_sec: float) -> Variant:
    var box := { "result": null }
    var timer := asc.get_tree().create_timer(timeout_sec)
    var on_sig: Callable
    on_sig = func(value):
        box.result = value
        if sig.is_connected(on_sig):
            sig.disconnect(on_sig)
    sig.connect(on_sig)
    await timer.timeout
    if sig.is_connected(on_sig):
        sig.disconnect(on_sig)
    return box.result
```

ASC 改造（一行）：
```gdscript
# AbilitySystemComponent._physics_process 末尾
for ability_id in granted_abilities.keys():
    if tags.has_tag(StringName("ability.activating." + String(ability_id))):
        granted_abilities[ability_id]._tick(self, delta)
```

**收益**：≈30 行代码，覆盖蓄力 / 自定义运行时逻辑 / D2.D 完美格挡 0.3s 窗口判定；与 SkillTimeline 主路径**互不冲突**（Timeline 仍是首选，`_tick` 只是兜底）。

#### 2.2.3 否决项（明确不做）

- ❌ 不做完整 Lyra UAbilityTask 体系（10+ Task 子类 / Latent Action 系统 / Blueprint Async Pin）
- ❌ 不做 Task 网络复制（Demo 单机）
- ❌ 不做 Skill Editor 端的 AbilityTask 可视化（与 Timeline 概念双轨）

### 2.3 CueManager 注册表（0.8d + 0.2d 风险缓冲）

#### 2.3.1 决策背景

当前散点的 EventBus 表现层订阅（M7/M8 时期累积）：

| 信号 | 订阅方 |
|---|---|
| `skill_event_sfx` | AudioManager |
| `skill_event_vfx` | VFXSpawner |
| `skill_event_camera_shake` | CameraRig |
| `skill_event_hit_stop` | HitStopHost |
| `skill_event_projectile` | （M8 后接，未启用） |
| `skill_event_custom` | （未启用） |
| `damage_dealt_v2` | DamagePopupPool / OverheadHealthBarManager / HitFlashController |

**痛点**：
1. 没有**统一注册表**：vfx_id / sfx_id 字符串散落在 Timeline.tres 里
2. 生命周期不统一：one-shot 与 looping cue 走同一信号
3. **Tag 路由能力缺失**：`&"slash_blue"` 无法表达"`Cue.Damage.Fire.Hit` 走火焰击中表现，`Cue.Damage.Fire.*` 通配走通用音效"
4. **D2.D 后会更严重**：13 步管线引入完美格挡 / 暴击 / 破韧 / 吸血 cue → EventBus 进一步膨胀
5. GE 没有表现层接口：buff 视觉无法说"附身期间循环播火焰特效"

#### 2.3.2 文件级动作（Phase 1）

| 文件 | 动作 | 要点 |
|---|---|---|
| `Script/Effects/CueManager.gd` | **新增** | Node 子类，挂 `GameInstance` 子节点（`GameInstance.cue_manager`，**不占 Autoload 名额**）；维护 `_bindings: Dictionary[StringName, CueBinding]`（cue_tag → binding）+ `_active_cues: Dictionary`（持续 cue 实例）；提供 `execute_cue(tag, instigator, payload={})` / `add_active_cue(tag, instigator, payload={})` / `remove_active_cue(tag, instigator)` 三个 API；Tag 父匹配（`Cue.Damage.Fire.Hit` 找不到时退化到 `Cue.Damage.Fire` → `Cue.Damage` → `Cue`）|
| `Script/Effects/CueBinding.gd` | **新增** | Resource 子类；字段：`cue_tag` / `lifetime: enum {ONE_SHOT, LOOPING}` / `sfx_id` / `vfx_scene_path` / `camera_shake: Vector2(intensity, duration)` / `hit_stop_ms` / `custom_handler: GDScript`（高级）；`execute(instigator, payload)` 方法按字段非空依次发对应 EventBus 信号 |
| `Data/Config/CueBindings.tres` | **新增（空表）** | CueBindings Resource：`bindings: Dictionary[StringName, CueBinding]`；首批占位 `&"Cue.Damage.Default.Hit"`（D2.D 配齐数值），其他 cue 空着等 D2.D / D6 填充 |
| `Script/Core/EventBus.gd` | 改 | 新增信号：`signal cue_executed(cue_tag: StringName, instigator: Node, payload: Dictionary)`（仅诊断用，让 rule-keeper 能 grep cue 调用点） |
| `Script/Core/GameInstance.gd` | 改 | `_ready` 末尾 `cue_manager = CueManager.new()` + `add_child(cue_manager)`；公开 `var cue_manager: CueManager` |
| `Script/GAS/GameplayEffect.gd` | 改 | 新增 `@export var cue_tags_while_active: Array[StringName] = []`；`AbilitySystemComponent._attach_active` 末尾遍历调 `cue_manager.add_active_cue(...)`，`_detach_active` 调 `remove_active_cue(...)` |

#### 2.3.3 收编现有 EventBus（向后兼容）

CueManager `_ready` 内同时订阅老的 `skill_event_*` 信号，把它们桥接到新 cue API。这样：
- **老路径**（Timeline EventTrack 直接 emit `skill_event_sfx`）→ 仍然可工作
- **新路径**（D2.D 起 DamagePipeline / GE 走 `cue_manager.execute_cue`）→ 走注册表 + Tag 路由

#### 2.3.4 D2.D 落地后的收益（前置铺垫）

- **DamagePipeline 第 13 步**直接发 `GameInstance.cue_manager.execute_cue(&"Cue.Damage.Default.Hit", attacker, {dealt: dmg, is_crit: true})` 一行；CueManager 自动派发音效 + 震屏 + 飘字 + 闪白
- **GE_Burning_3s** 实装"持续火焰特效"：GE 加 `cue_tags_while_active = [&"Cue.Buff.Burning.Active"]`，ASC `_attach_active` 时 `cue_manager.add_active_cue(...)`，`_detach_active` 时 `remove_active_cue(...)` —— **GE 终于有了表现层接口**
- **完美格挡 buff 持续 5s 银光特效**：同上，挂 `&"Cue.Buff.PerfectBlock.Active"`
- **EventTrack 关键帧**新增 `Kind.CUE_EXECUTE`（D2.D 时加）：payload `{cue_tag: &"Cue.Slash.Light"}`，技能编辑器里改一个 cue_tag 而不是改 sfx_id+vfx_id 两个字段

#### 2.3.5 否决项（明确不做）

- ❌ 不做完整 Lyra UGameplayCueManager（GameplayCueNotify Actor / GCN 子类化 / 异步加载 / 网络复制 ≈ 80% 代码用不上）
- ❌ Phase 1 不做 CueBinding 的 Cue Notify Actor 子类化（CueBinding Resource 直接用 sfx/vfx/shake/hit_stop 字段表达即可）
- ❌ Phase 1 不做编辑器内 Cue 预览（M7.7 PreviewStage 已能预览 vfx/sfx，cue 路由本身不需要）
- ❌ Phase 2（Excel 维护 CueBindings / GCN 子类）放到 D6+ 词条期再做

### 2.4 单测脚本

`Scenes/Debug/d2a_gas_basic_test.gd`（一次性测试场景，验完删除或并入 PreviewStage）：
1. 建一个 ASC + HealthSet（D2.B 完后接通），调 `set_attr(health_damage, 30)` → 触发 `_post_apply_effect` → `health_final` -30，并广播 `attribute_changed`
2. 创建 SetByCaller 模式 GE_DamageInstant（modifier 引用 `&"SetByCaller.Damage"`），spec 填 30 → apply → 同上
3. 创建一个测试 Ability 子类 override `_tick`，激活后看到每帧 print；2 秒后 `finish` 自动停 tick
4. 调 `GameInstance.cue_manager.execute_cue(&"Cue.Test.Beep", null, {})` → CueBindings.tres 填了 sfx_id=&"hit_normal" → 听到一声 hit_normal

### 2.5 验收

- [ ] AttributeSet 钩子加上后，老 6 个 GE 全部回归通过（M2 验收脚本完跑）
- [ ] `apply_effect_spec` 能正确传递 SetByCaller 数值
- [ ] EventBus 新增 `out_of_health` / `cue_executed` 信号在远程场景树可见
- [ ] `Ability._tick` 在激活期内每物理帧调用 1 次；finish 后停止
- [ ] `wait_event` 能正常等到信号 + 超时返回 null
- [ ] `GameInstance.cue_manager.execute_cue(&"Cue.Test.Beep", ...)` 通过注册表查到 binding 并发声
- [ ] CueManager Tag 父匹配：`&"Cue.Damage.Fire.Hit"` 注册表无该 tag 但有 `&"Cue.Damage"`，调 execute_cue 仍能命中默认 binding
- [ ] read_lints 0 Error；MCP `restart` + run_project 启动无 ScriptError

---

## 3. D2.B · 三套 AttributeSet 拆分 + 数据迁移（2.0d）

**目标**：把 1 套 7 字段的 CharacterAttributeSet 拆为 3 套 27 字段；同步迁移 AttributeGrowthTable 字段名 / Slime / Boss / Player 装配。

### 3.1 文件级动作

#### 新增 3 个 AttributeSet 子类

| 文件 | 字段（与 02 文档 §1 对齐） |
|---|---|
| `Script/GAS/Attributes/HealthSet.gd` | `health_final / health_max / health_healing / health_damage / stamina_current / stamina_max`；实现 `_post_apply_effect` 元属性管道；玩家额外加 5 个 block 字段（按文档 §1.5）—— **本阶段先把 block 字段加在 HealthSet**（避免又拆一个 BlockSet），D2.D 时 BlockComponent 直接读这套字段 |
| `Script/GAS/Attributes/PrimaryAttributeSet.gd` | 7 组共 21 字段：主属性 4 / 攻击 4 / 法术 2 / 防御 3 / 暴击 2 / 增减伤 2 / 能量速度 4 |
| `Script/GAS/Attributes/CombatSet.gd` | `base_damage / base_heal`（SetByCaller 入口） |

#### 弃用旧类（不删）

`Script/GAS/Attributes/CharacterAttributeSet.gd`：
- 顶部加注释 `## @deprecated D2.B; 仅保留作存档兼容/回滚锚点`
- 类体保持原样不动

#### 修改 ASC，支持多 AttributeSet

```gdscript
# AbilitySystemComponent.gd 改造（向后兼容）
@export var attribute_set: AttributeSet = null              # 老接口，保留
@export var attribute_sets: Array[AttributeSet] = []        # 新接口，多套并存

func _ready() -> void:
    # 老接口兼容：attribute_set 不为空时压入数组
    if attribute_set != null and not attribute_sets.has(attribute_set):
        attribute_sets.insert(0, attribute_set)
    # 复制 + 设置 owner_node
    for i in range(attribute_sets.size()):
        var dup := attribute_sets[i].duplicate(true) as AttributeSet
        dup.owner_node = get_parent()
        attribute_sets[i] = dup
    if attribute_sets.size() > 0:
        attribute_set = attribute_sets[0]    # 老引用指向第一份，保兼容

func get_attribute(attr_name: StringName) -> float:
    for set in attribute_sets:
        if set._has_attribute(attr_name):
            return set.get_attr(attr_name)
    return 0.0

func set_attribute(attr_name: StringName, value: float) -> float:
    for set in attribute_sets:
        if set._has_attribute(attr_name):
            return set.set_attr(attr_name, value)
    GameLogger.error("GAS", "no AttributeSet has attr %s" % attr_name)
    return 0.0
```

#### Growth 表字段映射

`Data/Config/AttributeGrowthTables/Growth_Slime.tres` / `Growth_Boss.tres`：

| 旧字段 | 新字段 | 备注 |
|---|---|---|
| `health` | `health_max` | 字段重命名 |
| `attack` | `attack_base` | 玩家用；敌人也用同字段，由 DamagePipeline 在没有 PrimaryAttributeSet 时降级取 `attack_base` |
| `defense` | `armor_base` | |
| `move_speed` | （独立字段，不属于三套 Set，保留为 BaseCharacter 内部）| 因为 02 文档 §1.2 的 `move_speed_mul` 是百分比修饰，原始值在角色组件里 |

`Script/Data/AttributeResolver.gd` 解析改造：把 `health` 自动重定向到 `health_max`，向下兼容旧 .tres 1 个版本（grace period）。

#### 玩家 / Slime / Boss 装配

| 角色 | 挂哪些 Set |
|---|---|
| Player | HealthSet + PrimaryAttributeSet + CombatSet |
| Slime | HealthSet + CombatSet（**不挂 Primary**，简化）|
| Boss | HealthSet + CombatSet（同上） |

`Scenes/Characters/*.tscn` 的 ASC 节点 inspector 改 `attribute_sets` 数组拖入对应 .tres。

#### 占位 Default tres

| 文件 | 用途 |
|---|---|
| `Data/Attributes/DefaultPlayer_HealthSet.tres` | 玩家初始 HealthSet |
| `Data/Attributes/DefaultPlayer_PrimaryAttributeSet.tres` | 玩家初始 21 主衍生属性 |
| `Data/Attributes/DefaultPlayer_CombatSet.tres` | 玩家 CombatSet（base_damage=0 base_heal=0） |
| `Data/Attributes/DefaultEnemy_HealthSet.tres` | 敌人共用 HealthSet 模板（Slime/Boss 用 ConfigCenter resolve 覆盖） |
| `Data/Attributes/DefaultEnemy_CombatSet.tres` | 敌人共用 CombatSet 模板 |

> **占位规则**：参照 R-DATA-01，所有数值仅作编辑器入口，实际值由 ConfigCenter 路径覆盖。

### 3.2 风险与回退

- **R1**：Slime/Boss 不挂 PrimaryAttributeSet，伤害公式取 attack 时找不到 → DamagePipeline 在 D2.D 内做"找不到字段返回 0.0"的降级，并 push_warning。
- **R2**：HUD 当前订阅 `attribute_changed(owner, &"health", ...)` → 改为 `health_final` 后 HUD 失效 → 本阶段 **同时改 HUD AttributeProvider**（`Script/UI/Providers/AttributeProvider.gd`），把 `health` 字段改为 `health_final`；其它 widget 通过 Provider 间接访问，0 改动。
- **回退锚点**：本阶段开工前打 git tag `pre-d2b`，失败时 `git reset --hard pre-d2b`。

### 3.3 验收

- [ ] 玩家 ASC 远程树看到 3 个 AttributeSet 子节点（或 attribute_sets 数组 3 项）
- [ ] Slime/Boss ASC 看到 2 个 Set
- [ ] `ASC.get_attribute(&"health_final")` 与 `&"attack_base"` 都能正确返回
- [ ] M3 普攻 / M4 战斗回归通过（伤害数值与 D2.A 前一致；DamagePipeline 还没接，所以走 1 步公式）
- [ ] HUD 血条正常刷新
- [ ] read_lints 0 Error；MCP run_project 0 ScriptError

---

## 4. D2.C · 9 GE + 8 步初始化 + 能量切换池（1.5d）

**目标**：建立 9 个核心 GE 资源 + 玩家初始化 8 步顺序 + EnergyComponent 切换池雏形（不接命中）。

### 4.1 9 个核心 GE（按 02 文档 §2）

`Data/Effects/`：

| 文件 | duration_type | Modifier | granted_tags | 备注 |
|---|---|---|---|---|
| `GE_Init_PrimaryAttributes.tres` | INSTANT | 11 个 LITERAL modifier 写主属性初值 | — | 实际值由 spawn 时 ConfigCenter resolve 覆盖 |
| `GE_Init_DerivedAttributes.tres` | DURATION（infinite=duration<=0）| 7 个 modifier 写衍生公式（attack_final = attack_base + attack_bonus）| — | 由于现有 AttributeModifier 只支持 add/multiply/override，"线性公式"通过两步 Modifier 表达：先 override base, 再 multiply mul |
| `GE_HealthInit_Full.tres` | INSTANT | health_final ← health_max | — | spawn / respawn / checkpoint |
| `GE_HealthRegen.tres` | PERIODIC（period=1.0, duration=-1）| health_healing += X | — | 战斗中由 application_blocked_tags=[State.Combat.Active] 屏蔽 |
| `GE_StaminaRegen.tres` | PERIODIC（period=0.5, duration=-1）| stamina_current += X | — | |
| `GE_BlockRegen.tres` | PERIODIC（period=0.2, duration=-1）| block_current += X | — | application_blocked_tags=[State.Combat.Active] |
| `GE_BlockState.tres` | DURATION（按 D 键时长）| — | granted_tags=[Combat.Block.Active] | BlockComponent.start_block() apply / stop_block() remove |
| `GE_PerfectBlockBuff.tres` | DURATION（5s） | dmg_inc_mul +0.5 | granted_tags=[Combat.Buff.PerfectBlock] | |
| `GE_CombatActive.tres` | DURATION（5s）| — | granted_tags=[State.Combat.Active] | CombatStateService 维护 |

> **注意**：当前 `AttributeModifier` 不支持"读其他属性当 magnitude"（即 `attribute_based_source`）。`GE_Init_DerivedAttributes` 的"`attack_final = attack_base + attack_bonus`"在本阶段**先用 Override 写死 attack_base 当 attack_final**（暂不做衍生），D2.D 把"衍生"逻辑放到 DamagePipeline 入口动态计算。等 D6 / D7 时再考虑加 `AttributeBasedSource` 让 GE 自身能引用其他属性。**这是简化项，详见 §7 风险登记**。

### 4.2 8 步初始化顺序

`Script/Character/BaseCharacter.gd` 的 `_wire_components` 末尾加：

```gdscript
func _initialize_attributes() -> void:
    if not _is_player(): return
    var asc: AbilitySystemComponent = $ASC
    # 1. 应用 GE_Init_PrimaryAttributes（写 strength/dexterity/... 初值）
    asc.apply_effect_to(asc, ConfigCenter.get_ge(&"GE_Init_PrimaryAttributes"), self)
    # 2. ConfigCenter resolve 角色等级 → override 主属性（D2.B 已做）
    _apply_growth_overrides()
    # 3. 应用 GE_Init_DerivedAttributes（写 attack_final 等衍生）
    asc.apply_effect_to(asc, ConfigCenter.get_ge(&"GE_Init_DerivedAttributes"), self)
    # 4. 装备覆盖词条（D4 时填实，本阶段空跑）
    # 5. 应用 GE_HealthInit_Full（health_final = health_max）
    asc.apply_effect_to(asc, ConfigCenter.get_ge(&"GE_HealthInit_Full"), self)
    # 6. 挂 GE_HealthRegen / GE_StaminaRegen / GE_BlockRegen（infinite）
    for ge_id in [&"GE_HealthRegen", &"GE_StaminaRegen", &"GE_BlockRegen"]:
        asc.apply_effect_to(asc, ConfigCenter.get_ge(ge_id), self)
    # 7. 注册到 CombatStateService（D2.D 再做）
    # 8. 完成
    EventBus.character_initialized.emit(self)
```

### 4.3 EnergyComponent 切换池

`Script/Character/Components/EnergyComponent.gd`（**新增**）：

```gdscript
class_name EnergyComponent
extends Node

@export var switch_energy_max: float = 50.0
var switch_energy: float = 0.0

func add_switch_energy(amount: float) -> void:
    switch_energy = clampf(switch_energy + amount, 0.0, switch_energy_max)
    EventBus.switch_energy_changed.emit(get_parent(), switch_energy, switch_energy_max)

func get_current_main_ult_energy() -> float:
    # D4 武器实例化后改读 EquipmentComponent.main_hand.current_ult_energy
    return 0.0

# D2.D 接 EventBus.damage_dealt_v2 后实装
func _on_damage_dealt(payload: Dictionary) -> void:
    pass
```

挂在 Player.tscn 上，初始数值由 `Data/Config/EnergyComponentDefault.tres` 配置（@export 字段直接 inspector 填）。

### 4.4 验收

- [ ] 9 个 GE .tres 创建完成、ConfigCenter `get_ge(id)` API 可拿
- [ ] Player spawn 时 8 步顺序执行，GameLogger 打印每步
- [ ] EnergyComponent 挂上后 `add_switch_energy(10)` 广播 `switch_energy_changed` 信号
- [ ] read_lints 0 Error；MCP run_project 0 ScriptError

---

## 5. D2.D · DamagePipeline 13 步 + 替换旧公式 + 格挡耐久（2.5d）

**目标**：13 步公式落地、HitDamageResolver 完全替换、格挡耐久 + CombatStateService 实装。

### 5.1 文件级动作

#### 新增 DamagePipeline

`Script/GAS/DamagePipeline.gd`（按 02 文档 §3 全文实现）：

```gdscript
class_name DamagePipeline

const _LOG_CH := "Damage"

static func compute_and_apply(
    attacker: Node,
    target: Node,
    base_damage: float,
    damage_tags: Array[StringName],
    is_skill: bool = false,
    forced_crit: bool = false
) -> Dictionary:
    # ... 13 步全文实现，参照 02 文档 §3 ...
    # 用 attacker.asc.get_attribute(&"attack_final") 等访问字段
    # 找不到字段（敌人无 PrimaryAttributeSet）时降级为 0 并 push_warning
```

**关键实现点**：
- **第 1 步暴击**：用 `randf()`，与现有 HitDamageResolver 的 RNG 行为一致
- **第 6/7 步完美格挡 buff / 完美格挡窗口**：buff 标签查 ASC.tags，窗口查 `target.is_perfect_block_window()`（BlockComponent 提供）
- **第 8 步普通格挡**：消耗格挡耐久通过 `target.asc.consume_block(amount)`
- **第 10 步施加伤害**：构造 `GameplayEffectSpec` from `&"GE_DamageInstant"`，`spec.set_by_caller_data[&"SetByCaller.Damage"] = dmg`，调 `target.asc.apply_effect_spec(spec)`，HealthSet `_post_apply_effect` 落值
- **第 13 步广播飘字**：`EventBus.damage_dealt_v2.emit({...})` —— 复用 M8 已有的 `damage_dealt_v2` 信号

#### 替换 HitDamageResolver

`Script/SkillSystem/HitDamageResolver.gd` 改为薄壳：

```gdscript
class_name HitDamageResolver

static func resolve_hit(caster: Node, target: Node, damage_node_index: int, skill_id: StringName) -> void:
    var node: DamageNode = ConfigCenter.get_damage_node(skill_id, damage_node_index)
    if node == null:
        push_warning("HitDamageResolver: no DamageNode for %s[%d]" % [skill_id, damage_node_index])
        return
    var base: float = node.damage_multiplier  # 02 文档 §3 第 0 步：base_damage 已是"技能注入的基础伤害（已含武器倍率）"，这里取 multiplier 当 base
    var tags: Array[StringName] = [node.damage_type]
    DamagePipeline.compute_and_apply(caster, target, base, tags, true, false)
```

> **重要**：现有 `HitDamageResolver` 的"caster.attack × multiplier + flat"逻辑**完全删除**，由 DamagePipeline 取 `attack_final` 自己算。
>
> ~~`extra_flat_damage` 字段保留在 DamageNode 但 D2.D 阶段先不用，D6 武器词条阶段再启用为"飞行属性"。~~
> **2026-05-23 决策变更**：`extra_flat_damage` 字段从 `DamageNode` **彻底移除**（避免长期闲置成为配置陷阱）；同时 `CombatBalanceConfig.attack_to_damage_factor` 全局换算系数也移除，伤害起点公式简化为 `dmg = max(atk, 1) × damage_multiplier`，`damage_multiplier` 直接当作**技能倍率**，由 DamageNode 配置。后续武器系统接入时若需要"固定额外伤害"，作为武器属性而非技能字段。

#### 新增 BlockComponent

`Script/Character/Components/BlockComponent.gd`（**新增**）：

```gdscript
class_name BlockComponent
extends Node

const PERFECT_BLOCK_WINDOW: float = 0.3

var _block_pressed_at: float = -1.0
var _is_blocking: bool = false

func start_block() -> void:
    _block_pressed_at = Time.get_ticks_msec() / 1000.0
    _is_blocking = true
    var asc := get_parent().asc
    asc.apply_effect_to(asc, ConfigCenter.get_ge(&"GE_BlockState"), get_parent())

func stop_block() -> void:
    _is_blocking = false
    var asc := get_parent().asc
    asc.tags.remove_tag(&"Combat.Block.Active")  # 直接清，不等 GE_BlockState 自然过期

func is_perfect_block_window() -> bool:
    if not _is_blocking: return false
    return (Time.get_ticks_msec() / 1000.0 - _block_pressed_at) <= PERFECT_BLOCK_WINDOW

func trigger_perfect_block_buff() -> void:
    var asc := get_parent().asc
    asc.apply_effect_to(asc, ConfigCenter.get_ge(&"GE_PerfectBlockBuff"), get_parent())
    EventBus.block_perfect_triggered.emit(get_parent())
```

`AbilitySystemComponent.consume_block(amount)` 实装：
```gdscript
func consume_block(amount: float) -> void:
    var current := get_attribute(&"block_current")
    var new_val := maxf(current - amount, 0.0)
    set_attribute(&"block_current", new_val)
    if new_val <= 0.0:
        # 破防硬直 1.2s
        tags.add_tag(&"Combat.Block.Broken")
        get_tree().create_timer(1.2).timeout.connect(func(): tags.remove_tag(&"Combat.Block.Broken"))
        # 强制松开 D 键
        var bc: BlockComponent = get_parent().get_node_or_null(^"BlockComponent")
        if bc: bc.stop_block()
```

#### 新增 CombatStateService

`Script/Combat/CombatStateService.gd`（**新增**，挂 GameInstance 子节点）：

```gdscript
class_name CombatStateService
extends Node

const COMBAT_TIMEOUT: float = 5.0
const COMBAT_RADIUS: float = 8.0  # 8m

var _last_combat_event_at: float = -1.0
var _is_in_combat: bool = false

func _ready() -> void:
    EventBus.damage_dealt_v2.connect(_on_damage)
    set_physics_process(true)

func _physics_process(_delta: float) -> void:
    if _is_in_combat:
        var elapsed := Time.get_ticks_msec() / 1000.0 - _last_combat_event_at
        if elapsed > COMBAT_TIMEOUT and not _has_enemies_nearby():
            _set_combat(false)

func _on_damage(payload: Dictionary) -> void:
    _last_combat_event_at = Time.get_ticks_msec() / 1000.0
    _set_combat(true)

func _set_combat(active: bool) -> void:
    if _is_in_combat == active: return
    _is_in_combat = active
    EventBus.combat_state_changed.emit(active)

func _has_enemies_nearby() -> bool:
    var player := get_tree().get_first_node_in_group(&"player")
    if player == null: return false
    for enemy in get_tree().get_nodes_in_group(&"enemies"):
        if player.global_position.distance_to(enemy.global_position) < COMBAT_RADIUS:
            return true
    return false
```

> **复用决策**：HUD 已有 `EventBus.combat_state_changed` 信号（HUD Phase 2 接的）。D2.D 调研后**复用同一信号**，CombatStateService 是该信号的**唯一发射源**，HUD-AttackTimer 等订阅方不动。

### 5.2 EnergyComponent 接通命中

`EnergyComponent.gd` 增加：

```gdscript
func _ready() -> void:
    EventBus.damage_dealt_v2.connect(_on_damage_dealt)

func _on_damage_dealt(payload: Dictionary) -> void:
    if payload.attacker != get_parent(): return
    var gain: float = ConfigCenter.get_energy_gain_for(payload)  # 查 EnergyGainTable.tres，本阶段先返回固定 5.0
    var mul := get_parent().asc.get_attribute(&"energy_gain_mul")
    add_switch_energy(_prob_round(gain * (1.0 + mul)))

static func _prob_round(x: float) -> int:
    var floor_v := floori(x)
    return floor_v + (1 if randf() < (x - floor_v) else 0)
```

`Data/Config/EnergyGainTable.tres`（**新增**）：占位字段挂起数值（02 文档 §4.2 完整 31 行表 D6 时再录），本阶段只填 `default: 5.0`。

### 5.3 验收

- [ ] 玩家普攻 Slime → DamagePipeline 13 步全跑通；GameLogger 打印每步中间值
- [ ] 玩家 ASC 加 `crit_chance=1.0` → 必暴击；伤害 ×1.5
- [ ] Slime ASC 加 `armor_base=100` → 玩家伤害减半（按 dmg×100/(100+100)=0.5）
- [ ] 玩家手动 `BlockComponent.start_block()` + 按下 0.3s 内被击 → 0 伤害 + 自身获得 PerfectBlock buff 5s
- [ ] 持续按 D 键 + 1s 后被击 → 伤害 ×0.4 落地 + block_current 减少
- [ ] block_current 耗尽 → 1.2s 内 ASC 持有 Combat.Block.Broken tag 且无法再触发格挡
- [ ] CombatStateService：玩家与 Slime 互打时 `combat_state_changed(true)` 广播；脱离 5s 后 `combat_state_changed(false)`
- [ ] EnergyComponent：普攻命中后 `switch_energy` 增加，HUD 切换池显示更新（如 HUD 已加该 widget）

---

## 6. D2.E · 飘字 / HUD 联调 / 验收回归（1.5d）

**目标**：HUD 完全适配新 27 字段 + 飘字 4 样式 + ShowDebug 全字段输出 + 数据热改回归。

### 6.1 飘字 4 样式

`Script/UI/DamagePopup.gd` 已存在（M8 实装）。改造点：
- `damage_dealt_v2` payload 加 `is_block` / `is_perfect_block` 字段（DamagePipeline 第 13 步已带）
- DamagePopup 按 4 状态选样式：
  - `is_crit=true` → 金色 + 加大字号
  - `is_perfect_block=true` → 银色"完美格挡"文字（不显数值）
  - `is_block=true` → 灰色 + 数值减半显示
  - 默认 → 白色普攻

### 6.2 ShowDebug 27 属性

`Script/Debug/AttributeDebugWidget.gd`（**新增**）：
- 按 F1 键打开
- 列出当前选中角色（默认玩家）的 3 套 AttributeSet 全部 27 字段
- 实时刷新（订阅 `EventBus.attribute_changed`）
- 文字布局：HealthSet (6) / PrimaryAttributeSet (21) 分组显示

### 6.3 数据热改回归

- 改 `Data/Effects/GE_HealthRegen.tres` 的 modifier 数值 → 启动后 1s 玩家回血量改变
- 改 `Data/Config/EnergyGainTable.tres` 的 default → 命中后 switch_energy 增加量改变
- **`EnergyGainTable.tres` 改一个数值，不重启工程能直接生效**（Resource 热改特性，只是不会主动重新加载，需触发一次 `ConfigCenter.reload_all()` 或重新 spawn 角色）

### 6.4 验收清单（D2 全里程碑）

> 完整对应 02 文档 §6 验收清单。

- [ ] HealthSet / PrimaryAttributeSet / CombatSet 三个 .gd 编译通过；F1 ShowDebug 一行能列全 27 属性
- [ ] 9 个 GE 资源完整可加载，初始化 8 步走完后玩家所有衍生属性（attack_final / armor_final / spell_power_final）正确
- [ ] 玩家普攻 Slime 触发 13 步公式：暴击 → 防穿 → 减伤 → 增伤 → 完美格挡判定 → 普通格挡 → 应用扣血 → 吸血 → 破韧 → 飘字
- [ ] Slime 完美格挡判定窗口内挨打 → 0 伤害 + 自身 PerfectBlock buff 5s（**可选**：仅在 Slime AI 接 Block 后才能验，否则跳过）
- [ ] CombatStateService：玩家与 Slime 互打时 `combat_state_changed(true)`；脱离 5s 且 8m 内无敌人后 `combat_state_changed(false)`
- [ ] EnergyComponent：普攻命中后 `switch_energy` 按配置加值；带 `energy_gain_mul=1.0` 词条时取整概率正确（5 次命中 4.5×2 = 9 期望）
- [ ] 飘字四样式可视区分（白/金/灰/银）
- [ ] `Data/Config/EnergyGainTable.tres` / `Data/Effects/GE_HealthRegen.tres` 改值不重启工程，触发一次 `ConfigCenter.reload_all()` 后生效
- [ ] M3 / M4 / M5 全部回归通过（普攻 / AI / 拾取 / 装备 / Boss 阶段）
- [ ] read_lints 0 Error；MCP run_project 0 ScriptError；编辑器 0 Parse Error

---

## 7. 风险登记

| # | 风险 | 触发概率 | 影响 | 缓解 |
|---|---|---|---|---|
| R-D2-01 | `GE_Init_DerivedAttributes` 用现有 AttributeModifier 表达"`a = b + c`"很别扭，最终可能写得难看 | 高 | 中 | 暂用 Override 写死 → DamagePipeline 入口动态计算衍生 → D6 时再升级 AttributeModifier 加 `AttributeBasedSource` |
| R-D2-02 | Slime / Boss 不挂 PrimaryAttributeSet，DamagePipeline 取 `crit_chance` 等返回 0.0 → 敌人对玩家**永不暴击**、**无防穿** | 高 | 低 | 接受 D2 阶段敌人无 RPG 词条；D6 / D7 加敌人 PrimaryAttributeSet 子集（仅 attack_base/armor_base/crit_chance） |
| R-D2-03 | EnergyGainTable 数值挂起，D2 验收时 `switch_energy` 的"5/秒"完全是占位 | 高 | 低 | D6 武器词条阶段一并补 31 行完整 EnergyGainTable |
| R-D2-04 | HUD AttributeProvider 改字段会牵动多个 widget；可能有遗漏 | 中 | 中 | D2.B 落地后跑 grep `&"health"` 全文检查；HUD 联调阶段加专项回归 |
| R-D2-05 | D5 SaveSystem 还没做，D2 新增 27 字段的存档格式没人接 | 中 | 低 | D2.E 验收清单加一行"字段名锁定"；D5 时直接序列化 attribute_sets 数组 |
| R-D2-06 | M8 飘字管线已重，再加 4 样式可能导致 DamagePopup 节点变胖 | 低 | 低 | DamagePopup 内部按 `payload.is_*` 分支即可；不拆 4 个不同 Popup 类 |
| R-D2-07 | BlockComponent 按 D 键事件源在 InputComponent；当前 InputComponent 没绑 `combat_block` action | 中 | 低 | D2.D 同时在 `project.godot` InputMap 加 `combat_block` action（默认 D 键），InputComponent 加监听 → BlockComponent.start_block / stop_block |
| R-D2-08 | CueManager Phase 1 注册表 `CueBindings.tres` 大部分 cue 没有视觉/音效资源；buff 类 active cue 在 D2.D 验收时会"沉默"（execute 命中 binding 但 sfx_id/vfx_scene_path 都为空，无表现） | 高 | 低 | 接受现状；CueManager 有 binding 即视为合规；D6 词条阶段补美术资源时一并填 binding 字段；D2.E 验收清单不强制可见效果，仅要求"调用链通" |
| R-D2-09 | `Ability._tick` + `wait_event` 助手与未来引入的 SkillTimeline 派生功能（如蓄力轨）可能职责重叠 | 低 | 低 | 在 Ability.gd 注释里明确"`_tick` 仅用于 SkillTimeline 表达不了的运行时分支；首选还是 SkillTimeline + EventTrack" |

---

## 8. 与其它里程碑的衔接

- **D1 输入映射**：本里程碑会**新增 1 个 InputAction**：`combat_block`（默认 D 键）；其余 14 个 D1 action 预留给后续，本阶段不动
- **D4 武器系统**：02 文档 §4 的"大招池挂武器"接口本阶段空跑（`get_current_main_ult_energy() -> 0.0`），D4 时填实
- **D5 存档系统**：D2.E 锁定 27 字段名 + 9 GE id；D5 序列化时直接走 `attribute_sets[i].duplicate(true)` 路径
- **D6 Boon 词条**：本阶段不实施 `attack_bonus` / `dmg_inc_mul` 等的 GE 注入路径；D6 时通过 `apply_effect_to(self, GE_Boon_*)` 套到玩家
- **HUD 系统**（HUD-D 阶段）：HUD AttributeProvider 升级、飘字 4 样式适配、ShowDebug 27 属性面板可作为 HUD-D 的子任务；本里程碑产出"接口对齐"，HUD 团队按需消化

---

## 9. 工时合计

| 阶段 | 工时 | 实际负责人 |
|---|---|---|
| D2.A · GAS 基建升级 + AbilityTask 轻量钩子 + CueManager | 2.7 d | 主 agent / GAS 子专家 |
| D2.B · 三套 AttributeSet + 数据迁移 | 2.0 d | 主 agent |
| D2.C · 9 GE + 8 步初始化 + 切换池 | 1.5 d | 主 agent |
| D2.D · DamagePipeline 13 步 + 格挡 + CombatStateService | 2.5 d | 主 agent |
| D2.E · 飘字 / HUD / 验收回归 | 1.5 d | 主 agent + HUD 子专家 |
| **合计** | **10.2 d** | |

> 工期参考：02 文档 §5 原列 6.7 d，本计划补充了"现状差距弥补（1.5 d）"+ "数据迁移与回归（0.8 d）"+ "AbilityTask + CueManager 基建（1.2 d）" ≈ +3.5 d。

---

## 10. 启动 checklist

开 D2.A 前必须确认：

- [ ] 用户确认本计划方案
- [ ] 打 git tag `pre-d2`（整个 D2 的回退锚点）
- [ ] 当前主分支 `git status` clean
- [ ] M5 / M9 验收已闭环（D2 不能依赖未验收的功能）
- [ ] HUD 当前完整可用（D2.B 改 AttributeProvider 时若 HUD 已坏会无法验证）
- [ ] 用户决策：是否在 D2 阶段就做 R-DATA-01 字段命名规则更新（旧 `health` → 新 `health_final` 写入全局规则文档）

---

## 11. 变更日志

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-05-21 | 首版规划：基于 02 文档锁定的设计 + Dolphin 当前 GAS 现状（M9 收尾）做 5 阶段任务分解；明确差距、风险与回退锚点；预估 9 工作日 |
| v0.2 | 2026-05-21 | D2.A 段扩展：评估 Lyra AbilityTask / GameplayCueManager 后决定**轻量化纳入**——AbilityTask 退化为 Ability 基类的 `_tick(asc, delta)` + `wait_event(asc, sig, timeout)` 双钩子（覆盖蓄力/0.3s 完美格挡窗口/等待 GameplayEvent）；GameplayCueManager 退化为 `CueManager + CueBinding 注册表 + Tag 父匹配路由`，挂 GameInstance 子节点不占 Autoload 名额，新增 GE.cue_tags_while_active 字段让 buff 持续 cue 自动管理。明确 5 项否决项（不做 Lyra 完整 Task 体系 / 不做 GCN Notify Actor / 不做网络复制 / 不做异步加载 / 不做编辑器双轨）。新增风险 R-D2-08（CueBindings 资源沉默）/ R-D2-09（Tick 与 Timeline 概念潜在重叠）。D2.A 工时 1.5d → 2.7d；总工期 9.0d → 10.2d |
