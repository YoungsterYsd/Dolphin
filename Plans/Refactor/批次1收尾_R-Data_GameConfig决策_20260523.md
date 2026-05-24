# 批次 1 收尾 · R-Data 完结 + GameConfig 顶层聚合决策

**日期**：2026-05-23  
**触发**：用户决定按 C→B→A 顺序推进；C 落规则完成后做 B（R-Data 剩余）的实施判断

---

## 1. R-Data 实际状态盘点（2026-05-23 17:30）

| 子任务 | 原计划（5-22） | 实际状态（5-23） |
|---|---|---|
| 角色属性 Growth 迁移 | .tres → JSON | ✅ 5-22 做了 JSON；5-23 早 R-Excel 重构再次迁移到 CSV（取代 JSON） |
| AttributeResolver 重写 | 吃 Dictionary 而非 Resource | ✅ 5-22 做完；5-23 R-Excel 期改 `resolve_row` 接 CSV 行 |
| ConfigCenter 加载逻辑 | 切 JSON 路径 | ✅ 5-22 改完；5-23 切 5 张 CSV |
| 旧 .gd 类清理 | AttributeGrowthEntry / Table / GrowthSegment | ✅ 5-22 删完 |
| 旧 .tres 清理 | Growth_Player/Boss/Slime.tres | ✅ 5-22 删完 |
| **空目录清理** | （未提及） | ✅ 5-23 本轮删 `Data/Common/AttributeGrowth/` + `Data/Config/AttributeGrowthTables/` |
| **GameConfig 顶层聚合** | 9 份 .tres → 1 份顶层 GameConfig.tres | ❌ 本轮**决策否决**（理由见 §2） |

---

## 2. GameConfig 顶层聚合 · 否决决策

### 2.1 原计划意图

把 `Data/Config/` 下 9 份零散主题配置（HitFeedback / HealthBar / Camera / Lighting / PostProcess / SfxBindings / CombatBalance / 等）合并为一个顶层 `GameConfig.tres`，业务侧统一通过 `ConfigCenter.game_config.camera.fov` 这种链式访问。

### 2.2 否决理由

1. **ConfigCenter 已经是顶层聚合**：现有 `get_camera_config()` / `get_hit_feedback_config()` / `get_combat_balance_config()` 等 API 已经提供了统一入口。再加一层 `GameConfig.tres` 是**重复抽象**。

2. **违背 R-DATA-03 主题独立原则**：刚落盘的 R-DATA-03 第三类配置归属表强调"按主题分文件，diff 友好"。把 9 份合并成一份反而：
   - 单文件从 30 行变成 300+ 行
   - 任意一个子字段改 → 整个 GameConfig.tres 被 git 标记修改（diff 噪声大）
   - 策划想改震屏强度要打开整个游戏配置文件，认知负担增加

3. **嵌套引用增加复杂度**：`GameConfig.camera: CameraConfig` 这种**资源套资源**的 .tres 编辑在 Godot 编辑器里需要展开多层 SubResource，不如直接打开 `CameraConfig.tres` 顺畅。

4. **类型分发逻辑不清晰**：业务侧到底是写 `ConfigCenter.get_camera_config()` 还是 `ConfigCenter.game_config.camera`？双轨 API 反而混乱。

5. **没有真实业务驱动**：原计划提出时只是出于"组织整洁"的直觉，没有具体业务需求（如热重载、批量打包、版本号统一等）能从聚合中显著获益。

### 2.3 替代方案：保持现状

- **ConfigCenter 作为唯一聚合入口**：现状已经满足"顶层"职责，业务侧零成本访问
- **每个主题一份 .tres**：满足 R-DATA-03 第二类（数据 + 引用其他 .tres / 自定义方法）的归属
- **未来如有真实热重载需求**：可单独引入 `ConfigCenter.reload_subset(StringName)` 而无需改资源结构

### 2.4 文档同步

- 总览 Roadmap 中的 "Phase 1 / R-Data / GameConfig 聚合" 任务标 ❌ **否决**
- SOLID 审核 §批次小结的 **U3** 答复扩展为：路径常量集中已实现于 ConfigCenter 顶部 const 块，GameConfig 顶层聚合不需要

---

## 3. 批次 1 整体完成状态

| 子阶段 | 状态 | 备注 |
|---|---|---|
| R-Core | ✅ 完成 | ConfigCenter 重写 + Autoload 弱类型清理 + has_signal/has_method 删 |
| R-ASC | ✅ 完成 | attribute_set 老接口删 + _NoopCueStub 删 + 格挡破防走 EventBus.block_broken |
| R-PreChange | ✅ 完成 | AttributeSet 反射 → 声明式 hook 表 |
| R-Data 角色属性 | ✅ 完成（被 R-Excel 取代） | 5-22 JSON / 5-23 CSV |
| R-Excel | ✅ 完成 | 5 张 CSV 替代 .tres + JSON |
| U2 删 CharacterAttributeSet | ✅ 实测早删 | 仅 Plans/ 历史文档提及 |
| U4 DamagePipeline 4 魔数 | ✅ 实测早已配置化 | CombatBalanceConfig.tres 8 字段齐全 |
| DamagePipeline 鸭子类型清理 | ✅ 5-23 完成 | NodeFinder + BlockComponent 强类型 + GameInstance.cue_manager 直访 |
| 空目录清理 | ✅ 5-23 完成 | 2 个空目录删除 |
| **GameConfig 顶层聚合** | ❌ 否决 | 见 §2 |
| **U1 ASC 拆分** | ❌ **否决（5-23 17:30 用户重新评估）** | 587 行内核心职责（属性/技能/GE/Tag）是 GAS 的本质耦合，强拆会割裂阅读链路；改为只做注释审计 |
| **批次 1 注释审计** | ✅ 5-23 完成 | 见 §3.5 |

### 规则更新

- ✅ R-ARCH-04（跨模块走 EventBus）落盘
- ✅ R-CODE-02（声明式 hook 表）落盘
- ✅ R-DATA-03（纯数据走 JSON）落盘
- ✅ 变更记录追加 2026-05-23 条目

### 3.5 注释审计（5-23 18:00 完成）

清理范围：批次 1 = `Script/Core/` + `Script/Data/` + `Script/GAS/` 共 32 个 .gd 文件。

| 类别 | 处理 | 数量 |
|---|---|---|
| **过期阶段名** D2.A / D2.B / D2.C / D2.D / D2.E（开发期里程碑标签，对未来读者无意义） | **删除** | ~21 处 |
| **重构期标签** R-Core 重构 / R-ASC 重构 / R-Attr 重构 / R-Excel 重构 / R-PreChange 重构 + 日期戳 | **删除**（重构完成即历史，文件本身就是结果） | ~8 处 |
| **R-PreChange 引用** | **改为 R-CODE-02 引用**（指向当前生效规则） | 3 处 |
| **02 文档 §3 第 8 步**（旧案文档路径引用） | **删除** | 2 处 |
| **M2 单 Set 时代** / **D6 词条期** 等开发轴标记 | **删除或改为通用描述** | 5 处 |
| 当前生效规则引用：R-CODE-01 / R-ARCH-02 / R-ARCH-03 / R-ARCH-04 / R-DATA-02 / R-CHAR-01 等 | **保留** | 不动 |
| 设计意图注释（聚合字段说明 / 8 步初始化序列 / 元属性管道说明 / Hook 表 schema） | **保留** | 不动 |

验证：批次 1 三大目录（Core/Data/GAS）grep `D2\.[A-E]|R-Attr|R-ASC[^-]|R-PreChange|R-Excel 重构|R-Core 重构|R-Data 重构` 命中 0。

注：批次 2/3 范围（UI / Effects / Combat / Character / SkillSystem / Items / Quest / Debug）仍有 41 处类似标记，**不在本批次 1 收尾范围内**，留给批次 2/3 启动时一并清理。

---

## 4. 自测

| 维度 | 状态 |
|---|---|
| 删除空目录 | ✅ Data/Common/AttributeGrowth/ 与 Data/Config/AttributeGrowthTables/ 已 Remove-Item -Recurse |
| 代码引用确认 | ✅ ConfigCenter 早已切到 CSV 路径，目录删除不影响业务 |
| 注释清理 lint | ✅ 详见 §5 自测段 |

---

## 5. 批次 1 整体收尾结论

**批次 1（Core + Data + GAS）正式完结**。

完成的修复 / 重构：
- ConfigCenter 弱类型 19 处 → 强类型直访 + 4 处 cfg.call 替换
- EventBus.has_signal 防御 30 处 + ConfigCenter.has_method 防御 3 处全删
- ASC `attribute_set` 老接口删 + `_NoopCueStub` 删 + 格挡破防走 EventBus 解耦
- AttributeSet `_pre_change_*` / `_post_apply_effect` 反射 → 声明式 hook 表
- Growth_*.tres → JSON → CSV（R-Excel 终态）
- DamagePipeline 鸭子类型 ×3 删（NodeFinder + BlockComponent 强类型）+ Autoload 反射访问改直访 + apply_break 死接口删
- 空目录清理 + 注释审计

驳回的提案：
- **GameConfig 顶层聚合**（违背 R-DATA-03 主题独立 / ConfigCenter 已是顶层 API）
- **ASC 631 行拆分**（587 行内核心职责是 GAS 本质耦合，强拆会降低可读性）

后续阶段：
- **批次 2** UI 重构（HUDManager 382 / DialogueWidget 333 / DamagePopupPool 198 等）—— 见 `Plans/Refactor/SOLID审核_批次2_UI_20260522.md`
- **批次 3** SkillSystem + AI + Combat 模块 —— 见 `Plans/Refactor/SOLID审核_批次3_*.md`
