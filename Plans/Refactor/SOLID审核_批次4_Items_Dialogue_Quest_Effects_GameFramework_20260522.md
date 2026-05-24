# SOLID 审核 · 批次 4：Items + Dialogue + Quest + Effects + GameFramework（L1 速扫）

> 审核日期：2026-05-22
> 范围：38 个 .gd 文件
> 严重级：🔴 Error / 🟡 Warning / 🟢 Note

---

## 1. Script/Items（8）

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| BossPortal.gd | 41 | 🟡 | 与 LevelTransitionArea 功能 95% 重叠（DRY 致命）；`_try_enter` 中 `level == null: return` 静默兜底 | 标记 deprecated 迁移到 LevelTransitionArea；或合并 |
| ConsumableDefinition.gd | 9 | 🟢 | 无明显问题 | 保留 |
| EquipmentComponent.gd | 99 | 🔴 | `_get_owner_asc` 用 `"asc" in owner` + 硬编码节点名双重兜底（违反 R-CHAR-01 + R-CODE-01）；`_unequip_internal` 硬编码兄弟节点名；`equip()` 中 `asc == null: return false` 静默降级 | 改用 NodeFinder；ASC 缺失改 assert |
| EquipmentDefinition.gd | 22 | 🟢 | Slot 枚举写死（武器/防具/饰品）— OCP 轻微但可接受 | 保留 |
| InventoryComponent.gd | 118 | 🟡 | 复用 EquipmentComponent 同款 `_get_owner_asc` 反模式（DRY）；`use()` 用 `if item is X` 链派发不同子类（OCP） | 抽 `CharacterComponent` 基类；用策略模式让 ItemDefinition 自分发 |
| ItemDefinition.gd | 22 | 🟢 | 纯数据基类 | 保留 |
| PickupArea.gd | 39 | 🟡 | `get_node_or_null("InventoryComponent")` 硬编码；`item == null: return` 兜底 | item null → assert；改 NodeFinder |
| VFXSpawner.gd | 50 | 🟡 | `EventBus.has_signal(...)` 防御；`offset_2d` 路径 M9 后应删；create_timer + lambda 释放有泄漏隐患 | 删防御 + 2D 分支；用 Tween/Timer 节点托管 |

---

## 2. Script/Dialogue（19）

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| ChoiceOption.gd | 16 | 🟢 | 纯数据 | 保留 |
| DialogueConfig.gd | 23 | 🟢 | 纯配置 Resource，R-DATA-02 落实 | 保留 |
| DialogueExpr.gd | 262 | 🟡 | 体量大但内聚（tokenizer+parser+evaluator 单文件 SoC 边界模糊）；多处鸭子类型 `asc.get(&"tags")` + `tc.has_method(&"has_tag")` | 拆 _Parser 独立文件；TagContainer 抽强类型 |
| DialogueGraph.gd | 39 | 🟢 | 纯数据 + 轻量 API | 保留 |
| DialogueGraphLoader.gd | 69 | 🟢 | TODO 受控；缓存字段未使用 | M10 联调后实装 |
| DialogueNode.gd | 20 | 🟢 | 基类清晰 | 保留 |
| DialogueRunner.gd | 283 | 🔴 | **类承担过多**：状态机+加载+占位符解析+HUD 切换+ASC 查询；6 处弱类型 Autoload 访问；硬编码 magic number 状态值 5/2；多处 `if cc == null: return` 兜底；`hsm.has_method(&"change_state")` 防御 | 拆 `DialogueTextResolver` + `DialogueHudBridge` + `DialoguePlayerContext`；状态值用枚举；Autoload class_name 化 |
| EffectHandlerRegistry.gd | 81 | 🟡 | Strategy 模式做得好；`_register_builtin` 硬编码 6 个 handler（OCP 轻微）；`handler.has_method(&"handle")` 防御 | 内置列表抽 .tres；handler 强类型化 |
| NextLink.gd | 13 | 🟢 | 纯数据 | 保留 |
| PortraitsConfig.gd | 16 | 🟢 | 纯数据 | 保留 |
| Handlers/AddTagHandler.gd | 34 | 🟡 | 玩家+ASC+TagContainer 三重 null/has_method 探测；与 QuestSystem._reward_tag 重复 | 抽 `PlayerLocator` 共享工具；TagContainer 强类型 |
| Handlers/CompleteQuestHandler.gd | 18 | 🟢 | `if QuestSystem == null` 防御 Autoload 多余 | 删 null 检查 |
| Handlers/HudToastHandler.gd | 18 | 🟢 | 干净 | 保留 |
| Handlers/PlaySfxHandler.gd | 23 | 🟢 | `am.has_method(&"play_sfx_by_id")` 防御多余 | 用 AudioManager 直调 |
| Handlers/SetVarHandler.gd | 22 | 🟢 | `gi.call(&"set_dialogue_var")` 弱类型 | GameInstance.set_dialogue_var(...) 直调 |
| Handlers/StartQuestHandler.gd | 18 | 🟢 | 同 CompleteQuestHandler | 删 null 检查 |
| Nodes/ChoiceNode.gd | 17 | 🟢 | 纯数据 | 保留 |
| Nodes/EffectNode.gd | 19 | 🟢 | 纯数据 | 保留 |
| Nodes/SpeechNode.gd | 23 | 🟢 | 纯数据 | 保留 |

---

## 3. Script/Quest（4）

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| QuestDef.gd | 30 | 🟢 | 纯数据 Resource | 保留 |
| QuestObjective.gd | 29 | 🟡 | `kind` 用 StringName 字符串硬编码 5 类；OCP 加新 kind 必改 QuestSystem._on_* 监听 | 改成 enum；或抽 ObjectiveTracker 子类按 kind 注册 |
| QuestReward.gd | 22 | 🟢 | 数据驱动设计良好 | 保留 |
| QuestSystem.gd | 272 | 🔴 | **多职责**：accept/abandon/complete + 监听推进 + reward dispatch + def 缓存（SRP）；`_on_enemy_died` 鸭子类型；硬编码节点名；6 处 `if X == null: return` 兜底；多处 has_signal 防御；与 AddTagHandler 重复 | 拆 `QuestProgressTracker` + `QuestRewardDispatcher` + `QuestRepository`；EnemyCharacter.entity_id 强类型；玩家+ASC 共享 PlayerLocator |

---

## 4. Script/Effects（3）

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| CueBinding.gd | 103 | 🟢 | 数据驱动模板；TODO 受控 | 保留 |
| CueBindings.gd | 33 | 🟢 | 干净 | 保留 |
| CueManager.gd | 148 | 🟡 | Tag 父匹配路由设计良好；BINDINGS_PATH 找不到时只 warn 不 assert | 缺资源改 assert；重复 add 走 stack 或 ignore 选项 export |

---

## 5. Script/GameFramework（4）

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| LevelDef.gd | 37 | 🟢 | 纯数据，R-DATA-02 良好 | 保留 |
| LevelManager.gd | 156 | 🟡 | 11 步异步流程线性堆叠在 `_run_load`（SRP/可读性）；`hsm.call(&"change_state", 8)` 硬编码 magic number；`_get_loading_widget` 三重回退查找 | HUDStateMachine.State 用枚举；流程拆 phase；group-only 查找 |
| LevelSpawnMarker.gd | 20 | 🟢 | 单一职责完美样本 | 保留 |
| LevelTransitionArea.gd | 110 | 🟡 | 与 BossPortal 95% 重复（DRY）；`require_interact` 双模式让单类承担接口+触发 Area 双职责（SRP） | 拆两子类；级别 null 改 assert |

---

## 批次小结

**Top 6 严重文件**：
1. **DialogueRunner.gd（283 行）🔴** — 与重构前 PlayerCharacter 同型同病
2. **QuestSystem.gd（272 行）🔴** — 4 职责堆叠
3. **EquipmentComponent.gd（99 行）🔴** — `_get_owner_asc` 双重兜底反模式
4. **LevelManager.gd（156 行）🟡** — 11 步流程线性堆 + magic number
5. **InventoryComponent.gd（118 行）🟡** — 同 EquipmentComponent 反模式
6. **LevelTransitionArea.gd / BossPortal.gd 🟡** — 95% 重复

**跨文件共性问题**（4 类）：
- **C1 · Autoload/同级节点弱类型访问**：15+ 处
- **C2 · 玩家+ASC+TagContainer 三段查询重复**：7 处
- **C3 · R-CODE-01 兜底反模式批量违规**：30+ 处
- **C4 · 硬编码 magic number / 节点名**：HUDStateMachine.State 数字（5/2/8）4 处 + 节点名 5+ 处

**与其他模块的耦合点**：
- Items ↔ Character：弱类型 `"asc" in owner`，应改 BaseCharacter 强类型
- Quest ↔ Dialogue：StartQuest/CompleteQuest 直调 QuestSystem ✓，但 if QuestSystem == null 防御多余
- Dialogue/Quest ↔ HUD：DialogueRunner 和 LevelManager 都通过弱类型 + magic number 切状态
- Effects/Cue ↔ Items/VFX：CueBinding emit signal → VFXSpawner 订阅，链路合规（推荐范式）

**待用户确认项**：
- **U1**：DialogueRunner 拆三组件还是只统一 Autoload 强类型 helper？
  - **2026-05-23 决定**：❌ **否决拆分**——283 行内"状态机+加载+占位符解析+HUD切换+ASC查询"是对话流程的本质耦合（同 ASC 决策）；改为 Autoload 直访 + magic number 枚举化 + has_method 防御删
- **U2**：BossPortal 与 LevelTransitionArea 合并？倾向 deprecated 平滑迁移
  - **2026-05-23 决定**：✅ deprecated 实施——BossPortal 标 @deprecated + 启动 push_warning；批次 5/6 期间迁移所有引用场景后再删除
- **U3**：QuestObjective.kind / EffectNode.effect_kind / QuestReward.kind 抽 `KindDispatcher[T]` 通用？
  - **2026-05-23 决定**：❌ 否决——三处 kind 字段语义完全不同，强抽通用 dispatcher 会引入泄漏抽象
- **U4**：HUDStateMachine.State 暴露 class_name 让外部用枚举常量？
  - **2026-05-23 决定**：✅ 实施——已用 `HUDStateMachine.State.LEVEL_TRANSITION` 等替换 magic number 8/2/5（GDScript 4.6 支持 Autoload 静态成员访问）
- **U5**：Items 三组件抽 CharacterComponent 基类？影响面大，需评估时机
  - **2026-05-23 决定**：❌ 否决——三组件只有"找 ASC"一处共性；改为引入 `PlayerLocator` 静态工具 + NodeFinder

---

## 2026-05-23 批次 4 完结总结

详见 `Plans/Refactor/批次4收尾_Items_Dialogue_Quest_Effects_GameFramework_20260523.md`。

主要成果：
- **新工具 PlayerLocator**：消除 7+ 处"玩家+ASC+TagContainer 三段查询"重复
- **C1 Autoload 弱类型 15+ 处全清** → Autoload 直访
- **C3 R-CODE-01 兜底反模式 30+ 处全删 / 改 assert**
- **C4 magic number 4 处** → `HUDStateMachine.State.*` 强类型枚举
- **U2 实施 / U4 实施 / U1·U3·U5 否决**
- **38 文件注释审计**：过期阶段标记 0 命中
- 自测全过：lint=0 / 编辑器 0 Parse Error / 启动期 EffectHandlerRegistry handlers=6 / DialogueRunner / QuestSystem / 全 Widget 注册
