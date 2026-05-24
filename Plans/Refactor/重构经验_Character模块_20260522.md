# Character 模块重构 · 经验与原则总结

> 重构日期：2026-05-22 凌晨
> 范围：`Script/Character/`、`Script/AI/BossAI.gd`、`Script/AI/States/AIState_Attack.gd`、
>      `Script/GAS/AbilitySystemComponent.gd`、`Script/UI/HUD.gd`、`Script/Util/`、
>      `Scenes/Characters/Player.tscn`、`Scenes/Characters/Enemy_Slime.tscn`
> 自测：✅ lint=0 / 编辑器 0 Parse Error / 端到端启动正常 / bootstrap_from_entity sets=3 + Regen 三件套全 apply

---

## 一、本次重构的关键成果

### 1.1 行数变化

| 文件 | 重构前 | 重构后 | 变化 |
|---|---|---|---|
| `PlayerCharacter.gd` | 306 | **35** | **-88.6%** |
| `EnemyCharacter.gd` | 200 | 100 | -50% |
| `BaseCharacter.gd` | 183 | 165 | -10%（功能下沉而非删减） |
| `AnimationComponent.gd` | 95 | 64 | -33%（删 2D 路径） |
| `MoveComponent.gd` | 65 | 48 | -26%（删 2D 兼容） |
| `HitFlashController.gd` | 142 | 95 | -33%（删 2D 路径） |
| `BlockComponent.gd` | 126 | 119 | -6%（封装 + 简化） |
| `BossAI.gd` | 49 | 73 | +49%（自我订阅 attribute_changed） |

### 1.2 新增组件 / 工具

- `Script/Util/NodeFinder.gd`：静态工具类，消除 4 处 sprite 查找重复
- `Script/Character/Components/VisualComponent.gd`：表现层（朝向 + idle/run + ground_offset）
- `Script/Character/Components/InteractorComponent.gd`：玩家交互检测（按 G 找最近 InteractableTarget）
- `AbilitySystemComponent.bootstrap_from_entity()`：属性 Bootstrap 主入口（数据驱动）
- `AbilitySystemComponent.ensure_attribute_sets()`：声明性创建 AttributeSet
- `AbilitySystemComponent.remove_effects_with_granted_tag()`：替换 BlockComponent 的越权调用

### 1.3 SOLID 改善

| 原则 | 改善前 → 改善后 |
|---|---|
| **SRP** | PlayerCharacter 五合一 → 仅声明"我是玩家 + 我要哪些 Set" |
| **OCP** | 加新角色类型必改 PlayerCharacter/EnemyCharacter → 通过 `_get_required_attribute_set_classes` 虚函数表达 |
| **DIP** | BlockComponent `asc.call(&"_detach_active")` 越权 → ASC 暴露公共 API |
| **DRY** | 4 处 sprite 查找 / 2 处属性注入流程 → 全部收口到 NodeFinder + ASC.bootstrap |
| **SoC** | 表现/输入/交互/Bootstrap 四类混在 PlayerCharacter → 各组件独立 |

---

## 二、本次重构提炼的 6 条原则（建议进入项目规则）

下面这 6 条原则在本次重构中反复验证有效，建议进项目全局规则。

### 原则 1 · 角色类只承担"声明 + 组件聚合"

**陈述**：`BaseCharacter` 派生类（`PlayerCharacter` / `EnemyCharacter` 等）的职责应严格限制为：
1. 加入对应组（`player` / `enemy` 等）
2. 通过虚函数声明配置（必备 AttributeSet 类、是否跳过 Regen 等）
3. 极少量 AI / 阶段编排（如 EnemyCharacter 找 player target）

**禁止**：
- 表现层逻辑（朝向 / 动画切换 / sprite 查找）
- 输入路由（按键映射、技能槽路由）
- 交互检测（找最近 interactable）
- 属性 Bootstrap 流程（数据解算 / GE apply）
- 跨类型判断（`if ai is BossAI`）

**度量**：玩家 / 敌人类应控制在 **80 行以内**；超过通常意味着混入了上面禁止的内容。

### 原则 2 · 组件是"可复用的能力单元"，不是"分类容器"

**陈述**：每个 Component 应该有**单一明确的能力**，能被任意角色 .tscn 自由组合挂载，且**不依赖具体的角色类型**。

**判据**：组件应该满足"换一个角色继续用还能跑"。例如：
- `VisualComponent` 可挂玩家 / NPC / 任何有 Sprite 的角色 ✓
- `InteractorComponent` 玩家 / NPC（NPC 主动交互别的目标时）都能用 ✓
- `BlockComponent` 玩家专用，但只依赖 ASC 不依赖 PlayerCharacter ✓

**反例**：Component 内 `if get_parent() is PlayerCharacter` —— 立刻丧失复用性。

### 原则 3 · 聚合容器的"职责扩张" vs "外部组件" 选择题

**陈述**：当出现"某流程涉及容器 X 内部的多个对象 + X 持有的状态"时，把流程放进 X 内部，通常优于放在外部组件。

**本次案例**：属性 Bootstrap 涉及 ASC.attribute_sets（多个 Set） + ASC.tags + ASC.active_effects，所以放进 ASC 自身（`bootstrap_from_entity`），而不是写在 BaseCharacter / 独立服务类里。

**判据**：
- ✓ 流程的输入/输出主要落在容器内部 → 进容器
- ✗ 流程涉及多个独立模块的协作 → 用独立服务（DamagePipeline 是这种）

### 原则 4 · 移除兜底，崩溃式失败优于隐式降级

**陈述**：配置错误、必备组件缺失、契约违反等情况，应让代码**直接崩**（assert / push_error），不要静默降级 / 兜底创建 / 用默认值继续跑。

**本次执行**：
- `BaseCharacter._bootstrap_attributes`：entity_id 为空且 ASC 也没有 → assert 崩
- `MoveComponent._ready`：父节点不是 CharacterBody3D → assert 崩
- `InputComponent._try_activate_slot`：slot 越界 / ASC 缺失 → assert 崩
- `ASC.bootstrap_from_entity`：CharacterInstanceEntry 不存在 → assert 崩

**反例（已删）**：
- `_inject_data_driven_attributes` 中 `if def == null: return`
- `_ensure_player_attribute_sets` 兜底 `new HealthSet()`
- `BlockComponent` 中 `if EventBus.has_signal(...)` 防御
- `AnimationComponent` 中无视 `has_animation` 强行 `play()`（保留检查但不 warn 不 fall back）

**保留的 warn**：仅"运行时数据缺失但业务可继续"的情况（如 AnimationComponent 找不到 sprite，对纯 MeshInstance3D 的 BossDemo 是合理的）。

### 原则 5 · "声明性创建" 不等于"兜底创建"

**陈述**：当需要保证某些资源/对象一定存在时，区分两种语义：

- **兜底创建**：调用方不知道需要什么，被调方"补上一个默认的"——**反模式**，应删除
- **声明性创建**：调用方明确声明所需清单，被调方按清单创建（已存在不重复）——**合理模式**

**本次实现**：`ASC.ensure_attribute_sets(required_classes)` 是声明性创建：
- 调用方（BaseCharacter._bootstrap_attributes）把 `[HealthSet, PrimaryAttributeSet, CombatSet]` 显式传入
- ASC 按列表创建（已挂的不重复，没挂的 new）
- 列表本身的获取方式是子类必须 override 的虚函数，**强制声明**

这避免了"PlayerCharacter 内部硬编码三个 Set 名"的 OCP 违反。

### 原则 6 · 跨模块通信 ≠ 跨实例通信；同模块内"自己订阅自家信号"是合理模式

**陈述**：让组件 / AI / 子系统**自己订阅** EventBus 中"与自己相关"的信号，比让上层节点回调它们更解耦。

**本次案例**：原 `EnemyCharacter._on_attr_changed` 内部判 `if ai is BossAI: evaluate_phase(...)`；改造为 `BossAI._ready` 内 `EventBus.attribute_changed.connect(_on_attribute_changed)`，BossAI 自己过滤"是不是我的宿主"。

**收益**：
- EnemyCharacter 不再知道 BossAI 的存在 → LSP 改善
- 加新 AI 类型（如 EliteAI 关心 stamina 变化）时不动 EnemyCharacter → OCP 改善
- 测试时可以独立 mock BossAI 的订阅函数 → 可测试性提升

**注意**：这并不违反 R-EVENT-01（信号集中声明 in EventBus.gd）。组件订阅 EventBus 信号是预期用法；只要不在业务节点 emit 全局意图信号即可。

---

## 三、过程中踩过的坑（避免后续重蹈覆辙）

### 坑 1 · BaseCharacter.asc 字段类型从 `Node` 改 `AbilitySystemComponent` 后，多处 `as AbilitySystemComponent` 转换变冗余

**现状**：本次已改 `asc: AbilitySystemComponent`，但项目里还有不少 `(asc as AbilitySystemComponent)` 写法。这些写法仍能工作但啰嗦。

**建议**：后续重构时顺手清理。

### 坑 2 · @export 字段从子类移到父类时，场景 .tscn 必须同步改

**现象**：`entity_id` 从 `EnemyCharacter` 上移到 `BaseCharacter` 后，由于 .tscn 里写的是 `entity_id = &"slime_lv1"`，Godot 仍按字段名匹配能正确加载。但 **`ability_slot_to_id` 从 `PlayerCharacter` 移到 `InputComponent` 后，旧 .tscn 里 `[node name="Player"]` 上的 `ability_slot_to_id = ...` 行会被 Godot 静默忽略**（因为 PlayerCharacter 不再有此字段）。

**教训**：移动 @export 字段后，必须**同步重写 .tscn**，否则配置会丢失。本次发现 → 重写 Player.tscn 解决。

### 坑 3 · `class_name` 互相依赖时的循环引用风险

**现象**：`InputComponent` 引用 `MoveComponent` + `AbilitySystemComponent`；`VisualComponent` 引用 `MoveComponent` + `AnimationComponent`；BaseCharacter 引用 4 个组件类。GDScript 4.6 静态识别这些 class_name 不报错，但**修改 class_name 后必须 `Tools/godot.bat restart` 让引擎重扫脚本缓存**，否则 `is XxxComponent` 判断会误判 false。

**教训**：本次每次新增 class_name（NodeFinder / VisualComponent / InteractorComponent）后都跑了 R-VERIFY-01 的 restart 流程，所以没踩坑。但要写进经验里提醒。

### 坑 4 · MCP `execute_editor_script` 的 print 不会回到 output

**现象**：第一次用 print 调试时返回 `output: []`。改用 `push_warning` 后日志才出现在 editor_panel。

**教训**：MCP 自测脚本里**用 `push_warning` 而不是 `print`**，便于通过 `get_editor_logs(source="editor_panel")` 抓取。

---

## 四、对项目全局规则的建议

下面 4 条建议进入 `Plans/全局规则.md`（具体由用户决定是否采纳）：

### 建议 1 · 新增 R-CHAR-03 · 角色类瘦身原则

**草案**：
- BaseCharacter 派生类的 .gd 文件不超过 80 行
- 派生类禁止承担：表现 / 输入 / 交互 / 属性注入 / 跨类型判断
- 这些职责必须下沉到组件 / ASC / EventBus 订阅

### 建议 2 · 新增 R-CODE-01 · 崩溃式失败优于隐式兜底

**草案**：
- 配置错误（entity_id 不存在、CharacterInstanceEntry 找不到等）→ `assert` 崩
- 必备组件缺失（玩家 ASC、MoveComponent 等）→ `assert` 崩
- 仅当"运行时数据缺失但业务可继续"时用 GameLogger.warn + 静默跳过
- 兜底创建（"找不到就 new 一个默认的"）一律视为反模式

### 建议 3 · 完善 R-CHAR-01 · 加上 NodeFinder 为标准查找方式

**草案**：在现有 R-CHAR-01 后追加：
- 角色组件之间通过 `NodeFinder.find_first_child_of_type(parent, Type)` 查找彼此
- 禁止 `for child in get_children(): if child is X` 这样的内联查找（应用 NodeFinder 替代）
- 禁止用 `get_node_or_null("HardcodedNodeName")` 引用同级节点（应按类型查找）

### 建议 4 · 强化 R-DATA-02 · 属性 Bootstrap 走 ASC.bootstrap_from_entity

**草案**：在现有 R-DATA-02 后追加：
- 角色属性初始化必须走 `AbilitySystemComponent.bootstrap_from_entity(entity_id, level, classes, skip_regens)`
- 禁止角色脚本 / 组件直接调 `AttributeResolver.apply_to_asc()` / `cfg.resolve_character_attributes()`
- 子类只通过 override `_get_required_attribute_set_classes` / `_should_skip_regens` 表达差异

---

## 五、给下一个模块重构的建议

### 5.1 推荐复用的模式

1. **虚函数表达差异 + 模板方法收口共有逻辑**：本次 `_get_required_attribute_set_classes()` / `_should_skip_regens()` 是好范例，下次类似多子类共有流程时优先用这种方式
2. **静态工具类消除查找重复**：`NodeFinder` 的 3 个 API 已经够覆盖 90% 场景；下次再发现重复时直接扩展它而不是另开新类
3. **聚合容器扩展公共 API 替代外部越权**：BlockComponent 调 `_detach_active` → 改用 `remove_effects_with_granted_tag` 是一个好案例；下次发现"外部要调内部 _xxx 方法"时，先考虑给容器加公共 API

### 5.2 慎重处理的点

1. **场景 .tscn 同步**：每次移动/重命名 @export 字段，必须同步重写所有引用它的 .tscn
2. **跨模块影响检查**：每次删字段前 grep 一遍其它模块（本次 HUD.gd 引用 `pc.ability_slot_to_id` 差点漏掉）
3. **R-VERIFY-01 自测**：每次 commit 都要跑 lint + restart + 端到端 run_project，能抓出 90% 的隐性 bug

### 5.3 暂未处理的待办（不在本次范围）

- `EnergyComponent._DEFAULT_GAIN_PER_HIT = 1.0` 硬编码，待 D6 EnergyGainTable 实装
- `HitDamageResolver._find_asc` 还有 `node.has_method(&"get_asc")` 这种鸭子类型查找，可优化
- `ASC.consume_block` 内部又调 `bc.call(&"stop_block")` 也是动态调用（虽然合规但可改强类型）
- ConfigCenter 至今没有 class_name → 全项目用 `get_node_or_null(^"ConfigCenter")` 弱类型访问，后续可统一

---

## 六、本次自测结果（R-VERIFY-01）

```
✅ Step 1 - read_lints: 0 errors, 0 warnings
✅ Step 2 - Tools/godot.bat restart: 编辑器重启成功
✅ Step 3 - get_editor_logs (editor_panel):
   - 0 Parse Error / 0 Script Error
   - Player.tscn / Enemy_Slime.tscn 实例化无错（16 / 10 组件齐）
✅ Step 4 - run_project 端到端：
   - InputController ready (watched=12)
   - ASC ready on Player, sets=0（启动期对，bootstrap 后变 3）
   - HealthInit_Full / HealthRegen / StaminaRegen / BlockRegen 全部 apply
   - bootstrap_from_entity done: entity=player_lv1 lv=1 sets=3
   - Player ready (move=true anim=true hit=true hurt=true asc=true entity=player_lv1)
✅ Step 5 - stop_project: 正常返回编辑器
```

---

## 七、变更记录

| 日期 | 变更 |
|---|---|
| 2026-05-22 00:50 | v1.0 首版完成；Character 模块重构落地 + 自测通过 |
