# SOLID 审核 · 批次 1：Core + Data + GAS（L1 速扫）

> 审核日期：2026-05-22
> 范围：`Script/Core/`（4）+ `Script/Data/`（13）+ `Script/GAS/`（15），共 32 个 .gd
> 严重级：🔴 Error / 🟡 Warning / 🟢 Note

---

## Core

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| ConfigCenter.gd | 479 | 🔴 | 8 个 `get_xxx_config()` 在 `null` 时兜底 `XxxConfig.new()`（违反 R-CODE-01）；7 份 `_load_*` 模板雷同（DRY），加新 Config 必改 `_bootstrap`/字段/路径常量四处（OCP 差） | 兜底改 `assert(cfg != null, ...)` 崩；抽 `_load_resource[T](path) -> T` 单一模板 + Config 注册表 `Dictionary[Script, path]` 按表驱动；`reload_all` 也跟着收口 |
| EventBus.gd | 278 | 🟢 | 60+ 个全局信号集中声明，分组清晰，符合 R-EVENT-01；信号数量已偏多但属业务复杂度本质问题 | 长期可按子域拆 `EventBusGAS / EventBusHUD / EventBusDialogue`（非紧急）；保留分块注释即可 |
| GameInstance.gd | 202 | 🟡 | SRP 偏胖：tag 加载 + 状态机 + 子系统装配 + 暂停输入 + F1 调试 widget 安装五合一；`_load_tag_registry` null 时兜底 `GameplayTagRegistry.new()`（违反 R-CODE-01） | tag 缺失改 `assert`；`_setup_attribute_debug_widget` 拆到独立 `DebugUIBootstrap` 节点；状态机部分可抽 `GameStateMachine` |
| GameLogger.gd | 29 | 🟢 | 极简门面，3 个 static，职责单一；R-LOG-01 标杆实现 | 无需重构 |

---

## Data

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| AttributeGrowthEntry.gd | 19 | 🟢 | 纯数据载体，3 字段，标准 Resource | 无 |
| AttributeGrowthTable.gd | 22 | 🟢 | 标准查表 Resource，`get_entry` 线性查找在小表（<20 字段）合理 | 无；如未来字段量增大再加 Dictionary cache |
| AttributeResolver.gd | 174 | 🟡 | `_ALIAS_MAP` 旧名→新名兼容是技术债（注释自承"D2.B 兼容"）；两个 `apply_to_*` 接口并存（老 `apply_to_attribute_set` 标 deprecated 但未删）；`apply_to_asc` 中 `if not asc is AbilitySystemComponent: return` 是兜底（违反 R-CODE-01） | 删除 `apply_to_attribute_set` 老接口（grep 0 调用方后）；ALIAS_MAP 给 D6 期定收口时间表；类型检查改 assert |
| CameraConfig.gd | 31 | 🟢 | 纯 @export 数据载体，R-DATA-02 合规 | 无 |
| CharacterInstanceEntry.gd | 35 | 🟢 | 标准条目 Resource；`move_speed_override = -1` 表"沿用成长表"是合理 sentinel | 无 |
| CharacterInstanceTable.gd | 28 | 🟢 | 简单线性查表，体量合理 | 无 |
| GrowthSegment.gd | 15 | 🟢 | 极简数据载体 | 无 |
| HealthBarConfig.gd | 22 | 🟢 | 纯 @export，分块注释清晰 | 无 |
| HitFeedbackConfig.gd | 38 | 🟢 | 同上，4 大类参数（震屏/冻帧/闪白/飘字）分组 | 字段渐多（38 行）若再增长可按主题拆 `ScreenShakeConfig / DamagePopupConfig` |
| LightingConfig.gd | 24 | 🟢 | 同 CameraConfig | 无 |
| PostProcessConfig.gd | 34 | 🟢 | 同上 | 无 |
| PreviewStageConfig.gd | 34 | 🟢 | `@tool` 注解，仅编辑器内嵌预览用，规则允许例外 | 无 |
| SfxBindings.gd | 32 | 🟢 | 标准查表；`get_stream` 找不到返回 null 是 R-CODE-01 保留 warn 场景（音效缺失业务可继续） | 无 |

---

## GAS

| 文件 | 行数 | 严重 | 主要问题（≤2 行） | 建议重构动作 |
|---|---|---|---|---|
| Ability.gd | 125 | 🟢 | 基类钩子设计清晰（`_can_activate_extra` / `_activate` / `_end` / `_tick` / `wait_event`）；`wait_event` 用 await + Callable 闭包符合 GDScript 4.6 习惯 | 无；可考虑给 `_activate` 默认警告改 `assert("must override")` 让漏写直接崩 |
| AbilitySystemComponent.gd | 631 | 🔴 | **行数巨型**承担 ASC + 11 子职责；`_get_cue_manager_safe` + `_NoopCueStub` 是兜底反模式（违反 R-CODE-01）；`consume_block` 1.2s 硬编码 + 直接 `get_node_or_null(^"BlockComponent")` 跨组件按名访问（违反 R-CHAR-01） | 拆 `ASCAbilityRegistry` / `ASCEffectRuntime` / `ASCAttributeBootstrap` 三个 mixin 节点；CueManager 改用 `assert(GameInstance.cue_manager != null)`；1.2s 提到 `CombatConfig.block_broken_stun_sec`；BlockComponent 反找改用 NodeFinder |
| | | | **2026-05-23 状态**：✅ R-ASC 已修 _NoopCueStub / 1.2s 进 CombatBalanceConfig / BlockComponent 反向调改 EventBus.block_broken；❌ 631 → 587 行后**用户重新评估否决拆分**（核心职责是 GAS 本质耦合，强拆会割裂阅读链路）；改为只做注释审计（5-23 完成） |
| AttributeModifier.gd | 70 | 🟢 | SRP 清晰；`SET_BY_CALLER` + 默认 `LITERAL` 双源设计良好 | 无；`resolve_magnitude` 中 spec=null 时 fallback 到 magnitude 是合理保留 warn |
| AttributeSet.gd | 117 | 🟡 | 反射式钩子 `has_method(_pre_change_*)` 每次 set_attr 都跑一次（性能 + 可读性双差）；`get_owner_asc` 内 `owner_node.get_class()` 字符串比对 + 取 script 全局名是脏类型探测 | `_pre_change_*` 改注册表：子类 `_ready` 时把回调注册进 `_pre_handlers: Dictionary[StringName, Callable]`；`get_owner_asc` 改受 ASC `_ready` 时显式 `owner_node.set_meta(&"asc", self)` |
| DamagePipeline.gd | 228 | 🔴 | `_get_asc` 用 `node.has_method` + 字段名查找鸭子类型（违反 R-CHAR-01）；`_remove_perfect_block_buff` 调 `asc.call(&"_detach_active", h)` 是越权访问私有 API（**与 BlockComponent 重构时已删的反模式同型，是遗漏！**）；`get_node_or_null(^"ConfigCenter")` × 2 重复；`target.has_method(&"is_perfect_block_window")` × 3 处都是兜底 | `_get_asc` 直接复用 `BaseCharacter.asc` 字段（已 class_name 化）+ assert；`_remove_perfect_block_buff` 改调已存在的 `asc.remove_effects_with_granted_tag(&"Combat.Buff.PerfectBlock")`；ConfigCenter 用强类型直访 |
| | | | **2026-05-23 状态**：✅ 全部已修（R-Core 改 ConfigCenter 强访 / R-ASC 改 越权调用 / 本轮改 has_method ×3 → BlockComponent 强类型 + GameInstance.cue_manager 直访 + _get_asc 节点名兜底删 + apply_break 死接口删） |
| GameplayEffect.gd | 61 | 🟢 | 纯数据 Resource，字段语义清晰 | 无 |
| GameplayEffectSpec.gd | 66 | 🟢 | RefCounted 单次应用包装，链式 `set_caller` 设计良好 | 无 |
| Abilities/Ability_TimelineDriven.gd | 85 | 🟡 | 6 处 `if X == null: warn + _safe_finish` 兜底（违反 R-CODE-01：ConfigCenter / GameInstance / skill_timeline_player 都是静态可知必备）；`asc.has_method(&"end_ability")` 防御过度 | 必备依赖改 `assert`；`_safe_finish` 仅保留给"timeline 找不到"这一运行时数据缺失场景；`asc` 形参类型从 Node 改 AbilitySystemComponent，去掉 has_method 防御 |
| Attributes/CharacterAttributeSet.gd | 29 | 🟡 | 已标 `@deprecated D2.B`，但仍被 main_scene TrainingDummy / 老存档 SaveSystem 引用 | 排期 D5 SaveSystem 落地后删除；近期保持原样 |
| | | | **2026-05-23 状态**：✅ 实测早在 R-Attr 阶段已删（.gd / main_scene.tscn 引用全清）；本审核栏是过时观察 |
| Attributes/CombatSet.gd | 17 | 🟢 | 仅 2 字段中转 Set，职责单一 | 无 |
| Attributes/HealthSet.gd | 130 | 🟡 | `_emit_out_of_health` 中 `EventBus.has_signal(&"out_of_health")` 是规则禁止的过度防御（R-CODE-01）；元属性管道 `_post_apply_effect` 中三分支堆在一起，OCP 差 | 直接删 `has_signal` 防御；元属性反应改注册表 `_meta_attr_handlers: Dictionary[StringName, Callable]`，子类 `_ready` 注册 |
| Attributes/PrimaryAttributeSet.gd | 129 | 🟡 | `recompute_derived` 注释自承"妥协方案"；4 个 `_pre_change_*` 钳到 [0,1] 重复（DRY） | 引入"AttributeBasedSource"或显式 listener；4 个 clamp01 改一个 `_clamp01_attrs: Array[StringName]` + 通用 `_pre_change_*` 路由 |
| Tags/GameplayTag.gd | 55 | 🟢 | 静态工具类，方法粒度合理 | 无；`is_valid_format` 每次 new RegEx 可缓存（性能微优化） |
| Tags/GameplayTagContainer.gd | 109 | 🟢 | 计数引用 + 父子匹配语义清晰 | 无 |
| Tags/GameplayTagRegistry.gd | 42 | 🟢 | 标准注册表 Resource，符合 R-GAS-01 宽松模式 | 无 |

---

## 批次小结

**最严重 5 个文件**（按重构收益/风险比排序）：

1. **`AbilitySystemComponent.gd`（631 行）🔴** — 单文件全行数最高，承担太多职责（registry / effect runtime / cue / attr bootstrap / block 操控），急需拆分；`_NoopCueStub` 兜底是 Character 重构经验文档中已点名要消的反模式
2. **`DamagePipeline.gd`（228 行）🔴** — 包含**已经在 Character 重构里被删过的越权调用** `asc.call(&"_detach_active")`，属于 ASC 已暴露 `remove_effects_with_granted_tag` 后的遗漏迁移，应优先修
3. **`ConfigCenter.gd`（479 行）🔴** — 8 个 `get_xxx_config` 在 null 时 `new XxxConfig.new()` 兜底，是 R-CODE-01 明确禁止的"找不到就 new 一个默认的"反模式
4. **`Ability_TimelineDriven.gd`（85 行）🟡** — 6 处 ConfigCenter / GameInstance 静态依赖兜底 warn，是 R-CODE-01 的典型违规
5. **`AttributeSet.gd`（117 行）🟡** — `has_method` 反射钩子模式是性能 + 可读性双坑

**跨文件共性问题**：

- **C1 · ConfigCenter / GameInstance 弱类型路径访问**（≥6 处）：`get_tree().root.get_node_or_null(^"ConfigCenter")` 在 ASC.gd / DamagePipeline.gd / Ability_TimelineDriven.gd 至少 6 处重复
- **C2 · 越权访问私有 `_xxx` 方法**：DamagePipeline 调 `asc.call(&"_detach_active")` 属重构遗漏
- **C3 · "找不到就 new 默认" 兜底反模式**：ConfigCenter（8 处）+ GameInstance.tag_registry（1 处）
- **C4 · `has_signal` / `has_method` 过度防御**：HealthSet / Ability_TimelineDriven 等多处
- **C5 · 反射式钩子探测**：AttributeSet 每次 set_attr 都 `has_method(_pre_change_*)`

**待与用户确认的不确定项**：

- **U1**：ASC 631 行是否要立即拆？建议排独立 milestone（"D3 GAS 瘦身"）
  - **2026-05-23 决定 v1**：✅ 用户确认需要拆，独立 milestone（不混进批次 1 收尾）
  - **2026-05-23 决定 v2（最终）**：❌ **用户重新评估否决**——587 行内核心职责（属性/技能/GE/Tag）是 GAS 的本质耦合，强拆会割裂阅读链路；改为只做注释审计（已 5-23 完成）
- **U2**：CharacterAttributeSet（@deprecated）是否可以现在就删？仍被 TrainingDummy 引用
  - **2026-05-23 决定**：✅ 用户确认可删；实测 R-Attr 阶段已彻底删除（代码层零引用）
- **U3**：ConfigCenter `_load_*` 模板抽 `_load_resource[T](path)` 用 Variant 返回还是传 Script 参数？
  - **2026-05-23 决定**：✅ R-Core 已采用 `_load_resource_typed(path, expected_class) -> Resource`（传 Script 参数路线），用户隐式确认
- **U4**：DamagePipeline 4 个魔数常量（DEFENSE_K=100 / BLOCK_REDUCTION=0.4）是否进 `CombatBalanceConfig.tres`？
  - **2026-05-23 决定**：✅ 用户确认进；实测早已配置化（CombatBalanceConfig.tres 8 个字段全部存在）
- **U5**：`AttributeSet._pre_change_*` 反射改注册表，AttributeSet 是 Resource 没 _ready，需在 ASC duplicate 后回调初始化，认可吗？
  - **2026-05-23 决定**：✅ 用户确认；R-PreChange 阶段已采用**声明式 hook 表 + _init 缓存**实现（与"注册表"等价但更静态可读，方向一致）

---

## 2026-05-23 批次 1 完结总结

- **R-Core / R-ASC / R-PreChange / R-Data / R-Excel 全部完成**（详见 `Plans/Refactor/重构进度_*` 系列文档）
- **U1 ~ U5 全部敲定**：U2/U3/U4/U5 已实施，U1 重新评估后**否决**（仅注释审计）
- **GameConfig 顶层聚合 ❌ 否决**：详见 `Plans/Refactor/批次1收尾_R-Data_GameConfig决策_20260523.md`，理由是 ConfigCenter 已是顶层聚合 + 主题独立配置更符合 R-DATA-03
- **ASC 拆分 ❌ 否决**：587 行内核心职责（属性/技能/GE/Tag）是 GAS 本质耦合，强拆会降低可读性；改为只做注释审计
- **批次 1 注释审计完成**：32 个 .gd 文件清理 ~32 处过期阶段标记（D2.A-E / R-* 重构日期戳 / 旧案文档引用），保留所有当前生效 R-* 规则引用
- **空目录清理**：`Data/Common/AttributeGrowth/` 与 `Data/Config/AttributeGrowthTables/` 已删除
- **新规则落盘**：R-ARCH-04（跨模块走 EventBus）+ R-CODE-02（声明式 hook 表）+ R-DATA-03（纯数据走 JSON）已写入 `Plans/全局规则.md`
