# M12 NPC + 对话 + 任务系统 - 开发日志

**完成日期**：2026-05-25
**关联策划/落地计划**：[NPC对话任务系统_落地计划_20260524.md](./NPC对话任务系统_落地计划_20260524.md)

---

## 一、本次交付内容

按落地计划 6 Phase 实施完毕，全部 R-VERIFY-01 通过，0 SCRIPT ERROR / 0 Parse Error。

### Phase 0：4 Loader + ConfigCenter API ✅

新增 4 个 CSV Loader（与 LootTableLoader 同模式，SOLID·SRP）：
- `Script/Data/Loaders/NPCConfigLoader.gd` —— NPC_Data + NPC_Diapack 二张表
- `Script/Data/Loaders/DialogueCsvLoader.gd` —— Dialogue 表
- `Script/Data/Loaders/QuestLoader.gd` —— Quest_Data 表
- `Script/Data/Loaders/ConditionLoader.gd` —— Condition 表

`ConfigCenter` 新增 7 个查询 API：
```
get_npc_def(npc_id) / get_diapack_entries(diapack_id)
get_dialogue_nodes(graph_id) / has_dialogue_graph(graph_id)
get_quest_step(quest_id, sub_id) / has_quest_step / find_quest_steps_by_deliver_dialogue
get_condition_set(cond_id)
```

启动日志验证：
```
ConfigCenter bootstrap done. ... npcs=2, diapacks=2, dialogues=5, quests=1, conditions=5
```

### Phase 1：ConditionEvaluator ✅

新建 `Script/Conditions/ConditionEvaluator.gd`：
- 静态 `eval(cond_id) -> bool`，支持 4 种 Type：`Lev / Quest_Ongoing / Quest_Finished / Quest_PendingDeliver`
- 同 cond_id 多 sub_id = AND 组合（A7 决策）
- cond_id <= 0 → true（无条件）
- cond_id 不存在 → true（fail-safe）

自测 7/7 PASS：
```
[PASS] cond_id=0 → true（无条件）
[PASS] cond_id=1 (Lev>=5) 默认1级 → false
[PASS] cond_id=2 (Quest_Ongoing 1) 未接 → false
[PASS] cond_id=3 (Quest_Finished 1) → false
[PASS] cond_id=4 (Quest_PendingDeliver 1) → false
[PASS] cond_id=5 (Lev>=3 AND Quest_Finished 1) AND → false
[PASS] cond_id=999 (不存在) → true (fail-safe)
```

### Phase 2：DialogueGraphLoader CSV 重写 + Runner 信号化 ✅

**对话子系统大改造**——把 StringName graph_id 体系切到 int + npc_id：

- **类字段 int 化**：DialogueGraph / DialogueNode / NextLink / ChoiceOption 全部 `node_id: int`
- **新建 DialogueGraphFactory**（替代 DialogueGraphLoader）：从 DialogueCsvLoader 取数据现场构图
- **DialogueRunner.start(graph_id: int, npc_id: int)** 双参数；信号 `dialogue_started/ended/aborted` 都加 npc_id 载荷
- **EventBus 新增** `dialogue_aborted` + `npc_dialogue_menu_requested`
- **DialogueRunner 用 ConditionEvaluator 替代 DialogueExpr**
- **CsvLoader 新增 `as_list_string`** API（配合 Branch_Text 解析）

**删除**：
- `Script/Dialogue/DialogueExpr.gd`（被 ConditionEvaluator 取代）
- `Script/Dialogue/DialogueGraphLoader.gd`（被 Factory 取代）
- `Script/Dialogue/Nodes/EffectNode.gd`（A1 决策：对话纯解耦）
- `Script/Dialogue/EffectHandlerRegistry.gd`（A1 决策）
- `Script/Dialogue/Handlers/*.gd` 全部 6 个 handler
- `Data/Manual/Dialogues/*.tres` 全部 2 个旧对话
- `project.godot` 移除 EffectHandlerRegistry Autoload 注册

**改造**：
- `NPCActor.gd` 字段 `dialogue_graph_id: StringName → int`，加 `npc_id: int`
- `HUDDebugCheats` F10 改为 `DialogueRunner.start(1001, 1)`
- `DialogueWidget.gd` / `InteractionPromptWidget.gd` 信号订阅签名 (int, int)
- `TestArena.tscn` ElderNPC 配置 `dialogue_graph_id = 1001 / npc_id = 1`

### Phase 3：NPCDialogueService + NPCActor 数据驱动 ✅

新建 `Script/Dialogue/NPCDialogueService.gd`：
- 静态服务（SOLID·SRP）：决定 NPC 互动该弹什么菜单
- 流程：NPC_Data.Diapack_ID → NPC_Diapack 子项 → ConditionEvaluator 过滤
  - 0 个可见 → `RESULT_NONE`（静默关闭）
  - 1 个可见 → 直接返回 graph_id（Q1b：自动跳过菜单）
  - ≥2 个可见 → `RESULT_MENU`（业务侧渲染菜单）

NPCActor 重写 `interact()`：
- 路径 1（兼容）：`dialogue_graph_id > 0` 时直接进入此对话
- 路径 2（M12 主路径）：`npc_id > 0` 时调 `NPCDialogueService.resolve_entry`，按结果分流

**菜单 Widget 暂未实装**（落地计划 Phase 3.5 待办）：≥2 选项时仅广播 `npc_dialogue_menu_requested` 信号，未来加 `NPCDiapackMenuWidget` 订阅渲染。当前测试数据村长 1 个可见选项，自动跳过菜单。

### Phase 4：QuestSystem 重写 + LevelLoader bulk_accept ✅

**QuestSystem 整体重写**：
- 状态键：`(quest_id: int, sub_id: int)` 二元组（编码为 `"q%d.s%d"` 字符串作 GameInstance.quest_states key）
- 状态机：`inactive → active → [pending_deliver] → completed`
- A3 接取路径：① `accept(quest_id)` / `bulk_accept([qids])`（仅当 sub_id=1 未激活时）；② 上一 sub 完成后自动接下一 sub
- A4 交付路径：监听 `EventBus.dialogue_ended(graph_id, npc_id)`，反查当前 active 步骤的 `Deliver_Dialogue_ID == graph_id`，若已达目标 → 完成
- A5 自动推进：`enemy_died` 推进 Kind=Monster；`item_added(owner, def, count)` 推进 Kind=Item；`dialogue_ended` 同时推进 Kind=NPC（按 npc_id）
- A2 奖励：`Drop_Rule_ID > 0` 时调 `LootSpawner.dispatch`（DRY，与怪物掉落同管线）

**EventBus 新信号**（M12 任务系统）：
```
quest_step_started(quest_id, sub_id)
quest_step_progress(quest_id, sub_id, current, target)
quest_step_pending_deliver(quest_id, sub_id)
quest_step_completed(quest_id, sub_id)
quest_series_completed(quest_id)
quest_abandoned(quest_id)
```
（旧 `quest_started / quest_objective_changed / quest_completed` 已删除）

**QuestTrackerWidget 重写**：
- 订阅新 `quest_step_*` 信号
- 步骤启动时显示 Toast「接受任务：xxx」
- pending_deliver 时显示「→ 回去汇报」提示
- 步骤完成时短暂淡出（1.5s），下一 sub 立即接上

**LevelDef 新字段** `init_quest_ids: PackedInt32Array`：
- LevelManager 在 `level_changed` 后调 `QuestSystem.bulk_accept(init_quest_ids)`
- A3：关卡初始化时自动接取，TestArena 直启时手动用 GM 命令测试（Shift+F8）

**清退**：
- `Data/Manual/Quests/quest_slay_slimes.tres` 删除
- `Script/Quest/QuestDef.gd / QuestObjective.gd / QuestReward.gd` 删除
- `ConfigCenter.get_quest_def` 删除

### Phase 5：GM 命令 ✅

`HUDDebugCheats` 新增 / 调整：
- `F10` → `DialogueRunner.start(1001, 1)` 启动村长接任务对话
- `Shift+F7` → `QuestSystem.complete_current_step(1)` 强制完成 quest_id=1 当前 active 步骤
- `Shift+F8` → `QuestSystem.bulk_accept([1])` 批量接取 quest_id=1（模拟关卡初始化）
- `F12` → `DialogueRunner.force_end()` 强制中断对话（已有，保留）

### Phase 6：开发日志 + 验收（本文）✅

---

## 二、SOLID / DRY 实践要点

### SRP（单一职责）
- 每个 Loader 只懂一张 csv（4 个独立 Loader）
- ConditionEvaluator 只做求值，不发信号、不操作 UI
- DialogueRunner 只播对话发信号，不知道 NPC / 任务 / 商店
- NPCDialogueService 只做"NPC → 弹什么菜单"决策，不发信号、不渲染
- QuestSystem 只做"状态机推进 + 奖励派发触发"，不渲染 UI
- LootSpawner 是统一的"奖励发放接口"（M12 验证已抽离，零工作）

### OCP（开放扩展，关闭修改）
- 新增 Condition Type（Item / Tag / Reach 等）= ConditionEvaluator match 加 1 分支
- 新增对话触发业务（传送 / cutscene / 小游戏）= 加新 Autoload 订阅 `dialogue_ended`，**不改任何既有文件**（A1 决策核心收益）
- 新增任务 Kind（Reach / Tricky）= QuestSystem 加 1 个 advance 函数

### DIP（依赖倒置）
- Evaluator / Service 收 cond_id / npc_id / quest_id 等抽象 ID，不直接依赖具体类
- 业务方通过 EventBus 信号通信，不直接调对端方法

### DRY（不重复）
- 奖励发放统一走 `LootSpawner.dispatch(drop_id)`（怪物 / 任务共用）
- 条件求值统一走 `ConditionEvaluator.eval(cond_id)`（对话选项 / NPC 菜单 / 任务接取共用）
- Loader 统一走 `CsvLoader.load_table` API（getter 链 `as_int / as_string / as_list_int / as_list_string`）

### R-EVENT-02（无 lambda 信号）
- 全部 connect 用具名 func（`_on_dialogue_ended` / `_on_step_started` 等）
- 0 lambda、0 .bind() 用法

---

## 三、R-VERIFY-01 自测记录

每个 Phase 末跑 read_lints + 直接进程跑 main_scene/TestArena + 抓日志：

| Phase | read_lints | runtime 启动 | 关键日志 |
|---|---|---|---|
| 0 | 0 | ✅ | `Loaders done: 2/2/5/1/5` + `bootstrap done` |
| 1 | 0 | ✅ | ConditionEvaluator 7/7 PASS |
| 2 | 0 | ✅ | DialogueRunner ready，无 effect 残留 |
| 3 | 0 | ✅ | `ElderNPC ready (npc_id=1)` |
| 4 | 0 | ✅ | `QuestSystem ready (M12 rewrite, sub-id chain mode)` + `QuestTrackerWidget mounted` |

---

## 四、踩坑沉淀

### 坑 1：新增 class_name 后直接进程跑 main_scene 报 Parse Error

**现象**：新建 NPCDialogueService.gd 后，TestArena 启动报 `Identifier "NPCDialogueService" not declared in the current scope.` × 5 处。

**根因**：`.godot/global_script_class_cache.cfg` 没注册新 class（cache 只在编辑器扫描时更新；直接进程跑不刷）。

**正解**：新增 .gd class 后**先跑一次** `Start-Process Godot --path . --editor --quit-after 60`（约 10-12s），让编辑器扫描后写 cache，再跑 runtime 验证。

**验证缓存注册**：`Select-String .godot\global_script_class_cache.cfg -Pattern "ClassName"`

### 坑 2：删除 .gd class 后 .tscn 残留引用

**现象**：删 EffectNode.gd 后，若有 .tscn 引用此类的 ext_resource，会让父场景子树整体不实例化。

**正解**：每次删 .gd / .tres 之后必跑全 .tscn 引用扫描：
```powershell
Get-ChildItem -Recurse -Include *.tscn,*.tres,*.uid | Select-String -Pattern "<deleted_class>"
```

### 坑 3：runtime 验证命令时长 + PowerShell CLIXML 污染

**现象**：`Start-Sleep 12` 后单条命令容易被 IDE 端 skip；PowerShell stdout 有时被序列化成 CLIXML。

**正解**：
- 单条命令 ≤ 12s（直接进程跑 + 短 sleep + Stop-Process Force）
- 长输出改读 `%APPDATA%\Godot\app_userdata\Dolphin\logs\godot.log` 拿全文
- runtime 命令一律 `requires_approval=false`，不再口头确认

---

## 五、未完待办（Phase 3.5 / 后续）

| 待办 | 说明 | 优先级 | 状态 |
|---|---|---|---|
| **NPCDiapackMenuWidget** | ≥2 个可见 Diapack 选项时的菜单 UI（订阅 `npc_dialogue_menu_requested` 信号） | P1 | ✅ **已完成（2026-05-25 23:55 后续提交）** |
| **NPC 头顶 ! / ?** | 任务可接 / 可交付时的视觉指示器 | P2 | ✅ **已完成（NPCQuestMarker.gd + NPC.tscn 接入；订阅 quest_step_* / dialogue_ended 自动刷新）** |
| **任务交付反查校验** | 当前对话 graph_id 与玩家正在对话的 NPC 是否匹配（避免任意 NPC 都能交付的过宽推进） | P2（用户设计为"任意 NPC 可交付"，可不做） | ❌ **跳过（与设计决策矛盾）** |
| **关卡 Init Quest 配置数据** | LevelDef.tres 实际填 init_quest_ids 字段，让真实关卡也走 bulk_accept 路径 | P1（任务实际生效必需） | ✅ **已完成（LevelDef_DialogueTest.tres + DialogueTestArena 直启场景兼容）** |
| **NPC_Diapack 数据一致性** | 当前村长选项 sub_id=2 (Dialogue=1102) 对应 sub=2 交付，但 Cond=4 (Quest_PendingDeliver q=1) 不区分 sub_id —— 需要为 q=1 不同 sub_id 各自待交付状态分别配 cond_id 和 NPC_Diapack 选项行（如村长应有"提交证物 1101"、"已剿史莱姆 1102" 等多行）| P2（数据完善，不阻塞架构） | ✅ **已完成（2026-05-25 02:00）：**<br>① Condition Type 枚举新增 `Quest_StepPendingDeliver`（Param=quest*100+sub）<br>② Condition cond=6/7/8/9 对应 q=1 sub=1/2/3/4<br>③ 村长 NPC_Diapack 重写 5 行严格对齐每个 sub_id 的 Deliver_Dialogue_ID<br>④ ConditionEvaluator 加 `_is_step_pending_deliver` 桥接 |
| **OpenShopHandler / ShopSystem** | 商店本期不做（A8） | P3（后续模块） | ⏳ |

---

## 六、文件清单

### 新增（11 文件）
```
Script/Data/Loaders/NPCConfigLoader.gd
Script/Data/Loaders/DialogueCsvLoader.gd
Script/Data/Loaders/QuestLoader.gd
Script/Data/Loaders/ConditionLoader.gd
Script/Conditions/ConditionEvaluator.gd
Script/Dialogue/DialogueGraphFactory.gd
Script/Dialogue/NPCDialogueService.gd
Data/FromExcel/NPC_Data.csv
Data/FromExcel/NPC_Diapack.csv
Data/FromExcel/Dialogue.csv
Data/FromExcel/Quest_Data.csv
Data/FromExcel/Condition.csv
```

### 改造（10 文件）
```
Script/Core/ConfigCenter.gd  —— 加 7 个 getter；删 get_quest_def
Script/Core/EventBus.gd  —— 改 dialogue_* 签名；新增 6 个 quest_step_* 信号
Script/Quest/QuestSystem.gd  —— 整体重写
Script/Dialogue/DialogueRunner.gd  —— 整体重写（int + npc_id）
Script/Dialogue/DialogueGraph.gd / DialogueNode.gd / NextLink.gd / ChoiceOption.gd  —— 字段 int 化
Script/Character/NPCActor.gd  —— 数据驱动重写
Script/UI/Widgets/QuestTrackerWidget.gd  —— 订阅新信号重写
Script/UI/Widgets/DialogueWidget.gd / InteractionPromptWidget.gd  —— 信号签名适配
Script/UI/HUDDebugCheats.gd  —— GM 命令调整
Script/GameFramework/LevelManager.gd / LevelDef.gd  —— bulk_accept 接入
Script/Data/CsvLoader.gd  —— 新增 as_list_string
Scenes/Levels/TestArena.tscn  —— ElderNPC 配置 npc_id=1
project.godot  —— 移除 EffectHandlerRegistry Autoload
```

### 删除（13 文件）
```
Script/Dialogue/DialogueExpr.gd
Script/Dialogue/DialogueGraphLoader.gd
Script/Dialogue/EffectHandlerRegistry.gd
Script/Dialogue/Nodes/EffectNode.gd
Script/Dialogue/Handlers/AddTagHandler.gd
Script/Dialogue/Handlers/CompleteQuestHandler.gd
Script/Dialogue/Handlers/HudToastHandler.gd
Script/Dialogue/Handlers/PlaySfxHandler.gd
Script/Dialogue/Handlers/SetVarHandler.gd
Script/Dialogue/Handlers/StartQuestHandler.gd
Script/Quest/QuestDef.gd
Script/Quest/QuestObjective.gd
Script/Quest/QuestReward.gd
Data/Manual/Dialogues/debug_test_graph.tres
Data/Manual/Dialogues/npc_elder_greeting.tres
Data/Manual/Quests/quest_slay_slimes.tres
```

---

## 七、Excel 测试数据（5 张表）

完整范例见 `Tools/Excel/{NPC表,对话表,任务表,触发条件表}.xlsx`。

**剧情线**：村长 4 步链式任务（quest_id=1）
1. sub=1 收集史莱姆证物 ×2 → 交付对话 1101 → Drop=2001（金币+经验）
2. sub=2 击杀小怪 A ×3 → 交付对话 1102 → Drop=2002
3. sub=3 拜访铁匠 ×1 → 交付对话 1103 → Drop=2003
4. sub=4 击败 BossB ×1 → 无交付对话直接完成 → Drop=2004
