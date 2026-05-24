# 04 · Autoload 现状（C0-T4）

> **生成日期**：2026-05-21
> **数据来源**：`project.godot` `[autoload]` 段。
> **状态**：⚠️ **当前 10 项，已超出 R-ARCH-02 上限 6**。

---

## 一、当前 Autoload 列表（按 project.godot 注册顺序）

| # | 节点名 | 路径 | 来源里程碑 | 是否在白名单（R-ARCH-02 旧版） | 备注 |
|---|---|---|---|---|---|
| 1 | ConfigCenter | `res://Script/Core/ConfigCenter.gd` | M6 | ✅ | 集中加载配置；启动顺序最早（其它依赖它） |
| 2 | EventBus | `res://Script/Core/EventBus.gd` | M1 | ✅ | 全局信号集中点 |
| 3 | GameInstance | `res://Script/Core/GameInstance.gd` | M1 | ✅ | 顶层状态机；持 SkillTimelinePlayerHost / HitStopHost / VFXSpawner 子节点 |
| 4 | LevelManager | `res://Script/GameFramework/LevelManager.gd` | M1 / M5 实装 | ✅ | 关卡切换 |
| 5 | AudioManager | `res://Script/Audio/AudioManager.gd` | M1 / M5 实装 | ✅ | 三总线 + SfxBindings |
| 6 | SettingsManager | `res://Script/Settings/SettingsManager.gd` | M1 / M5 实装 | ✅ | ConfigFile 持久化 |
| 7 | InputContextManager | `res://Script/Input/InputContextManager.gd` | HUD P0-T1（2026-05-20） | ❌ **未入白名单** | InputContext 栈 |
| 8 | HUDManager | `res://Script/UI/HUDManager.gd` | HUD P1-T4 | ❌ **未入白名单** | 8 层 CanvasLayer 管理 |
| 9 | UIExtensionSubsystem | `res://Script/UI/UIExtensionSubsystem.gd` | HUD P1-T6 | ❌ **未入白名单** | slot 注册系统 |
| 10 | HUDStateMachine | `res://Script/UI/HUDStateMachine.gd` | HUD P1-T8 | ❌ **未入白名单** | 9 状态切换 |

## 二、规则现状（R-ARCH-02）

`Plans/全局规则.md` 第 41 行：

> R-ARCH-02 · Autoload 数量上限 **6**；仅限 EventBus / GameInstance / LevelManager / AudioManager / SettingsManager / ConfigCenter

**冲突**：HUD Phase 0 / Phase 1（用户已默认推进）引入了 4 个新 Autoload，规则未同步更新。
**rule-keeper 影响**：T5 规则扫描会爆 4 个 Error。

---

## 三、决策（用户已拍板 · 推荐方案）

**过渡期上限 10 + 目标态 6**：

1. **过渡期（现状）**：白名单 10 项 = 旧 6 + 新 4（Input/HUD 系列）。
2. **目标态**（HUD Phase 2 完成 + 第三步重构后）：4 个新 Autoload **收编为 GameInstance 子节点**（参考 M7.2 SkillTimelinePlayerHost 做法）：

```
GameInstance (Autoload, 第三个)
├── skill_timeline_player_host: SkillTimelinePlayerHost
├── hit_stop_host: HitStopHost
├── vfx_spawner: VFXSpawner
├── input_context_manager: InputContextManager   ← 收敛目标
├── hud_manager: HUDManager                       ← 收敛目标
├── ui_extension_subsystem: UIExtensionSubsystem  ← 收敛目标
└── hud_state_machine: HUDStateMachine            ← 收敛目标
```

收编后通过 `GameInstance.hud_manager` / `GameInstance.input_context_manager` 访问，不破坏现有调用站点（可用 alias 临时兼容）。

---

## 四、规则文档更新计划（→ C2-T1）

C2-T1 阶段我会修改 `Plans/全局规则.md` R-ARCH-02：

```diff
- ### R-ARCH-02 · Autoload 数量上限 6
+ ### R-ARCH-02 · Autoload 数量上限（过渡期 10 / 目标态 6）

- - **内容**：Autoload 仅限 `EventBus` / `GameInstance` / `LevelManager` / `AudioManager` / `SettingsManager` / `ConfigCenter`（M6 起新增）；新增 Autoload 必须先在 `Plans/开发计划.md` 或 `Plans/二期开发计划.md` 变更记录中说明并经用户确认。
+ - **内容**：
+   - **过渡期白名单（10 项）**：ConfigCenter / EventBus / GameInstance / LevelManager / AudioManager / SettingsManager / **InputContextManager** / **HUDManager** / **UIExtensionSubsystem** / **HUDStateMachine**
+   - **目标态白名单（6 项）**：ConfigCenter / EventBus / GameInstance / LevelManager / AudioManager / SettingsManager
+   - 其余 4 个（HUD 系列）必须在 HUD Phase 2 完成 + 第三步重构后**收编为 GameInstance 子节点**（参考 M7.2 SkillTimelinePlayerHost 做法）
+ - **过渡期截止**：第三步重构完成后；过渡期间不允许再新增 Autoload（三期 M11 DialogueRunner / M12 QuestManager / CurrencyManager 全部走 GameInstance 子节点路线）
```

同步更新 `规则变更记录` 追加：

```
| 2026-05-21 | R-ARCH-02 上限 6 → 过渡期 10 + 目标态 6；4 个 HUD Autoload 列入收编计划 | HUD Phase 0/1 已落地的事实 |
```

---

> **C0-T4 完成标记**：✅ 已生成。
