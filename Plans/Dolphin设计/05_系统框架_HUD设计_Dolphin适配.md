# 05 · 系统框架 / HUD 系统设计（Dolphin 适配版）

> **文档定位**：Dolphin 项目（Godot 4.6 / RPG + BossRush）HUD 系统的总体设计策划案，覆盖**层级架构、数据输入、动画播放、扩展机制、状态管理、配置持久化、多端适配、性能、可测试性** 9 大维度。
> **状态**：架构 / 接口 / 信号 / 资源结构**全部锁定**；具体数值（颜色、字号、像素位置、动画时长）按主理人「代码骨架优先」原则**全部挂起**，落 `.tres` 配置后再调。
> **生成日期**：2026-05-20
> **来源**：本批与前 4 篇并行；不依赖前项目原始文档，但承接 Dolphin 既有 `Script/UI/` + `Scenes/UI/` 的实现现状。

---

## 0. 设计目标与铁律

### 0.1 一句话目标

> **加一个 HUD 模块 = 新建一个 `.tscn` + 注册一行代码 + 喂一份 `.tres` 配置，不动核心代码。**

### 0.2 量化指标

| 维度 | 指标 |
|---|---|
| **完善** | 覆盖战斗 / 导航 / 养成 / 反馈 / 系统 / 调试 6 大类，共 ≥ 30 种元素 |
| **可扩展** | 新增 1 个 widget 改动 ≤ 3 个文件（场景 + 注册项 + 配置项） |
| **解耦** | HUD 不直接 import 任何 `Player` / `EnemyCharacter` / `BossAI` / `Ability` 具体类 |
| **可配置** | 颜色 / 字号 / 位置 / 显隐 / 动画时长 100% 走 `.tres`，不允许硬编码 |
| **多端** | PC 键鼠 / 手柄 / 触屏 三套布局，安全区自动适配 |
| **性能** | HUD 整体每帧 < 0.5ms；同屏世界 HUD ≤ 20；飘字 100% 池化 |

### 0.3 五条铁律（写进每个 widget 代码评审 checklist）

| ID | 铁律 | 检查方式 |
|---|---|---|
| **R-HUD-01** | **HUD 不写回业务数据**——单向数据流 Gameplay → Data → HUD | grep `EventBus.emit_signal` 应只出现在「玩家点按钮 → UIAction」一类位置 |
| **R-HUD-02** | **HUD 不直接 `get_node("../Player")`**——必须通过 `bind(provider)` 或订阅 `EventBus` | grep `get_node` 不允许跨场景树查找业务节点 |
| **R-HUD-03** | **数值/颜色/像素全走 `.tres`**——禁止硬编码 `Color(1,0,0)` / `font_size=32` / `position=Vector2(120,80)` | 代码扫描 `Color\(` / `font_size *=` 命中即否决 |
| **R-HUD-04** | **HUD 元素必须可在 Showcase 场景独立运行**——脱离 Gameplay 喂假数据也能展示 | `Scenes/Debug/HUDShowcase.tscn` 每个 widget 一份 |
| **R-HUD-05** | **跨模块通信只走 `EventBus`**——业务模块发信号、HUD 订阅；不允许业务模块直接 `hud.set_xxx()` | 沿用 R-EVENT-01 |

---

## 1. UE → Godot 等价物映射

| UE / Lyra 概念 | Godot 4.6 等价物 | Dolphin 落地 |
|---|---|---|
| `UPrimaryGameLayout` | 多个 `CanvasLayer` 组合 | `HUDManager`（Autoload）+ Scenes/UI/HUD_Main.tscn 主容器 |
| `UCommonActivatableWidget` + Stack | `Control` + 自定义 `BaseWidget.gd` + 栈数组 | `Script/UI/BaseWidget.gd` + `HUDManager.push_widget/pop_widget` |
| `UUIExtensionSubsystem` | 自定义 Autoload + 字典注册表 | `Script/UI/UIExtensionSubsystem.gd`（新增） |
| `IndicatorSystem` (3D → 屏幕投影) | `Camera3D.unproject_position` + Control | 已存在 `DamagePopupPool._project_to_screen` 范式，复用扩展为 `WorldIndicatorLayer` |
| `UGameplayMessageSubsystem` | Autoload signal | 已有 `EventBus.gd`（无需新增） |
| `UCommonInputModeManager` | `Control.mouse_filter` + `set_process_input` + 输入模式枚举 | `BaseWidget.input_mode` 字段 + `HUDStateMachine` |
| `Theme/StyleSheet` | `Theme.tres` + `theme_override_*` | `Data/Config/UITheme.tres` |
| `UMG Animation` | `AnimationPlayer` / `Tween` / `AnimationTree` | 各 widget 内置 `AnimationPlayer` |

---

## 2. HUD 层级架构（Layer System）⭐核心

### 2.1 层级定义（自底向上，8 层）

| 层 | 名称 | CanvasLayer | 节点路径 | 输入策略 | 暂停策略 | 用途 |
|---|---|---|---|---|---|---|
| **L0** | World HUD | 0（跟随相机） | `HUD_Main/L0_World` | Pass | Pausable | 敌人头顶血条、伤害飘字、互动提示「按 G」、世界目标点指引 |
| **L1** | Game HUD | 1 | `HUD_Main/L1_Game` | Pass | Pausable | 玩家血条 / 蓝条 / 经验条、技能槽 Hotbar、Buff 列表、小地图、Boss 血条 |
| **L2** | Game Menu | 2 | `HUD_Main/L2_GameMenu` | Block | Pausable | 背包、技能树、地图、装备替换面板（半覆盖式） |
| **L3** | Menu | 3 | `HUD_Main/L3_Menu` | Block | Always | 暂停菜单、设置菜单、存档读档 |
| **L4** | Modal | 4 | `HUD_Main/L4_Modal` | Block + 阻塞下层 | Always | 确认框、商店购买、剧情对话、Boss 出场卡 |
| **L5** | Notification | 5 | `HUD_Main/L5_Notification` | Pass | Always | Toast、成就解锁、拾取提示、连击数 |
| **L6** | Loading | 6 | `HUD_Main/L6_Loading` | Block | Always | 章节切换、关卡过渡、读档加载 |
| **L7** | Debug | 99 | `HUD_Main/L7_Debug` | Pass | Always | FPS、坐标、状态机日志、命中判定可视化（仅 Debug Build） |

### 2.2 层属性配置（每层都可独立配置）

```gdscript
# Script/UI/HUDLayerPolicy.gd  (Resource)
class_name HUDLayerPolicy
extends Resource

@export var layer_id: StringName = &""
@export var canvas_layer_index: int = 1
@export var visible: bool = true
@export_enum("Pass", "Absorb", "Block", "BlockAndCascade") var input_policy: int = 0
@export_enum("Always", "Pausable", "WhenPaused") var process_mode: int = 1
@export var fade_in_duration: float = 0.0    # 数值挂起，初值 0
@export var fade_out_duration: float = 0.0
@export var max_stack_size: int = 0           # 0 = 无栈管理；>0 启用栈
```

### 2.3 栈式管理规则（仅 L2 / L3 / L4）

| 操作 | 规则 |
|---|---|
| `push_widget(layer, widget)` | 推入栈顶；自动停用栈中其他 widget 的输入；可选淡出动画 |
| `pop_widget(layer)` | 弹出栈顶；触发 widget 的 `_on_hide()`；下方 widget 自动重新激活输入 |
| **Back Action** | `Esc` / 手柄 B → 自动 pop 栈顶；如栈空 → push 暂停菜单 |
| **冲突处理** | Modal 弹窗期间，`ui_pause` 等热键被阻塞 |

### 2.4 接口骨架（HUDManager Autoload）

```gdscript
# Script/UI/HUDManager.gd  (Autoload，建议 project.godot autoload 第 7 项)
extends Node

const LAYERS: Array[StringName] = [
    &"L0_World", &"L1_Game", &"L2_GameMenu",
    &"L3_Menu", &"L4_Modal", &"L5_Notification",
    &"L6_Loading", &"L7_Debug",
]

var _layer_nodes: Dictionary = {}     # StringName -> CanvasLayer
var _layer_stacks: Dictionary = {}    # StringName -> Array[Control]
var _layer_policies: Dictionary = {}  # StringName -> HUDLayerPolicy

func setup(hud_main_root: Node) -> void: ...
func push_widget(layer: StringName, widget: Control) -> void: ...
func pop_widget(layer: StringName) -> Control: ...
func get_top_widget(layer: StringName) -> Control: ...
func clear_layer(layer: StringName) -> void: ...
```

---

## 3. HUD 元素清单（完善性）

> 本节列出 Demo 阶段必须覆盖的 6 类共 30+ 种元素。**√ = M9 已有；△ = M9 部分实现；✖ = 待新增**。

### 3.1 战斗类（Combat HUD · 16 项）

| 元素 | 数据源 | 现状 | 所在层 | 备注 |
|---|---|---|---|---|
| 玩家血条 | `EventBus.attribute_changed` | √ HUD.gd | L1 | 已实现 |
| 玩家蓝条 | 同上 | √ HUD.gd | L1 | 已实现 |
| 玩家经验条 | `EventBus.attribute_changed`（experience/xp_to_next） | ✖ | L1 | 待 D2 加属性 |
| 玩家头像 + 等级 | `CharacterInstanceEntry` | ✖ | L1 | |
| **技能槽 Hotbar** | `PlayerCharacter.ability_slot_to_id` + `asc.get_cooldown_remaining` | △ Slot1/Slot2 | L1 | 扩到 6 槽（Q/W/E/R/Shift+Q/Ult） |
| Buff 列表 | `EventBus.effect_applied/removed` | ✖ | L1 | 流动布局，最多 8 个 |
| Debuff 列表 | 同上 | ✖ | L1 | 与 Buff 分行显示 |
| 连击数（Combo） | `ComboTracker`（待建） | ✖ | L1 | 命中累加，2s 不命中清零 |
| **Boss 血条（顶部）** | Boss `ASC` + `EventBus.boss_phase_changed` | √ BossHealthBar.tscn | L1 | 多阶段染色 |
| 小怪头顶血条 | `OverheadHealthBarManager` | √ EnemyOverheadHealthBar.gd | L0 | 已实现 |
| 伤害飘字 | `EventBus.damage_dealt_v2` | √ DamagePopupPool.gd | L0 | 已实现，普通/暴击二档 |
| 治疗飘字 | `DamagePopupPool.popup_heal()` | √ | L0 | 已实现 |
| MISS / 闪避飘字 | `EventBus.damage_dealt_v2`（amount=0 + 标记） | ✖ | L0 | 扩展 v2 信号 payload |
| 受击屏幕泛红 / Vignette | `EventBus.damage_dealt_v2`（target=player） | ✖（HitFeedbackConfig 已有字段） | L1 全屏遮罩 | 复用 HitFeedbackConfig |
| 击杀提示 / 多杀 | `EventBus.enemy_died` 内部计数 | ✖ | L5 | 飞过式 |
| 闪避 / 格挡反馈 | `EventBus.combat_state_changed` 派生 | ✖ | L1 + 屏幕震动 | 与 D1 输入联动 |

### 3.2 导航类（Navigation HUD · 5 项）

| 元素 | 现状 | 所在层 |
|---|---|---|
| 小地图 Minimap（圆形） | ✖ | L1 |
| 大地图（按 M 打开） | ✖ | L2 |
| 任务追踪条 Quest Tracker | ✖ | L1 右上 |
| 路径指引箭头 | ✖ | L0 屏幕边缘 |
| 区域名进入提示 | ✖ | L5 顶部淡入 |

### 3.3 养成类（Progression HUD · 4 项）

| 元素 | 现状 | 所在层 |
|---|---|---|
| 升级提示「LEVEL UP!」 | ✖ | L5 全屏特效 |
| 装备替换比较卡片 | ✖ | L4 拾取时弹 |
| 经验 / 金币飘字 | ✖（DamagePopup 可复用） | L0 |
| 仓库（已有设计 D5） | ✖ | L2 |

### 3.4 反馈类（Feedback HUD · 6 项）

| 元素 | 现状 | 所在层 |
|---|---|---|
| Toast 通知 | △（`EventBus.hud_toast_requested` 已有信号） | L5 右上 |
| Tooltip（控件 hover） | ✖ | L4 跟随光标 |
| 拾取提示堆叠 | ✖ | L5 右下 |
| 成就解锁卡 | ✖ | L5 右下大卡 |
| Boss 即将攻击警告 | ✖ | L1 屏幕边红光 |
| 死亡 / 胜利 / 失败大字 | ✖ | L4 全屏 |

### 3.5 系统类（System HUD · 6 项）

| 元素 | 现状 | 所在层 |
|---|---|---|
| 暂停菜单 | √ PauseMenu.tscn | L3 |
| 设置菜单 | √ SettingsMenu.tscn | L3 |
| 背包 / 仓库 | √ InventoryUI.tscn | L2 |
| 存档读档面板 | ✖（D5 接入） | L4 |
| 对话框（剧情） | ✖（M11 接入） | L1 底部 |
| 加载界面 | ✖ | L6 |

### 3.6 调试类（Debug HUD · 4 项，仅 Debug Build）

| 元素 | 所在层 |
|---|---|
| FPS / 帧时间 / Draw Call | L7 |
| 玩家坐标 / 状态机当前态 | L7 |
| 命中判定可视化（射线、判定框） | L7（叠 L0） |
| HUD 边界 / 安全区辅助线 | L7 |

---

## 4. 数据输入：HUD ← 业务（解耦核心）

### 4.1 三种数据源模式（按场景选择）

| 模式 | 适用场景 | Dolphin 落地 |
|---|---|---|
| **A · 事件驱动**（一次性 / 低频） | 飘字、击杀提示、拾取通知、升级、成就、Toast | 订阅 `EventBus.*` 信号 |
| **B · 属性绑定**（持续 / 高频） | 血条、蓝条、经验条、CD、Buff 时长 | `bind(provider: Resource)` + `provider.changed` 信号 |
| **C · 世界投影**（跟随 3D / 2D 物体） | 敌人头顶血条、互动提示、伤害飘字定位 | 复用 `DamagePopupPool._project_to_screen` 投影范式 |

### 4.2 数据契约（最小接口约定）

> **R-HUD-02 强制项**：所有 widget 不允许直接 `cast as PlayerCharacter`，只允许依赖以下契约。

```gdscript
# Script/UI/Contracts/IAttributeReadable.gd  (新增)
class_name IAttributeReadable
extends RefCounted

func get_value() -> float: return 0.0
func get_max_value() -> float: return 1.0
func get_attribute_name() -> StringName: return &""
signal changed(old: float, new: float)
```

```gdscript
# Script/UI/Contracts/IWorldAnchored.gd  (新增)
class_name IWorldAnchored
extends RefCounted

func get_world_position() -> Variant: return null   # Vector2 / Vector3
func is_visible_to_camera() -> bool: return true
signal world_position_changed
```

```gdscript
# Script/UI/Contracts/ICooldownReadable.gd  (新增)
class_name ICooldownReadable
extends RefCounted

func get_cooldown_remaining() -> float: return 0.0
func get_cooldown_max() -> float: return 1.0
func get_ability_id() -> StringName: return &""
```

> **现有 `AbilitySystemComponent.get_cooldown_remaining()` 直接满足 ICooldownReadable**，无需改造。

### 4.3 单向数据流约束

```
┌──────────────┐  emit signal   ┌──────────────┐  bind/listen  ┌──────────────┐
│  Gameplay    │ ─────────────▶ │  EventBus /  │ ────────────▶ │  HUD Widget  │
│  (业务模块)  │                │  Provider    │               │              │
└──────────────┘                └──────────────┘               └──────────────┘
       ▲                                                              │
       │                       UIAction signal                        │
       └──────────────────────────────────────────────────────────────┘
                  （仅玩家点按钮等输入交互可反向）
```

### 4.4 与现有 EventBus 信号的对接表

| HUD 元素 | 订阅信号 | 处理方式 |
|---|---|---|
| 玩家血条 / 蓝条 | `attribute_changed(owner, attr, old, new)` | filter `owner == player and attr in [&"health",&"max_health",...]` |
| 经验条 | `attribute_changed`（attr=`&"experience"`） | 同上 |
| 技能槽 CD | `_process` 主动 poll `asc.get_cooldown_remaining`（已有） | 接 `ICooldownReadable` 后改成 `cooldown_started` 信号 + Tween |
| 技能高亮 | `ability_activated` / `ability_ended` | 槽位描边 + 闪光 |
| 飘字 | `damage_dealt_v2` | DamagePopupPool（已实现） |
| Buff 列表 | `effect_applied` / `effect_removed` | 增删图标 |
| 头顶血条 | `enemy_spawned` / `enemy_died` | OverheadHealthBarManager（已实现） |
| Boss 血条 | `boss_phase_changed` + Boss `attribute_changed` | 多阶段染色 |
| Toast | `hud_toast_requested(text, duration)` | 已有信号，新增订阅者 |
| 区域名进入 | `level_changed(level_id)` | 查 `LevelDef.display_name` |
| 关卡完成横幅 | `level_completed(level_id)` | L4 全屏卡 |
| 升级特效 | 新增 `attribute_changed` filter（attr=`&"level"`） | — |
| 死亡面板 | `player_died` | L4 |
| 拾取提示 | `inventory_changed` | L5 右下条目 |
| 装备替换提示 | `equipment_changed(owner, slot)` | L4 比较卡 |

> **新增信号建议**（写进本期 HUD 实装时一并补到 EventBus）：
> - `signal player_combo_changed(count: int)`
> - `signal player_pickup_displayed(item_id: StringName, quantity: int)`
> - `signal hud_state_requested(state: StringName)`（HUDStateMachine 输入）

---

## 5. 动画与表现层（Animation & Feedback）

### 5.1 动画分类（5 类，每类规定时长档）

| 类型 | 触发 | 实现 | 时长档（数值挂起） |
|---|---|---|---|
| **入场** | widget show | Tween Fade/Slide/Scale | XS / S / M / L 四档 |
| **退场** | widget hide | Tween 反向 | 取入场档的 0.7× |
| **数值变化** | 数值跳变 | Tween 插值 | M 档（暂定） |
| **状态变化** | hover/pressed/focused | Theme + Tween | XS 档 |
| **强调 (Emphasis)** | 暴击 / 低血量警告 / 升级 | AnimationPlayer 循环 | 持续到状态结束 |

### 5.2 动画驱动方案选择矩阵

| 复杂度 | 推荐 | 例 |
|---|---|---|
| 简单（数值平滑、淡入淡出） | `Tween` | 血条插值、Toast 淡入 |
| 中等（多轨道编排：位置+缩放+颜色+音效） | `AnimationPlayer` | 升级特效、Boss 出场卡 |
| 复杂（状态机切换） | `AnimationTree` | Boss 血条三阶段切换、玩家头像情绪 |

### 5.3 通用动画规范

| 项目 | 规范 |
|---|---|
| 缓动函数 | 入场 `EASE_OUT`，退场 `EASE_IN`，强调 `EASE_IN_OUT` |
| 节奏分档 | XS（最小 widget）/ S（按钮反馈）/ M（面板）/ L（章节卡）—— 具体毫秒挂起 |
| 数值跳变 | 血条「双层条」——白条快速到位，红条缓动追上（D2 击杀/暴击体感） |
| 暴击飘字 | 字号 ×1.5、颜色取 `HitFeedbackConfig.damage_popup_crit_color`、向上飞行 `damage_popup_drift_distance` |
| 低血警告 | 屏幕边 Vignette + 心跳音 + 血条闪烁（HP < 阈值，阈值挂起） |
| 减少动画 | 设置项 `accessibility/reduce_motion`（无障碍 / 性能模式），开启后所有 Tween 时长 ×0 |

### 5.4 性能要点

| 项 | 措施 |
|---|---|
| 飘字 / Toast / World HUD | **必须对象池化**（DamagePopupPool 已有范式） |
| 离屏剔除 | World HUD 视野外 / 距离 > 阈值不更新 transform |
| 批处理 | 相似 widget 共用 AtlasTexture，减 Draw Call |
| RichTextLabel | 仅在对话 / Tooltip 用；HUD 主体禁用 |
| `_process` 滥用 | HUD 节点默认 `process_mode = INHERIT`，**只在确实需要每帧更新时打开** |

---

## 6. 扩展机制（Extensibility）⭐另一个核心

> 目标：**新增 1 个 HUD 模块改动 ≤ 3 个文件**。

### 6.1 扩展点（Slot）模式

主 HUD 场景预留 8 个命名 Slot（空 `Control` + 命名锚点）：

```
HUD_Main.tscn
├─ L0_World            (CanvasLayer=0, follow_camera=true)
├─ L1_Game             (CanvasLayer=1)
│  ├─ Slot.TopLeft        (PlayerInfo / HP / MP / EXP)
│  ├─ Slot.TopCenter      (BossHealthBar)
│  ├─ Slot.TopRight       (Minimap / QuestTracker)
│  ├─ Slot.BottomLeft     (Buff / Combo)
│  ├─ Slot.BottomCenter   (Hotbar)
│  ├─ Slot.BottomRight    (Pickup / Achievement)
│  └─ Slot.Center         (Reticle / TargetLock)
├─ L2_GameMenu / L3_Menu / L4_Modal / L5_Notification / L6_Loading / L7_Debug
```

### 6.2 Registry 注册 API

```gdscript
# Script/UI/UIExtensionSubsystem.gd  (Autoload，新增第 8 项)
extends Node

# slot_tag -> Array[ExtensionEntry]
var _registry: Dictionary = {}

class ExtensionEntry:
    var handle: int
    var widget_scene: PackedScene
    var priority: int
    var enabled: bool

func register_widget(slot_tag: StringName, scene: PackedScene, priority: int = 0) -> int:
    """注册一个 widget 到指定 Slot，返回 handle 用于 unregister。"""

func unregister_widget(handle: int) -> void: ...

func reload_layout(layout_res: HUDLayoutResource) -> void:
    """切关卡 / DLC 时清空并按新配置批量注册。"""
```

### 6.3 新增 1 个 HUD 模块的标准 3 步法

1. **新建场景**：`Scenes/UI/Widgets/MyWidget.tscn`，根节点继承 `BaseWidget.gd`
2. **绑定数据**：在 `_ready()` 里 `EventBus.xxx.connect(...)` 或 `bind(provider)`
3. **挂到 Slot**：在某个 Autoload / GameFeature 启动时调用一次：
   ```gdscript
   UIExtensionSubsystem.register_widget(
       &"L1.Slot.TopRight",
       preload("res://Scenes/UI/Widgets/MyWidget.tscn"),
       priority=10
   )
   ```

> **改动文件清单**：
> - `Scenes/UI/Widgets/MyWidget.tscn`（新增）
> - `Script/UI/Widgets/MyWidget.gd`（新增）
> - `Data/Config/HUDLayout.tres`（新增 1 行注册项）—— 替代步骤 3 的硬编码

### 6.4 配置驱动（HUDLayoutResource）

```gdscript
# Script/UI/HUDLayoutResource.gd  (Resource)
class_name HUDLayoutResource
extends Resource

# slot_tag -> Array[WidgetMount]
@export var mounts: Dictionary = {}

class WidgetMount:
    extends Resource
    @export var widget_scene: PackedScene
    @export var priority: int = 0
    @export var enabled: bool = true
    @export var config_override: Resource    # 可注入额外参数 Resource

# 资源文件：
# Data/Config/HUDLayout_Default.tres   主世界默认布局
# Data/Config/HUDLayout_BossRush.tres  BossRush 模式（隐藏 Minimap，显示 WaveCounter）
# Data/Config/HUDLayout_Cutscene.tres  过场（仅保留字幕）
```

### 6.5 BaseWidget 基类（统一约束）

```gdscript
# Script/UI/BaseWidget.gd  (新增)
class_name BaseWidget
extends Control

signal closed
signal data_bound(provider: Resource)

@export var widget_id: StringName = &""
@export var data_provider: Resource              # 通用 Provider，支持 Mock
@export_enum("Pass", "Absorb", "Block") var input_mode: int = 0
@export var visible_in_pause: bool = false
@export var theme_resource: Theme

@onready var _anim_player: AnimationPlayer = get_node_or_null(^"AnimationPlayer")

func _ready() -> void:
    _apply_input_mode()
    _apply_theme()
    if data_provider != null:
        bind_data(data_provider)

func bind_data(provider: Resource) -> void:
    """子类重写：绑定到具体 Provider。"""
    data_provider = provider
    data_bound.emit(provider)
    refresh()

func refresh() -> void: pass            # 子类重写
func _on_show() -> void:                # 入场动画
    if _anim_player and _anim_player.has_animation(&"show"):
        _anim_player.play(&"show")
func _on_hide() -> void:
    if _anim_player and _anim_player.has_animation(&"hide"):
        _anim_player.play(&"hide")
    closed.emit()

func _apply_input_mode() -> void:
    match input_mode:
        0: mouse_filter = Control.MOUSE_FILTER_PASS
        1: mouse_filter = Control.MOUSE_FILTER_STOP
        2: mouse_filter = Control.MOUSE_FILTER_STOP

func _apply_theme() -> void:
    if theme_resource != null:
        theme = theme_resource
```

### 6.6 主题与样式扩展

| 资源 | 路径 | 内容 |
|---|---|---|
| 全局 Theme | `Data/Config/UITheme.tres` | 字号 / 颜色 / 圆角 / 按钮高度 |
| HUD 颜色 token | `Data/Config/UIColorTokens.tres` | 血色 / 蓝色 / 暴击色 / 治疗色 / 警告色 |
| 飘字配置（已有） | `Data/Config/HitFeedbackConfig.tres` | popup 颜色 / 字号 / 飘字距离（**不重复定义**） |
| 血条配置（已有） | `Data/Config/HealthBarConfig.tres` | 头顶血条尺寸 / 颜色 / 隐藏距离 |

> 所有数值的 ground truth：**HitFeedbackConfig + HealthBarConfig + UITheme + UIColorTokens** 四份 `.tres`，HUD 代码不允许出现裸数值。

### 6.7 输入扩展（手柄 / 触屏）

- InputMap 集中：所有 HUD 热键 action 名以 `ui_panel_*` / `hud_*` 前缀（已有 `ui_pause` / `ui_panel_build`）
- `BaseWidget.input_mode` 决定是否阻塞下层
- 设备切换：监听 `Input.joy_connection_changed` → `HotkeyHint` widget 自动切按键图标
- 触屏：单独 `HUDLayout_Touch.tres`，按钮 ≥ 80×80、间距 ≥ 16

---

## 7. HUD 状态机（HUDStateMachine）

### 7.1 状态定义

| 状态 | 进入条件 | 可见层 | 输入处理 |
|---|---|---|---|
| `Boot` | 启动 | L6 | 全 Block |
| `MainMenu` | LevelManager 进入主菜单关 | L3 | 仅 L3 |
| `Gameplay` | LevelManager 进入战斗关 | L0 + L1 + L5 | 走 InputController |
| `Paused` | `ui_pause` 按下 | L0 / L1 淡化 + L3 | L3 独占 |
| `PanelOpen` | 玩家按 I / B / M | L0 / L1 淡化 + L2 | L2 独占（Esc 退出） |
| `Dialogue` | M11 对话开启 | L1 限制 + 对话框 | 仅对话快进键 |
| `Cutscene` | 过场触发 | L0 黑边 + L4 字幕 | 仅 Skip 键 |
| `Dead` | `EventBus.player_died` | L4 死亡面板 | 仅复活/读档 |
| `LevelTransition` | LevelManager 切关 | L6 | 全 Block |

### 7.2 切换规则

```gdscript
# Script/UI/HUDStateMachine.gd  (Autoload 第 9 项 或 GameInstance 子节点)
extends Node

enum State { BOOT, MAIN_MENU, GAMEPLAY, PAUSED, PANEL_OPEN, DIALOGUE, CUTSCENE, DEAD, LEVEL_TRANSITION }

signal state_changed(old: int, new: int)

func change_state(new_state: int) -> void:
    # 1. 校验转移合法
    # 2. 调用旧状态 _exit
    # 3. 调用新状态 _enter（push/pop layer，应用 process_mode）
    # 4. emit state_changed
```

### 7.3 与 GameInstance.GameState 联动

| GameInstance.GameState | HUDStateMachine.State |
|---|---|
| Boot | Boot |
| Title | MainMenu |
| Playing | Gameplay |
| Paused | Paused |
| LevelTransition | LevelTransition |
| Dead | Dead |

> 一一映射；监听 `EventBus.game_state_changed` 自动切换。

---

## 8. 配置与持久化（Settings & Save）

> 与 D5 存档系统对接，所有 HUD 配置走 `SettingsManager`（已有 Autoload）。

### 8.1 玩家可调项（写入 `user://settings.cfg`）

| 配置项 | 取值 | 默认（数值挂起） |
|---|---|---|
| `hud/scale` | 0.8 / 1.0 / 1.25 / 1.5 | 1.0 |
| `hud/opacity` | 0.5 ~ 1.0 | 1.0 |
| `hud/show_minimap` | bool | true |
| `hud/show_damage_numbers` | bool | true |
| `hud/show_buff_durations` | bool | true |
| `hud/show_enemy_health_bars` | bool | true |
| `hud/colorblind_mode` | none / protanopia / deuteranopia / tritanopia | none |
| `hud/reduce_motion` | bool | false |
| `hud/subtitle_size` | small / medium / large | medium |
| `hud/subtitle_background_opacity` | 0 ~ 1.0 | 0.5 |
| `hud/safe_area_padding` | 0~64 px | 32 |

### 8.2 自定义布局（高级，写入 `save://hud_layout.tres`）

允许玩家拖拽 HUD 元素位置（仅高级模式开放），保存为单独 `.tres`，与 D5 GameSave 分离。

### 8.3 设置应用流程

```
SettingsManager.load() → emit settings_loaded
   → HUDManager.apply_settings(s)
       → 各 BaseWidget.apply_settings(s)（修改 Theme override）
```

---

## 9. 多端 / 多分辨率适配

### 9.1 分辨率策略

| 项 | 配置 |
|---|---|
| 设计基准 | 1920 × 1080 |
| 拉伸模式 | `display/window/stretch/mode = canvas_items` |
| 长宽比 | `aspect = expand` |
| 最小支持 | 1280 × 720 |
| 最大支持 | 3840 × 2160 + 21:9 / 32:9 |
| 安全区 | `MarginContainer` 读取 `DisplayServer.screen_get_safe_area`，无安全区时取 `hud/safe_area_padding` 设置项 |

### 9.2 锚点与布局规则

- **强制使用 `anchor_*` + `offset_*`**，禁止绝对坐标
- 全部走 `Container`（`HBoxContainer` / `VBoxContainer` / `GridContainer` / `MarginContainer`），禁止绝对位置子节点（除世界投影）
- 文本控件预留 1.4× 长度（德 / 俄文），按钮宽度自适应

### 9.3 设备配置文件

| 文件 | 适用 |
|---|---|
| `Data/Config/HUDLayout_PC.tres` | 键鼠默认 |
| `Data/Config/HUDLayout_Gamepad.tres` | 手柄（按钮提示图标切换） |
| `Data/Config/HUDLayout_Touch.tres` | 触屏（增大按钮，新增虚拟摇杆） |

---

## 10. 性能与监控

### 10.1 预算

| 指标 | 目标 |
|---|---|
| HUD 整体帧时间 | < 0.5 ms |
| 同屏世界 HUD 数 | ≤ 20（敌人头顶 + 飘字） |
| 飘字对象池容量 | 初始 20，按 2× 扩容（已实现） |
| 同帧 Toast 数量 | ≤ 5 |
| RichTextLabel 实例 | ≤ 3（仅对话 + Tooltip） |
| Draw Call | HUD ≤ 30 |

### 10.2 监控（仅 Debug Build）

L7 调试层显示：
- HUD 元素数量 / Draw Call
- 飘字池命中率 / 当前 busy 数
- 世界 HUD 投影耗时
- 各层栈深度

### 10.3 优化措施清单

| 措施 | 实施位置 |
|---|---|
| 对象池 | DamagePopupPool（已有）/ ToastPool / WorldIndicatorPool（新增） |
| 离屏剔除 | EnemyOverheadHealthBar：距离 > `HealthBarConfig.hide_distance` 不更新 |
| 节流 | 高频 attribute（如 mana_regen）合批更新（每 0.1s 一次） |
| 关闭非必要动画 | `reduce_motion` 设置项 |
| Atlas 打包 | 所有 HUD 图标合并到 1~2 张 AtlasTexture |

---

## 11. 可测试性（Testability）

### 11.1 Mock DataProvider

每个 BaseWidget 接受 `data_provider: Resource`，可用 `MockAttributeProvider.gd` / `MockCooldownProvider.gd` 喂假数据，脱离 Gameplay 独立运行。

### 11.2 Showcase 场景

```
Scenes/Debug/HUDShowcase.tscn
├─ ShowcasePanel_Combat    （HP/MP/EXP/Hotbar/Buff/Combo 各一份，按钮触发动画）
├─ ShowcasePanel_Boss      （Boss 三阶段血条 + 出场卡）
├─ ShowcasePanel_Feedback  （飘字 / 击杀提示 / Toast / 成就）
├─ ShowcasePanel_Menus     （暂停 / 设置 / 背包 / 仓库）
└─ ShowcasePanel_World     （飘字定位 / 头顶血条 / 互动提示）
```

### 11.3 预设状态快捷键

Showcase 场景内：F1 满血、F2 残血、F3 暴击连发、F4 Boss战、F5 死亡、F6 升级。

### 11.4 截图回归

关键状态截图存 `Plans/Dolphin设计/screenshots/HUD/`，做视觉回归对比。

---

## 12. 任务分解（开发实施清单）

> 与 `Plans/开发计划.md` / `Plans/二期开发计划.md` 集成；建议按 **HUD-A → HUD-B → HUD-C → HUD-D** 四批落地。

### HUD-A 阶段：基础设施（约 4d）

| 任务 | 交付 | 验收 |
|---|---|---|
| A.1 新增 `HUDManager.gd` Autoload + 8 层 CanvasLayer 结构 | `Script/UI/HUDManager.gd` + `Scenes/UI/HUD_Main.tscn` 改造 | F12 弹层级调试输出 |
| A.2 新增 `BaseWidget.gd` 基类 | `Script/UI/BaseWidget.gd` | 现有 5 个 widget 改继承通过 |
| A.3 新增 `UIExtensionSubsystem.gd` Autoload + Slot 命名 | `Script/UI/UIExtensionSubsystem.gd` | register/unregister API 单测通过 |
| A.4 新增 `HUDLayoutResource.gd` + 默认布局 `.tres` | `Script/UI/HUDLayoutResource.gd` + `Data/Config/HUDLayout_Default.tres` | 切换 layout 资源后 HUD 自动重组 |
| A.5 新增 `HUDStateMachine.gd` + 与 GameInstance.GameState 联动 | `Script/UI/HUDStateMachine.gd` | 暂停 / 死亡 / 切关三场景验证 |

### HUD-B 阶段：现状迁移（约 3d，**不新增功能**）

| 任务 | 交付 |
|---|---|
| B.1 现有 HUD.gd / DamagePopup / OverheadHealthBar / Boss 血条 改造为 BaseWidget 子类 |
| B.2 拆分到 Slot.TopLeft / Slot.TopCenter / Slot.BottomCenter |
| B.3 现有 InventoryUI / PauseMenu / SettingsMenu 接入栈管理（L2 / L3） |
| B.4 全部裸数值迁移到 `Data/Config/UITheme.tres` + `UIColorTokens.tres` |

### HUD-C 阶段：完善 HUD 元素（约 6d）

| 任务 | 元素 |
|---|---|
| C.1 战斗类补全 | 经验条 / 头像 / 6 槽 Hotbar / Buff 列表 / Combo / 击杀提示 |
| C.2 反馈类补全 | Toast / Tooltip / Pickup 堆叠 / 死亡胜利大字 |
| C.3 导航类补全 | Minimap / QuestTracker（QuestSystem 接入前先 Mock） |
| C.4 养成类补全 | LevelUp 特效 / 装备替换卡 |

### HUD-D 阶段：扩展支持（约 2d）

| 任务 | 交付 |
|---|---|
| D.1 多布局 `.tres`（PC / Gamepad / Touch / BossRush / Cutscene） | 5 份 `HUDLayout_*.tres` |
| D.2 HUDShowcase 场景 + Mock Provider | `Scenes/Debug/HUDShowcase.tscn` + `Script/UI/Mocks/*.gd` |
| D.3 设置项接入 SettingsManager | `hud/*` 11 项可在 SettingsMenu 调 |
| D.4 L7 Debug 层 | FPS / 元素数 / Draw Call / 池统计 |

---

## 13. 验收清单（HUD 系统整体）

- [ ] **R-HUD-01**：grep 全量 widget，无 `EventBus.emit_signal` 反向写业务数据
- [ ] **R-HUD-02**：grep 全量 widget，无 `cast as PlayerCharacter` / `cast as EnemyCharacter` / `get_node("../Player")`
- [ ] **R-HUD-03**：grep 全量 widget，无 `Color\(` / `font_size *=` / 裸像素位置
- [ ] **R-HUD-04**：HUDShowcase 场景每个 widget 可脱离 Gameplay 单独运行
- [ ] **R-HUD-05**：跨模块仅通过 EventBus 通信
- [ ] 8 层级全部建立，输入 / 暂停 / 栈管理三策略可配置
- [ ] 6 大类 30+ 元素清单全部有归属层 + 数据源 + 现状标记
- [ ] HUDLayout 切换资源后 HUD 自动重组（≥ 3 个 layout 验证）
- [ ] 所有数值 / 颜色 / 像素 100% 来自 `.tres`
- [ ] 切换分辨率 / 长宽比（720p / 1080p / 4K / 21:9）布局不破坏
- [ ] HUD 整体帧时间 < 0.5 ms（Debug 层验证）
- [ ] HUDShowcase + Mock Provider + 6 个预设状态快捷键全部可用
- [ ] 5 类设置项（缩放 / 不透明度 / 显隐 / 色盲 / 减少动画）持久化通过

---

## 附录 A · 文件目录约定

```
Scenes/UI/
  HUD_Main.tscn                  # 8 层 + 7 个 Slot 占位
  Widgets/
    PlayerInfoWidget.tscn
    HotbarWidget.tscn
    BuffListWidget.tscn
    BossHealthBar.tscn           # 已有
    EnemyOverheadBar.tscn        # 已有（DamagePopupPool 等同级管理）
    Minimap.tscn
    QuestTracker.tscn
    Toast.tscn
    Tooltip.tscn
    LevelUpBanner.tscn
    EquipCompareCard.tscn
    SubtitleBox.tscn
    LoadingScreen.tscn
    BossEntranceCard.tscn
  Panels/
    InventoryUI.tscn             # 已有（移入）
    PauseMenu.tscn               # 已有（移入）
    SettingsMenu.tscn            # 已有（移入）
    DeathPanel.tscn
    StashUI.tscn                 # D5 新增
    DialogueBox.tscn             # M11 新增

Script/UI/
  BaseWidget.gd                  # 新增
  HUDManager.gd                  # 新增
  UIExtensionSubsystem.gd        # 新增
  HUDStateMachine.gd             # 新增
  HUDLayoutResource.gd           # 新增（Resource）
  HUDLayerPolicy.gd              # 新增（Resource）
  Contracts/
    IAttributeReadable.gd
    IWorldAnchored.gd
    ICooldownReadable.gd
  Mocks/
    MockAttributeProvider.gd
    MockCooldownProvider.gd
  Widgets/...                    # 各 widget 控制脚本
  Panels/...

Data/Config/
  UITheme.tres                   # 字号 / 圆角 / 按钮规格（新增）
  UIColorTokens.tres             # 颜色（新增）
  HUDLayout_Default.tres
  HUDLayout_BossRush.tres
  HUDLayout_PC.tres
  HUDLayout_Gamepad.tres
  HUDLayout_Touch.tres
  HUDLayout_Cutscene.tres
  HitFeedbackConfig.tres         # 已有，复用
  HealthBarConfig.tres           # 已有，复用
```

---

## 附录 B · 命名规范

| 类别 | 规范 | 示例 |
|---|---|---|
| Slot Tag | `L{n}.Slot.{Position}` 全大驼峰位置 | `L1.Slot.TopLeft` / `L1.Slot.BottomCenter` |
| Widget ID | `widget_<功能>` snake_case | `widget_player_info` / `widget_boss_hp` |
| InputAction | `hud_<动作>` 或 `ui_panel_<面板>` | `hud_toggle_minimap` / `ui_panel_inventory` |
| Resource 文件 | `HUDLayout_<场景>.tres` / `UI<Topic>.tres` | `HUDLayout_BossRush.tres` / `UITheme.tres` |
| EventBus signal | `snake_case_过去式` | `pickup_displayed` / `combo_changed` |
| Theme override key | `theme_override_<type>/<name>` | `theme_override_colors/font_color` |

---

## 附录 C · 与现有 Autoload 集成清单

| Autoload | HUD 用途 |
|---|---|
| `ConfigCenter` | 提供 `HitFeedbackConfig` / `HealthBarConfig` / `UITheme` / `HUDLayout` |
| `EventBus` | HUD 唯一跨模块通信通道（见 §4.4） |
| `GameInstance` | 提供 GameState 枚举，触发 HUDStateMachine 切换 |
| `LevelManager` | 切关时通知 HUDManager `clear_layer(L0/L1)` 并 push Loading |
| `AudioManager` | HUD 动画配套音效（暴击 / 升级 / 拾取）走它 |
| `SettingsManager` | 11 项 hud/* 配置读写 |
| **`HUDManager`** ⭐ | 新增 |
| **`UIExtensionSubsystem`** ⭐ | 新增 |
| **`HUDStateMachine`** ⭐ | 新增（也可作为 GameInstance 子节点，可选） |

---

## 附录 D · 与既有文档的关系

| 文档 | 关系 |
|---|---|
| `01_战斗框架_输入映射` | 提供 `combat_*` / `ui_*` action 名 → HUD 热键映射 |
| `02_战斗框架_属性公式` | 提供 `attribute_changed` 字段名 → HUD 血条 / 蓝条 / 经验条订阅源 |
| `03_战斗框架_武器切换` | 双武器切换 UI（Hotbar 双槽 + 切换动画） |
| `04_系统框架_死亡存档仓库` | 死亡面板 / 存档读档面板 / 仓库 UI 由 D5 接入 |
| `04B_铁律与任务分解` | 10 条 Cheese 防守铁律对 HUD 的延伸：HUD 不允许显示「调试穿墙」「无敌模式」（除 Debug Build） |

---

## 变更日志

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-05-20 | 首次建立。基于现有 `Script/UI/` + `Scenes/UI/` 现状萃取，对接 D1~D5 设计文档；架构 / 接口 / 信号 / 资源结构全锁定，具体数值（颜色 / 字号 / 像素 / 时长）全挂起。|
