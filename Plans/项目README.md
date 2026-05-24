# Dolphin 项目 · 总体说明（新人入项目 Day 1 必读）

> **生成日期**：2026-05-21
> **目标读者**：从零进入项目的新人 / 新合作者 / 跨 agent 接手者
> **读完后你应当知道**：项目做了什么 / 怎么跑起来 / 整体架构是怎样的 / 未来要往哪里走

---

## 0. 一句话项目定位

> **Dolphin** —— Godot 4.6 引擎下的 **HD-2D 俯视角 ARPG + Boss Rush** Demo 工程；把 Unreal/Lyra 的核心架构思想（GAS / Experience / GameFeature / ModularActor / CommonUI / IndicatorSystem）按 Godot 习惯重写一遍，作为后续完整 ARPG 的起步地基。

| 维度 | 选型 |
|---|---|
| 引擎 | Godot 4.6（Forward+） |
| 视角 | 俯视角 HD-2D（Sprite3D billboard + 3D 几何 + 后处理） |
| 玩法骨架 | 跑图 → 战斗 → Boss 房 → 通关 |
| 战斗模型 | 移植 Lyra GAS：AttributeSet + GameplayEffect + Ability + GameplayTag |
| 数据驱动 | ConfigCenter + .tres / 三期起接 Excel→JSON |
| 编辑器扩展 | 自研 Skill Editor（@tool EditorPlugin，时间轴可视化） + GodotMCP（AI 助手通过 HTTP 操作编辑器） |

---

## 1. 5 分钟跑起来

### 1.1 环境

- **Godot 4.6** 标准版（Forward+ 渲染）
- Windows 10/11；其它平台理论可行未测
- Python 3.11+（仅在 M10 Excel 工具开工后需要）

### 1.2 启动

1. 用 Godot 编辑器打开 `d:/Demos/Godot/Dolphin`（含 `project.godot`）
2. 主场景已设为 `Scenes/Levels/TestArena.tscn`，按 F5 直接跑
3. 控制：
   - **WASD** 移动（XZ 平面，向上对应世界 -Z）
   - **A**（鼠标左键替代）普攻
   - **Q/W/E/R** 技能槽（当前仅 A 槽接通）
   - **Space** 大招
   - **I** 背包 / **Esc** 暂停
   - **R** 重开场景

### 1.3 启动后会看到什么

- 一份 HUD（HP/MP 条 + 6 槽 Hotbar）
- 3 只 Slime（数据驱动，等级 1）
- 紫色发光盒 = Boss 传送门（走过去进 BossRoom）
- 绿色亮盒 = 药水拾取，灰白盒 = 铁剑拾取

### 1.4 如果 Godot 没启动起来

最常见原因：新增 `class_name` 后类缓存未刷新。运行：
```
Tools\godot.bat restart
```
重启编辑器一次即可。详见 §6.4 R-VERIFY-01。

---

## 2. 项目目录速读（新人优先记住的 8 个目录）

```
Dolphin/
├── project.godot              # ★ Godot 入口；含 10 个 Autoload + InputMap
├── Script/                    # ★ 所有业务代码（98 个 .gd，按子系统分目录）
│   ├── Core/                  #   ConfigCenter / EventBus / GameInstance / GameLogger
│   ├── Character/             #   BaseCharacter + 6 个组件
│   ├── GAS/                   #   Lyra GAS 的 Godot 重写
│   ├── SkillSystem/           #   技能时间轴运行时（M7 核心）
│   ├── AI/                    #   状态机 + Boss 阶段机
│   ├── Items/                 #   物品 / 装备 / 拾取 / VFX
│   ├── UI/                    #   HUD 框架 + 9 个 widget + Contracts
│   ├── Camera/Lighting/Audio/Settings/Input/Data/GameFramework/
├── Scenes/                    # ★ 场景文件（角色 / 关卡 / UI / 主入口）
├── Data/                      # ★ 所有可调参数 .tres（44 张），ConfigCenter 加载
├── Content/                   # ★ 美术资源（Sprite / 音频 / 字体）
├── addons/                    # 编辑器插件
│   ├── skill_editor/          # ★ 自研技能时间轴编辑器（底部 Dock）
│   └── godot_mcp/             # AI 助手 HTTP 桥（端口 9180）
├── Tools/                     # 命令行工具（godot.bat / 三期 excel2tres）
└── Plans/                     # ★ 所有设计文档与里程碑计划
    ├── 项目README.md          # 本文档
    ├── 开发计划.md             # 一期 M1-M5
    ├── 二期开发计划.md         # M6-M9
    ├── 三期开发计划.md         # M10-M12（未开工）
    ├── 全局规则.md             # ★ 11 条强约束
    ├── 人工待办_M8M9.md        # 等用户补的资源
    ├── _Inventory/            # ★ 项目盘点台账（9 份）
    └── Dolphin设计/           # 7 篇专题设计稿（HUD / 战斗 / 输入 / 死亡存档）
```

### 2.1 第 1 天必读 5 份文档

| 顺序 | 文档 | 你能学到 |
|---|---|---|
| 1 | **本 `项目README.md`** | 总览（30 分钟） |
| 2 | `Plans/全局规则.md` | 11 条强约束（避坑） |
| 3 | `Plans/_Inventory/01_代码清单.md` | 99 个脚本是什么 |
| 4 | `Plans/_Inventory/04_Autoload现状.md` | 10 个 Autoload 各司其职 |
| 5 | `Plans/_Inventory/05_EventBus信号.md` | 全局信号有哪些 |

---

## 3. 整体架构（一张图入门）

### 3.1 Autoload 层（全局服务，10 项）

```
project.godot [autoload]（按启动顺序）
─────────────────────────────────────────
1. ConfigCenter        ★ 数据中心：加载 13 类 .tres，提供 get_xxx_config()
2. EventBus            ★ 信号枢纽：34 个 signal 集中声明，跨模块通信唯一通道
3. GameInstance        顶层状态机 + 持有 SkillTimelinePlayerHost / HitStopHost / VFXSpawner 子节点
4. LevelManager        关卡切换
5. AudioManager        BGM/SFX/UI 三总线 + SfxBindings 池
6. SettingsManager     ConfigFile 持久化（user://settings.cfg）
7. InputContextManager HUD Phase 0 引入；输入上下文栈
8. HUDManager          HUD Phase 1；8 层 CanvasLayer 管理
9. UIExtensionSubsystem HUD Phase 1；slot → widget 注册
10.HUDStateMachine     HUD Phase 1；9 状态切换
```

> ⚠️ **注意**：当前 10 项已超出 `全局规则.md` R-ARCH-02 的上限 6（已识别为 P0 重构候选 REF-2，详见 _Inventory/09）。

### 3.2 子系统层（详见 §4）

```
┌──────────────────────────────────────────────────────────────────┐
│                      用户输入（InputMap）                         │
│      WASD / A / Q W E R / Space / S(闪避) / D(格挡) / Esc         │
└─────────────┬────────────────────────────────────────────────────┘
              │ Godot _unhandled_input
              ▼
┌──────────────────────────────────────────────────────────────────┐
│   InputController（鉴权前置：InputContextManager.is_action_allowed）│
└─────────────┬────────────────────────────────────────────────────┘
              │ EventBus.player_input_action_pressed(action)
              ▼
┌──────────────────────────────────────────────────────────────────┐
│   PlayerCharacter（BaseCharacter 派生）                           │
│   - InputComponent → MoveComponent → CharacterBody3D.move_and_slide│
│   - 按 action 名分发到 ASC.try_activate(ability_id)                │
└─────────────┬────────────────────────────────────────────────────┘
              │
              ▼
┌──────────────────────────────────────────────────────────────────┐
│   AbilitySystemComponent（GAS 核心）                               │
│   - try_activate → 检查 Cost / CD / Tags → ab._activate(self)      │
│   - 子类 Ability_TimelineDriven._activate                          │
│           ↓                                                        │
│      GameInstance.skill_timeline_player.play(timeline, caster)     │
└─────────────┬────────────────────────────────────────────────────┘
              │ 多个 ActiveTimeline 并发推进
              ▼
┌──────────────────────────────────────────────────────────────────┐
│   SkillTimelinePlayerHost（数据驱动技能播放）                      │
│   ├─ AnimationTrack → AnimationComponent.play(name)                │
│   └─ EventTrack:                                                   │
│      ├─ HITBOX_ENABLE → 直管 HitboxComponent.enabled = true        │
│      └─ 6 类广播 Event Kind → EventBus.skill_event_*               │
└─────────────┬────────────────────────────────────────────────────┘
              │
              ├─ skill_event_sfx        → AudioManager
              ├─ skill_event_camera_shake → CameraRig.shake
              ├─ skill_event_hit_stop   → HitStopHost
              ├─ skill_event_vfx        → VFXSpawner
              └─ HitboxComponent.hit_landed → HitDamageResolver
                   │ 查 SkillDamageTable[skill_id][damage_node_index]
                   │ 算最终伤害 (damage_mul × caster.attack + flat)
                   ▼
              AbilitySystemComponent.apply_effect_to(target.asc, GE)
                   │ → AttributeSet.set_attr(health, ...)
                   │   → EventBus.attribute_changed
                   │   → EventBus.damage_dealt_v2(target, instigator, amount, node, is_crit)
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│   表现层订阅                                                       │
│   ├─ HUD（HP/MP 条）              ← attribute_changed             │
│   ├─ EnemyOverheadHealthBar       ← attribute_changed + filter    │
│   ├─ DamagePopupPool              ← damage_dealt_v2               │
│   ├─ HitFlashController（角色身上）← Hurtbox.hit_received          │
│   └─ BossHealthBar                ← attribute_changed + boss_phase│
└──────────────────────────────────────────────────────────────────┘
```

> 📌 **记住一句话**：**输入 → ASC → SkillTimeline → EventBus → 表现层**。所有跨模块通信走 EventBus，所有可调数值走 ConfigCenter。

---

## 4. 核心子系统（11 个）

> 每个子系统给：**入口类 / 关键文件 / 数据 .tres / Lyra 对应物**。详细 API 见 `_Inventory/01_代码清单.md`。

### 4.1 Core · 核心服务（4 个 Autoload）

| 类 | 文件 | 职责 | Lyra 对应 |
|---|---|---|---|
| ConfigCenter | `Script/Core/ConfigCenter.gd` | 启动时加载 13 类 .tres；提供 `get_character_def(id)` / `get_skill_timeline(id)` / `get_hit_feedback_config()` 等统一 API | `UAssetManager` + `UPrimaryDataAsset` |
| EventBus | `Script/Core/EventBus.gd` | 34 个全局 signal 集中声明，跨模块通信唯一通道 | `UGameplayMessageSubsystem` |
| GameInstance | `Script/Core/GameInstance.gd` | 顶层 5 状态机（BOOT/MENU/PLAYING/PAUSED/GAME_OVER）+ 持 SkillTimelinePlayerHost / HitStopHost / VFXSpawner 三个子节点 | `UGameInstance` |
| GameLogger | `Script/Core/GameLogger.gd` | 日志门面（带 channel 前缀） | `UE_LOG(LogXxx, ...)` |

### 4.2 Character · 角色与组件（9 个文件）

```
BaseCharacter（CharacterBody3D + @tool）  ← Lyra ALyraCharacter
├── MoveComponent              ← MovementComponent
├── AnimationComponent         ← 自动选 AnimatedSprite3D / AnimationPlayer
├── HitboxComponent (Area3D)   ← 攻击判定
├── HurtboxComponent (Area3D)  ← 受击判定
├── InputComponent             ← 仅玩家
├── HitFlashController         ← 闪白 Shader（M8）
└── AbilitySystemComponent     ← Lyra ULyraAbilitySystemComponent
```

派生：`PlayerCharacter` / `EnemyCharacter`（数据驱动属性）/ Boss 复用 EnemyCharacter+`BossAI`。

> 详见 `Plans/Dolphin设计/02_战斗框架_属性公式_Dolphin适配.md`。

### 4.3 GAS · 战斗框架（10 文件，移植 Lyra GAS 最小子集）

| 类 | 职责 | Lyra 对应 |
|---|---|---|
| `AttributeSet` | 属性容器；`set_attr(name, val)` 统一钳制 + emit 信号 | `UAttributeSet` |
| `CharacterAttributeSet`（子类） | health / max_health / mana / max_mana / attack / defense / move_speed | `ULyraHealthSet` / `ULyraCombatSet` |
| `GameplayEffect` | 三类型：Instant / Duration / Periodic；含 Modifier 数组 | `UGameplayEffect` |
| `AttributeModifier` | 单条属性修改（attribute / op / magnitude） | `FGameplayModifierInfo` |
| `Ability` | 抽象基类（含 timeline_id / damage_table_skill_id / cost / CD / tags） | `UGameplayAbility` |
| `Ability_TimelineDriven`（**唯一具体类**） | M7 推翻重写后所有技能走它；驱动 SkillTimeline | `ULyraGameplayAbility_FromEquipment` |
| `AbilitySystemComponent` | 聚合 attribute_set + abilities + tags + cooldowns + active_effects | `UAbilitySystemComponent` |
| `GameplayTag*` | 三件套：Tag 静态工具 / Container（引用计数） / Registry（注册表） | `FGameplayTag` / `FGameplayTagContainer` |

**未做**（Lyra 有但 Dolphin 故意省略）：AbilityTask / GameplayCueManager / GameplayMessage（用 EventBus 替代）

### 4.4 SkillSystem · 技能时间轴（16 文件，**M7 核心创新**）

```
SkillTimeline.tres（DataAsset）
├── duration: float
└── tracks: Array[SkillTrack]
     ├── AnimationTrack ─→ keyframes: Array[AnimationKeyframe]（time + anim_name）
     └── EventTrack    ─→ keyframes: Array[EventKeyframe]（time + kind + payload）
                          按 kind 分 8 种：
                          ├ HITBOX_ENABLE / DISABLE      ← Player 直管
                          ├ SFX_PLAY                     ← AudioManager
                          ├ VFX_SPAWN                    ← VFXSpawner
                          ├ PROJECTILE_SPAWN             ← 待实装
                          ├ CAMERA_SHAKE                 ← CameraRig
                          ├ HIT_STOP                     ← HitStopHost
                          └ CUSTOM_SIGNAL                ← 业务订阅
```

运行时：
- `SkillTimelinePlayerHost`（GameInstance 子节点） · 多 caster 并发；按 handle_id 调度
- `ActiveTimeline` · 单次播放实例
- `HitDamageResolver` · 命中时查 SkillDamageTable 算伤害
- `HitStopHost` / `EventTrackHandler` · 事件分派

**配套编辑器**：`addons/skill_editor/`（底部 Dock，时间轴菱形可视化 + Inspector + Play 预览）—— 类似 UE5 Sequencer 的 Godot 重写。

> 这是项目独立设计、不是 Lyra 直接对应。Lyra 的等价物是 GameplayAbility 内的硬编码逻辑 + AnimMontage。

### 4.5 AI · 状态机（8 文件）

```
AIController（持 current_state）
├─ 普通敌人：AIState_Idle ↔ Chase ↔ Attack；受击 Hit；死亡 Dead
└─ Boss：BossAI 派生，按 HP% 切阶段（70%/30%），每阶段 ability_set 不同
```

> 状态用 RefCounted（不是 Node），节省开销。Lyra 对应 `UBTService` / `UStateTreeComponent`，Dolphin 简化为手写状态机。

### 4.6 Items · 物品 / 装备 / 拾取（8 文件）

| 类 | 职责 | Lyra 对应 |
|---|---|---|
| ItemDefinition / EquipmentDefinition / ConsumableDefinition | 物品定义 | `ULyraInventoryItemDefinition` + Fragment |
| InventoryComponent / EquipmentComponent | 玩家身上的背包 / 装备槽 | `ULyraInventoryManagerComponent` / `ULyraEquipmentManagerComponent` |
| PickupArea / BossPortal | 场景拾取 / 关卡传送 | `IPickupable` |
| VFXSpawner | 订阅 `EventBus.skill_event_vfx` 实例化特效 | `UGameplayCueManager` |

> 装备特性：`equip(item)` 内部对玩家 ASC `apply_effect`（Duration=Infinite GE），卸下时 remove。**移植自 Lyra 的 EquipmentManager 范式**。

### 4.7 UI / HUD · 系统（22 文件）

#### 框架层（HUD Phase 0/1，**已落地**）

| 类 | 职责 | Lyra 对应 |
|---|---|---|
| `HUDManager`（Autoload） | 8 层 CanvasLayer + 每层 widget 栈 | `UPrimaryGameLayout` |
| `BaseWidget`（Control 基类） | 含 `_on_show / _on_hide` 钩子 + input/pause/theme 字段 | `UCommonActivatableWidget` |
| `HUDStateMachine`（Autoload） | 9 状态切换（Boot/MainMenu/Gameplay/Paused/PanelOpen/Dialogue/Cutscene/Dead/LevelTransition） | UE 顶层 GameMode 状态 |
| `UIExtensionSubsystem`（Autoload） | slot → widget 注册（`register_widget(slot_tag, scene)`） | `UUIExtensionSubsystem` |
| `Contracts/I*Readable.gd` × 3 | UI 抽象数据接口（不直依赖业务类） | UE Interface（DIP） |
| `InputContextManager`（Autoload） + InputContext.tres × 6 | 输入上下文栈（默认 deny + inherit_from） | `UCommonInputModeManager` |
| `UIDurations.tres` / `UIColorTokens.tres` / `UITheme.tres` | 数据驱动的时长 / 颜色 / 主题 | UMG StyleAsset |

#### Widget 层（HUD Phase 2 待迁移，**当前直 cast 业务类**）

`HUD.gd` / `BossHealthBar` / `InventoryUI` / `PauseMenu` / `SettingsMenu` / `EnemyOverheadHealthBar` / `OverheadHealthBarManager` / `DamagePopup` / `DamagePopupPool` —— 9 个旧 widget。

> 8 层结构、5 条铁律、组件化分类详见 `Plans/Dolphin设计/05_系统框架_HUD设计_Dolphin适配.md`。

### 4.8 Camera / Lighting · 视觉（2 文件）

- `CameraRig`（Node3D + SpringArm3D + Camera3D）·  pitch=-55°/distance=8m/fov=45°（CameraConfig.tres 可调） + `shake` + `zoom_punch`
- `LightingApplier` · 运行时把 LightingConfig + PostProcessConfig 注入当前场景 WorldEnvironment（SSAO/Bloom/Fog；DOF 待 M9.7 接入 CameraAttributesPractical）

### 4.9 Input · 输入框架（3 文件，HUD Phase 0）

- `InputController`（Node） · 读 InputMap → 调 InputContextManager 鉴权 → emit `EventBus.player_input_action_pressed`
- `InputContextManager`（Autoload） · 栈管理（push/pop/replace_top/clear_to_default）
- `InputContext`（Resource） · 单份配置（context_id / explicit_allowed / explicit_blocked / allow_all / inherit_from）

> 6 份预制 Context：Gameplay（默认 allow_all）/ PanelOpen / Modal / Dialogue / Cutscene / Dead

### 4.10 Audio / Settings / Level（3 个 Autoload）

- `AudioManager` · BGM/SFX/UI 三总线 + 8 路 SFX 池 + 订阅 `skill_event_sfx`
- `SettingsManager` · ConfigFile 持久化到 `user://settings.cfg`
- `LevelManager` · `load_level(id)` 异步切换；按 `LevelDef.tres` 切 BGM/Boss

### 4.11 Editor 工具（2 个插件）

- `addons/skill_editor/` · 底部 Dock 时间轴可视化 + 内嵌 SubViewport 预览（M7.4-M7.7） · 项目独有
- `addons/godot_mcp/` · HTTP 端口 9180，让 AI 助手通过 154 个 MCP 工具操作编辑器（核对节点树 / 跑脚本 / 启停项目）

---

## 5. 已实现功能清单（按里程碑回溯）

| 里程碑 | 主题 | 状态 | 关键交付 |
|---|---|---|---|
| M1 | 基建骨架 | 🟢 | 5 Autoload + BaseCharacter + 5 组件 + InputMap |
| M2 | GAS 最小闭环 | 🟢 | AttributeSet + GameplayEffect + Ability + GameplayTag 三件套 |
| M3 | 玩家可玩 + HUD | 🟢 | PlayerCharacter + 旧 HUD（HP/MP/技能槽） + CameraRig |
| M4 | 怪物 + 战斗闭环 | 🟢 | EnemyCharacter + AIController + 5 状态 + Slime |
| M5 | 道具/装备/Boss/关卡 | 🟢 | Inventory + Equipment + BossAI 阶段机 + LevelManager 实装 + BossRoom |
| **M6** | ConfigCenter + 数据驱动属性 | 🟢 | 二期开始；CharacterInstanceTable + AttributeGrowthTable |
| **M7** | 技能编辑器 + 数据驱动技能 | ✅ 待最终验收 | SkillTimeline 资源类 16 个 + 全 EditorPlugin（Dock + 预览） + 推翻 Ability_BasicAttack |
| **M7.7** | 编辑器内嵌可视/可听预览 | 🟡 进行中 | SubViewport + 拖拽 SpriteFrames + 真实音效震屏 |
| **M8** | 命中反馈四件套 | ✅ 待视觉验收 | HitFlash Shader + DamagePopup 池化 + EnemyOverhead+LayeredBoss 血条 + zoom_punch + VFXSpawner |
| **M9** | HD-2D 全量 3D 化 | ✅ 待视觉验收 | M1–M5 全场景 2D→3D + Sprite3D billboard + WorldEnvironment + Camera3D |
| **HUD P0** | 输入上下文 + 时长档 + 信号 | 🟢 | InputContextManager + 6 Context.tres + UIDurations + 4 新信号 |
| **HUD P1** | 核心架构 | 🟢（接入待 P2） | BaseWidget + HUDManager + UIExtensionSubsystem + HUDStateMachine + Contracts × 3 + HUD_Main.tscn 8 层 |
| **HUD P2** | 现状迁移（旧 9 widget 接入新框架） | ⏸ 未开始 | — |
| **HUD P3** | 元素补全（22 项 widget） | ⏸ 未开始 | — |
| **HUD P4** | 完善与验收 | ⏸ 未开始 | — |
| **三期 M10** | Excel 配置工作流 | ⏸ 未开始 | — |
| **三期 M11** | 对话系统 | ⏸ 未开始 | — |
| **三期 M12** | NPC + 商店 + 任务 | ⏸ 未开始 | — |

> ⏸ = 计划已成熟（详见 `Plans/三期开发计划.md` / `Plans/Dolphin设计/06_HUD落地路线`），等启动信号。

---

## 6. 设计哲学（5 条核心 + 11 条规则）

### 6.1 核心思想（按 Lyra 思想映射）

| Lyra 原则 | Dolphin 落地 | 检查点 |
|---|---|---|
| **数据驱动一切**（Lyra Experience + GameFeatureAction） | 玩家可见数值全走 .tres + ConfigCenter；M10 起接 Excel-JSON | R-DATA-01 / R-DATA-02 |
| **组件组装**（Lyra ModularActor） | BaseCharacter 自动收集子组件；新增组件不改 BaseCharacter | R-CHAR-01 |
| **跨模块解耦**（Lyra GameplayMessage） | EventBus 集中声明 34 信号；禁止 `get_node("/root/...")` 跨场景树 | R-ARCH-01 / R-EVENT-01 |
| **技能数据资源化**（Lyra GA + AnimMontage） | SkillTimeline.tres 时间轴 + DamageNode + EditorPlugin；新增技能 0 行代码 | R-GAS-03 |
| **UI 分层 + 接口注入**（Lyra UPrimaryGameLayout + IDataReadable） | HUDManager 8 层 + Contracts 接口 + UIExtensionSubsystem 插槽 | R-HUD-01..05 |

### 6.2 11 条强约束规则（详见 `全局规则.md`）

| ID | 内容 | 严重 |
|---|---|---|
| R-ARCH-01 | 跨模块通信走 EventBus | 🔴 |
| R-ARCH-02 | Autoload 上限 6（**当前现状 10，过渡期允许**） | 🔴 |
| R-GAS-01 | GameplayTag 必须注册 | 🟡 |
| R-GAS-02 | 属性必须经 set_attr 修改 | 🔴 |
| R-GAS-03 | Ability/GE 必须 Resource 化 | 🔴 |
| R-DIR-01 | 目录分层（Script/Scenes/Data/Content） | 🔴 |
| R-NAME-01 | class_name 走 PascalCase / 场景同名脚本走 snake_case | 🟡 |
| R-CHAR-01 | 角色组件对外 API 2D/3D 通用 | 🔴 |
| R-CHAR-02 | 3D 场景节点纯洁性（HUD CanvasLayer 例外） | 🔴 |
| R-DATA-01 | 玩家可见数值走 .tres | 🔴 |
| R-DATA-02 | 数据驱动优先；遇硬编码主动询问是否固化 | 🔴 |
| R-EVENT-01 | 全局信号集中声明 | 🔴 |
| R-LOG-01 | 用 GameLogger，不裸 print | 🟡 |
| R-VERIFY-01 | commit 后先 lint → restart → MCP 自测 → 必要时呼叫用户手测 | 🔴 |

### 6.3 当前合规情况（来自 `_Inventory/07_错误清单.md`）

| 规则 | 通过率 | 主要违规 |
|---|---|---|
| R-ARCH-01 / R-EVENT-01 | ✅ 100% | 0 处 `get_node("/root/...")`；EventBus 集中正确 |
| R-ARCH-02 | ❌ 当前违规 | 10 项 vs 上限 6（HUD P0/P1 引入 4 项；待 REF-2 收编） |
| R-GAS-02 | ✅ 100% | AttributeSet.set_attr 全部走对 |
| R-LOG-01 | ✅ 100% | 业务代码 0 裸 print |
| R-DATA-01/02 | 🟡 4 处违规 | HUD.gd / DamagePopup / BossHealthBar 4 处裸 Color（待 DIR-1.2 接入 UIColorTokens.tres） |
| R-HUD-02 (DIP) | ❌ 待修 | HUD.gd:114 `as PlayerCharacter`（待 DIR-1.1 接 Contracts） |

### 6.4 R-VERIFY-01 自测流程（每次 commit 后）

```
1. read_lints                         ← 静态校验
2. Tools/godot.bat restart            ← 重启编辑器，刷 class_name 缓存
3. MCP 自测（godot-mcp，端口 9180）    ← 跑 get_editor_logs / execute_editor_script / run_project
4. 跑得通 → 直接「✅ 通过」；跑不动 → 显式呼叫用户手测
```

---

## 7. 未来修改方向（路线图）

> 来源：`_Inventory/08_开发方向.md`（10 条开发方向 DIR-1..10）+ `_Inventory/09_重构方向.md`（10 项重构候选 REF-1..10）。

### 7.1 P0 必做（占总工期 60%）

| 方向 | 主题 | 工期 | 内含重构 |
|---|---|---|---|
| **DIR-2** | Player 接入 ConfigCenter，消除 DefaultPlayerAttributes 直引 | 0.5d | + REF-7（AttributeSet.bind_owner） |
| **DIR-1** | HUD 收尾（Phase 2-4，9 widget 接 Contracts → 22 widget 元素补全 → 完善验收） | 9-14d | + REF-1（DIP 主战场） + REF-2（Autoload 收编 4→0） + REF-9 |
| **DIR-3** | 三期 M10 Excel 配置工作流（独立 Python 工程 + JSON 输出） | 4-5d | + REF-3（ConfigCenter 拆 Loader） |

### 7.2 P1 主要扩展（占 25%）

| 方向 | 主题 | 工期 |
|---|---|---|
| DIR-4 | 三期 M11 对话系统（DialogueGraph + DialogueRunner + DialogueWidget） | 5-6d |
| DIR-5 | 三期 M12 NPC + 商店 + 任务骨架 | 4-5d |
| DIR-6 | 战斗补全（CombatStateService / ProjectileSpawner / Buff·Debuff List） | 3-4d |
| DIR-7 | 美术资源补齐（SFX 8 / VFX 2 / 字体 / Slime SpriteFrames / Boss Mesh / 地面贴图） | 持续 |

### 7.3 P2 收尾（占 15%）

| 方向 | 主题 | 工期 |
|---|---|---|
| DIR-8 | 视觉调优（M9.7 DOF + HD-2D 后处理参数） | 1-2d |
| DIR-9 | 编辑器与工具链体验（Skill Editor Undo/Redo / godot.bat 强化 / verify.bat） | 2-3d |
| DIR-10 | 存档持久化系统（SaveGame + 自动存档 + Checkpoint + 死亡复活） | 4-5d |

### 7.4 推荐执行顺序

```
Day 0 ─┐
       │  DIR-2     0.5d   ← 解锁 DIR-3
       │
Day 1  │  DIR-1.1   3-4d   HUD widget 接 Contracts（含 REF-1+REF-2）
Day 4  │  DIR-1.2   0.5d   裸 Color 接 UIColorTokens
       │
Day 5  │  DIR-3     4-5d   M10 Excel（含 REF-3）
       │
Day 10 │  DIR-1.3-6 6-8d   HUD Phase 3 元素补全（合并 DIR-6.3/6.4）
       │
Day 18 │  DIR-4     5-6d   M11 对话
Day 24 │  DIR-5     4-5d   M12 NPC+Shop+Quest
       │
Day 29 │  DIR-1.7   1-3d   HUD Phase 4 完善验收
Day 32 │  DIR-6     2d     战斗补全剩余
Day 35 │  DIR-8/9   3-5d   视觉/工具链调优
Day 41 │  DIR-10    4-5d   存档系统
       │
Day 46+│  DIR-7     美术资源穿插持续
```

总工期 35-50 天（不含调优 / 美术）。

### 7.5 不在路线内（明确排除）

- 多职业系统（仅 Player 单原型）
- 多语言 / 国际化（M14+）
- Boss 多阶段被动技能（超 Demo 范围）
- 联网 / 多人（Roguelike 单机为先）
- 全工程改 GDExtension/C++（无性能瓶颈）
- 改 ECS（Godot 不是 ECS 引擎）

---

## 8. 入项目实操指南

### 8.1 第 1 周建议任务

| 天 | 任务 |
|---|---|
| Day 1 | 读完本文档 + `全局规则.md` + 跑通 TestArena |
| Day 2 | 读 `Plans/_Inventory/01-07` 7 张盘点表 |
| Day 3 | 读 `Plans/Dolphin设计/05/06/07` HUD 三连 + 跟着 06_HUD 路线表过一遍代码 |
| Day 4 | 读 GAS 4 个核心类源码（AttributeSet / GameplayEffect / Ability / AbilitySystemComponent） |
| Day 5 | 读 SkillSystem 16 个文件 + 在 Skill Editor 里改一个 Timeline 看看效果 |
| Day 6-7 | 选一条 DIR（推荐 DIR-2）作为第一个独立 commit 任务 |

### 8.2 改代码前必做

1. **Read 一遍同模块的现有代码**（90% 的"新写"其实可以复用）
2. **检查是否有对应 .tres**（很可能不需要写代码，只需要改配置）
3. **检查是否有对应 EventBus signal**（很可能不需要新加信号）
4. **改完 commit 走 R-VERIFY-01 自测流程**（lint → restart → MCP）

### 8.3 与 AI 助手协作

项目已配置 `addons/godot_mcp/`（HTTP 端口 9180）。可以让 AI：
- 自动读编辑器日志
- 执行编辑器脚本（验证 .tres 加载 / 节点结构）
- 启停项目跑端到端验证
- 操作场景树（add_child / set_property）

> 详见 `addons/godot_mcp/README.md` 与 `c:\Users\Administrator\.codebuddy\mcp.json`。

### 8.4 出问题怎么办

| 现象 | 第一反应 |
|---|---|
| 启动报 `Could not find type X` / `class_name` 不识别 | `Tools\godot.bat restart` |
| .tres 加载得到 placeholder | 同上（@tool 脚本必须重启刷类缓存） |
| MCP 工具找不到 | 检查 IDE 端 `mcp.json` `{"godot-mcp": {"url": "http://localhost:9180/mcp"}}` + Godot 编辑器是否打开 |
| 改 @tool 脚本不生效 | 同上重启 |
| `var x := variant_func()` 警告当 Error | 改 `var x: ExplicitType = ...` 或 `var x: Variant = ...` |
| Godot 4.x DOF 不工作 | 用 `CameraAttributesPractical` 挂 Camera3D（M9.7 待办） |
| 找不到怎么改某个数值 | 全文 grep `xxx` → 大概率在某张 `.tres` 里；改 .tres 再重启 |

---

## 9. 索引（一页式查询）

| 我想… | 查这里 |
|---|---|
| 改一个属性数值 | `Data/Config/AttributeGrowthTables/Growth_*.tres` 或 `CharacterInstances.tres` |
| 改一个技能时序 | Godot 编辑器底部 Skill Editor Dock 打开 `Data/Skills/Timelines/Timeline_*.tres` |
| 改一个伤害公式 | `Data/Config/SkillDamageTable.tres` |
| 改命中反馈手感（震屏 / 冻帧 / 飘字） | `Data/Config/HitFeedbackConfig.tres` |
| 改血条 | `Data/Config/HealthBarConfig.tres` |
| 加一个新音效 | `Data/Config/SfxBindings.tres` 加 sfx_id → AudioStream |
| 加一个新 GE / GameplayEffect | `Data/Effects/GE_*.tres` |
| 加一个新道具 | `Data/Items/Item_*.tres` + 拖到场景 PickupArea 节点 |
| 加一个新 HUD 元素 | 看 `Plans/Dolphin设计/07_HUD组件化设计_交互与落地.md` 7 类组件 + 落地步骤 |
| 加一个新关卡 | `Scenes/Levels/` 新建 .tscn + `Data/Levels/LevelDef_*.tres` + 注册到 LevelManager |
| 加一个新敌人类型 | 复用 `EnemyCharacter` + 新建 `CharacterInstanceEntry`（CharacterInstances.tres）+ 新 GrowthTable |
| 看完整里程碑历史 | `Plans/开发计划.md` + `Plans/二期开发计划.md` 文末「变更记录」 |
| 看 19 项已知问题 | `Plans/_Inventory/07_错误清单.md` |
| 看接下来要做什么 | `Plans/_Inventory/08_开发方向.md` |
| 看哪些代码该重构 | `Plans/_Inventory/09_重构方向.md` |

---

## 10. 联系人 / 维护约定

- **维护方式**：本文档由主 agent 在每个里程碑闭环后**主动更新**（参考 `_Inventory/01-09` 的现状） + 在新里程碑启动前由用户审阅
- **过期检测**：本文档"已实现功能清单（§5）"与 `Plans/开发计划.md` / `Plans/二期开发计划.md` 文末状态表必须保持一致
- **变更原则**：
  - 修架构 / 加 Autoload → 必须同步改 §3 §4 §6
  - 完成里程碑 → 必须同步改 §5
  - 调整路线 → 必须同步改 §7

---

> **版本**：v1.0 · 2026-05-21
> **生成依据**：`_Inventory/01-09` 9 份盘点 + `Plans/开发计划.md` / `二期开发计划.md` / `三期开发计划.md` / `全局规则.md` + `Dolphin设计/01-07` 7 篇专题
> **下一次更新触发条件**：DIR-1.1 / DIR-2 / DIR-3 任一启动或完成时
