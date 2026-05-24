# 玩家走 Lyra 标准路径 · Editor 配置指南

> **背景**：当前 Demo 用 `ARPGCharacterWithAbilities`（自带 ASC）已能让 NPC 跑通 GAS 链路，但**玩家**应回归 Lyra 标准 —— `ARPGCharacter` + `URPGHeroComponent`（GameFeature 注入）+ PlayerState 持有 ASC。
>
> **目标**：让玩家 PIE 启动后 `showdebug abilitysystem` 屏幕显示 `RPGCharacter_0` 的 8 个 Init/Derive/Regen GE 全部 Active。
>
> **代码侧已完成**：
> - ✅ UE 5.7 引擎自带 `UGameFeatureAction_AddComponents`（无需自写）
> - ✅ `URPGHeroComponent` 实现完整（IGameFrameworkInitStateInterface 全套钩子）
> - ✅ `URPGPawnExtensionComponent.InitializeAbilitySystem` 是 HeroComponent 的回调入口
> - ✅ `ARPGPlayerState` 持有 ASC + 在 OnExperienceLoaded 时调 SetPawnData → AbilitySet.GiveToAbilitySystem
> - ✅ Build/Editor 已编译通过（已链接 `UGameFeatureAction_AddComponents`）
>
> **你要做的事**：在 Editor 里配置 **3 个资产**，约 5 分钟。

---

## 总览：Lyra 玩家初始化链路

```
Map 加载
  ↓
ARPGGameMode.HandleMatchAssignmentIfNotExpired
  ↓
ULyraExperienceManagerComponent 加载 B_RPG_Experience_TestArena
  ↓ (Experience 加载完成)
执行 Experience.Actions[] 列表中的每个 GameFeatureAction
  ├─ UGameFeatureAction_AddComponents (本指南要新增)
  │   └─ 给 ARPGCharacter 注入 URPGHeroComponent
  └─ ...其他 Action（Input/Widget/Cue 等）
  ↓
Pawn Spawn (ARPGCharacter)
  ↓
URPGHeroComponent::OnRegister() → RegisterInitStateFeature
  ↓
HeroComponent 收到 InitState_Spawned → DataAvailable → DataInitialized
  ↓ (DataInitialized 阶段)
HeroComponent.HandleChangeInitState
  → PawnExtComp.InitializeAbilitySystem(PlayerState.ASC, PlayerState)
    → ASC.InitAbilityActorInfo(OwnerActor=PlayerState, AvatarActor=Pawn)
    → 触发 PawnExtComp.OnAbilitySystemInitialized
      → ARPGCharacter.OnAbilitySystemInitialized → HealthComponent 初始化
  ↓
PlayerState.OnExperienceLoaded (此时 PawnData 已就绪)
  → SetPawnData(PawnData)
    → 遍历 PawnData.AbilitySets[]
    → AbilitySet.GiveToAbilitySystem(PlayerState.ASC)
      → 8 个 GE 依次 Apply → 30+ 属性初值正确

最终：showdebug abilitysystem 屏幕显示 RPGCharacter_0 的 ASC（实际位置在 PlayerState）
       上挂载 8 个 GE + 2 个 AttributeSet + 30+ 字段。
```

---

## Step 1：把 PawnData 的 PawnClass 切回 `RPGCharacter`

> 之前为应急把 `DA_RPG_PawnData_Default.PawnClass` 改成了 `RPGCharacterWithAbilities`，现在要切回 Lyra 标准 `RPGCharacter`。

### 1.1 操作步骤

1. Content Browser 进入：`Content/Characters/Heroes/RPG/`
2. 双击打开 `DA_RPG_PawnData_Default.uasset`
3. 在 Class Defaults / Details 面板找 **Pawn Class** 字段
4. 下拉选择 **`RPG Character`**（C++ 类，对应 `ARPGCharacter`）
   - **不要**选 `RPG Character With Abilities`
   - **不要**留 None
5. **Ability Sets** 字段保持 `AbilitySet_RPG_Vital` 不变 ✅
6. 顶部 **Save**（Ctrl+S）

### 1.2 验收

- [ ] **PD-1** PawnData.PawnClass = `RPGCharacter` ✅
- [ ] **PD-2** PawnData.AbilitySets 数组包含 `AbilitySet_RPG_Vital` ✅

---

## Step 2：在 Experience 里加 `Add Components` Action

> 这是**关键步骤**。Experience 资产现在是空的（只引用 PawnData），必须新增一个 GameFeatureAction 把 HeroComponent 注入到 RPGCharacter 上，否则 Pawn 永远拿不到 ASC。

### 2.1 操作步骤

1. Content Browser 进入：`Content/System/Experiences/`
2. 双击打开 `B_RPG_Experience_TestArena.uasset`
3. 在 Class Defaults / Details 面板找 **Actions** 数组（类型：`UGameFeatureAction[]`）
   - 通常在 "Gameplay" 分类下
   - 如果没看到 Actions 字段 → 切换到 Class Defaults 视图
4. 点击 Actions 数组右侧的 `+` 按钮（**Add Element**）
5. 在新增 Element 的下拉选择器里 → 搜索 **`Add Components`** → 选 `UGameFeatureAction_AddComponents`
6. 展开这个新增 Element，找 **Component List** 数组 → 点 `+` 增加一项
7. 配置该 Component Entry：

| 字段 | 值 |
|---|---|
| **Actor Class** | `RPGCharacter`（C++ 类，**不是** `RPGCharacterWithAbilities`） |
| **Component Class** | `RPGHeroComponent`（C++ 类） |
| **Client Component** | ✅（勾上） |
| **Server Component** | ✅（勾上） |

> ⚠️ 注意：`Actor Class` 和 `Component Class` 的下拉里**会同时出现 BP 子类**，请明确选 C++ 原始类（图标是 C++ 蓝色圆点，名称是 `RPGCharacter` / `RPGHeroComponent`）。

8. **Save**（Ctrl+S）

### 2.2 完整配置截图（应有的状态）

```
B_RPG_Experience_TestArena
├─ Default Pawn Data: DA_RPG_PawnData_Default
└─ Actions[0]: GameFeatureAction_AddComponents
   └─ Component List[0]:
      ├─ Actor Class: RPGCharacter (C++ class)
      ├─ Component Class: RPGHeroComponent (C++ class)
      ├─ Client Component: ✅
      └─ Server Component: ✅
```

### 2.3 是否需要再加其它 Action？

A3 阶段**不需要**。后续阶段会按需添加：

| Action 类型 | 何时需要 |
|---|---|
| `Add Input Context Mapping` | A4 接入 EnhancedInput（IMC_RPG_Default 等） |
| `Add Input Binding` | A4 接入 InputAction → GA 绑定（武器攻击/格挡/闪避） |
| `Add Abilities` | 选用：把额外 Ability/AbilitySet 在 Experience 层注入（与 PawnData.AbilitySets 二选一） |
| `Add Widget` | A6 注入 HUD（血条/蓝条 Widget） |
| `Add Gameplay Cue Path` | A5 美化阶段把额外的 Cue 资产路径加入 |

### 2.4 验收

- [ ] **EXP-1** `B_RPG_Experience_TestArena.Actions[]` 至少 1 个 Element ✅
- [ ] **EXP-2** Element 类型是 `Add Components` ✅
- [ ] **EXP-3** Component List 含 1 项：RPGCharacter → RPGHeroComponent，Client+Server 都勾选 ✅
- [ ] **EXP-4** 资产 Save 完成（Content Browser 该资产无 `*` 标记） ✅

---

## Step 3：验证

### 3.1 启动 PIE

`L_TestArena01` → Play

### 3.2 检查 Output Log

PIE 启动后**立即搜**这几条关键日志：

```
RPGHeroComponent
```

**应能看到**（顺序大致如此）：

```
LogRPGAbilitySystem: [HeroComponent] OnRegister - Spawned -> DataAvailable -> DataInitialized -> GameplayReady
LogRPGAbilitySystem: [PawnExtComp] InitializeAbilitySystem with PS ASC <addr>
LogRPGAbilitySystem: [A2] PlayerState SetPawnData → granted N AbilitySet(s)
```

### 3.3 控制台命令

```
showdebug abilitysystem
```

按 ` 关闭控制台 → 屏幕左上应显示：

```
GAMEPLAYEFFECTS for avatar RPGCharacter_0 (authority)
  GE_PrimaryAttributes_Init    [completed]    Mod: HealthBase.Override 100, ...
  GE_HealthSet_Init            [completed]    Mod: StaminaMax.Override 100, StaminaCurrent.Override 100
  GE_Health_Derive_Max         [active]       Mod: HealthMax (Custom Calc URPGMMC_HealthMax)
  GE_Attack_Derive_Final       [active]       Mod: AttackFinal (Custom Calc URPGMMC_AttackFinal)
  GE_Defense_Derive_Final      [active]       Mod: DefenseFinal (Custom Calc URPGMMC_DefenseFinal)
  GE_Health_Init_Full          [completed]    Mod: HealthFinal.Override (AttributeBased HealthMax)
  GE_Stamina_Regen_OutOfCombat [active]       Period 0.10s, IgnoreTags: RPG.State.Combat.Active
  GE_Stamina_Regen_InCombat    [active]       Period 0.10s, RequiredTags: RPG.State.Combat.Active

CONTROLLER: RPGPlayerController_0  Pawn: RPGCharacter_0
```

按 **End 键**循环到 Attributes 类别，应看到：

```
URPGHealthSet (on PlayerState)
  HealthFinal:    100.000
  HealthMax:      100.000
  StaminaCurrent: 100.000
  StaminaMax:     100.000
  HealthHealing:  0.000 (Meta)
  HealthDamage:   0.000 (Meta, HideFromModifiers)

URPGPrimaryAttributeSet (on PlayerState)
  HealthBase:    100.000
  HealthBonus:   0.000
  HealthMul:     0.000
  AttackBase:    10.000
  AttackBonus:   0.000
  AttackMul:     0.000
  AttackFinal:   10.000
  DefenseBase:   10.000
  DefenseBonus:  0.000
  DefenseMul:    0.000
  DefenseFinal:  10.000
  MoveSpeed:     600.000
  CritChance:    0.050
  CritDamage:    0.500
  ...
```

### 3.4 完整 DOD

- [ ] **D-1** Output Log 出现 `[HeroComponent]` 字样 → HeroComponent 已注入 ✅
- [ ] **D-2** Output Log 出现 `granted N AbilitySet(s)` → AbilitySet 已 Give ✅
- [ ] **D-3** showdebug abilitysystem 屏幕显示 `RPGCharacter_0` Pawn（**不是** `RPGCharacterWithAbilities_0`） ✅
- [ ] **D-4** 屏幕显示 8 个 GE Active/Completed ✅
- [ ] **D-5** End 键切到 Attributes 类别 → HealthSet/PrimaryAttributeSet 全字段值正确 ✅

---

## 风险与回滚

### 风险 R1：HeroComponent 注入失败

**现象**：showdebug 还是只显示玩家信息，没看到 ASC 段；Output Log 找不到 `[HeroComponent]`。

**排查**：
1. 确认 Actor Class 选的是 `RPGCharacter`（C++）而不是 BP 子类 `BP_RPGCharacter` 等
2. 确认 Component Class 选的是 `RPGHeroComponent`（C++）
3. 确认 Client + Server 都勾选
4. 重启 Editor（不只是 Stop PIE）让 Experience 资产重新加载

### 风险 R2：还是看到 `RPGCharacterWithAbilities_0`

**现象**：屏幕 Pawn 名字仍然是 `WithAbilities`。

**根因**：PawnData.PawnClass 没改成功，或被其它机制覆盖。

**修复**：检查 GameMode 是否硬编码了 PawnClass override（搜 `RPGGameMode.cpp` 的 `DefaultPawnClass`）。一般情况下 `DA_RPG_PawnData_Default.PawnClass` 就是最终值。

### 风险 R3：8 个 GE 只 Apply 部分

**现象**：屏幕显示 ASC 已挂载，但只有 1-2 个 GE，不是 8 个。

**根因**：`AbilitySet_RPG_Vital` 内部 `Granted Gameplay Effects` 数组没填齐。

**修复**：打开 `AbilitySet_RPG_Vital.uasset`，确认 GrantedGameplayEffects 包含 8 个 GE（顺序按 §3.3.4 8 步）。

### 回滚

如果 Lyra 路径死活配不通，**临时回退**：把 `DA_RPG_PawnData_Default.PawnClass` 改回 `RPGCharacterWithAbilities`，玩家继续用自带 ASC 路径。**A3 验收一样能过**，只是后续 A4 接入 EnhancedInput → GA 时需要对应改造（HeroComponent 不存在意味着 Lyra 标准的 InputAction → AbilityInputBinding 链路也要单独搭建，工作量翻倍）。

---

## 与既有文档的关系

| 文档 | 涉及内容 |
|---|---|
| `19_A3_主理人配置清单.md` §4 | AbilitySet_RPG_Vital DataAsset 创建（保持不变） |
| `19_A3_主理人配置清单.md` §5 | DamageNumberSubsystem WBP 配置（保持不变） |
| `14_后续日程与验收清单.md` §3.10 V3.1 | 本指南完成后才能勾选 V3.1（属性初值正确） |

---

> **指南版本**：v1（2026-05-15）
> **维护人**：项目主理人
> **完成时间预估**：5 分钟（PawnData 切类 1 分钟 + Experience 加 Action 3 分钟 + 验证 1 分钟）
> **下一步**：A4 接入 EnhancedInput（同样在 Experience 加 `Add Input Context Mapping` + `Add Input Binding` 两个 Action）
