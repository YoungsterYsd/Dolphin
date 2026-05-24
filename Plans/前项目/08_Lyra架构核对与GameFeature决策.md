# 08 · Lyra 架构核对与 GameFeature 决策报告

> **版本**：v1.1（锁定版 · 主理人已签字）
> **作者**：UE 代码架构师（ue-rpg-architect-57）
> **日期**：2026-05-11
> **目标读者**：主理人 + implementer
> **本文件作用**：对 `d:/UE_Work/FDRPG/LyraStarterGame/` 做**实地摸底**，回答"FDRPG 是否需要 GameFeature 架构"，并给出**可执行**的接入路径与对 07 文档的协同修订。
> **关联文档**：06 技术架构、07 项目改造执行方案 v1.1、05 架构骨架。

---

## §0 执行摘要（TL;DR）

### 0.0 v1.1 主理人签字决策（2026-05-11）

本次主理人对 6 项关键决策点全部做出选择，以下为**锁定版决定**。**本文件其余所有内容以此决策为准**：

| # | 决策点 | 锁定选择 | 与 v1.0 架构师推荐 |
|---|---|---|---|
| **DP-1** | Lyra GameFeature **基础设施**（GameFeatures 插件本体 + ModularGameplay + 主模块 `GameFeatures/` 子目录 7 个 Action + Policy） | **全部保留，仅改名为 RPG 命名**（主模块侧 Lyra→RPG；插件本体不动） | ✅ 一致 |
| **DP-2** | Lyra **自带 5 个业务 GameFeature**（ShooterCore / ShooterMaps / ShooterExplorer / ShooterTests / TopDownArena） | **完整删除**（整目录移出 `Plugins/GameFeatures/`） | ✅ 一致 |
| **DP-3** | Demo 阶段是否拆**业务 GameFeature Plugin** | **不拆**。所有业务代码放主模块 `RPGGame`（= 方案 B） | ✅ 一致 |
| **DP-4** | **Experience 使用深度** | **深度使用**：主菜单 / 角色选择 / 枢纽 / 4 副本 各一个 Experience（共 **7 个**） | ✅ 一致（具体数量锁定） |
| **DP-5** | v1.0+ **演进时机** | **Demo 阶段完全不约定演进触发条件**。v1.0 发布后再单独评估 | 🟡 比架构师推荐的"资产量触发"**更保守**。架构师接受此决定，不再在 Demo 文档中埋任何"未来承诺" |
| **DP-6** | **CommonUI + UIExtensionSubsystem** 使用策略 | **全用**：CommonUI 四层 PrimaryGameLayout（Game/GameMenu/Menu/Modal）+ UIExtensionSubsystem 插槽式 UI | ✅ 一致 |

**签字日期**：2026-05-11
**签字人**：主理人
**本版生效起**：07 文档 v1.1 及 implementer Day 1 全部以此为依据执行。

**DP-5 特别说明**：架构师原推荐方案包含"资产量 > 2GB 触发拆 RPGMaps Plugin"等 4 条渐进式演进路径。主理人选择"**Demo 阶段不写任何演进触发条件**"，本报告 §7 相应调整为"v1.0 之后评估"占位；不再作为正式路线图。此选择的好处是**Demo 文档对未来零承诺，避免误导 implementer 提前埋架构**。

1. **Lyra 5.7 的 GameFeature 体系已经搭好，不是"要不要装"的问题，而是"要不要用业务化 GameFeature"的问题**。`GameFeatures` 基础插件 + `ModularGameplay` + `LyraGameFeaturePolicy` + 7 个自定义 `GameFeatureAction_*` 是 Lyra 主模块内置的，**无法移除**（DP-1 已锁定：全保留并改名为 RPG 命名）。

2. **Demo 阶段已锁定方案 B · 轻度使用**（DP-3）：业务代码全部放主模块 `RPGGame`，**Experience + ActionSet + LevelStreaming** 承担所有场景切换；**0 个业务 GameFeature Plugin**；Lyra 自带 5 个 `Plugins/GameFeatures/Shooter*` 与 `TopDownArena` **完整删除**（DP-2），不保留参考——参考实现可在 `d:/UE_Work/FDRPG/LyraStarterGame/` 原始副本中查阅，RPG 工程内只留清爽的基础设施。

3. **DP-2 删除 5 个业务 GameFeature 的理由**：① 5 个加起来 ~5700 个资产，占磁盘 ~800MB，而 RPG 一个都不会激活，纯浪费；② 它们反向依赖 `LyraGame` 主模块（ShooterCore 的 Build.cs 里就有），RPG 主模块改名为 `RPGGame` 后这些插件**必然编译失败**，要么花时间改名、要么花时间在 uproject 里禁用——不如直接删；③ LyraStarterGame 原始副本还在 `d:/UE_Work/FDRPG/LyraStarterGame/`，作为**工程外参考**比工程内留着更干净。

4. **Demo 阶段 Experience 清单（DP-4 锁定）**：7 个 Experience —— 主菜单 / 角色选择 / 枢纽（观测塔）/ 4 个副本（破碎钟楼 / 锈蚀工厂 / 溺亡之歌 / 永燃废墟）。**每个 Experience 的 `GameFeaturesToEnable = []` 空数组**。

5. **07 文档 v1.1 同步修订**：本报告的所有锁定决策已反向写入 07 v1.1 的 §3、§4、§8、§11；**Day 1 清单已重写**（见 07 §13），implementer 按新版 Day 1 执行。

---

## §1 Lyra 项目架构实地摸底（实测）

> 摘取自 `d:/UE_Work/FDRPG/LyraStarterGame/`，非通用介绍，仅记录本工程实际存在的内容。

### 1.1 uproject 启用清单（来自 `LyraStarterGame.uproject`）

**主模块**（2 个）：
- `LyraGame`（Runtime, Default phase, 依赖 DeveloperSettings/Engine）
- `LyraEditor`（Editor, Default phase）

**Plugins 总数 71**，Enabled 共 62 个。按类型分组如下（只列关键的，移除 VR/MagicLeap/ResonanceAudio 等关闭项）：

| 分组 | 插件 | 作用 |
|---|---|---|
| **GAS 三件套** | GameplayAbilities, GameplayTags, GameplayTasks（自带） | GAS 基础 |
| **ModularGameplay 基础** | ModularGameplay, ModularGameplayActors | 组件热注入 |
| **GameFeatures 基础** | **GameFeatures**（插件本体，必须启用） | Plugin 生命周期管理 |
| **输入** | EnhancedInput | 新输入系统 |
| **UI 基础** | CommonUI, CommonGame, CommonInput, CommonLoadingScreen, CommonUser, UIExtension, GameSettings | CommonUI 全家桶 |
| **消息系统** | GameplayMessageRouter, AsyncMixin | 解耦通信 |
| **DataDriven** | DataRegistry, AssetReferenceRestrictions | 数据表 + 资产引用规则 |
| **音频** | Metasound, AudioModulation, AudioGameplay, AudioGameplayVolume, SoundUtilities, Spatialization | 音频全家桶 |
| **动画** | AnimationLocomotionLibrary, AnimationWarping | 动画库 |
| **AI & 交互** | SmartObjects, GameplayInteractions, ContextualAnimation, GameplayBehaviors, GameplayBehaviorSmartObjects, GameplayStateTree | AI/互动全家桶 |
| **网络** | ReplicationGraph, SignificanceManager, OnlineSubsystemSteam, OnlineServices*, SteamSockets, AESGCMHandlerComponent, DTLSHandlerComponent | 网络复制/加密（单机暂不用） |
| **世界** | PocketWorlds, Water, Volumetrics, Niagara | 场景/特效 |
| **调试** | GameplayInsights, AssetSearch, Gauntlet, FunctionalTestingEditor, RuntimeTests, AutomatedPerfTesting | 测试/Profiling |
| **工具** | ActorPalette, ModelingToolsEditorMode, GeometryScripting, MovieRenderPipeline, MoviePipelineMaskRenderPass | 编辑器工具 |
| **特殊** | Reflex（NVIDIA 低延迟）, WinDualShock（PS 手柄 Win 支持） | 平台 |
| **对话** | CommonConversation, GameSubtitles | 对话/字幕 |
| **主机** | PlayFabParty（仅 XB 平台） | 组队 |
| **工作流** | LyraExtTool | Lyra 内部编辑器扩展 |
| **示例内容** | LyraExampleContent（被 Shooter*/TopDownArena 依赖） | 共享美术资产 |

**业务型 GameFeature Plugins（5 个，全部在 `Plugins/GameFeatures/` 下）**：
- ShooterCore
- ShooterMaps
- ShooterExplorer
- ShooterTests
- TopDownArena

### 1.2 业务 GameFeature Plugin 逐个核对（**本节为核心摸底**）

每个业务 GameFeature 都有完全一致的**"三件套"uplugin 特征**：

```
"ExplicitlyLoaded": true,              ← 不主动加载，由 Experience 触发
"EnabledByDefault": false,             ← 工程启动时默认关闭
"BuiltInInitialFeatureState": "Registered"  ← 初始状态仅"注册"，未激活
```

这三个字段一起决定：**工程启动时所有业务 GameFeature 只被"登记"到 GameFeaturesSubsystem，代码/资产不加载内存**，直到某个 Experience 明确把插件名填进 `GameFeaturesToEnable` 并被加载时才激活。

#### 1.2.1 ShooterCore · 玩法核心
| 字段 | 值 |
|---|---|
| 描述 | "Gameplay systems for Game1 / Shooter Game" |
| Modules | ShooterCoreRuntime（Runtime, Default phase） |
| 依赖 plugins | GameplayAbilities, ModularGameplay, GameplayMessageRouter, AsyncMixin, CommonUI, CommonGame, GameSubtitles, EnhancedInput, **LyraExampleContent** |
| C++ 代码规模 | 14 个 .h + 12 个 .cpp（Public + Private） |
| C++ 放了什么 | ① 辅助瞄准输入修改器（AimAssist*），② 连杀/连杀消息处理器（ElimChain/ElimStreak/AssistProcessor），③ 成就系统（Accolade*），④ 世界拾取 Actor（LyraWorldCollectable），⑤ TDM 出生点组件，⑥ 射击专属 Settings |
| 资产规模 | 258 .uasset + 2 .umap |
| 反向依赖 | **`ShooterCoreRuntime.Build.cs` 里 PublicDependencyModuleNames 包含 `LyraGame`** —— 这是重要事实：业务 GameFeature 反过来依赖主模块 |
| 移除后 | Lyra 工程主模块仍能编译启动，但所有射击类 Experience（B_ShooterGame_*）会失效 |

#### 1.2.2 ShooterMaps · 地图集合（**纯资产插件**）
| 字段 | 值 |
|---|---|
| 描述 | "Maps for Game1 / Shooter Game" |
| Modules | **无 C++ 模块**（`.uplugin` 里没有 Modules 字段） |
| 依赖 plugins | ShooterCore, LyraExampleContent |
| 资产规模 | 5325 .uasset + 5 .umap（最大的业务 Plugin，地图体量堆在这） |
| 价值定位 | **地图作为独立 Plugin 的典型实现**：代码 0，全资产；版本控制/合并冲突/下载体积可独立处理 |

#### 1.2.3 ShooterExplorer · 核心上叠加冒险元素（**与 FDRPG 最像**）
| 字段 | 值 |
|---|---|
| 描述 | "**Builds onto ShooterCore, adding adventure elements.**" |
| Modules | **无 C++ 模块** |
| 依赖 plugins | ShooterCore, LyraExampleContent |
| 资产规模 | 48 .uasset + 3 .umap + 1 .ini |
| 包含 Experience | `B_TestInventoryExperience.uasset`（测试背包 Experience） |
| 移除后 | ShooterCore 仍正常，只损失冒险模式 |
| **FDRPG 启示** | **"一个核心 Plugin（ShooterCore）+ 多个叠加 Plugin（Explorer / 新冒险包）"** 这个模式，就是未来 FDRPG v2.0 加"新副本 DLC"时要复刻的架构。Demo 阶段不需要，但 Plugin 设计模板心中要有数 |

#### 1.2.4 ShooterTests · 测试 Plugin（**带 Shipping 排除**）
| 字段 | 值 |
|---|---|
| 描述 | "Tests for Game1 / Shooter Game" |
| Modules | ShooterTestsRuntime（Runtime, Default phase, `TargetConfigurationDenyList: ["Shipping"]`） |
| 依赖 plugins | ShooterCore, AsyncMessageSystem, CQTest, CQTestEnhancedInput, GameplayAbilities, ModularGameplay, EnhancedInput, LyraExampleContent |
| C++ 代码规模 | 9 .h + 9 .cpp |
| 关键设计 | **TargetConfigurationDenyList=["Shipping"]** —— 打包 Shipping 时此模块自动排除，测试代码/资产零污染发行版 |
| **FDRPG 启示** | Demo 后期若要做 CI 测试体系，这是标准做法：**所有测试工具放独立 GameFeature，Shipping 自动剔除**。目前 Demo 工期紧，不启用；但 v1.0 后**一定要加**一个 `RPGTests` GameFeature |

#### 1.2.5 TopDownArena · 俯视角模式（**FDRPG 必读**）
| 字段 | 值 |
|---|---|
| 描述 | "Gameplay Systems for Game2 / Top Down Arena" |
| Modules | TopDownArenaRuntime（Runtime, Default phase） |
| 依赖 plugins | GameplayAbilities, LyraExampleContent, Niagara |
| C++ 代码规模 | **5 .h + 5 .cpp（极简）**，Public 只 2 个 .h：`LyraCameraMode_TopDownArenaCamera.h` + `TopDownArenaRuntimeModule.h` |
| 资产规模 | 85 .uasset + 2 .umap（含 2 个 Experience：`B_TopDownArenaExperience.uasset`、`B_TopDownArena_Multiplayer_Experience.uasset`） |
| C++ 放了什么 | **只有一个特有相机模式**。其余全靠蓝图 + Experience + ActionSet 拼装 |
| **FDRPG 启示**（关键） | **"玩法模式 = 一个 Plugin"这个模式的最低成本实现**：C++ 只写本模式特有的东西（相机/特有组件），**绝不在 GameFeature 里复写主模块已有的类**。FDRPG 若要做 v1.0 的"竞技场 PVP 模式"或"肉鸽限时模式"，直接照抄这个结构 |

### 1.3 主模块 `LyraGame` 目录结构（一级+二级）

```
Source/LyraGame/                                [228+ .h，规模大]
├── AbilitySystem/           27 .h + 24 .cpp    ← GAS 扩展（ASC/Attribute/Ability 基类、Phase 子系统）
│   ├── Abilities/
│   ├── Attributes/
│   ├── Executions/
│   └── Phases/
├── Animation/                                  ← LyraAnimInstance
├── Audio/                                      ← 音频混音子系统
├── Camera/                  7 .h + 5 .cpp      ← CameraMode 基类、UICamera、ThirdPerson、PenetrationAvoidance
├── Character/               8 .h + 8 .cpp      ← LyraCharacter / Pawn / PawnData / HeroComp / HealthComp / PawnExt
├── Cosmetics/               6 .h + 5 .cpp      ← 外观系统（角色部件）
├── Development/                                ← Developer Settings / BotCheats
├── Equipment/               6 .h + 6 .cpp      ← EquipmentDefinition / Instance / Manager / QuickBar
├── Feedback/               10 .h + 9 .cpp      ← 手柄震动、音效 Feedback
├── GameFeatures/            8 .h + 8 .cpp      ← ★ 7 个自定义 GameFeatureAction + Policy
├── GameModes/              10 .h +10 .cpp      ← ★ ExperienceDefinition / Manager / ActionSet / GameMode
├── Hotfix/                                     ← 运行时 Hotfix
├── Input/                   7 .h + 7 .cpp      ← LyraInputConfig / Component / Modifier
├── Interaction/            11 .h + 6 .cpp      ← 交互 & Pickup
├── Inventory/               8 .h + 8 .cpp      ← InventoryItemDefinition/Instance/Manager/Fragment
├── Messages/                5 .h + 4 .cpp      ← GameplayMessage 定义
├── Performance/                                ← PerformanceSettings
├── Physics/                                    ← 物理材质扩展
├── Player/                  8 .h + 8 .cpp      ← PlayerController / PlayerState / PlayerSpawningComponent
├── Replays/                                    ← 回放系统
├── Settings/               20 .h +14 .cpp      ← Settings 子系统
├── System/                 14 .h +13 .cpp      ← AssetManager / DevSettings / 全局系统
├── Teams/                  11 .h +11 .cpp      ← 阵营系统
├── Tests/                                      ← Unit Test
├── UI/                     40 .h +39 .cpp      ← HUD / IndicatorSystem / PerfStats / Frontend / Subsystem
├── Weapons/                 8 .h + 8 .cpp      ← WeaponInstance / RangedWeapon / Spawner / DebugSettings
├── LyraGame.Build.cs
├── LyraGameModule.cpp
├── LyraGameplayTags.h/cpp
└── LyraLogChannels.h/cpp
```

**两个关键子目录**：

- `GameModes/` —— Experience 机制的代码实现，**全部在主模块**，不在任何 GameFeature 里（否则鸡生蛋问题）。
- `GameFeatures/` —— **7 个自定义 GameFeatureAction 的实现都在主模块**：
  - `GameFeatureAction_AddAbilities.cpp/h` — 给指定 Actor class 批量授予 Ability/AttributeSet
  - `GameFeatureAction_AddGameplayCuePath.cpp/h` — 注册额外的 GameplayCue 搜索路径
  - `GameFeatureAction_AddInputBinding.cpp/h` — 绑定 InputConfig 到 Actor
  - `GameFeatureAction_AddInputContextMapping.cpp/h` — 注入 IMC 到玩家
  - `GameFeatureAction_AddWidget.cpp/h` — 把 Widget 加到指定 UI Slot
  - `GameFeatureAction_SplitscreenConfig.cpp/h` — 分屏配置切换
  - `GameFeatureAction_WorldActionBase.cpp/h` — 上述 Action 的共同基类
  - `LyraGameFeaturePolicy.cpp/h` — Lyra 覆写的全局 Plugin 加载策略

### 1.4 Experience + GameFeature 联动机制（源码级验证）

#### 1.4.1 `ULyraExperienceDefinition` 数据结构（实测 `LyraExperienceDefinition.h`）

```cpp
UCLASS(BlueprintType, Const)
class ULyraExperienceDefinition : public UPrimaryDataAsset
{
    // 需要激活的 GameFeature Plugin 名字列表（字符串数组）
    UPROPERTY(EditDefaultsOnly, Category = Gameplay)
    TArray<FString> GameFeaturesToEnable;

    // 默认 PawnData（角色组装数据）
    UPROPERTY(EditDefaultsOnly, Category=Gameplay)
    TObjectPtr<const ULyraPawnData> DefaultPawnData;

    // 本 Experience 激活时执行的 Action 列表（Instanced，每 Experience 独立）
    UPROPERTY(EditDefaultsOnly, Instanced, Category="Actions")
    TArray<TObjectPtr<UGameFeatureAction>> Actions;

    // 可复用的 ActionSet 组合（DataAsset，多 Experience 共享）
    UPROPERTY(EditDefaultsOnly, Category=Gameplay)
    TArray<TObjectPtr<ULyraExperienceActionSet>> ActionSets;
};
```

**就这 4 个字段**，极其简洁。

#### 1.4.2 `ULyraExperienceManagerComponent` 加载流程（实测 `LyraExperienceManagerComponent.cpp`）

从代码中看到的 7 阶段状态机：

```
ELyraExperienceLoadState:
  Unloaded
    ↓ SetCurrentExperience() 被调用
  Loading
    ↓ StreamableManager 异步加载 Experience 的 PrimaryAssetBundle
    ↓ OnAssetsLoadedDelegate 回调
    ↓ OnExperienceLoadComplete()
    ↓ 收集所有 GameFeaturesToEnable（Experience 自己的 + 所有 ActionSet 的）
    ↓ CollectGameFeaturePluginURLs() → 把 plugin 名字转成 URL
    ↓ 对每个 URL 调用 UGameFeaturesSubsystem::Get().LoadAndActivateGameFeaturePlugin()
  LoadingGameFeatures
    ↓ 每个 plugin 加载完成回调 OnGameFeaturePluginLoadComplete()
    ↓ NumGameFeaturePluginsLoading 递减到 0
  LoadingChaosTestingDelay（可选，测试用）
  ExecutingActions
    ↓ 对 CurrentExperience->Actions 逐个调用：
    ↓   Action->OnGameFeatureRegistering()
    ↓   Action->OnGameFeatureLoading()
    ↓   Action->OnGameFeatureActivating(Context)
    ↓ 然后遍历 ActionSets 做同样的事
  Loaded
    ↓ 三个优先级广播：
    ↓   OnExperienceLoaded_HighPriority.Broadcast()
    ↓   OnExperienceLoaded.Broadcast()
    ↓   OnExperienceLoaded_LowPriority.Broadcast()
  Deactivating
```

**核心调用链**（`OnExperienceLoadComplete` 第 252 行起）：

```
Experience 加载完成
    ↓
遍历 Experience.GameFeaturesToEnable + 所有 ActionSet.GameFeaturesToEnable
    ↓
去重后形成 GameFeaturePluginURLs
    ↓
UGameFeaturesSubsystem::LoadAndActivateGameFeaturePlugin(URL, callback)
    ↓（所有 plugin 激活完成）
遍历 Actions + ActionSets 的 Actions
    ↓
Action->OnGameFeatureRegistering() → OnGameFeatureLoading() → OnGameFeatureActivating(Context)
    ↓
Action 依据自己类型干活（加 Ability/加 Widget/加 InputMapping/...）
    ↓
LoadState = Loaded，广播三优先级事件
```

#### 1.4.3 Experience 资产在哪里放（实测）

工程里共 15 个 `*Experience*.uasset`，分布如下：

| 位置 | 资产 | 归属 |
|---|---|---|
| `Content/System/Experiences/B_LyraDefaultExperience.uasset` | 默认 Experience | **主模块 Content** |
| `Content/System/FrontEnd/B_LyraFrontEnd_Experience.uasset` | 前端菜单 Experience | **主模块 Content** |
| `Content/System/DefaultEditorMap/B_ExperienceList3D.uasset` | 编辑器测试用 | **主模块 Content** |
| `Plugins/GameFeatures/ShooterExplorer/Content/System/Experiences/B_TestInventoryExperience.uasset` | 冒险模式测试 | **GameFeature 内** |
| `Plugins/GameFeatures/TopDownArena/Content/System/Experiences/B_TopDownArenaExperience.uasset` | 俯视角竞技场 | **GameFeature 内** |
| `Plugins/GameFeatures/TopDownArena/Content/System/Experiences/B_TopDownArena_Multiplayer_Experience.uasset` | 俯视角多人 | **GameFeature 内** |

**重要结论**：Experience 资产**可以放主模块、也可以放 GameFeature 内**，Lyra 的惯例是：
- **通用 Experience（前端、默认）** → 主模块 Content
- **某玩法模式专属 Experience** → 该模式的 GameFeature 内

这就解释了 **ShooterCore 里为何没有 Experience 资产** —— ShooterCore 是"玩法零件库"，Experience（组装产物）由 `ShooterMaps` 或主模块或 `ShooterExplorer` 等上层定义。

### 1.5 综合架构图（文字版）

```
┌──────────────────────────────────────────────────────────────┐
│              Engine Plugins (5.7 自带，启用 62 个)              │
│  GameplayAbilities / ModularGameplay / CommonUI / GameFeatures │
│  EnhancedInput / Niagara / StateTree / SmartObjects / ...      │
└────────────────┬─────────────────────────────────────────────┘
                 │（静态依赖）
                 ▼
┌──────────────────────────────────────────────────────────────┐
│  LyraGame (Runtime Module, 主模块, ~228 h，23 子目录)            │
│  ───────────────────────────────────────────────────────────  │
│  • GameMode / GameState / PlayerController / PlayerState       │
│  • LyraCharacter / PawnData / HeroComponent / HealthComponent  │
│  • AbilitySystem 基类 (ASC/AttributeSet/Ability/Execution)     │
│  • Equipment / Inventory / Weapons（武器 & 装备基础框架）      │
│  • Teams / Cosmetics / Interaction / Camera / UI / Audio       │
│  • ★ GameModes/LyraExperienceDefinition + ExperienceManager    │
│  • ★ GameFeatures/GameFeatureAction_Add*（7 个自定义 Action）    │
│  • ★ LyraGameFeaturePolicy（全局 Plugin 策略）                  │
└──────┬───────────────────────────────────────────────────────┘
       │（反向依赖：Plugin.Build.cs 里写 "LyraGame"）
       │
       ▼
┌─────────────────────────────────────────────────────────────┐
│  Plugins/GameFeatures/   （业务 GameFeature, ExplicitlyLoaded） │
│  ──────────────────────────────────────────────────────────   │
│  ShooterCore    : 14.h + 258 资产  (射击玩法零件库)            │
│  ShooterMaps    : 0.h  + 5325 资产 (地图集合, 纯资产插件)      │
│  ShooterExplorer: 0.h  + 48 资产   (冒险模式, 叠在 Core 上)    │
│  ShooterTests   : 9.h  + 30 资产   (测试, Shipping 排除)       │
│  TopDownArena   : 5.h  + 85 资产   (俯视角模式, 独立玩法)      │
└─────────────────────────────────────────────────────────────┘

启动时：GameFeatures 全部「Registered」但未加载代码/资产到内存
↓
玩家进入某个 Experience（例如 B_TopDownArenaExperience）
↓
ExperienceManagerComponent 读取 GameFeaturesToEnable = ["TopDownArena"]
↓
UGameFeaturesSubsystem::LoadAndActivateGameFeaturePlugin("TopDownArena")
↓
TopDownArena 插件代码/资产加载完成
↓
Experience 的 Actions 数组逐个 Activate
   · AddAbilities → 给玩家授予 TDM 相关能力
   · AddInputContextMapping → 注入该模式 IMC
   · AddWidget → 加 HUD 组件
↓
状态进入 Loaded，玩法开始
```

---

## §2 GameFeature 核心价值评估

> 解决什么问题 → FDRPG 是否命中 → 价值打分（★ 1~5）

| # | GameFeature 解决的核心问题 | FDRPG Demo 是否命中 | 价值（★ 1~5） |
|---|---|---|---|
| 1 | **模块热插拔**（运行时加载/卸载） | 不命中。Demo 单机、无 DLC、所有副本启动即可访问 | ★ |
| 2 | **章节 DLC 可独立发布** | 不命中。Demo 只发一次完整版 | ★ |
| 3 | **不同玩法模式共享主干**（PvP/PvE） | 不命中。Demo 只有 PvE Roguelike 一种模式 | ★ |
| 4 | **超大 Game 模块拆分** | 部分命中但**不是瓶颈**。Lyra 主模块 228+ h 已是大模块范例，工作良好 | ★★ |
| 5 | **并行开发隔离**（多人同时改不冲突） | 小团队不命中。单人 / 2~3 人为主 | ★ |
| 6 | **测试代码 Shipping 排除** | **命中（但 Demo 阶段低优先级）**。v1.0 后有 CI 需求时必接 | ★★★ |
| 7 | **纯资产插件隔离**（地图集合） | 部分命中。4 副本各 300MB+ 资产，拆分利于版本控制 | ★★★ |
| 8 | **章节上叠加内容**（ShooterExplorer 模式） | **v1.0+ 命中**，Demo 不命中 | ★★ |
| 9 | **章节选择单独打包 + 下载** | 完全不命中（单机、无在线 patch） | ☆ |
| 10 | **调试隔离**（临时关掉某副本快速定位问题） | **轻度命中**，但单模块用 `#if` 预编译宏或 DeveloperSettings 开关一样能做 | ★★ |

**综合判断**：GameFeature 的 10 个典型价值点中，FDRPG Demo 命中度最高的是 #7（资产隔离），但纯资产插件**不需要 C++ 模块**（参考 ShooterMaps），成本极低、随时可拆。**无一条命中需要 C++ 代码分包**。

---

## §3 FDRPG 对 GameFeature 的需求匹配分析

> 基于 01~07 策划案，逐条核查"某个 FDRPG 系统是否应该 GameFeature 化"。

### 3.1 候选系统逐个打分

| FDRPG 系统 | 特征 | 是否适合 GameFeature？ | 建议归属 |
|---|---|---|---|
| **角色属性 / GAS 扩展**（Health/Stamina/Focus） | 全局基础，所有副本/UI 都用 | ❌ 不适合。基础类必须全局可用，不能等某 Experience 激活才生效 | 主模块 `RPGGame/AbilitySystem/` |
| **双武器系统**（主副武器切换） | 全局基础 | ❌ 不适合。同上 | 主模块 `RPGGame/Weapons/` |
| **存档系统**（策划案 03） | 全局，初始点就要能存 | ❌ 不适合。存档子系统必须 GameMode 一上来就活 | 主模块 `RPGGame/Save/` |
| **肉鸽强化系统**（5 层词条） | 仅副本内激活 | **△ 理论可 GameFeature，但 Demo 不必**。副本共用词条库 = 主模块共享；各副本独有词条 = 少量资产差异，可由 Experience 的 ActionSet 切换 DataAsset 实现 | 主模块 `RPGGame/Roguelike/`（Demo）；v1.0+ 可拆 `RPG_RoguelikeCore` |
| **初始点枢纽场景** | 单一场景，启动默认激活 | ❌ 不适合。Lyra FrontEnd 模式直接用，无需单独 GameFeature | 主模块 Content + Experience |
| **副本 #1 · 破碎钟楼** | 独立场景 + 专属敌人 + 专属机制 | **△ Demo 不必，v1.0+ 可拆**。资产量大 → 拆成"纯资产 Plugin"（仿 ShooterMaps）即可，不需要 C++ 模块 | Demo: 主 Content/Maps/；v1.0+: `RPGMaps_DungeonChime`（纯资产） |
| **副本 #2 · 锈蚀工厂** | 同上 | 同上 | 同上 |
| **副本 #3 · 溺亡之歌**（水下机制？） | 可能有独特玩法 | **△ 看策划落地**：若水下 = 专属 CharacterMovementComponent + 专属 UI，有一定独立性 | Demo: 主模块；若机制独特可 v1.0+ 单独 `RPG_UnderwaterPack` |
| **副本 #4 · 永燃废墟** | 同 #1 | 同 #1 | 同 #1 |
| **4 把武器**（分别做成 Plugin？） | 强绑核心战斗循环 | ❌ **不适合**。武器基类必须在主模块，单把武器 = 1 个 DataAsset + 1 个子 Ability BP，不值得 Plugin | 主模块 `RPGGame/Weapons/` + DataAsset 配置 |
| **外观 / 角色皮肤 DLC** | 纯资产叠加 | **v1.0+ 适合**。完全仿 Lyra Cosmetics | v1.0+: `RPGCosmetics_*` 纯资产 GameFeature |
| **调试功能**（Cheats/Debug UI/测试关） | 仅开发期使用 | **命中**（但 Demo 阶段可用 DeveloperSettings/#if 代替） | Demo: 主模块 `RPGGame/Development/` + `#if !UE_BUILD_SHIPPING`；v1.0+ 建议拆 `RPGTests` 仿 ShooterTests，Shipping 自动排除 |
| **对话系统**（若启用 CommonConversation） | 全局 | ❌ 不适合 | 主模块 |

### 3.2 关键对比：FDRPG 副本切换 vs Lyra 玩法切换

| 维度 | Lyra 工程里的做法 | FDRPG 可行做法 |
|---|---|---|
| 玩法模式切换（射击 ↔ 俯视角） | 两个独立 GameFeature：ShooterCore + TopDownArena | FDRPG 只有一种玩法（Roguelike ARPG），**无玩法模式切换需求** |
| 同玩法下不同地图切换 | 单 GameFeature（ShooterMaps）内切多个 map；或同 Experience 内 LevelStreaming | **FDRPG 4 副本都是同玩法**，最适合：**LevelStreaming + 同一 RPGGameMode + 多 Experience DataAsset** |
| 地图集合打包 | ShooterMaps（纯资产 Plugin，0 C++） | Demo 直接放 `Content/Maps/Dungeons/` 即可，**v1.0+ 资产膨胀后再拆成纯资产 Plugin** |

**结论**：FDRPG 的"副本切换"**不是 Lyra 的"玩法切换"，而是 Lyra 的"地图切换"**。用 Experience + LevelStreaming 就完美覆盖，**不需要 GameFeature**。

### 3.3 Demo 阶段的真实场景清单（4 个 Experience 就够）

```
B_RPG_Hub_Experience               ← 初始点枢纽
B_RPG_Dungeon_Chime_Experience     ← 副本 1 · 破碎钟楼
B_RPG_Dungeon_Factory_Experience   ← 副本 2 · 锈蚀工厂
B_RPG_Dungeon_Song_Experience      ← 副本 3 · 溺亡之歌
B_RPG_Dungeon_Ashes_Experience     ← 副本 4 · 永燃废墟
（+ 1 个 FrontEnd Experience 做主菜单，共 5 个）
```

**这 5 个 Experience 的 `GameFeaturesToEnable` 全都是空数组**（Demo 阶段无业务 GameFeature）。差异仅在：
- `DefaultPawnData`（不同副本可能换 PawnData，如带 BossEntry 音效差异）
- `Actions`（加不同的 IMC 切换、HUD 组件、副本专属成就 Widget）
- `ActionSets`（共享"战斗 HUD ActionSet"、"RPG 基础输入 ActionSet"）

---

## §4 三档方案对比 + 明确推荐

### 方案 A · 完全不用 GameFeature（不推荐）

**做法**：
- 所有代码/资产放 `RPGGame` 主模块 + `Content/`
- **连 Experience 机制也绕开**，改用传统 `DefaultGameMode` + `OpenLevel`
- 关闭（不引用）Lyra 主模块里的 `GameFeatures/` 子目录代码

**优点**：简单直观。

**致命缺点**：
- 等于**把 Lyra 最核心的设计全部扔掉**，沦为"空 UE5 项目手搓 ARPG"
- 无法复用 Lyra 的 FrontEnd、关卡切换加载进度、多 Pawn 配置等基础设施
- 角色组装（HeroComponent/PawnExtensionComponent）失去激活时机（依赖 Experience Loaded 事件）
- **与 07 文档的 Phase A 所有"基于 Lyra 基座"设定相矛盾**

**判决**：❌ 不要选。跟 Lyra 做的工作量差异 = **半年 vs 整年 Demo 周期**。

---

### 方案 B · 轻度使用 GameFeature（✅ 强烈推荐）

**做法**：
- **保留 Lyra 全部 GameFeature 基础设施**（`Plugins/GameFeatures` 插件本体 + 主模块内的 7 个 Action + `LyraGameFeaturePolicy`）
- **全面使用 Experience + ActionSet 机制做场景切换**
- **业务代码 0 个 GameFeature Plugin**，全部放主模块 `RPGGame` 及其子目录
- **Demo 的 5 个 Experience 的 `GameFeaturesToEnable` 全部为空**
- 保留 Lyra 自带 5 个 `Plugins/GameFeatures/Shooter*` + `TopDownArena`，仅用作**只读参考**，不加载到 RPG Experience
  - 在 RPG 的 Experience 里明确不引用它们 → 运行时不激活 → 无性能/内存负担
  - **保留它们的源码/资产** → 随时打开查看 Lyra 官方写法

**优点**：
- Demo 阶段架构简单（单模块），**编译速度快、调试直接**
- 保留 Lyra 所有设计模式（Experience、PawnData、ModularGameplay、HeroComponent 注入时机）
- **零架构债**：v1.0 要上新副本 DLC / 新玩法时，直接新建一个业务 GameFeature 叠加即可，**不改老代码**
- 5~7 个月 Demo 周期**完全够**

**缺点**：
- 主模块会略微膨胀（预计最终 150~250 个 .h，对标 Lyra 228 h 量级）—— 但**这是经验证的可接受规模**，Lyra 自己就这么干
- `RPGGame/` 下代码耦合度略高于"纯 GameFeature 化" —— 但 Demo 阶段耦合 = **快速调试** > **干净分层**

**判决**：✅ **推荐**。唯一理由充分的方案。

---

### 方案 C · 重度使用 GameFeature（Demo 阶段不推荐）

**做法**：
- 每个副本一个 GameFeature Plugin：`RPG_Dungeon_Chime` / `RPG_Dungeon_Factory` / `RPG_Dungeon_Song` / `RPG_Dungeon_Ashes`
- 武器也分 Plugin：`RPG_Weapon_Melee` / `RPG_Weapon_Ranged` / `RPG_Weapon_Staff` / `RPG_Weapon_Shield`
- 肉鸽系统独立：`RPG_RoguelikeCore`
- 测试独立：`RPGTests`
- 主模块只留最薄的基类（Character/ASC/AttributeSet/SaveSubsystem）

**优点**：
- 彻底隔离，未来扩展最灵活
- 对标 Lyra 官方推荐架构

**致命缺点**：
- **Demo 工期增加 20~40%**：每个 Plugin 的 uplugin、Build.cs、目录结构、模块注册都要搭建和维护
- 跨 Plugin 类引用必须走 `GameFeatureAction`（不能直接 include .h 硬引用）→ 调试路径变长
- 新人上手成本高（GameFeatureAction 的类型选择、时机、Activate 流程理解门槛）
- **Demo 期暴露不出架构收益**：4 副本都同步开放、无 DLC、无模式切换 → Plugin 化收益 ≈ 0
- **过早优化**的典型反模式

**判决**：❌ Demo 阶段坚决不选。**v1.0 之后如果规模真起来了，再选择性地拆**。

### 4.1 三方案最终对比表

| 维度 | A · 完全不用 | **B · 轻度（推荐）** | C · 重度 |
|---|---|---|---|
| Lyra Experience 机制 | ❌ 绕开 | ✅ 全面使用 | ✅ 全面使用 |
| Lyra 原生 GameFeature 基础设施 | ❌ 抛弃 | ✅ 保留 | ✅ 保留 |
| 业务 GameFeature Plugin 数量 | 0 | **0（Demo）/ 按需（v1.0+）** | 8~12 个 |
| Lyra 自带 Shooter* / TopDownArena | 删除 | **保留作只读参考** | 删除 |
| Demo 工期影响 | **工期 +50%**（等于重写 Lyra） | **零影响** | **工期 +20~40%** |
| 调试难度 | 高（没有基础设施） | **低** | 中高（跨 Plugin 追踪） |
| 架构债 | 极高（抛弃 Lyra） | **零** | 中（提前分得太细，后期改结构成本高） |
| 适合团队规模 | 单人 | **1~3 人** | 5+ 人 |
| v1.0+ 演进难度 | 需重构 | **最平滑**：业务没分，想拆随时拆 | 最顺（已经拆好） |
| 推荐度 | ❌ 0% | **✅ 100%** | ❌ 15% |

### 4.2 最终决策锁定（v1.1）

> **已采纳方案 B + 具体执行参数锁定**。主理人 2026-05-11 签字。

| 执行参数 | 锁定值 |
|---|---|
| 业务 GameFeature Plugin 数量 | **0**（Demo 全程） |
| Lyra 自带 5 个业务 GameFeature | **完整删除**（DP-2）—— 与 v1.0 推荐中的"保留作只读参考"不同，主理人选择更彻底的做法 |
| Lyra GameFeature 基础设施 | **全保留**（DP-1）：`Plugins/GameFeatures/` 插件本体 + `ModularGameplay` + 主模块 `GameFeatures/` 子目录（7 个 Action + Policy）+ `GameModes/`（Experience 机制） |
| Experience 数量 | **7 个**（DP-4），见 §6.2 |
| Experience 的 `GameFeaturesToEnable` | **全部 = `[]` 空数组** |
| CommonUI + UIExtension | **全用**（DP-6）—— PrimaryGameLayout 四层栈 + UIExtensionSubsystem 插槽 |
| v1.0+ 演进时机 | **Demo 阶段完全不约定**（DP-5）—— §7 所有"拆 Plugin"动作降级为"v1.0 之后评估"参考阅读，不进入路线图 |

**理由收敛为一句话**：**GameFeature 是解决"未来会发生的复杂度"的架构工具，但 Demo 阶段 FDRPG 没有任何一项复杂度已经发生；而 Experience 机制本身就能覆盖所有 Demo 场景，所以"保留基础设施 + 删掉不用的业务 Plugin + 业务全放主模块"是帕累托最优。**

---

## §5 对 07 项目改造执行方案的必执行修订清单（v1.1）

> v1.0 时本节还是"建议"，v1.1 锁定后升级为 **07 文档 v1.1 必须完成的修订项**。07 v1.1 已完成以下所有修订，本节保留作为**对照检查清单**。

### 5.1 07 文档必执行修订项（implementer 无需执行，仅核对）

| 07 文档位置 | 必做修订 | 完成状态 |
|---|---|---|
| §0 文档定位 | 新增"v1.1 协同修订说明"，引用 08 v1.1 的 6 项决策 | ✅ 已写入 |
| §3 命名映射规则 | 新增"保留/删除清单"：明确列出 Lyra 基础设施插件全保留、5 个业务 GameFeature 全删除 | ✅ 已写入 |
| §3.6 Lyra 子插件 | 从"不改"细化为"**保留并全启用 11 个基础插件**"列表 | ✅ 已写入 |
| §4.2 Lyra 模板拷贝 | 改为"**从 `d:/UE_Work/FDRPG/LyraStarterGame/` 拷贝，排除 5 个业务 GameFeature**"，给出 robocopy 排除参数 | ✅ 已写入 |
| §5.3 拆 GameFeature 时机 | 简化为"**Demo 阶段不拆；v1.0 再评估**"（对齐 DP-5 保守决定） | ✅ 已写入 |
| §7 启动验证清单 | 新增验证项：UnrealMCP 可用 / CommonUI+UIExtension 启用 / 5 个业务 GameFeature 不在目录 / LyraFrontend 能加载 | ✅ 已写入 |
| §8 后续切片 | 对齐 7 个 Experience 的落地时机 | ✅ 已写入 |
| §9 Build.cs 配置 | 新增"GameFeature 基础设施保留清单"（插件启用列表） | ✅ 已写入 |
| §11 Day 1~5 清单 | **Day 1 重写**（删除 5 个业务 Plugin + 拷贝 Lyra + 改名模块）；**Day 3 补充**（CoreRedirects + Tag 批改） | ✅ 已写入 |
| §13（新增章节） | **Day 1 即刻执行清单**（命令行级别） | ✅ 已写入 |

### 5.2 §9 GameFeature 基础设施保留清单（已写入 07 v1.1 §9.x）

以下文件是 Lyra 主模块的 GameFeature 体系核心，**Demo 阶段全部保留并改名**：

```
Source/RPGGame/GameFeatures/          ← 子目录保留
├── GameFeatureAction_AddAbilities.h/cpp       → RPGGameFeatureAction_AddAbilities
├── GameFeatureAction_AddGameplayCuePath.h/cpp → 同上
├── GameFeatureAction_AddInputBinding.h/cpp    → 同上
├── GameFeatureAction_AddInputContextMapping.h/cpp → 同上
├── GameFeatureAction_AddWidget.h/cpp          → 同上
├── GameFeatureAction_SplitscreenConfig.h/cpp  → 同上
├── GameFeatureAction_WorldActionBase.h/cpp    → 同上
└── LyraGameFeaturePolicy.h/cpp                → RPGGameFeaturePolicy

Source/RPGGame/GameModes/              ← Experience 机制代码
├── LyraExperienceDefinition.h/cpp             → RPGExperienceDefinition
├── LyraExperienceManagerComponent.h/cpp       → RPGExperienceManagerComponent
├── LyraExperienceActionSet.h/cpp              → RPGExperienceActionSet
├── LyraExperienceManager.h/cpp                → RPGExperienceManager
├── AsyncAction_ExperienceReady.h/cpp          → AsyncAction_RPGExperienceReady
├── LyraUserFacingExperienceDefinition.h/cpp   → RPGUserFacingExperienceDefinition
└── LyraWorldSettings.h/cpp                    → RPGWorldSettings
```

### 5.3 §9 Lyra 基础设施 Plugin 保留清单（11 个，已写入 07 v1.1）

**全部保留且启用**（插件内部代码不改名，只改主模块对它们的外部引用）：

| Plugin | 保留理由 |
|---|---|
| `Plugins/AsyncMixin/` | 异步加载工具，GAS/Experience 加载依赖 |
| `Plugins/CommonGame/` | CommonUI 的游戏层封装，LyraFrontend 依赖 |
| `Plugins/CommonLoadingScreen/` | 关卡切换 Loading 界面，Experience 加载时显示 |
| `Plugins/CommonUser/` | 玩家身份/登录抽象（单机也要，否则 PlayerState 初始化链断） |
| `Plugins/GameFeatures/`（插件本体） | GameFeature 生命周期核心，DP-1 必留 |
| `Plugins/GameplayMessageRouter/` | Lyra 消息总线，解耦通信基础 |
| `Plugins/GameSettings/` | 设置菜单框架，CommonUI 依赖 |
| `Plugins/GameSubtitles/` | 字幕系统（Demo 不用但不影响编译，留着以备扩展） |
| `Plugins/LyraExampleContent/` | 基础共享美术资产（大厅、UI 素材），LyraFrontend 依赖 |
| `Plugins/LyraExtTool/` | Lyra 内部编辑器扩展 |
| `Plugins/ModularGameplayActors/` | ModularCharacter 基类所在，LyraCharacter 的父类 |
| `Plugins/PocketWorlds/` | 局部世界（角色选择预览场景），DP-4 角色选择 Experience 需要 |
| `Plugins/UIExtension/` | UIExtensionSubsystem，DP-6 必留 |

**删除清单**（`Plugins/GameFeatures/` 目录下，5 个业务 GameFeature 整目录删除）：

| Plugin | 删除理由 |
|---|---|
| `ShooterCore/` | 射击玩法零件库，反向依赖 `LyraGame`，改名后必失败 |
| `ShooterMaps/` | 射击地图集合，5325 个 .uasset，纯浪费磁盘 |
| `ShooterExplorer/` | 射击冒险模式，依赖 ShooterCore |
| `ShooterTests/` | 射击测试，依赖 ShooterCore |
| `TopDownArena/` | 俯视角竞技场模式，俯视角相机实现可在 LyraStarterGame 原始副本中参考 |

**运行期验证**：删除后，RPG 编辑器启动时 Output Log 搜 `Shooter` / `TopDownArena`，应 **0 命中**。

---

## §6 Demo 阶段可执行规划

### 6.1 Demo 全程 GameFeature 相关动作清单

| Phase | 时间窗 | GameFeature 相关动作 |
|---|---|---|
| **A1**（Day 1~5） | Week 1 | **删除 5 个业务 GameFeature** → 保留 Lyra GameFeature 基础设施 → 主模块改名 RPGGame |
| **A2**（Week 2~3） | 输入/PawnData + **Experience_FrontEnd_Menu 跑通** | 1 个 Experience |
| **A3**（Week 3~5） | 战斗/GAS | 不涉及 GameFeature |
| **A4**（Week 5~7） | 存档/肉鸽 + **Experience_HubWorld** | 累计 2 个 Experience |
| **A5**（Week 7~10） | 4 副本 Experience + 角色选择 Experience | 累计 7 个 Experience |
| **A6**（Week 10~16） | UI/打磨/交付 | 不涉及 GameFeature |
| **里程碑 M · Demo 发布** | 月末 | **0 个业务 GameFeature Plugin + 7 个 Experience** |

### 6.2 Experience 数据表（DP-4 锁定，7 个）

> implementer 按下表创建 7 个 `URPGExperienceDefinition` 子类 DataAsset。所有 Experience 的 `GameFeaturesToEnable` 字段**固定为空数组 `[]`**。

| # | Experience 资产名 | 用途 | DefaultPawnData | Actions（关键） | ActionSets | 创建时机 |
|---|---|---|---|---|---|---|
| 1 | `B_RPG_Experience_FrontEnd_Menu` | 主菜单（对标 Lyra `B_LyraFrontEnd_Experience`） | 无（MenuPawn 或 None） | `AddWidget`（主菜单 Widget 到 Menu 层）+ `AddInputContextMapping`（菜单 IMC） | `DA_RPG_ActionSet_MenuUI` | **A2** |
| 2 | `B_RPG_Experience_CharacterSelect` | 角色选择（PocketWorlds 预览） | 无（使用 PocketWorlds 内的预览 Pawn） | `AddWidget`（角色选择 Widget）+ PocketWorlds 配置 | `DA_RPG_ActionSet_CharSelectUI` | **A5** |
| 3 | `B_RPG_Experience_HubWorld` | 初始点枢纽（观测塔，世界观文档 04） | `DA_RPG_PawnData_Hero` | `AddWidget`（枢纽 HUD：简化版，无战斗条）+ `AddInputContextMapping`（移动/交互，**无战斗输入**） | `DA_RPG_ActionSet_CoreInput` + `DA_RPG_ActionSet_HubHUD` | **A4** |
| 4 | `B_RPG_Experience_Dungeon_BrokenBellTower` | 副本 1：破碎钟楼 | `DA_RPG_PawnData_Hero`（**4 副本共用**，Demo 单角色） | `AddWidget`（战斗 HUD + BossHealthBar 占位）+ `AddAbilities`（副本专属机关触发能力） | `DA_RPG_ActionSet_CoreInput` + `DA_RPG_ActionSet_CombatInput` + `DA_RPG_ActionSet_CombatHUD` + `DA_RPG_ActionSet_CoreAbilities` | **A5** |
| 5 | `B_RPG_Experience_Dungeon_RustedFactory` | 副本 2：锈蚀工厂 | 同上 | 同上（机关能力差异） | 同上 | **A5** |
| 6 | `B_RPG_Experience_Dungeon_DrowningSong` | 副本 3：溺亡之歌 | 同上 | 同上（若有水下机制，追加 `AddAbilities`：呼吸/游泳） | 同上 | **A5** |
| 7 | `B_RPG_Experience_Dungeon_EternalEmbers` | 副本 4：永燃废墟 | 同上 | 同上（机关能力差异） | 同上 | **A5** |

**ActionSet 共享复用清单**（Content/System/ActionSets/）：
- `DA_RPG_ActionSet_CoreInput`（基础 IMC：移动/相机/交互）—— 3~7 号共用
- `DA_RPG_ActionSet_CombatInput`（战斗 IMC：攻击/切换武器/闪避）—— 4~7 号共用
- `DA_RPG_ActionSet_MenuUI`（主菜单 UI）—— 1 号专用
- `DA_RPG_ActionSet_CharSelectUI`（角色选择 UI）—— 2 号专用
- `DA_RPG_ActionSet_HubHUD`（枢纽 HUD：简化版）—— 3 号专用
- `DA_RPG_ActionSet_CombatHUD`（血条/焦点条/十字准心）—— 4~7 号共用
- `DA_RPG_ActionSet_CoreAbilities`（GAS 核心能力：普攻/受伤/死亡/交互）—— 4~7 号共用

**规则**：
1. **每个 Experience 的 `GameFeaturesToEnable` 固定 `[]`**（整表强制）
2. **DefaultPawnData**：主菜单/选角 = None；枢纽 = Hero；4 副本 = Hero（Demo 单角色）
3. **副本间差异**只在 `Actions` 字段的 `AddAbilities`（副本专属机关能力）和少量 Widget，不在 ActionSet

### 6.3 检查点（M 节点验收）

Demo 交付前，确认：
- [ ] `Source/RPGGame/` 代码量在 150~250 .h 区间（对标 Lyra）
- [ ] `Source/` 下**没有** `RPG_*` 业务 Plugin 目录
- [ ] `Plugins/GameFeatures/` 目录为**空**（或仅剩 UE 自带的 GameFeatures 插件本体），**5 个 Shooter*/TopDownArena 已不存在**
- [ ] `Plugins/` 保留 11 个 Lyra 基础设施插件（见 §5.3 清单）+ UnrealMCP
- [ ] **7 个 RPG Experience DataAsset 全部存在**，`GameFeaturesToEnable` 字段 100% 为空
- [ ] PIE 启动时 Output Log 无 `Shooter` / `TopDownArena` 相关日志（= DP-2 生效）

---

## §7 后续 v1.0+ 演进路径（**参考阅读 · Demo 不预埋**）

> **DP-5 决定**：Demo 阶段**完全不约定任何演进触发条件**。本节所有内容**降级为 v1.0 发布后的评估参考**，不进入 Demo 路线图。implementer **不要**在 Demo 工期内做以下任何动作，即使看到 Content/Maps/ 资产膨胀也不拆。
>
> 本节保留只为给 v1.0 后的同事一个"历史推演参考"，并非路线图。

### 7.1 第一个业务 GameFeature：`RPGMaps`（纯资产，最安全） — **v1.0 之后评估**

**触发**：资产总量（Content/Maps/ + Dungeons 资源包）超过 2GB 或第 5 个副本立项。

**步骤**：
1. 新建 `Plugins/GameFeatures/RPGMaps/RPGMaps.uplugin`，照抄 ShooterMaps.uplugin：
   ```json
   {
     "CanContainContent": true,
     "ExplicitlyLoaded": true,
     "EnabledByDefault": false,
     "BuiltInInitialFeatureState": "Registered",
     "Plugins": [ { "Name": "RPGGame", "Enabled": true } ]
   }
   ```
   （**无 Modules 字段**，零 C++）
2. 把所有 `Content/Maps/Dungeons/` 资产**整体 Migrate** 到 `Plugins/GameFeatures/RPGMaps/Content/Maps/`
3. 修改每个 `B_RPG_Dungeon_*_Experience` 的 `GameFeaturesToEnable` 字段，追加 `"RPGMaps"`
4. 用 AssetReferenceRestrictions 配置验证：没有主模块资产引用 RPGMaps（理应没有）

**风险**：低。纯资产移动，CoreRedirects 可处理所有硬引用。
**工期**：1~2 天。

### 7.2 第二个：`RPGTests`（测试 Plugin，Shipping 自动排除） — **v1.0 之后评估**

**触发**：团队开始做 CI / 自动化回归 / 有调试 Widget 不想进 Shipping 包。

**步骤**：新建 `Plugins/GameFeatures/RPGTests/`，照抄 `ShooterTests.uplugin`，关键字段：
```json
"Modules": [ {
  "Name": "RPGTestsRuntime",
  "Type": "Runtime",
  "LoadingPhase": "Default",
  "TargetConfigurationDenyList": [ "Shipping" ]
} ]
```
把所有 `#if !UE_BUILD_SHIPPING` 包裹的 Debug 工具代码从主模块迁出。

**工期**：3~5 天。

### 7.3 第三个：第一个叠加型副本 Plugin（`RPG_DungeonPack_X`） — **v1.0 之后评估**

**触发**：v1.0 后的新副本 #5 作为可选 DLC 发布。

**步骤**：仿 `ShooterExplorer`。uplugin 依赖 `RPGGame + RPGMaps`。里面放：
- 1 个新 Experience（新副本）
- 1~2 个新怪物 BP
- 1~3 个新肉鸽词条 DataAsset
- 可能 1 个新 GameplayAbility（副本专属机关触发）
- 若需新 C++ 类（罕见），建一个薄 Runtime 模块

**依赖主模块全部基类**，不重写 Character/ASC。

**工期**：初次 1 周（搭 Plugin 框架），之后每个新副本 Plugin 2~3 天。

### 7.4 完全不推荐的演进方向（即使 v2.0 也别做）

- ❌ 每把武器独立 Plugin
- ❌ 每个 GA 独立 Plugin
- ❌ 把 GAS/Save/Equipment 基础框架拆出主模块

**理由**：这些是业务地基，频繁被引用，拆成 Plugin 后跨模块引用代价远大于隔离收益。Lyra 官方的示范是"基础零件留主模块，玩法组装拆 GameFeature"，我们照做。

---

## §8 附录

### 8.1 关键源码位置索引（本报告引用自）

| 内容 | 文件 |
|---|---|
| Experience 结构体 | `LyraStarterGame/Source/LyraGame/GameModes/LyraExperienceDefinition.h` |
| Experience 加载逻辑 | `LyraStarterGame/Source/LyraGame/GameModes/LyraExperienceManagerComponent.cpp` (L187~L354) |
| GameFeature Policy | `LyraStarterGame/Source/LyraGame/GameFeatures/LyraGameFeaturePolicy.cpp` |
| 7 个自定义 Action | `LyraStarterGame/Source/LyraGame/GameFeatures/GameFeatureAction_*.h/cpp` |
| ShooterCore uplugin | `LyraStarterGame/Plugins/GameFeatures/ShooterCore/ShooterCore.uplugin` |
| ShooterTests Shipping 排除 | `LyraStarterGame/Plugins/GameFeatures/ShooterTests/ShooterTests.uplugin` (L25-27) |
| TopDownArena C++ | `LyraStarterGame/Plugins/GameFeatures/TopDownArena/Source/TopDownArenaRuntime/Public/LyraCameraMode_TopDownArenaCamera.h` |

### 8.2 术语对照表

| 术语 | 解释 |
|---|---|
| GameFeature Plugin | 带 `ExplicitlyLoaded=true` 三件套字段的 Plugin，走 GameFeaturesSubsystem 生命周期 |
| 业务 GameFeature | 承载具体玩法/副本/模式代码的 GameFeature（对比：基础设施 GameFeature = GameFeatures 插件本体） |
| Experience | `ULyraExperienceDefinition`，一份 DataAsset 描述"这场游戏体验=什么 Pawn+激活哪些 Plugin+执行哪些 Action" |
| ActionSet | `ULyraExperienceActionSet`，可被多个 Experience 引用的 Action 集合，复用载体 |
| GameFeatureAction | 一段可执行的注入指令（加 Ability / 加 Widget / 加 IMC …），Experience 加载完成后依次执行 |
| BuiltInInitialFeatureState | "Registered" = 登记未加载；"Loaded" = 代码加载；"Active" = 全激活。Lyra 业务 Plugin 全用 "Registered" |
| Experience 7 阶段 | Unloaded → Loading → LoadingGameFeatures → LoadingChaosTestingDelay → ExecutingActions → Loaded → Deactivating |

### 8.3 一页纸速查决策树

```
问：X 系统要不要做成 GameFeature？

是否满足至少一条？
  □ 需要 Shipping 自动剔除（测试/Debug）
  □ 资产总量 > 2GB 的独立包
  □ 是可选 DLC / 后期发布
  □ 是完全不同的玩法模式（非同玩法的新副本）
  □ 引入了会被多个 DLC 复用的全新功能模块

  ├─ 是 → 考虑 GameFeature
  │    │
  │    └─ 且当前 Demo 未发布？
  │         ├─ 是 → 推迟到 v1.0+，Demo 期继续放主模块
  │         └─ 否 → 照 §7 步骤新建 Plugin
  │
  └─ 否 → 放主模块 RPGGame/<子目录>/
```

### 8.4 v1.1 决策一览卡（可打印 A4）

> 主理人与 implementer 桌面速查卡。所有决策均以此为准。

```
╔══════════════════════════════════════════════════════════════════════╗
║        FDRPG · v1.1 架构决策一览卡 · 2026-05-11 锁定                 ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  【6 项决策】                                                        ║
║  DP-1  Lyra 基础设施 GameFeature ......... 全保留，改 RPG 命名      ║
║  DP-2  Lyra 5 个业务 GameFeature ......... 完整删除                 ║
║  DP-3  Demo 业务 GameFeature Plugin ...... 0 个（全放 RPGGame 主模块）║
║  DP-4  Experience 深度使用 ............... 7 个（见下）             ║
║  DP-5  v1.0+ 演进时机 .................... Demo 不约定，v1.0 再评估║
║  DP-6  CommonUI + UIExtension ............ 全用                     ║
║                                                                      ║
║  【7 个 Experience 清单】                                            ║
║    1. B_RPG_Experience_FrontEnd_Menu          (主菜单)             ║
║    2. B_RPG_Experience_CharacterSelect        (角色选择)           ║
║    3. B_RPG_Experience_HubWorld               (枢纽：观测塔)       ║
║    4. B_RPG_Experience_Dungeon_BrokenBellTower   (副本1：破碎钟楼) ║
║    5. B_RPG_Experience_Dungeon_RustedFactory     (副本2：锈蚀工厂) ║
║    6. B_RPG_Experience_Dungeon_DrowningSong      (副本3：溺亡之歌) ║
║    7. B_RPG_Experience_Dungeon_EternalEmbers     (副本4：永燃废墟) ║
║  所有 Experience 的 GameFeaturesToEnable = []                       ║
║                                                                      ║
║  【Lyra Plugin 保留/删除清单】                                       ║
║  删除（整目录）：                                                   ║
║    ✗ Plugins/GameFeatures/ShooterCore/                              ║
║    ✗ Plugins/GameFeatures/ShooterMaps/                              ║
║    ✗ Plugins/GameFeatures/ShooterExplorer/                          ║
║    ✗ Plugins/GameFeatures/ShooterTests/                             ║
║    ✗ Plugins/GameFeatures/TopDownArena/                             ║
║  保留（11 个基础插件 + UnrealMCP）：                                ║
║    ✓ AsyncMixin                   ✓ LyraExampleContent              ║
║    ✓ CommonGame                   ✓ LyraExtTool                     ║
║    ✓ CommonLoadingScreen          ✓ ModularGameplayActors           ║
║    ✓ CommonUser                   ✓ PocketWorlds                    ║
║    ✓ GameplayMessageRouter        ✓ UIExtension                     ║
║    ✓ GameSettings                 ✓ GameSubtitles                   ║
║    ✓ UnrealMCP (项目已有)                                           ║
║                                                                      ║
║  【命名改造规则】                                                    ║
║    主模块 LyraGame → RPGGame （含 .Build.cs / Target.cs / API 宏） ║
║    类名 ULyraXxx → URPGXxx / ALyraXxx → ARPGXxx （详见 07 §3.3）   ║
║    Tag  Lyra.* → RPG.*                                              ║
║    .uproject  LyraStarterGame → RPGGame                             ║
║    插件内部类名不改（11 个保留插件 + UnrealMCP）                    ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## §9 变更日志

| 版本 | 日期 | 作者 | 变更摘要 |
|---|---|---|---|
| v1.0 | 2026-05-10 | ue-rpg-architect-57 | 首版。完成 Lyra 架构实地摸底、3 档方案对比、推荐方案 B、对 07 文档协同修订建议 |
| **v1.1** | **2026-05-11** | ue-rpg-architect-57 | **主理人签字锁定 6 项决策**。§0 新增决策一览；§4.2 升级为"最终决策锁定"；§5 升级为"必执行修订清单"并扩充 Plugin 保留/删除清单；§6.2 新增 7 个 Experience 数据表；§7 标注"Demo 不预埋，v1.0 之后评估"；§8.4 新增"v1.1 决策一览卡" |

---

> **本文档 v1.1 作为签字版本，任何后续变更需新开 v1.2 并经主理人同意。implementer 的 Day 1 按 07 v1.1 §13 执行。**
