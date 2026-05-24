# 重构进度 · U2 + U4 + DamagePipeline 收尾

**日期**：2026-05-23  
**触发**：用户回应 SOLID 审核 5 个待确认项 U1-U5  
**前置文档**：`Plans/Refactor/SOLID审核_批次1_Core_Data_GAS_20260522.md`

---

## 1. 用户决定汇总

| 项 | 决定 | 备注 |
|---|---|---|
| **U1** | ASC 631 行**需要拆**，但**另起独立 milestone** | 量大不混进当前批次 1 收尾 |
| **U2** | 删除 `CharacterAttributeSet` | 实测**早已删除**，审核报告是过时观察 |
| **U3** | （隐式确认）`_load_resource_typed(path, expected_class) -> Resource` | R-Core 已用此实现，按现状 |
| **U4** | DamagePipeline 4 魔数进 CombatBalanceConfig | 实测**早已配置化**，审核报告是过时观察 |
| **U5** | AttributeSet 反射改注册表 | R-PreChange 阶段已完成（声明式 hook 表 + _init 缓存） |

---

## 2. 实际改动

### 2.1 U2 复核（CharacterAttributeSet）

✅ 复核结果：**代码层早已彻底清理**，无需操作

证据：
- `Script/GAS/Attributes/CharacterAttributeSet.gd` 不存在（被 R-Attr 阶段删除，参见 `Plans/Refactor/重构进度_R-Attr_20260522.md` L113/121）
- `Script/` 全目录 grep `CharacterAttributeSet` 命中 0
- `Scenes/` 全目录命中 0
- `Data/` 全目录命中 0
- 仅 `Plans/` 目录有 17 处历史文档提及（属史料保留）

### 2.2 U4 复核（DamagePipeline 4 魔数）

✅ 复核结果：**早已配置化**，无需操作

证据：DamagePipeline.gd 的 4 个关键平衡系数读取均走 `bal: CombatBalanceConfig`：

| 公式 | 旧魔数（审核误指） | 当前实现 |
|---|---|---|
| 防御公式 K | `DEFENSE_K = 100` | `bal.defense_k`（默认 500，与旧案对齐） |
| 普通格挡减伤 | `BLOCK_REDUCTION = 0.4` | `bal.block_damage_reduction` |
| 格挡耐久消耗 | （审核未指） | `bal.block_durability_consume_ratio` |
| 完美格挡 buff 加成 | （审核未指） | `bal.perfect_block_buff_dmg_bonus` |
| 破韧基础占比 | `0.1` | `bal.break_base_ratio` |

`Data/Config/CombatBalanceConfig.tres` 8 个字段全部存在并赋值。

### 2.3 DamagePipeline 真正剩余清单收尾

审核 §批次小结 还有 4 个未处理项：

| # | 改动 | 原代码 | 新代码 |
|---|---|---|---|
| 1 | 鸭子类型 has_method | `if target.has_method(&"is_perfect_block_window") and target.call(&"is_perfect_block_window")` | `var bc: BlockComponent = NodeFinder.find_first_child_of_type(target, BlockComponent) as BlockComponent; if bc != null and bc.is_perfect_block_window()` |
| 2 | 鸭子类型 has_method | `if target.has_method(&"trigger_perfect_block_buff"): target.call(&"trigger_perfect_block_buff")` | `bc.trigger_perfect_block_buff()`（共享 #1 的 bc 引用，强类型直调） |
| 3 | 死接口 apply_break | `if target.has_method(&"apply_break"): target.call(&"apply_break", break_pts)` | 整段删除（apply_break 全项目零实现）；保留破韧值变量 `_break_pts` 加 TODO 注释为 D6 韧性条预留 |
| 4 | Autoload 反射访问 | `var gi: Node = attacker.get_tree().root.get_node_or_null(^"GameInstance"); if gi != null and gi.get(&"cue_manager") != null: gi.cue_manager.execute_cue(...)` | `GameInstance.cue_manager.execute_cue(...)`（R-ARCH-03 强类型直访，启动期必有，缺失即崩） |
| 5 | _get_asc 节点名兜底 | `var direct: Node = node.get_node_or_null(^"AbilitySystemComponent"); if direct is AbilitySystemComponent: return direct` | 整段删除；改为 `GameLogger.warn` 标识"调用方传错节点"并 return null |

收益：
- 整体减少 ~10 行代码
- 移除 4 处反射调用 + 1 处节点名硬编码兜底
- DamagePipeline.gd 当前状态：209 行 → 209 行（数学没动；行数变化主要是注释精简与 dead code 删除互相抵消）

---

## 3. 自测

| 维度 | 状态 |
|---|---|
| lint | ✅ 0 errors / 0 warnings |
| 编辑器 Parse Error | ✅ 0（仅 Boss/Visual 已知无害） |
| 启动期 bootstrap | ✅ Player sets=3 / TrainingDummy sets=1 / 全部 Widget 注册 |
| 数学链路回归 | ✅ DamagePipeline 内部所有 ASC.get_attribute / bal.xxx / 元属性管道路径**完全未动**；改动仅限鸭子类型查找方式与 Autoload 解析方式 |

**未在 MCP 自动化验证范围**：实际打击触发的伤害公式（运行时按键交互），按已确认原则纳入手测清单。

---

## 4. 审核报告同步

更新 `Plans/Refactor/SOLID审核_批次1_Core_Data_GAS_20260522.md`：
- L52（CharacterAttributeSet 行）→ 标 ✅ 已删
- L46-48（DamagePipeline 行）→ 标 ✅ 已修
- L82-86（U1-U5 行）→ 全部标 ✅ 已确认 / 已实现

---

## 5. 批次 1 当前状态

| 子阶段 | 状态 |
|---|---|
| R-Core | ✅ 完成（21 文件） |
| R-ASC | ✅ 完成（11 文件） |
| R-PreChange | ✅ 完成（声明式 hook 表 ≈ U5） |
| R-Data 角色属性部分 | ✅ 完成（3 JSON + AttributeResolver 重写） |
| **U2 / U4 / U3 / U5 收尾** | ✅ 本轮完成 |
| **U1（ASC 631 拆分）** | ⏳ 排独立 milestone |
| R-Data 剩余（GameConfig 顶层聚合 + 9 子配置） | ⏳ 待启动 |

---

## 6. 下一步候选

按用户决定 U1 独立排，剩余可走的：

- **A**：直接启动 **U1 milestone（ASC 631 拆分）**——本轮立即开始
- **B**：先做 **R-Data 剩余 GameConfig 顶层聚合**——批次 1 真正收尾
- **C**：先回 **a/b/c/d**（规则提案，3 条新规则）落盘，再开 A 或 B
- **D**：跳到 **批次 2（UI 重构）** 启动——HUDManager / DialogueWidget 拆分

**我的建议顺序**：**C → B → A**
- C 先落规则锁住已沉淀的设计原则（防止 ASC 拆分时再走老路）
- B 收尾批次 1 让批次 1 完整结案（R-Data 没收尾的话审核报告还有遗留）
- A 才启动新 milestone（ASC 拆分本身体量大，应当作为批次 1.5 / 1.6 单独立项）

请回复你倾向的顺序。
