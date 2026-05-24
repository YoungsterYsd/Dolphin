# R-ASC + R-PreChange + R-Data（角色属性部分）阶段进度报告

> 日期：2026-05-22
> 紧接 R-Core 阶段，按总览 Roadmap 的 3 个最小风险阶段一气呵成。

---

## 一、规则更新（先行）

`Plans/全局规则.md` 追加 2 项：

### 1. 新增 R-ARCH-03「Autoload 使用约定」

- Autoload .gd 禁止加 class_name（防类静态调用语义冲突）
- 业务侧统一通过 Autoload 名直访（`ConfigCenter.get_xxx()` / `EventBus.signal_name.emit(...)` / `GameInstance.cue_manager`）
- 禁动态查找 Autoload（`get_node_or_null(^"ConfigCenter")`）
- 禁字符串反射（`cfg.call(&"get_ge", ...)`）

### 2. R-CODE-01「启动期必备资源白名单」

明确 11 份必备资源（CharacterInstances / SkillDamageTable / 6 个 Config / CombatBalanceConfig / GameplayTags + 2 份可选），缺失即 assert 崩；统一走 `_load_resource_typed(path, expected_class)` 模板。

---

## 二、R-ASC 阶段（最小改动方案 1 + 格挡 GA 化变体）

### 改动清单（11 文件）

| 文件 | 改动 |
|---|---|
| `Script/GAS/AbilitySystemComponent.gd` | 删 `attribute_set` 老接口字段 + _ready 兼容代码 + ensure_attribute_sets 末尾老接口同步 + _apply_modifiers 兼容路径；删 `_NoopCueStub` + `_get_cue_manager_safe` 改用 `GameInstance.cue_manager` 直访；`consume_block` 1.2s 硬编码改读 `CombatBalanceConfig.block_broken_stun_sec`；破防硬直反向调 BlockComponent 改为 emit `EventBus.block_broken`（去越权耦合） |
| `Script/Core/EventBus.gd` | 新增 signal `block_broken(blocker)` |
| `Script/Character/Components/BlockComponent.gd` | 订阅 `EventBus.block_broken` → 自己 stop_block |
| `Script/UI/HUD.gd` | `attribute_set.get_attr(...)` → `asc.get_attribute(name, default)` 跨 Set 查找 |
| `Script/UI/EnemyOverheadHealthBar.gd` | 同上 |
| `Script/UI/BossHealthBar.gd` | 同上 |
| `Script/Items/EquipmentComponent.gd` | `m.apply_to(asc.attribute_set)` → 用 `asc.find_set_with_attr(m.attribute)` 路由（装备 modifier 跨 Set：ATK 在 PrimaryAttributeSet，HP 在 HealthSet） |
| `Script/UI/Providers/AttributeProvider.gd` | `asc.get(&"attribute_set")` 反射 → `asc.get_attribute(name, default)` 强类型；`var asc: Node` → `var asc: AbilitySystemComponent` |
| `Scenes/Main/main_scene.tscn` | TrainingDummy 的 ASC：`attribute_set = SubResource(...)` → `attribute_sets = Array[Resource]([SubResource(...)])` |

### 关键设计

**格挡破防解耦**：之前 `ASC.consume_block` 反向 `get_node_or_null(^"BlockComponent")` + `bc.call(&"stop_block")` 是越权耦合；改为 ASC emit `EventBus.block_broken(get_parent())`，BlockComponent `_ready` 中订阅并自己 stop_block。这是 R-ARCH-01（跨模块走 EventBus）的标准做法。

### 自测

- lint 0 错误
- 编辑器 0 Parse Error
- 启动日志：`bootstrap_from_entity done: entity=player_lv1 lv=1 sets=3` + 9 个 Widget 注册成功

---

## 三、R-PreChange 阶段（声明式 hook 表）

### 设计：用 UE-style 宏精神替代反射

GDScript 没有真宏，但可用**子类返回声明字典**实现等价效果：

```gdscript
# AttributeSet 基类
func _get_attribute_hooks() -> Dictionary:
    return {}  # 子类覆盖

func _init() -> void:
    _hooks_cache = _get_attribute_hooks()  # 一次性缓存

func set_attr(attr, value):
    var hook = _hooks_cache.get(attr, {})
    var lo = hook.get(&"clamp_min", 0.0)
    var hi = hook.get(&"clamp_max", INF)
    if hook.has(&"max_attr"): hi = get(hook[&"max_attr"])
    var clamped = clampf(value, lo, hi)
    set(attr, clamped)
    if hook.has(&"post_apply"):
        (hook[&"post_apply"] as Callable).call(attr, old, clamped)
```

支持 4 种声明：
- `clamp_min / clamp_max`：固定区间钳制（替代 `_pre_change_xxx` 4 处 clamp01）
- `max_attr`：动态读另一字段作为上限（替代旧 `get_attribute_max(stamina_current)` override）
- `post_apply: Callable`：set 落值后回调（替代 `_post_apply_effect` 反射；元属性管道 health_damage → health 等）

### 改动

| 文件 | 之前 | 之后 |
|---|---|---|
| `Script/GAS/AttributeSet.gd` | `set_attr` 内 `has_method("_pre_change_" + str(attr))` 反射；调用方 override `_post_apply_effect` / `get_attribute_max` | 一次 `Dictionary.get(attr, {})` 查表，O(1) |
| `Script/GAS/Attributes/PrimaryAttributeSet.gd` | 4 个 `_pre_change_xxx` 函数 (10 行) | 1 个 `_get_attribute_hooks` dict (8 行) |
| `Script/GAS/Attributes/HealthSet.gd` | `_post_apply_effect` 大 if-else（25 行）+ `get_attribute_max(stamina_current)` override（4 行） | 1 个 `_get_attribute_hooks` (8 行) + 3 个职责单一的小函数 `_on_health_damage_applied / _on_health_healing_applied / _on_health_applied` (13 行) |

### 收益

- **集中声明**：每个 Set 的钩子表一目了然，新人查一眼就知道有哪些特殊行为
- **去反射**：每次 set_attr 一次 dict 查找代替字符串拼接 + has_method 查找
- **OCP**：加新 hook 不改基类，只在子类 dict 里加一行
- **可测试**：声明结构是纯数据，可单测

### 自测

启动日志显示元属性管道仍工作：
```
[Player] apply HealthInit_Full -> [Player]
  [Player] health_healing: 0.00 -> 999999.00   ← post_apply 触发
[Player] bootstrap_from_entity done: sets=3
```
（如果 hook 表不通，HealthInit_Full 会写 health_healing=999999 但不会反应到 health，玩家会 0 血崩。）

---

## 四、R-Data 角色属性部分（Growth → JSON）

### 改动结构

**新增**：3 份 JSON 配置 + 1 个目录

```
Data/Common/AttributeGrowth/
  ├─ Growth_Player.json
  ├─ Growth_Boss.json
  └─ Growth_Slime.json
```

**JSON 格式**（保留原 .tres 语义不变）：

```json
{
  "id": "growth_player",
  "entries": [
    {
      "attribute": "health_base",
      "base": 100.0,
      "segments": [
        { "breakpoint": 10, "per_level": 10.0 }
      ]
    },
    ...
  ]
}
```

**重写**：

| 文件 | 改动 |
|---|---|
| `Script/Data/AttributeResolver.gd` | 不再依赖 `AttributeGrowthEntry/Table/Segment` 类，直接吃 `Dictionary`（JSON 解析后结构）；`resolve_entry / resolve` 都改 dict 参数 |
| `Script/Core/ConfigCenter.gd` | `GROWTH_TABLES_DIR` 改 `Data/Common/AttributeGrowth`；`_load_growth_tables` 用 `FileAccess.get_file_as_string + JSON.parse_string` 替代 `load(.tres)`；`_growth_tables` 缓存类型变 `Dictionary[StringName, Dictionary]`；`get_attribute_growth_table` 返回 Dictionary 替代 Resource |

**删除**：

| 文件 | 备注 |
|---|---|
| `Script/Data/AttributeGrowthEntry.gd` (+.uid) | 类已不再被任何代码引用 |
| `Script/Data/AttributeGrowthTable.gd` (+.uid) | 同上 |
| `Script/Data/GrowthSegment.gd` (+.uid) | 同上 |
| `Data/Config/AttributeGrowthTables/Growth_Player.tres` | 已迁移到 JSON |
| `Data/Config/AttributeGrowthTables/Growth_Boss.tres` | 同上 |
| `Data/Config/AttributeGrowthTables/Growth_Slime.tres` | 同上 |

### 收益

- **不依赖 Godot Resource 序列化**：策划用任意文本编辑器都能改（VSCode / Notepad++ 都行，无需开 Godot 编辑器）
- **更易批量生成**：Excel → JSON 比 Excel → tres 简单得多（Plans/三期开发计划.md §82 已规划 Generated/Growth.json 自动化路径）
- **类数量减少**：Script/Data/ 从 8 个 .gd 减到 5 个（删 3 个纯数据 Resource 类）

### 自测

启动日志：
```
[Config] ConfigCenter bootstrap done. characters=4, growth_tables=3, ...
[GAS] [Player] bootstrap_from_entity done: entity=player_lv1 lv=1 sets=3
```
- `growth_tables=3` 表示 3 份 JSON 全部成功加载（Player + Boss + Slime）
- bootstrap sets=3 表示 JSON 数据被正确解析 → resolve 成 Dictionary → 跨 3 个 Set 路由写入 ASC

---

## 五、累计本轮 3 阶段统计

| 阶段 | 文件改动 | 文件新增 | 文件删除 |
|---|---|---|---|
| R-ASC | 9 | 0 | 0 |
| R-PreChange | 3 | 0 | 0 |
| R-Data | 2 | 3 | 9（3 .gd + 3 .uid + 3 .tres） |
| **合计** | **14** | **3** | **9** |

| 自测项 | R-ASC | R-PreChange | R-Data |
|---|---|---|---|
| read_lints | ✅ 0 | ✅ 0 | ✅ 0 |
| 编辑器启动 | ✅ 0 Parse Error | ✅ 0 | ✅ 0 |
| run_project | ✅ bootstrap sets=3 | ✅ 元属性管道走通 | ✅ growth_tables=3 |

---

## 六、新沉淀的设计模式（待确认是否升格规则）

### 模式 1：Autoload 跨模块通信替代越权调用

**反模式**：`ASC._consume_block` 内 `bc.call(&"stop_block")` 反向调 BlockComponent 私有 API
**正解**：`ASC` emit `EventBus.block_broken(blocker)`，BlockComponent 自己订阅并响应

适用场景：A 模块状态变化需通知 B 模块自我响应。

### 模式 2：声明式 hook 表替代命名约定反射

**反模式**：`if has_method("_pre_change_" + str(attr))` 跑反射查同名钩子函数
**正解**：基类提供 `_get_attribute_hooks() -> Dictionary` 虚函数，子类返回声明 dict；基类一次缓存查表

适用场景：基类调度多个可能的子类钩子（生命周期、属性变更、状态切换等）。

### 模式 3：纯数据配置走 JSON 而非 Resource

**反模式**：纯数据类（`AttributeGrowthEntry / Table / Segment`）写 .gd 类 + .tres 序列化
**正解**：JSON 直接表达数据结构 + 一个解析方法（`AttributeResolver.resolve(dict)`），无需为每层数据定义 Resource 子类

适用场景：纯数据载体（无方法 / 无 ATTRIBUTE_ACCESSORS / 不需要 Inspector 编辑）。Resource 仍适合：需要 Inspector 编辑 / 需要在 .tres 引用其它资源（材质/AudioStream/PackedScene）。

---

## 七、剩余 Roadmap

按总览 Roadmap：

- ✅ Phase 1 共性问题（G1/G2/G3/G5）已基本清完
- 🚧 R-Data 的 GameConfig 顶层聚合（思路 A）尚未做（你说"至少做完角色属性"，本轮只做了 Growth → JSON）
- ⏸ Phase 2（GAS 巨型类拆分：ASC + DamagePipeline）未启动
- ⏸ Phase 3（UI 巨型类拆分：HUDManager + DialogueWidget + State 枚举）未启动
- ⏸ Phase 4-6 未启动

请你拍板下一步：
- **A**：继续 R-Data 的 GameConfig 聚合部分（HitFeedback/HealthBar/Camera/Lighting/PostProcess 等 9 份子配置 → GameConfig.tres 顶层）
- **B**：跳到 Phase 2 GAS 巨型类拆分（ASC 631 行 → 三段式或最小整理）
- **C**：跳到 Phase 3 UI 巨型类拆分（HUDManager 502 行）
- **D**：先暂停，跑一轮端到端手测（玩家移动 / 普攻 / 格挡破防 / TrainingDummy 受击）
- **E**：把模式 1/2/3 升格成新规则后再走

我推荐 **D + E**：先跑一轮手测确认 R-ASC 的格挡破防 + R-PreChange 的元属性管道 + R-Data 的 JSON 加载在实战中不出问题；同时把上述 3 个模式升格成 R-* 规则避免后续重蹈覆辙。
