# 07 · HUD 组件化设计 / 交互类型与落地实现

> **文档定位**：在 `05_系统框架_HUD设计_Dolphin适配.md`（架构） + `06_HUD落地路线_四阶段Todo与验收.md`（路线）的基础上，针对 **HUD 元素本身** 做组件化拆解，明确每类组件「是否可交互、交互类型、交互逻辑」与 **Godot 4.6 落地方案**（优先复用原生与现有框架）。
> **状态**：组件清单 / 交互契约 / 落地节点 / 资源定义全锁定；具体像素/颜色/时长沿用 05/06 的"挂起"原则。
> **生成日期**：2026-05-21
> **不重复内容**：层级 L0~L7、Slot 命名、五条铁律、HUDStateMachine 状态枚举见 05；commit 级 Todo 见 06。

---

## 0. 总览

### 0.1 一句话目标

> **每一个 HUD 元素都能用「(组件类型, 数据契约, 交互契约, 落地节点)」四元组描述；新增任意 HUD 元素时不再从零思考交互方式。**

### 0.2 五条组件级铁律（在 05 R-HUD-01..05 之上扩展）

| ID | 铁律 |
|---|---|
| **R-HUD-COMP-01** | 每个组件归属唯一组件类型（§1 7 类）；混合型必须拆成多个原子组件再组合 |
| **R-HUD-COMP-02** | 组件交互能力由 `InteractKind` 枚举显式声明（§2.1）；脚本里禁止隐式吃事件 |
| **R-HUD-COMP-03** | 可交互组件必须支持键鼠 + 手柄 + 触屏三种输入路径（至少不报错；触屏可降级） |
| **R-HUD-COMP-04** | HUD 内交互意图通过 `EventBus.hud_intent_*` 信号统一上抛，不直接调业务 API |
| **R-HUD-COMP-05** | 组件原生节点选型遵循 §4 决策矩阵；原生能满足时禁止自绘 |

> R-HUD-COMP-04 把「玩家在背包里点*使用药水*」这类**意图**跟「业务真正去 use」分开，业务订阅意图、决定怎么做（金币够不够、CD 在不在），HUD 不需要懂这些规则。

---

## 1. 组件类型分类（7 类原子组件）

| # | 组件类型 | 中文 | 是否可交互 | 典型示例 | 原生节点首选 |
|---|---|---|---|---|---|
| **C1** | Display | 显示型 | ❌ | 玩家血条、Boss 血条、伤害飘字、连击数、Toast、区域名横幅、击杀提示 | `ProgressBar` / `Label` / `TextureRect` |
| **C2** | Indicator | 世界投影 | ❌（多数）/ ⚠️（少数支持点击） | 敌人头顶血条、互动提示「按 E」、目标点箭头 | `Control` + `Camera3D.unproject_position` |
| **C3** | Hotkey-Trigger | 热键触发，UI 仅显示状态 | ⚠️间接 | 技能 Hotbar、消耗品快捷栏、武器切换指示 | `Panel` + `Label` + `ColorRect` |
| **C4** | Pointer-Selectable | 指针/焦点选择 | ✅ | 暂停菜单按钮、设置项、商店列表、对话选项、确认对话框 | `Button` / `ItemList` / `OptionButton` / `MenuBar` |
| **C5** | Drag-Slot | 拖拽槽位 | ✅ | 背包格子、装备槽、Hotbar 重排、技能树拖入 | `Control` + Godot 原生 D&D API |
| **C6** | Editable-Field | 可编辑字段 | ✅ | 音量滑条、名字输入、按键重映射、HUD 缩放 | `LineEdit` / `HSlider` / `SpinBox` / `CheckBox` |
| **C7** | Compound | 复合容器 | ✅（继承子组件） | 背包面板、商店面板、装备比较卡、设置菜单、对话框 | `Panel` + `VBox/HBox/Grid` |

### 1.1 组件类型选型决策树

```
新组件诞生
  ├─ 仅展示数据，不响应任何输入？           → C1
  ├─ 需要跟随 3D 世界中某个物体？           → C2
  ├─ 通过键盘热键（Q/W/E/R/数字键）触发？    → C3（UI 只显示状态）
  ├─ 鼠标 / 手柄选项卡选中并按下？
  │     ├─ 单一动作 → C4
  │     └─ 把 A 拖到 B → C5
  ├─ 输入数值 / 文字 / 切档位？             → C6
  └─ 由上面多种组合 → C7
```

---

## 2. 交互能力契约

### 2.1 InteractKind 枚举（写进 `Script/UI/HUDInteract.gd`）

```gdscript
class_name HUDInteract
extends RefCounted

## 组件可声明的交互方式。可叠加（位运算）。
enum Kind {
    NONE              = 0,
    HOVER             = 1 << 0,    ## 鼠标 hover 显 Tooltip
    CLICK             = 1 << 1,    ## 单击触发动作
    DOUBLE_CLICK      = 1 << 2,    ## 双击触发"使用 / 装备"等强动作
    RIGHT_CLICK       = 1 << 3,    ## 右键菜单
    DRAG_SOURCE       = 1 << 4,    ## 可被拖出
    DROP_TARGET       = 1 << 5,    ## 可接受拖入
    KEYBOARD_FOCUS    = 1 << 6,    ## 可获焦（Tab / 方向键导航）
    HOTKEY            = 1 << 7,    ## 通过 InputAction 触发
    LONG_PRESS        = 1 << 8,    ## 长按（手柄 / 触屏）
    SCROLL            = 1 << 9,    ## 滚轮调整
    TEXT_INPUT        = 1 << 10,   ## 文本输入
}
```

### 2.2 BaseWidget 扩展字段（Phase 3 启动时追加，向后兼容）

> 已交付 BaseWidget 已有 input_mode / pause_policy / theme_resource / data_provider；在它们旁边再加两个 export，默认值不影响现有 widget。

```gdscript
## 组件类型（C1~C7）。
@export var component_kind: HUDComponentKind.Kind = HUDComponentKind.Kind.DISPLAY

## 交互能力（位运算叠加）。
@export_flags(
    "Hover", "Click", "Double Click", "Right Click",
    "Drag Source", "Drop Target", "Keyboard Focus",
    "Hotkey", "Long Press", "Scroll", "Text Input"
) var interact_kinds: int = 0
```

### 2.3 交互意图信号（Phase 3 在 EventBus.gd 追加 11 条）

```gdscript
# ─────────────────────────────────────────────────────────────
# HUD 组件交互意图（Phase 3 新增）
# 命名约定：hud_intent_<动作>，payload 自描述、不带业务对象引用
# ─────────────────────────────────────────────────────────────

## 玩家请求使用某物品（背包 / Hotbar 都走这条）
signal hud_intent_use_item(owner: Node, item_id: StringName, slot_index: int)

## 玩家拖拽某物品到目标槽（背包→装备 / Hotbar 重排 / 装备→背包）
signal hud_intent_move_item(owner: Node, src: Dictionary, dst: Dictionary)

## 玩家请求装备某物品
signal hud_intent_equip_item(owner: Node, item_id: StringName, equip_slot: int)

## 玩家请求卸下某槽位
signal hud_intent_unequip_item(owner: Node, equip_slot: int)

## 玩家请求购买商店物品（quantity=-1 = 全部）
signal hud_intent_purchase(shop_id: StringName, item_id: StringName, quantity: int)

## 玩家请求出售物品到商店
signal hud_intent_sell(shop_id: StringName, item_id: StringName, slot_index: int, quantity: int)

## 玩家在对话框选了一个选项
signal hud_intent_dialogue_choice(graph_id: StringName, choice_index: int)

## 玩家在确认框选 Yes/No
signal hud_intent_modal_confirm(modal_id: StringName, confirmed: bool, payload: Dictionary)

## 玩家点了某个按钮（菜单 / 按钮通用）
signal hud_intent_button_pressed(button_id: StringName, payload: Dictionary)

## 玩家修改了某个设置项（音量 / 缩放 / 显隐 / 键位）
signal hud_intent_setting_changed(key: StringName, value: Variant)

## 玩家在世界 HUD 上点击 Indicator（如点小地图敌人 → 设置标记）
signal hud_intent_world_indicator_clicked(target: Node, payload: Dictionary)
```

> **R-HUD-COMP-04 实操**：HUD 永远 emit `hud_intent_*`；业务订阅这些信号判断是否真的执行（金币够不够 / CD 在不在 / 状态允不允许）。

### 2.4 交互响应链（统一时序）

```
┌──────────────┐  原始输入    ┌─────────────────┐  解析 InteractKind
│ Godot 输入   │ ──────────▶ │  Widget._input  │ ─────────────────┐
│ (mouse/key)  │              │  / _gui_input   │                  │
└──────────────┘              └─────────────────┘                  ▼
                                                          ┌──────────────────┐
                                                          │  emit hud_intent │
                                                          └──────────────────┘
                                                                    │
                              ┌─────────────────────┬──────────────┴───────────────────┐
                              ▼                     ▼                                  ▼
                       Inventory 业务订阅    Equipment 业务订阅                AudioManager 订阅
                       （检查能否 use）       （检查 slot 兼容）                （播 ui_click 音效）
```

---

## 3. 组件清单（按 7 类组织）

> 命名规则：`widget_<功能>` snake_case；交互能力缩写：H=Hover / C=Click / DC=DoubleClick / RC=RightClick / DS=DragSource / DT=DropTarget / KF=KeyboardFocus / HK=Hotkey / LP=LongPress / SC=Scroll / TI=TextInput。

### 3.1 C1 Display（21 个，全部 `interact_kinds = NONE`）

| widget_id | 中文 | 数据源 | 所在层 | 现状 |
|---|---|---|---|---|
| widget_player_hp | 玩家血条 | `attribute_changed(health, max_health)` | L1.TopLeft | √ HUD.gd 迁移 |
| widget_player_mp | 玩家蓝条 | 同上（mana） | L1.TopLeft | √ |
| widget_player_xp | 经验条 | 同上（experience） | L1.TopLeft | ✖ Phase 3 |
| widget_player_avatar_level | 头像 + 等级 | `IAttributeReadable(level)` | L1.TopLeft | ✖ Phase 3 |
| widget_boss_hp | Boss 血条 | Boss `ASC` + `boss_phase_changed` | L1.TopCenter | √（迁移到分层版） |
| widget_damage_popup | 伤害飘字 | `damage_dealt_v2` | L0 | √ |
| widget_combo_count | 连击数 | 新 `ComboTracker` + `combo_changed` | L1.BottomLeft | ✖ Phase 3 |
| widget_killfeed | 击杀提示飞过 | `enemy_died` | L5 顶部 | ✖ Phase 3 |
| widget_buff_list | Buff 流式图标 | `effect_applied/removed` | L1.BottomLeft | ✖ Phase 3 |
| widget_debuff_list | Debuff 流式图标 | 同上 | L1.BottomLeft | ✖ Phase 3 |
| widget_toast | 通用 Toast | `hud_toast_requested` | L5 右上 | √信号 |
| widget_pickup_notification | 拾取条目 | `inventory_changed` | L5 右下 | ✖ Phase 3 |
| widget_area_name_banner | 区域名横幅 | `level_changed` → 查 LevelDef | L5 顶部 | ✖ Phase 3 |
| widget_big_banner | 死亡 / 胜利大字 | `player_died / level_completed` | L4 全屏 | ✖ Phase 3 |
| widget_hit_vignette | 受击屏幕泛红 | `damage_dealt_v2(target=player)` | L1 全屏 | ✖ Phase 3 |
| widget_low_hp_alert | 低血警告心跳 | `attribute_changed(health) < 阈值` | L1 全屏 | ✖ Phase 3 |
| widget_subtitle | 字幕 | `dialogue_node_changed` (M11) | L1 底部 | M11 |
| widget_loading_screen | 加载界面 | `level_started/finished` | L6 全屏 | ✖ Phase 4 |
| widget_fps_overlay | 调试 FPS | Engine.get_frames_per_second | L7 | Debug |
| widget_debug_state | 状态机日志 | `hud_state_changed` | L7 | Debug |
| widget_drawcall_debug | DrawCall 数 | RenderingServer | L7 | Debug |

**C1 共同特征**：`mouse_filter = MOUSE_FILTER_IGNORE`（避免吃下层点击）。

### 3.2 C2 Indicator（5 个）

| widget_id | 中文 | 跟随对象 | 交互 | 备注 |
|---|---|---|---|---|
| widget_overhead_hp | 敌人头顶血条 | 敌人 | NONE | √ 现有；统一到 C2 标准 |
| widget_overhead_name | 敌人名字 / 等级 | 敌人 | HOVER（显示更多） | 可选 |
| widget_interact_prompt | 「按 E 交互」 | NPC / 拾取物 | HOTKEY（按 E → emit `hud_intent_button_pressed("interact")`） | M12 |
| widget_world_marker | 自定义世界标记 | 任意目标点 | NONE | 任务系统标点 |
| widget_offscreen_arrow | 屏幕边缘指引箭头 | 任意目标点 | NONE | 目标超出视口时显示 |

**C2 落地约定**：
- 全部挂在 `L0_World` CanvasLayer 下（HUD 例外，R-CHAR-02 合规）。
- 共用 `Script/UI/Util/WorldProjector.gd`（从现有 `DamagePopupPool._project_to_screen` 抽出，Phase 2 P2-T3 已规划）。
- 离屏剔除：`is_position_behind` 或屏幕外 → `visible = false`（不要 free）。
- 距离剔除阈值走 `HealthBarConfig.overhead_show_distance`（已有）。

### 3.3 C3 Hotkey-Trigger（4 个）

| widget_id | 中文 | 槽位 | 触发 InputAction | 备注 |
|---|---|---|---|---|
| widget_hotbar_skill | 技能 Hotbar | 6（Q/W/E/R/Shift+Q/Ult） | `combat_skill_q/w/e/r/shift_q/ult` | √ 已有 2 槽，扩展 |
| widget_hotbar_consumable | 消耗品快捷栏 | 4（数字 1~4） | `hotbar_consumable_1..4` | ✖ Phase 3 可选 |
| widget_weapon_swap_indicator | 武器切换指示 | — | `combat_weapon_swap` | D3 接入 |
| widget_dodge_charge | 闪避充能数 | — | `combat_dodge` | D1 接入 |

**C3 交互模式**：
- UI 本身**不响应鼠标**（点也不触发技能）；仅显示状态（CD 遮罩 / 按键图标 / 充能数）。
- 触发完全依赖 `InputController` 把按键映射成 InputAction → ASC.try_activate。
- HUD 通过 `ICooldownReadable` 拿 CD：每帧 poll `asc.get_cooldown_remaining()`（现有实现）。
- **手柄 / 键盘图标自动切换**：监听 `Input.joy_connection_changed` → `HotkeyHint` 切贴图。

### 3.4 C4 Pointer-Selectable（10 个）

| widget_id | 中文 | InteractKinds | 上抛信号 | 备注 |
|---|---|---|---|---|
| widget_main_menu_button | 主菜单按钮 | C+KF+H | `hud_intent_button_pressed("menu_<name>")` | Phase 4 |
| widget_pause_menu_button | 暂停菜单按钮 | C+KF+H | 同上 | √ 迁移 |
| widget_settings_tab_button | 设置 Tab 切换 | C+KF | `hud_intent_button_pressed("settings_tab_<name>")` | √ |
| widget_dialogue_choice_button | 对话选项 | C+KF+H+HK（数字键 1~N） | `hud_intent_dialogue_choice` | M11 |
| widget_modal_confirm_button | Modal 确认 / 取消 | C+KF+HK（Enter/Esc） | `hud_intent_modal_confirm` | Phase 3 |
| widget_shop_item_row | 商店物品行 | C+KF+H+DC（双击购买） | `hud_intent_purchase` | M12.2 |
| widget_shop_buy_button | 购买按钮 | C+KF | `hud_intent_purchase` | M12.2 |
| widget_quest_log_entry | 任务条目 | C+KF+H | `hud_intent_button_pressed("quest_<action>")` | M12.3 |
| widget_skill_tree_node | 技能树节点 | C+KF+H+RC | `hud_intent_button_pressed("skill_<action>")` | 远期 |
| widget_minimap_marker | 小地图标记点 | C+H | `hud_intent_world_indicator_clicked` | Phase 3 |

**C4 落地约定**：
- 优先用 `Button`（自带焦点 / hover / pressed / disabled 四态、自带 Enter 触发、自带 hover 主题）。
- 自定义视觉：用 `Control` + `_gui_input` 自处理 InputEventMouseButton + InputEventKey，但**必须显式声明 `interact_kinds`** 以便 Showcase 自检。
- **手柄导航**：通过 `focus_neighbor_*` 显式串好上下左右；或父容器走 `FocusMode.ALL`。
- **声音反馈**：所有 C4 在 `pressed` 时由 AudioManager 订阅 `hud_intent_button_pressed` 播 `ui_click`。

### 3.5 C5 Drag-Slot（4 个）

| widget_id | 中文 | DragSource | DropTarget | 备注 |
|---|---|---|---|---|
| widget_inventory_slot | 背包格子 | ✅ | ✅（接受其他背包格 → 排序 / 接受装备槽 → 卸下） | √ 重构 |
| widget_equipment_slot | 装备槽 | ✅（拖到背包 → 卸下） | ✅（接受兼容物品） | √ 重构 |
| widget_hotbar_slot_skill | 技能 Hotbar 槽 | ✅（拖到另一槽 → 重排） | ✅（接受技能图标） | 远期 |
| widget_stash_slot | 仓库格子 | ✅ | ✅ | D5 |

**C5 落地约定**（Godot 4.6 原生 D&D API）：

```gdscript
class_name InventorySlotWidget
extends BaseWidget

func _get_drag_data(_at: Vector2) -> Variant:
    if _item_id == &"":
        return null
    var preview := _build_drag_preview()
    set_drag_preview(preview)
    return {
        "kind": &"inventory_item",
        "item_id": _item_id,
        "src_slot_index": _slot_index,
        "src_widget_id": widget_id,
    }

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
    if typeof(data) != TYPE_DICTIONARY:
        return false
    return data.get("kind") in [&"inventory_item", &"equipment_item"]

func _drop_data(_at: Vector2, data: Variant) -> void:
    EventBus.hud_intent_move_item.emit(
        _owner_node,
        data,                                                      # src
        { "kind": &"inventory_item", "dst_slot_index": _slot_index } # dst
    )
```

> **关键约束**：HUD 不直接调 `InventoryComponent.move_item()`；只 emit `hud_intent_move_item`，业务侧订阅决定能不能移、移到哪里去（含同 stack 合并）。

**双击 / 右键的统一抽象**：
- 双击 = `hud_intent_use_item`（消耗品）或 `hud_intent_equip_item`（装备）
- 右键 = 弹 `widget_context_menu`（C7 复合组件），上抛 `hud_intent_button_pressed("context_<action>")`
- 拖回背包 = `hud_intent_unequip_item`

### 3.6 C6 Editable-Field（7 个）

| widget_id | 中文 | 控件 | 上抛信号 |
|---|---|---|---|
| widget_setting_volume | 音量滑条 | `HSlider` | `hud_intent_setting_changed("audio.bgm_volume", 0.7)` |
| widget_setting_resolution | 分辨率下拉 | `OptionButton` | `hud_intent_setting_changed("display.resolution", "1920x1080")` |
| widget_setting_fullscreen | 全屏切换 | `CheckBox` | `hud_intent_setting_changed("display.fullscreen", true)` |
| widget_setting_keybind | 按键重映射 | 自定义 `Button`（捕获下次按键） | `hud_intent_setting_changed("input.combat_attack", &"mouse_left")` |
| widget_setting_hud_scale | HUD 缩放 | `HSlider` | `hud_intent_setting_changed("hud.scale", 1.25)` |
| widget_save_slot_rename | 存档命名 | `LineEdit` | `hud_intent_button_pressed("save_name_submitted", {name})` |
| widget_dialogue_input_text | 对话文本输入（远期） | `LineEdit` | 同上 |

**C6 落地约定**：
- 优先用 Godot 原生（自带键鼠 + 手柄焦点 + 触屏）。
- 设置类全部走 `hud_intent_setting_changed(key, value)`；SettingsManager 订阅 → 检查合法 → 写 `user://settings.cfg` → emit `EventBus.settings_changed`。

### 3.7 C7 Compound（10 个）

| widget_id | 中文 | 包含子组件 | 所在层 | 备注 |
|---|---|---|---|---|
| widget_inventory_panel | 背包面板 | C5×N + C5 装备区 + C1 金币 + C4 关闭 | L2 栈 | √ 重构 |
| widget_pause_menu | 暂停菜单 | 多 C4 按钮 | L3 栈 | √ |
| widget_settings_menu | 设置菜单 | C4 Tab + 多 C6 字段 | L3 栈 | √ |
| widget_shop_panel | 商店面板 | C4 列表 + C1 金币 + C4 购买按钮 + C5 拖出 | L4 栈 | M12.2 |
| widget_dialogue_box | 对话框 | C1 文本 + 头像 C1 + C4 选项行 | L1 底部子栈 | M11 |
| widget_modal_confirm | 通用确认框 | C1 文本 + C4 是 / 否 | L4 栈 | Phase 3 |
| widget_equip_compare_card | 装备比较卡 | C1 属性对比 + C4「替换 / 取消」 | L4 弹 | Phase 3 |
| widget_quest_log | 任务日志面板 | C4 列表 + C1 详情 | L2 栈 | M12.3 |
| widget_minimap_panel | 大地图面板 | C2 标记列表 + C4 中心定位 | L2 栈 | 远期 |
| widget_tooltip | 通用 Tooltip | C1 内容 + 跟随光标 | L4 顶部 | Phase 3 |

**C7 落地约定**：
- 用 `Panel` + `MarginContainer` + `VBox/HBox` 拼装；**不要**自己处理子组件交互，依赖原生焦点链 + 子组件本身上抛的 hud_intent。
- 复合容器仅负责：入场退场动画 / 主题主色 / 关闭按钮 / 焦点初始化；任何业务交互由内层 C4/C5/C6 上抛。
- ESC / 手柄 B = 自动 pop 栈（HUDManager.pop_widget）；战斗按键由 InputContext 屏蔽。

---

## 4. 原生节点选型决策矩阵

> R-HUD-COMP-05：能用原生就用原生。本节是 widget 编写者的查表速查。

| 需求 | 首选 | 备选 | 自绘理由 |
|---|---|---|---|
| 进度条（HP/MP/EXP） | `ProgressBar` | `TextureProgressBar` | 双层条 + ghost 追条用 ProgressBar + `_draw` 叠层（已在 LayeredBossHealthBar 实践） |
| 文本 | `Label` | `RichTextLabel`（仅对话 / Tooltip） | HUD 主体禁用 RichTextLabel（性能） |
| 按钮 | `Button` | `TextureButton` | 自定义视觉时继承 Button 改 Theme，避免自绘 |
| 物品图标格子 | `Control` + `TextureRect` + `Label` 数量 | `NinePatchRect` | 拖拽必须自处理 _get_drag_data |
| 数值滑条 | `HSlider` / `VSlider` | `Range` | — |
| 数值加减 | `SpinBox` | `LineEdit + Button×2` | — |
| 下拉选择 | `OptionButton` | `ItemList` | — |
| 选项列表（很多项） | `ItemList` | `Tree` | — |
| 多列表格（任务 / 物品） | `Tree`（columns_mode=true） | `ItemList`（单列） | 任务条目展开收起用 Tree 最舒服 |
| Tab 切换 | `TabContainer` / `TabBar` | 自做按钮组 | 设置菜单的 Tab 走 TabContainer |
| Toast / 通知堆叠 | `VBoxContainer` 内动态加 `Panel` | — | — |
| 拖拽 Preview | Godot 原生 `set_drag_preview` API | — | — |
| 焦点环 / 键盘导航 | Godot 原生 `focus_*` + `FocusMode` | — | — |
| 模糊背景 / 半透明遮罩 | `ColorRect` + `BackBufferCopy`（如要模糊） | `Panel` 主题 | — |
| 圆形 / 雷达 | `Control` + `_draw` 自绘 + `Path2D` | `Polygon2D` | 小地图建议 SubViewport 渲染地图 + Control 叠雷达点 |
| 输入捕获 | `LineEdit` / 自定义 `_input` 监听 InputEventKey | — | — |
| Drag&Drop | Godot 原生 4 个虚函数 | — | 不要造轮子 |
| Tooltip | Godot 原生 `tooltip_text`（简单）/ widget_tooltip 跟随光标 | — | 复杂 Tooltip 用 widget_tooltip |
| 输入提示图标（手柄/键盘） | `TextureRect` + `Input.joy_connection_changed` | — | — |

### 4.1 何时**必须自绘**（少数例外）

| 场景 | 例外原因 |
|---|---|
| 自定义图形（雷达扫描线、技能 CD 转圈遮罩、Boss 血条 ghost 追条 + 分段竖线） | 原生 ProgressBar 不支持 |
| 复杂蒙版（暴击伤害飘字的描边 + 渐变） | Label 字体描边只能走 Theme，渐变需 Shader |
| 世界 HUD 的精确投影定位 | Camera.unproject_position 后必须自己设 position |

> 自绘时仍挂 `_draw` 在 `Control` 上，所有可调参数（颜色、半径、宽度）扔到 `.tres`（R-HUD-03）。

---

## 5. 跨组件协作 / 状态切换

### 5.1 复合 widget 内部交互链（背包面板示例）

```
玩家拖动 widget_inventory_slot[3] 的物品到 widget_equipment_slot[Weapon]
   │
   ├─ inventory_slot._get_drag_data → 返回 payload={item_id, src=3}
   ├─ equipment_slot._can_drop_data → 检查 payload.kind 兼容（不查业务）
   ├─ equipment_slot._drop_data    → emit EventBus.hud_intent_equip_item(player, item_id, slot=Weapon)
   │
   ▼
EquipmentComponent 订阅 hud_intent_equip_item
   │
   ├─ 查 ItemDefinition.slot 是否兼容 → 不兼容 → emit hud_toast_requested("不可装备到此槽")
   ├─ 兼容 → 调 self.equip(item) → 自动 emit equipment_changed
   ▼
HUD 订阅 equipment_changed → 刷新 widget_inventory_panel
```

### 5.2 状态机阻断输入（已有 InputContext）

| HUDStateMachine 状态 | InputContext | HUD 可交互范围 |
|---|---|---|
| GAMEPLAY | Gameplay (allow_all) | 仅 C2 / C3（其他被层级隐藏） |
| PANEL_OPEN | PanelOpen（屏蔽 combat_*） | 当前层 + L2 内 C4/C5/C6 |
| PAUSED | PanelOpen | L3 内 C4/C6 |
| DIALOGUE | Dialogue | 仅对话框 C4 选项 |
| CUTSCENE | Cutscene | 仅 Skip C4 |
| DEAD | Dead | 仅死亡面板 C4 |

> Phase 0 已交付 6 份 InputContext.tres + InputContextManager；Phase 3 widget 上线时**只需**调 `HUDStateMachine.change_state(...)`。

### 5.3 手柄 / 键盘 / 触屏 三路输入兼容速查

| 交互 | 键鼠 | 手柄 | 触屏 |
|---|---|---|---|
| 选中按钮 | 鼠标 hover + 点 / Tab + Enter | 方向键 + A | 直接点 |
| 双击使用物品 | 双击 | A 键长按 0.3s 视为双击 | 双击 |
| 拖拽 | 按住 + 拖动 | A 抓起 + 方向键 + A 放下 | 按住 + 拖 |
| 右键菜单 | 右键 | Y 键 | 长按 0.5s |
| ESC 退出 | ESC | B 键 | 屏幕角的 X 按钮 |
| 滚轮调音量 | 滚轮 | 摇杆 Y 轴 | 拖滑条 |

> 触屏暂不优先，但**禁止依赖 hover**：所有 hover 动效必须在 `mouseEntered` / `focusEntered` 双触发（手柄走 focus）。

---

## 6. 资源结构（与 ConfigCenter 对接）

> 已规划：`HitFeedbackConfig` / `HealthBarConfig` / `SfxBindings` / `UIDurations`（已有）；本节列 Phase 3 新增。

### 6.1 `Data/Config/UITheme.tres`（Phase 2 P2-T7 创建）

```gdscript
# Godot 原生 Theme.tres 直接用即可；如要包装一层：
class_name UITheme
extends Resource

@export var theme: Theme
@export var radius_small: int = 4
@export var radius_medium: int = 8
@export var radius_large: int = 12
@export var button_min_height: int = 36
@export var slot_size: int = 48      # 物品 / 技能 / Hotbar 槽统一边长
```

### 6.2 `Data/Config/UIColorTokens.tres`（Phase 2 同上）

```gdscript
class_name UIColorTokens
extends Resource

@export var color_hp:           Color
@export var color_mp:           Color
@export var color_xp:           Color
@export var color_buff_text:    Color
@export var color_debuff_text:  Color
@export var color_warning:      Color
@export var color_critical:     Color
@export var color_heal:         Color
@export var color_loot_normal:  Color
@export var color_loot_rare:    Color
@export var color_loot_epic:    Color
@export var color_loot_legend:  Color
```

### 6.3 `Data/Config/HUDInteractConfig.tres`（**Phase 3 新增**）

> 把"双击间隔 / 长按时间 / 拖拽阈值 / 滚轮灵敏度"等交互手感参数全部挂这里。

```gdscript
class_name HUDInteractConfig
extends Resource

@export var double_click_interval: float = 0.30          ## 鼠标 / 触屏双击间隔（秒）
@export var gamepad_long_press_to_double_click: float = 0.30  ## 手柄 A 长按视为双击的时长
@export var long_press_duration: float = 0.50            ## 右键菜单长按时长（触屏）
@export var drag_threshold_pixels: float = 8.0           ## 触发拖拽的最小位移
@export var drag_preview_scale: float = 1.0              ## 拖拽 preview 缩放
@export var scroll_step_volume: float = 0.05             ## 滚轮单格音量步进
@export var tooltip_hover_delay: float = 0.50            ## Tooltip hover 触发延迟
@export var focus_change_duration_tag: StringName = &"XS" ## 焦点改变动画档（取自 UIDurations）
```

### 6.4 `Data/Config/HUDLayout_Default.tres`（Phase 1 P1-T7 已建空版）

> Phase 3 在此填 widget 与 slot 映射，参考 §3 各组件「所在层」字段。

---

## 7. 落地实现策略

### 7.1 新系统 vs 现有框架的取舍

| 需求 | 复用 | 新增 |
|---|---|---|
| 显隐生命周期 | ✅ BaseWidget | — |
| 层级管理 | ✅ HUDManager | — |
| 状态机 | ✅ HUDStateMachine | — |
| 输入屏蔽 | ✅ InputContextManager | — |
| 时长档 | ✅ UIDurations | — |
| 数据契约 | ✅ Contracts/I*Readable | — |
| 主题 / 颜色 | ✅ Godot 原生 Theme + UITheme/UIColorTokens.tres | — |
| 按钮 / 滑条 / 列表 | ✅ Godot 原生 Control | — |
| 拖拽 | ✅ Godot 原生 D&D API | — |
| 焦点 / 键盘导航 | ✅ Godot 原生 `focus_neighbor_*` | — |
| 世界投影 | ✅ Camera3D.unproject_position | — |
| 飘字 / Toast 池化 | ✅ DamagePopupPool 模式 | — |
| 状态切换 + 输入屏蔽组合 | ✅ HUDStateMachine + InputContextManager | — |
| **InteractKind 枚举** | ❌ | ✅ 新增 `Script/UI/HUDInteract.gd` |
| **HUDComponentKind 枚举** | ❌ | ✅ 新增 `Script/UI/HUDComponentKind.gd` |
| **hud_intent_* 信号族** | ⚠️ EventBus 现有信号偏底层 | ✅ 新增 11 条 |
| **HUDInteractConfig.tres** | ❌ | ✅ 新增 |
| **WorldProjector.gd 工具** | ⚠️ 散在 DamagePopupPool 内 | ✅ 抽出（Phase 2 P2-T3 已规划） |

> **结论**：仅新增 4 个轻量模块（HUDInteract / HUDComponentKind 两个枚举类、`hud_intent_*` 11 个信号、HUDInteractConfig.tres）。其他全部复用 Godot 原生与已落地框架。

### 7.2 新系统的存在理由（必须列出）

| 新系统 | 不引入会怎样 | 引入后能做什么 |
|---|---|---|
| **HUDInteract / HUDComponentKind 枚举** | 各 widget 自定义"我是不是可点击"语义；Showcase / 自动化测试无法批量跑过 | 统一契约 → Showcase 时自动校验声明的交互是否真的生效 |
| **hud_intent_\* 信号族** | HUD 直接调 `InventoryComponent.use_item()` 等业务方法 → 违反 R-HUD-01（HUD 不写回业务）+ R-EVENT-01（跨模块走 EventBus）；单测无法 mock | 业务侧只需订阅信号即可单测；HUD 在 Showcase 里 emit 假信号验证视觉；不同业务（Inventory / Equipment / Shop）共享一套 widget 不需重写 |
| **HUDInteractConfig.tres** | 双击间隔、拖拽阈值等手感参数硬编码 → 跨 widget 不一致 → 玩家投诉某些面板手感诡异 | 统一一处调，R-DATA-02 合规 |
| **WorldProjector.gd 工具** | 投影逻辑散在 3 个 Manager 各一份 | 单点维护，2D/3D 切换时只改一处 |

### 7.3 落地 Phase 顺序（嵌入 06 路线）

| 06 阶段 | 本文档对应工作 |
|---|---|
| Phase 0（已完成） | 无；地基 |
| Phase 1（已完成） | BaseWidget 已支持 `interact_kinds` 字段（追加 §2.2 两个 export 字段，向后兼容） |
| **Phase 2** | 新增 HUDComponentKind / HUDInteract / HUDInteractConfig.tres（不影响现有迁移）；现有 5 widget 迁移时**只为 InventoryUI / PauseMenu / SettingsMenu** 标 component_kind=COMPOUND，子控件不强制 |
| **Phase 3** | EventBus 追加 11 个 hud_intent 信号；新增 widget 全部按 §3 清单实现，并按 §2.4 时序上抛 intent；Inventory / Equipment / Shop 业务侧改为订阅 hud_intent_*，逐步把 HUD 直调拆掉 |
| **Phase 4** | HUDShowcase 跑通时遍历所有 widget，按 component_kind / interact_kinds 自检（auto-test） |

### 7.4 现存代码对接清单（Phase 3 启动时检查）

| 现有代码 | 现状 | 调整 |
|---|---|---|
| `InventoryUI.gd` 直接 `_inventory_comp.use_item(slot)` | 业务直调 | 改为 `EventBus.hud_intent_use_item.emit(player, item_id, slot)` |
| `EquipmentComponent.gd` `equip(item)` | API 暴露给 HUD | 改为订阅 `hud_intent_equip_item` |
| `PauseMenu.gd` `_on_resume_pressed → GameInstance.change_state(PLAYING)` | 直调 | 可保留（系统类按钮简单）；或改 `hud_intent_button_pressed("pause_resume")` 由 GameInstance 订阅 |
| `SettingsMenu.gd` `_on_volume_changed → SettingsManager.set("audio.bgm", v)` | 直调 | 改 `hud_intent_setting_changed("audio.bgm", v)` 由 SettingsManager 订阅 |
| `DamagePopupPool._project_to_screen` | 内部静态 | 抽到 `Script/UI/Util/WorldProjector.gd` 复用（P2-T3 已规划） |

### 7.5 Showcase / 自动化测试（与 06 Phase 4.1 P4-T5..T7 联动）

每个 widget 在 HUDShowcase 中通过 5 项**契约自检**（编辑器内跑一段 GDScript）：

```gdscript
# Tools/HUDComponentSelfTest.gd（伪代码）
for widget_scene in all_widget_scenes:
    var w := widget_scene.instantiate() as BaseWidget
    assert(w.component_kind != HUDComponentKind.Kind.UNKNOWN)
    assert(w.widget_id != &"")
    # 1. component_kind 匹配 interact_kinds（如 C1 必须 NONE）
    if w.component_kind == HUDComponentKind.Kind.DISPLAY:
        assert(w.interact_kinds == 0)
    # 2. mouse_filter 与 input_mode 匹配
    # 3. theme 已设
    # 4. 没有硬编码 Color() / font_size = N
    # 5. data_provider 为 null 时 refresh() 不崩
    w.queue_free()
```

---

## 8. 速查矩阵（一页式）

### 8.1 「我要做 XXX」→ 应该用什么组件 + 节点 + 信号

| 业务诉求 | 组件类型 | 节点选型 | 上抛信号 |
|---|---|---|---|
| 显示一个数值（HP/MP） | C1 | `ProgressBar` + `Label` | — |
| 跟着敌人头顶飞（血条/名字） | C2 | `Control` + `Camera3D.unproject_position` | — |
| 按 Q 放技能（UI 仅显示 CD） | C3 | `Panel` + `Label` 数字 + `ColorRect` 遮罩 | （由 InputController → ASC，不上抛） |
| 点按钮做一件事 | C4 | `Button` | `hud_intent_button_pressed(button_id)` |
| 点列表行选物品 | C4 | `ItemList` 或 `Tree` | `hud_intent_button_pressed(...)` |
| 拖物品到装备槽 | C5 | `Control` + 原生 D&D | `hud_intent_move_item / equip_item` |
| 双击使用物品 | C5 | 同上 | `hud_intent_use_item` |
| 调音量 / 缩放 | C6 | `HSlider` | `hud_intent_setting_changed(key, value)` |
| 文字输入存档名 | C6 | `LineEdit` | `hud_intent_button_pressed("save_name_submitted", {name})` |
| 切 Tab | C6 | `TabContainer` | （视情况，可不必上抛） |
| 弹一个 Yes/No 框 | C7 | `Panel` + 2×Button | `hud_intent_modal_confirm(...)` |
| 弹商店面板 | C7 | Panel + Tree + Button + Label | `hud_intent_purchase / sell` |
| 自定义视觉的雷达 / 圆形血条 | C1 自绘 | `Control._draw` | — |

### 8.2 「我要新增一个 widget」→ 6 步法

1. **选类型**：按 §1.1 决策树定 C1~C7。
2. **建场景**：`Scenes/UI/Widgets/MyWidget.tscn`，根 `Control extends BaseWidget`，挂可选 `AnimationPlayer` 名为 `show / hide` 的两段动画。
3. **实现 GDScript**：
   - 标 `component_kind` 与 `interact_kinds`。
   - 在 `_ready()` 订阅相关 `EventBus` 信号或 `data_provider.changed`。
   - 实现 `refresh()`（C1/C2）或 `_gui_input` 上抛 `hud_intent_*`（C4~C7）。
   - 拖拽走 `_get_drag_data / _can_drop_data / _drop_data`（C5）。
4. **挂主题 + 颜色 token**：`@export var theme_resource: Theme = preload("res://Data/Config/UITheme.tres")`；颜色全用 `UIColorTokens.tres`。
5. **注册到 HUDLayout**：在 `Data/Config/HUDLayout_Default.tres` 的 `mounts` 数组追加一项 `{slot_tag, widget_scene, priority, enabled}`，**不写代码**。
6. **进 Showcase**：`Scenes/Debug/HUDShowcase.tscn` 加一份 panel 拖入并喂 Mock provider；R-HUD-04。

---

## 9. 验收清单（HUD 组件化体系）

> 与 06 Phase 3 / Phase 4 验收联动。

### 9.1 类型与契约

- [ ] HUDComponentKind / HUDInteract 两个枚举类落地，全部 widget 标注 component_kind ≠ UNKNOWN
- [ ] 11 个 `hud_intent_*` 信号在 EventBus 集中声明，参数类型符合 R-EVENT-01
- [ ] BaseWidget 增加 `component_kind` / `interact_kinds` 两个 export 字段，默认值兼容现有 widget
- [ ] HUDInteractConfig.tres 落库；double_click_interval / drag_threshold_pixels 等参数全部由它读取

### 9.2 组件落地

- [ ] C1 Display 21 个全部上线，无任何 mouse_filter=STOP（避免吃下层点击）
- [ ] C2 Indicator 共用 `WorldProjector.gd`；离屏 / 距离剔除生效
- [ ] C3 Hotkey-Trigger 触发完全走 InputAction，UI 不响应鼠标点击
- [ ] C4 优先用 `Button`；自定义视觉时显式声明 `interact_kinds`
- [ ] C5 全部用 Godot 原生 `_get_drag_data / _can_drop_data / _drop_data`；上抛 `hud_intent_move_item / equip_item / use_item`
- [ ] C6 全部用 Godot 原生 `HSlider / LineEdit / OptionButton / SpinBox / CheckBox`；统一上抛 `hud_intent_setting_changed`
- [ ] C7 仅负责入退场动画 + 关闭按钮 + 焦点初始化；业务交互全在内层

### 9.3 业务接驳

- [ ] InventoryComponent / EquipmentComponent / ShopManager 从"被 HUD 直调"改为"订阅 hud_intent_*"；grep widget 中 `<业务>.method(` 调用归零
- [ ] SettingsManager 订阅 `hud_intent_setting_changed` 并写 `user://settings.cfg`
- [ ] AudioManager 订阅 `hud_intent_button_pressed` 播 `ui_click`

### 9.4 输入兼容

- [ ] 全 HUD 走一遍键鼠交互：所有 C4/C5/C6 都能用 Tab 焦点导航 + Enter 触发
- [ ] 接入手柄走一遍：C4 用方向键 + A 全部可达，C5 走 A 抓起 + 方向键 + A 放下
- [ ] hover 效果不依赖鼠标：手柄移焦时同样触发 highlight

### 9.5 Showcase 自检

- [ ] HUDComponentSelfTest 跑通：所有 widget 5 项契约 PASS
- [ ] 每个组件都能在 HUDShowcase 中喂 Mock Provider 独立预览（R-HUD-04）

---

## 10. 命名 / 文件目录约定

```
Script/UI/
  HUDInteract.gd                      # 新增（小，仅枚举）
  HUDComponentKind.gd                 # 新增（小，仅枚举）
  Util/
    WorldProjector.gd                 # 新增（P2-T3 抽出）
  Widgets/
    Display/                          # C1
      PlayerHpWidget.gd
      ComboCountWidget.gd
      ...
    Indicator/                        # C2
      EnemyOverheadHpWidget.gd
      InteractPromptWidget.gd
      ...
    Hotkey/                           # C3
      HotbarSkillWidget.gd
      ...
    Selectable/                       # C4
      DialogueChoiceButton.gd
      ShopItemRow.gd
      ...
    DragSlot/                         # C5
      InventorySlotWidget.gd
      EquipmentSlotWidget.gd
      ...
    Editable/                         # C6
      VolumeSliderWidget.gd
      KeybindButton.gd
      ...
    Compound/                         # C7
      InventoryPanelWidget.gd
      ShopPanelWidget.gd
      ...
Scenes/UI/Widgets/                    # 与 Script/UI/Widgets 同名子目录
Data/Config/
  UITheme.tres                        # Phase 2
  UIColorTokens.tres                  # Phase 2
  HUDInteractConfig.tres              # Phase 3 新增
  HUDLayout_Default.tres              # Phase 1 已有（Phase 3 填充）
```

---

## 11. 与现有规则的合规性

| 规则 | 本方案如何保证合规 |
|---|---|
| **R-HUD-01**（HUD 不写回业务） | 全部走 `hud_intent_*` 信号；业务订阅，不接受 HUD 直调 |
| **R-HUD-02**（HUD 不直接 cast 业务类） | 子组件依赖 `IAttributeReadable / ICooldownReadable / IWorldAnchored` 三契约；对业务对象只通过 `data_provider: Resource` |
| **R-HUD-03**（数值 / 颜色 / 像素全走 .tres） | 所有手感参数挂 `HUDInteractConfig.tres` / `UIColorTokens.tres` / `UITheme.tres` / `UIDurations.tres` |
| **R-HUD-04**（Showcase 独立运行） | 每个 widget 配 Mock Provider；§7.5 自检脚本验证 |
| **R-HUD-05**（跨模块走 EventBus） | 11 个 `hud_intent_*` 信号集中声明 |
| **R-ARCH-02**（Autoload 上限 6） | 不新增 Autoload；HUDComponentKind / HUDInteract 都是普通类 |
| **R-EVENT-01**（全局信号集中声明） | 11 条 hud_intent 全部进 EventBus.gd |
| **R-DATA-02**（数据驱动优先） | HUDInteractConfig.tres 承接所有可调手感参数 |
| **R-CHAR-02**（3D 场景节点纯洁性 / HUD 例外） | 所有 widget 在 CanvasLayer 下；C2 Indicator 仅做投影计算，不在 Node3D 子树挂 2D 节点 |

---

## 变更日志

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-05-21 | 首次建立。基于 05 / 06 / Phase 0 落地现状萃取，引入 7 类组件 + InteractKind 枚举 + 11 条 hud_intent 信号 + HUDInteractConfig.tres，全面对齐 Godot 4.6 原生与已落地框架。仅新增 4 个轻量模块，其余 100% 复用。|
