# SOLID 审核 · Character 模块（L2 样板报告）

> 审核日期：2026-05-21
> 审核范围：`Script/Character/` 共 **12 个 .gd 文件**
> 审核口径：SOLID + DRY + SoC + 组合优于继承；顺带标注 Dolphin R-* 规则
> 严重级：🔴 Error（必须重构） / 🟡 Warning（建议重构） / 🟢 Note（提示，可不动）

---

## 0. 模块总评

| 维度 | 评分 | 说明 |
|---|---|---|
| 整体设计方向 | ★★★★☆ | "BaseCharacter + Component 子节点 + ASC + EventBus" 这套结构是对的，组件优于继承的思想已落地 |
| SRP（单一职责） | ★★☆☆☆ | `PlayerCharacter` 严重违反；`BaseCharacter` 在 D2.C 后开始混入业务流程 |
| OCP（开闭） | ★★★☆☆ | AttributeSet 兜底创建逻辑硬编码在 PlayerCharacter / EnemyCharacter 各一份，加新角色类型必须改这两个文件 |
| LSP（里氏替换） | ★★★★☆ | BaseCharacter 子类语义一致，无明显违反 |
| ISP（接口隔离） | ★★★★☆ | 组件粒度合理 |
| DIP（依赖倒置） | ★★☆☆☆ | 多处 `get_tree().root.get_node_or_null(^"ConfigCenter")`、各组件直接 EventBus 全局耦合 |
| DRY | ★★☆☆☆ | `_inject_data_driven_attributes` 在 Player/Enemy 几乎复制；`_ensure_*_attribute_sets` 模式雷同；多个组件各自写 `_get_asc()` / `_resolve_sprite()` |
| SoC（关注点分离） | ★★☆☆☆ | PlayerCharacter 把表现 / 输入 / 交互 / 属性 Bootstrap 四类混一起 |
| 组合优于继承 | ★★★★☆ | 组件化做得不错；只是 PlayerCharacter 把本该是组件的逻辑写成了内联方法 |

**Top 3 待重构文件**（按收益/风险比排序）：

1. `PlayerCharacter.gd` 🔴 — 拆出 Visual / Interactor / AbilityInputBinder 三个组件
2. `BaseCharacter.gd` 🟡 — 把 `_inject_data_driven_attributes` 模板上移；`_initialize_attributes_post_inject` 业务流程下沉到独立服务
3. `BlockComponent.gd` 🟡 — 直接调 `asc.call(&"_detach_active", h)` 越权访问私有 API（违反封装 + Demeter）

---

## 1. 文件级审核

### 1.1 `BaseCharacter.gd`（183 行）🟡

**职责现状**：
- ✅ 收集子组件并暴露引用（`_collect_components`）
- ✅ 接线 InputComponent → MoveComponent（`_wire_components`）
- ✅ Hitbox 命中转发到 HitDamageResolver（`_on_hit_landed`）
- ⚠️ Sprite 地面偏移工具方法（`_apply_sprite_ground_offset`）
- 🔴 **D2.C 8 步初始化序列**（`_initialize_attributes_post_inject`，37 行业务流程）

**违反原则**：

| 位置 | 问题 | 原则 |
|---|---|---|
| L143-182 `_initialize_attributes_post_inject` | 基类承担"加 GE_HealthInit/HealthRegen/StaminaRegen/BlockRegen"等具体业务流程；新增 Regen 种类需要改基类 | SRP / OCP |
| L70-87 `_apply_sprite_ground_offset` + `_find_sprite_base_3d` | 视觉调整逻辑跟"角色基类"职责无关；该归入 VisualComponent | SRP / SoC |
| L90-103 `_collect_components` 用 `if/elif` 链穷举每种组件类型 | 加新组件必改基类 | OCP |
| L162 `cfg.call(&"get_ge", ...)` | 用 `call` 而不是直接方法调用，因为 ConfigCenter 类型未导入；属于躲避静态类型 | DIP |
| L150 `get_tree().root.get_node_or_null(^"ConfigCenter")` | 全 Autoload 直接路径访问；与 `EnemyCharacter._inject_data_driven_attributes` / `BlockComponent._get_asc` 等多处重复 | DRY / DIP |

**重构建议**：

1. **抽出 `CharacterAttributeBootstrap`（独立服务/组件）**：把"8 步初始化序列"从基类搬走，基类只负责暴露 ASC 引用与发"我准备好了"信号。
2. **组件收集泛化**：`_collect_components` 改为遍历 `get_children() + 维护 Dictionary[Script, Node]`，新增组件不动基类。
3. **Sprite 偏移搬到 VisualComponent**（与 PlayerCharacter 的 `_resolve_sprite` 合并）。
4. **ConfigCenter 访问统一封装**：在 `Core/` 下加 `ConfigCenter.gd` 的强类型 `class_name`（如已是则统一全项目用 `ConfigCenter.xxx()`），消除 `get_node_or_null` 写法。

**对应 Dolphin 规则**：R-ARCH-01（跨模块通信）、R-DATA-02（数据驱动）— 当前基本合规但访问方式可优化。

---

### 1.2 `PlayerCharacter.gd`（306 行）🔴 **最严重**

> 上一轮已经详细分析过。重申要点：

**违反原则**（按严重度）：

| 位置 | 问题 | 原则 |
|---|---|---|
| 全文 | 同时承担：表现（_update_facing/_update_animation/_resolve_sprite）+ 输入派发（ACTION_TO_SLOT 路由）+ 交互检测（_on_interact_pressed）+ 属性 Bootstrap（_inject_data_driven_attributes）+ 消耗品占位 | **SRP（致命）** |
| L214-266 `_inject_data_driven_attributes` | 与 `EnemyCharacter._inject_data_driven_attributes` 70% 重复 | **DRY（致命）** |
| L271-306 `_ensure_player_attribute_sets` | 硬编码 "玩家就是 HealthSet+PrimaryAttributeSet+CombatSet 三套"；加新角色类型需写新方法 | **OCP** |
| L138-159 `_on_interact_pressed` | "找最近 interactable 调 interact" 这是交互系统的活，放在角色类里 | SRP / SoC |
| L171-205 `_update_facing` / `_resolve_sprite` 持有 `_sprite_3d` / `_sprite_2d` | 表现层耦合 2D/3D 节点类型，应封装到 VisualComponent | SoC / R-CHAR-01 边界模糊 |
| L100-120 `_on_input_action_pressed` 硬编码 ACTION_TO_SLOT 与 match | 加新输入动作必改 PlayerCharacter | OCP |

**重构建议**：分两阶段

**阶段 A（低风险）**：
- 抽 `CharacterVisualComponent` ← `_resolve_sprite` + `_update_facing` + `_update_animation`
- 抽 `InteractorComponent` ← `_on_interact_pressed` + 4m 范围搜寻

**阶段 B（中风险，配合 EnemyCharacter 一起）**：
- 抽 `AbilityInputBinder` 组件 ← `ACTION_TO_SLOT` + `ability_slot_to_id` + `_try_activate_slot`
- 把 `_inject_data_driven_attributes` 模板上移到 BaseCharacter，通过虚函数 `_get_required_attribute_set_classes()` 表达差异
- `_ensure_player_attribute_sets` 改为通用 `_ensure_attribute_sets(asc, classes)` 工具方法

**预期收益**：从 306 行 → 50 行左右。

**对应 Dolphin 规则**：R-CHAR-01（边界值得复检）、R-DATA-02（数据驱动 ✓）。

---

### 1.3 `EnemyCharacter.gd`（200 行）🟡

**职责现状**：
- ✅ 注册 enemy 组、找 Player target、AI 状态注册
- ✅ 数据驱动属性注入
- ⚠️ AttributeSet 兜底创建（敌人版）
- ⚠️ HP=0 切 dead 的 EventBus 监听
- 🔴 `_update_animation` **空函数**留作 placeholder（L195-200）

**违反原则**：

| 位置 | 问题 | 原则 |
|---|---|---|
| L73-127 `_inject_data_driven_attributes` | 与 PlayerCharacter 几乎复制 | **DRY（致命）** |
| L136-161 `_ensure_enemy_attribute_sets` | 与 PlayerCharacter 的 `_ensure_player_attribute_sets` 同模式不同枚举 | DRY / OCP |
| L172-177 `_register_default_states` | 硬编码 5 个 AI 状态；BossAI 想加新状态需改本类或用别的方式注册 | OCP |
| L180-192 `_on_attr_changed` | 角色类直接 `if ai is BossAI` 类型判断 + 调 `evaluate_phase` | LSP / 组合优于继承（应通过信号让 BossAI 自己订阅） |
| L195-200 `_update_animation` | **空函数仅占位** | 死代码 |
| L41-52 `hurtbox.damaged.connect(func ...)` | 匿名 lambda 捕获 ai，难以单测、难追踪订阅 | 可测试性 |

**重构建议**：

1. 与 PlayerCharacter 共享 `_inject_data_driven_attributes` 模板（上移到 BaseCharacter）
2. AI 状态注册改为 `@export var ai_states: Dictionary[StringName, AIState]` 由场景配；或由 AIController 自带默认状态集
3. **`_on_attr_changed` 中的 BossAI 类型判断挪到 BossAI 自己订阅** EventBus.attribute_changed —— 谁需要谁订阅，不要让父类替子类组件做事
4. 删除空 `_update_animation` 或填实

**对应 Dolphin 规则**：R-DATA-02（合规）、R-EVENT-01（合规）。

---

### 1.4 `NPCActor.gd`（110 行）🟢

**职责现状**：清晰 — Area3D 范围检测 + 派发 EventBus.interaction_target_* + interact() 启动对话图 + 朝向玩家。

**违反原则**：

| 位置 | 问题 | 原则 |
|---|---|---|
| L41-43 `(col.shape as SphereShape3D).radius = interact_radius` | 假设碰撞形状一定是 Sphere；如果场景里换成 Box 就失效 | LSP / 防御性 |
| L41 `interact_range.get_node_or_null("CollisionShape3D")` | 硬编码节点名 | OCP（场景节点改名就崩） |

**重构建议**：

- 节点查找改为按类型而非名称：`for c in interact_range.get_children(): if c is CollisionShape3D ...`
- shape 类型支持多形状或者文档里强约束"必须是 Sphere"。

**评级**：🟢 — 整体职责清晰，问题轻微，可以不动。

**对应 Dolphin 规则**：R-CHAR-02（合规，纯 3D 节点）、R-EVENT-01（合规）。

---

### 1.5 `Components/AnimationComponent.gd`（95 行）🟢

**职责现状**：清晰 — 在父节点子树找 AnimatedSprite3D/2D，封装 play/stop/is_playing。

**违反原则**：

| 位置 | 问题 | 原则 |
|---|---|---|
| L72-94 `_find_animated_sprite_3d` / `_find_animated_sprite_2d` | 两个递归查找方法重复，仅 type 不同 | DRY |
| L41-46 `play()` 中 3D 路径检查 has_animation，2D 路径不检查 | 行为不一致 | LSP |

**重构建议**：

- 把两个 _find_* 合并为泛型 `_find_first_of_type(node, type) -> Node`
- 2D 路径也加上 `sprite_frames.has_animation` 检查保持一致

**评级**：🟢 — 小问题。可在重构 Visual 组件时一并处理。

**对应 Dolphin 规则**：R-CHAR-01（合规，对外 API 平台无关）。

---

### 1.6 `Components/BlockComponent.gd`（126 行）🟡

**职责现状**：监听 `combat_block` 输入、apply/detach `GE_BlockState`、提供完美格挡判定 API。

**违反原则**：

| 位置 | 问题 | 原则 |
|---|---|---|
| L86-87 `asc.call(&"_detach_active", h)` | **越权访问私有方法**（带下划线前缀的内部 API）；如果 ASC 重构会立刻爆 | **封装/Demeter（严重）** |
| L78-87 主动找 active_effect 并 detach 的循环 | 这是 ASC 应该提供的能力（如 `remove_effects_with_tag(tag)`），不该让外部组件遍历 | DIP / 封装 |
| L62-68 / L103-108 两次直接 `get_tree().root.get_node_or_null(^"ConfigCenter")` + `cfg.call(&"get_ge", name)` | 重复 ConfigCenter 访问模式 | DRY |
| L117-125 `_get_asc()` | 与其他多个组件各自写一份 `_get_asc()` 重复 | DRY |
| L28-32 `EventBus.has_signal(&"player_input_action_pressed")` 防御 | 防御性写法过度（信号是静态声明的，不可能动态消失） | KISS / 防御过度 |

**重构建议**：

1. **ASC 暴露公共方法 `remove_effects_with_granted_tag(tag: StringName)`**，BlockComponent 调用它而不是 `_detach_active`
2. 抽出 `Components/CharacterComponent.gd` 基类（or mixin）提供 `_get_asc()` / `_get_config_center()`
3. 删除多余的 `has_signal` 防御

**对应 Dolphin 规则**：R-ARCH-01（合规，走 EventBus 订阅输入）、R-GAS-02（合规走 GE）。

---

### 1.7 `Components/EnergyComponent.gd`（101 行）🟢

**职责现状**：双池能量系统的"切换池"数据载体，含命中加能量钩子。

**违反原则**：

| 位置 | 问题 | 原则 |
|---|---|---|
| L84-87 `if parent != null and &"asc" in parent: asc = parent.get(&"asc")` | 又是一份"找父节点 ASC"的写法 | DRY |
| L57 `_DEFAULT_GAIN_PER_HIT: float = 1.0` 硬编码 | 注释说 "D6 时改读 EnergyGainTable.tres" | R-DATA-02（已有 TODO）|
| L49-53 `get_current_main_ult_energy()` 返回 0 占位 | 占位实现 | 可接受（D4 实装） |

**评级**：🟢 — 整体良好，自带 TODO 标记的硬编码是受控的。

**对应 Dolphin 规则**：R-EVENT-01（合规）、R-DATA-02（自带 TODO）。

---

### 1.8 `Components/HitboxComponent.gd`（52 行）🟢

**职责现状**：清晰单一 — Area3D 子类，enabled 时检测 HurtboxComponent 并 emit `hit_landed`。

**违反原则**：无明显违反。

**评级**：🟢 优秀样本 — 这就是组件应有的体量。

**对应 Dolphin 规则**：R-CHAR-02（合规）。

---

### 1.9 `Components/HurtboxComponent.gd`（23 行）🟢

**职责现状**：极简 — Area3D 子类，提供 `take_damage` API + `damaged` 信号。

**违反原则**：无。

**评级**：🟢 完美样本。

---

### 1.10 `Components/InputComponent.gd`（26 行）🟢

**职责现状**：极简 — 只负责把 InputMap 的 move_* 输出为 `Vector3(XZ 平面)`。

**违反原则**：无。

**评级**：🟢 完美样本，正是"职责缩窄"后的样子，可作为其它组件的参照。

**对应 Dolphin 规则**：R-CHAR-01（合规，对外 Vector3）。

---

### 1.11 `Components/MoveComponent.gd`（65 行）🟢

**职责现状**：3D 移动数学 + `move_and_slide()`，对外 API 全 Vector3。

**违反原则**：

| 位置 | 问题 | 原则 |
|---|---|---|
| L33-40 `set_input_dir` 兼容旧 2D 输入（dir.y 当 z）| 兼容性代码长期化会演变成隐式 bug；建议加注释说明何时下线 | YAGNI / 技术债 |

**评级**：🟢 — 良好。兼容代码是历史包袱，可在 M9 启动 R-CHAR-02 强制后清理。

---

### 1.12 `Components/HitFlashController.gd`（142 行）🟡

**职责现状**：监听 Hurtbox.damaged，给 sprite 闪白/染红（2D Shader / 3D modulate 双路径）。

**违反原则**：

| 位置 | 问题 | 原则 |
|---|---|---|
| L88-112 `_resolve_sprite` + `_assign_sprite_node` | 与 PlayerCharacter._resolve_sprite / AnimationComponent._find_animated_sprite_* 第三份 sprite 查找代码 | **DRY** |
| L25-26 同时持 `_sprite_2d: CanvasItem` + `_sprite_3d: SpriteBase3D` | 实现两条互斥路径，类内分支多 | SoC |
| L38-46 `_ready` 顺序：resolve_sprite → resolve_hurtbox → apply_shader → pull_config | 多个独立步骤都在 _ready 串行；初始化失败时静默跳过 | 防御性（warn 不到位）|

**重构建议**：

1. 在共享的 `VisualComponent` 暴露 `get_visual_node()`（统一 sprite 查找）
2. 拆为 `HitFlash2D` / `HitFlash3D` 两个具体子类，工厂方法或场景里二选一挂载
3. 也可以接受现状（双路径在一个类里），因为 R-CHAR-02 在 M9 后只剩 3D 路径

**对应 Dolphin 规则**：R-DATA-02（合规，颜色/时长走 HitFeedbackConfig）、R-CHAR-02（M9 启动后 2D 路径需删）。

---

## 2. 模块级共性问题汇总

下面这些**跨文件**问题，在重构时应该一并解决：

### 2.1 ConfigCenter 访问模式重复（出现 ≥5 次）

```gdscript
# 在 BaseCharacter / PlayerCharacter / EnemyCharacter / BlockComponent / HitFlashController 各自重复
var cfg: Node = get_tree().root.get_node_or_null(^"ConfigCenter")
if cfg == null: return
var ge = cfg.call(&"get_ge", &"...")
```

**根因**：`ConfigCenter` 没暴露 `class_name`（或暴露了但没全项目统一用强类型引用）。

**统一方案**：
```gdscript
# 直接调（前提：ConfigCenter 是 Autoload + 有 class_name）
ConfigCenter.get_ge(&"...")
```

### 2.2 sprite 查找重复（出现 4 次）

`PlayerCharacter._resolve_sprite` / `AnimationComponent._find_animated_sprite_3d` / `HitFlashController._resolve_sprite` / `BaseCharacter._find_sprite_base_3d`

**统一方案**：抽 `Util/NodeFinder.find_first_of_type(root, type)` 或 `VisualComponent` 暴露统一访问。

### 2.3 ASC 引用查找重复（出现 3+ 次）

`BlockComponent._get_asc` / `EnergyComponent._on_damage_dealt` / 其他组件

**统一方案**：抽 `CharacterComponent` 基类提供 `_get_asc()` / `_get_owner_character()`。

### 2.4 AttributeSet 兜底创建模式重复

`PlayerCharacter._ensure_player_attribute_sets`（3 个 Set）与 `EnemyCharacter._ensure_enemy_attribute_sets`（2 个 Set）逻辑同构。

**统一方案**：
```gdscript
# 在 BaseCharacter
func _ensure_attribute_sets(classes: Array) -> void:
    for cls in classes:
        var has = false
        for s in asc_node.attribute_sets:
            if s.get_script() == cls: has = true; break
        if not has:
            var inst = cls.new()
            inst.owner_node = self
            asc_node.attribute_sets.append(inst)
```

子类只需 `_ensure_attribute_sets([HealthSet, PrimaryAttributeSet, CombatSet])`。

### 2.5 数据驱动属性注入流程重复

`PlayerCharacter._inject_data_driven_attributes` 与 `EnemyCharacter._inject_data_driven_attributes` 70% 复制。

**统一方案**：上移到 BaseCharacter 做模板方法：
```gdscript
# BaseCharacter
func _inject_data_driven_attributes() -> void:
    # 共有的 entity_id/asc/cfg 防御 + resolve + apply_to_asc
    ...
    _ensure_attribute_sets(_get_required_attribute_set_classes())
    AttributeResolver.apply_to_asc(values, asc_node)
    ...

# 虚函数
func _get_required_attribute_set_classes() -> Array:
    return []  # 默认无；子类覆盖
```

---

## 3. 重构优先级建议

| 优先级 | 重构项 | 风险 | 收益 | 建议时机 |
|---|---|---|---|---|
| P0 | 抽 `CharacterVisualComponent`（合并 _resolve_sprite × 4 处） | 低 | 高 | 立即可做 |
| P0 | 抽 `InteractorComponent`（PlayerCharacter._on_interact_pressed） | 低 | 中 | 立即可做 |
| P1 | `_inject_data_driven_attributes` 模板上移 BaseCharacter | 中 | 高 | M8/M9 之间 |
| P1 | `_ensure_attribute_sets` 通用化 | 中 | 中 | 与 P1 同步 |
| P1 | 抽 `AbilityInputBinder`（ACTION_TO_SLOT 路由） | 中 | 中 | 配合输入系统迭代 |
| P2 | `ASC.remove_effects_with_granted_tag()` 公共 API + BlockComponent 改用 | 中 | 中 | ASC 模块下次迭代 |
| P2 | 抽 `CharacterComponent` 基类（统一 _get_asc / _get_config_center） | 低 | 中 | 顺手做 |
| P3 | 删 `EnemyCharacter._update_animation` 空函数 | 极低 | 极低 | 下次清理 |
| P3 | 修 `NPCActor` 节点查找的容错 | 极低 | 极低 | 下次清理 |

---

## 4. 与 Dolphin R-* 规则的交叉

| Dolphin 规则 | Character 模块合规度 | 备注 |
|---|---|---|
| R-CHAR-01（2D/3D 通用 API） | 🟡 大体合规，但 PlayerCharacter._update_facing 在角色层暴露了 sprite_3d/_sprite_2d 双字段 | 重构 VisualComponent 后就完全合规 |
| R-CHAR-02（3D 节点纯洁性） | 🟡 主体 3D，残留 2D 兼容代码（MoveComponent 旧 2D 输入兼容、HitFlashController 2D 路径） | M9 启动前清理 |
| R-DATA-02（数据驱动） | 🟢 整体合规（属性走 ConfigCenter、HitFlash 走 HitFeedbackConfig） | EnergyComponent _DEFAULT_GAIN_PER_HIT 自带 TODO |
| R-ARCH-01（跨模块走 EventBus） | 🟢 合规 | BlockComponent / EnemyCharacter / NPCActor 都走 EventBus |
| R-EVENT-01（信号集中声明） | 🟢 合规 | 业务节点上的 signal 仅 hit_landed/damaged 等局部 |
| R-LOG-01（GameLogger） | 🟢 合规 | 全部走 GameLogger.info/warn |
| R-GAS-02（属性走 set_attr） | 🟢 合规 | 没看到外部直赋 |

---

## 5. 待与用户确认的不确定项

下面这些地方我**拿不准重构方向**，建议与你对齐：

- **U1**：`_initialize_attributes_post_inject` 这个 8 步流程，按当前代码是基类提供 + 子类调用模板方法。你希望它**保持在基类**，还是**抽成独立 `CharacterAttributeBootstrap` 服务**？前者侵入小，后者更解耦。
- **U2**：`PlayerCharacter` 拆分时，`startup_ability_set` / `entity_id` / `level_override` 这几个 @export 是**保持在 PlayerCharacter 上**（玩家专属），还是**上移到 BaseCharacter**（让所有角色都能用）？我倾向上移，因为 Enemy 也用了同名机制。
- **U3**：`AbilityInputBinder` 抽出后，`ability_slot_to_id` 应该**继续作为 PlayerCharacter 的 @export**（场景里配置）还是**作为 InputBinder 自己的 @export**（更聚合）？后者更纯粹，但要求场景里必须挂 InputBinder 子节点。
- **U4**：`EnemyCharacter._on_attr_changed` 里的 `if ai is BossAI: evaluate_phase` —— 如果让 BossAI 自己订阅 EventBus.attribute_changed，**Boss 实体多份监听同一全局信号**会带来过滤成本。是否可接受？还是用 BossAI 子节点订阅自家 hurtbox/asc 的 attribute_changed（更局部）？
- **U5**：Sprite 查找统一封装放在哪？候选：① `Script/Util/NodeFinder.gd`（纯工具）② `VisualComponent` 暴露 API（位置耦合但语义清晰）③ 不动（现在的几处重复体量小）。

---

## 6. 下一步

- 你看完本报告后，**挑出认可的重构项**
- 我再去做 L1 全项目速扫（其余 11 个子目录、约 148 个文件），输出汇总报告
- 最后产出《重构 Roadmap》按里程碑落地

> 报告版本：v1.0（Character 模块样板）
> 后续如需修订，请在文末追加变更记录。
