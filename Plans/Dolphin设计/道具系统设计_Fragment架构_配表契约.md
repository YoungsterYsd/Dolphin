# 道具系统设计 · Fragment 架构 + CSV 双轨配表契约

> **创建日期**：2026-05-23
> **架构灵感**：Lyra Inventory Fragment（UE 5）—— 组合式物品定义
> **数据载体**：CSV 主导 + .tres 仅承载 Resource 引用（与 R-DATA-03 修订版一致）
> **状态**：✅ 设计定稿，待启动 Phase 1 编码

---

## 一、设计目标

1. **可扩展**：加新物品类型 = 组合现有 Fragment，不再写新继承类
2. **数据驱动**：所有数值/文本走 CSV，策划在 Excel 编辑
3. **资源解耦**：Texture/GE/GA 引用集中在 .tres，CSV 只放路径字符串
4. **与 GAS 一体**：装备属性加成走 GE 临时挂载，与现有 GE 系统无缝
5. **规则合规**：满足 R-DATA-01/02/03 / R-CODE-01/02 / R-ARCH-04 / R-CHAR-01

---

## 二、核心架构：Fragment 模式（钩子化）

### 2.1 整体分层

```
┌─────────────────────────────────────────────────────────┐
│ 数据层（启动期一次性加载）                                  │
│   CsvTableSource         （IO：load 所有 CSV → Dict 缓存）  │
│   ItemFragmentFactory    （路由：kind → Fragment.from_csv） │
│   ItemConfigLoader       （装配：扫表组装 ItemDefinition）   │
│   AffixPlanLoader        （词条池数据）                     │
│   FragmentRegistry       （集中表：kind ↔ class ↔ csv_path）│
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 模型层（Resource，无副作用）                                │
│   ItemDefinition  （模板：id/name/icon_path + fragments[]）│
│   ItemInstance    （实例：def_id + stat_tags）              │
│   ItemFragment    （基类 + 4 个虚钩子）                    │
│     ├── Fragment_Currency  (intercepts_inventory_add)     │
│     ├── Fragment_Equip     (on_instance_created 滚字)     │
│     ├── Fragment_GA        (on_equipped/unequipped)       │
│     ├── Fragment_GE        (on_equipped/unequipped)       │
│     ├── Fragment_Quest     (on_use)                       │
│     ├── Fragment_Quality   (UI)                           │
│     └── Fragment_Stackable (堆叠初始化)                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 行为层（Node，挂在 BaseCharacter 子节点）                   │
│   InventoryComponent  （薄路由：触发 fragment.on_use 等）   │
│   EquipmentComponent  （薄路由：触发 fragment.on_equipped） │
└─────────────────────────────────────────────────────────┘
```

### 2.2 ItemFragment 钩子契约

基类 `ItemFragment` 提供 5 个虚钩子，子类按需 override（默认 noop）：

| 钩子 | 触发时机 | 默认行为 | 主要 override 者 |
|---|---|---|---|
| `static from_csv_row(row, source)` | Loader 装配期 | 抽象（必须 override） | 所有 Fragment |
| `on_instance_created(instance)` | `ItemInstance.create_new()` 时 | 无 | Fragment_Equip 滚字 / Fragment_Stackable 写初始 stack |
| `intercepts_inventory_add(def, count) -> bool` | InventoryComponent.add 入口 | false | Fragment_Currency 拦截到 CurrencyManager |
| `handle_inventory_add(owner, def, count) -> int` | intercept 返回 true 时 | 0 | Fragment_Currency |
| `on_use(owner, instance) -> bool` | InventoryComponent.use | true（允许走通用消耗流程） | Fragment_Currency 返回 false 阻断 / Fragment_Quest emit 信号 / Fragment_Equip 调装备 |
| `on_equipped(owner, instance)` | EquipmentComponent.equip | 无 | Fragment_GA 授予 / Fragment_GE 挂载 |
| `on_unequipped(owner, instance)` | EquipmentComponent.unequip | 无 | Fragment_GA 撤销 / Fragment_GE 移除 |

**核心好处**：加新 Fragment 类型 = 写新 .gd + 在 FragmentRegistry 加 1 行；**InventoryComponent / EquipmentComponent 永不修改**（OCP）。

### 2.3 ItemDefinition 极简化（去冗余字段）

```gdscript
class_name ItemDefinition extends Resource

@export var item_id: int = 0
@export var display_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var consumable: bool = false       # 通用 flag：use 后是否扣 1
@export var fragments: Array[ItemFragment] = []

# 不存 rarity / max_stack 字段——通过 Fragment 间接读
func get_max_stack() -> int:
    var f := find_fragment(Fragment_Stackable) as Fragment_Stackable
    return f.initial_count if f != null else 1

func get_rarity() -> int:
    var f := find_fragment(Fragment_Quality) as Fragment_Quality
    return f.rarity if f != null else 1

func find_fragment(fragment_type: GDScript) -> ItemFragment:
    for f in fragments:
        if is_instance_of(f, fragment_type):
            return f
    return null

func has_fragment(fragment_type: GDScript) -> bool:
    return find_fragment(fragment_type) != null
```

**单一真相源**：rarity/max_stack 只存在于 Fragment 内，避免双轨数据漂移。

### 2.4 与 Lyra 的对应

| Lyra (UE) | Dolphin (Godot) |
|---|---|
| `ULyraInventoryItemDefinition` | `ItemDefinition.gd` (Resource) |
| `ULyraInventoryItemFragment` | `ItemFragment.gd` (Resource 基类) |
| `ULyraInventoryItemInstance` | `ItemInstance.gd` (Resource) |
| `FGameplayTagStackContainer` | `ItemInstance.stat_tags: Dictionary` |
| `ULyraInventoryManagerComponent` | `InventoryComponent.gd` (Node) |
| Blueprint .uasset 编辑 | CSV (数值) + .tres (Resource 引用) |
| `OnInstanceCreated()` | `on_instance_created()` 同名钩子 |

---

## 三、配表契约（已定稿）

### 3.1 文件分布

```
Tools/Excel/
├── 道具表.xlsx
│   ├── Item_Data         (主表，每行一件物品)
│   ├── Frag_Currency
│   ├── Frag_Equip
│   ├── Frag_GA
│   ├── Frag_GE
│   └── Frag_Quest
└── 词条随机表.xlsx
    └── attr_plan         (装备词条池)

↓ excel2Config 工具导出 ↓

Data/FromExcel/
├── Item_Data.csv
├── Frag_Currency.csv
├── Frag_Equip.csv
├── Frag_GA.csv
├── Frag_GE.csv
├── Frag_Quest.csv
└── attr_plan.csv
```

### 3.2 Fragment 类型清单（Phase 1 锁定）

| 类型名 | 来源 | 子表 | 说明 |
|---|---|---|---|
| **Currency** | Item_Data.Fragment 显式 | Frag_Currency | 货币（不进背包网格） |
| **Equip** | Item_Data.Fragment 显式 | Frag_Equip | 装备（含词条滚字） |
| **GA** | Item_Data.Fragment 显式 | Frag_GA (1:N) | 装备时临时学到 GA |
| **GE** | Item_Data.Fragment 显式 | Frag_GE (1:N) | 装备时常驻挂载 GE |
| **Quest** | Item_Data.Fragment 显式 | Frag_Quest | 任务道具 |
| **Quality** | 主表 Rarity ≥ 1 自动构造 | — | UI 染色 |
| **Stackable** | 主表 Stack > 0 自动构造 | — | 堆叠 |

> **命名约定**：Fragment 类型名 = 子表名去 `Frag_` 前缀（PascalCase）。

### 3.3 主表 `Item_Data` 字段表

| 列 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `id` | Int | — | 主键（非 0） |
| `sub_id` | Int | 空 | 主表均为主行；空 |
| `备注` | Ignore | — | 策划备注，不导出 |
| `Name` | String | "" | 显示名（i18n 系统上线后改 .translation） |
| `Desc` | String | "" | 描述 |
| `Fragment` | List(String) | {} | 该物品挂载哪些 Fragment（去 Frag_ 前缀） |
| `Rarity` | Int | 1 | 品质 1-5；≥1 自动构造 Fragment_Quality |
| `Icon` | String | "" | 图标路径 `res://Content/Icons/Items/<name>.png` |
| `Stack` | Int | 1 | 堆叠上限；=0 不进背包网格（货币用） |
| `Consumable` | Int(0/1) | 0 | use() 后是否扣 1 个堆叠 |

### 3.4 子表字段表

#### Frag_Currency
| 列 | 类型 | 说明 |
|---|---|---|
| `Icon_On_Tip` | String | HUD 货币栏 / 飘字提示用图标 |

#### Frag_Equip
| 列 | 类型 | 说明 |
|---|---|---|
| `Slot` | Enum(Weapon,Armor,Shoes) | 装备槽位 |
| `num_main` | Int | 主词条**抽取条数**（不放回加权抽样） |
| `affix_plan_main` | Int | 主词条池 plan_id（→ attr_plan.id） |
| `num_sub` | Int | 副词条抽取条数 |
| `affix_plan_sub` | Int | 副词条池 plan_id |

#### Frag_GA（1:N，全子行）
| 列 | 类型 | 说明 |
|---|---|---|
| `GA_Path` | String | `res://Data/Abilities/...tres` 完整路径 |

> 一件装备可挂多个 GA：每条 GA 一个 sub_id 子行；id=item_id。

#### Frag_GE（1:N，全子行）
| 列 | 类型 | 说明 |
|---|---|---|
| `GE_Path` | String | `res://Data/Effects/...tres` 完整路径 |

> 装备时挂载 Duration=Infinite 的 GE，卸下时移除；用于"装备特殊额外效果"接口（如吸血、反伤、光环）。

#### Frag_Quest
| 列 | 类型 | 说明 |
|---|---|---|
| `Quest_ID` | Int | 任务 id；use() 时 emit `EventBus.quest_item_used(item_id, quest_id, user)` |

#### attr_plan（独立 xlsx · 词条池）
| 列 | 类型 | 说明 |
|---|---|---|
| `Attr_Type` | String | 属性名（StringName，对应 AttributeSet 字段） |
| `Op` | Enum(add,multiply,override) | 修饰器操作 |
| `Val` | Float | 值（固定，不滚范围） |
| `Weight` | Int | 加权抽样权重 |

> plan_id 是主键；同 plan_id 多个子行 = 候选词条池。

---

## 四、运行时合并流程

### 4.1 启动期 Loader（3 层架构）

#### 4.1.1 FragmentRegistry · 集中元数据表

```gdscript
# Script/Items/FragmentRegistry.gd
class_name FragmentRegistry extends RefCounted

## Fragment 类型注册表 —— 加新 Fragment 仅在此加 1 行
const REGISTRY: Array = [
    {"kind": &"Currency", "class": Fragment_Currency, "csv": "res://Data/FromExcel/Frag_Currency.csv"},
    {"kind": &"Equip",    "class": Fragment_Equip,    "csv": "res://Data/FromExcel/Frag_Equip.csv"},
    {"kind": &"GA",       "class": Fragment_GA,       "csv": "res://Data/FromExcel/Frag_GA.csv"},
    {"kind": &"GE",       "class": Fragment_GE,       "csv": "res://Data/FromExcel/Frag_GE.csv"},
    {"kind": &"Quest",    "class": Fragment_Quest,    "csv": "res://Data/FromExcel/Frag_Quest.csv"},
]

static func get_entry(kind: StringName) -> Dictionary:
    for e in REGISTRY:
        if e["kind"] == kind:
            return e
    return {}

static func get_all_csv_paths() -> Array:
    var paths: Array = []
    for e in REGISTRY:
        paths.append(e["csv"])
    return paths
```

#### 4.1.2 CsvTableSource · 数据源抽象（IO 层）

```gdscript
# Script/Data/Loaders/CsvTableSource.gd
class_name CsvTableSource extends RefCounted

var _tables: Dictionary = {}  # path → Dictionary[int, RowDict]

func load_paths(paths: Array) -> void:
    for p in paths:
        _tables[p] = CsvLoader.load_table(p)

func get_table(path: String) -> Dictionary:
    assert(_tables.has(path), "CsvTableSource: not loaded: %s" % path)
    return _tables[path]
```

#### 4.1.3 ItemFragmentFactory · Fragment 装配工厂

```gdscript
# Script/Data/Loaders/ItemFragmentFactory.gd
class_name ItemFragmentFactory extends RefCounted

## 按 kind 路由到对应 Fragment 类的 from_csv_row 工厂方法
static func build(kind: StringName, item_id: int, source: CsvTableSource) -> ItemFragment:
    var entry := FragmentRegistry.get_entry(kind)
    assert(not entry.is_empty(), "ItemFragmentFactory: unknown kind '%s'" % kind)
    var cls: GDScript = entry["class"]
    var csv_path: String = entry["csv"]
    var row: Dictionary = source.get_table(csv_path).get(item_id, {})
    # 调用类的静态 from_csv_row（GDScript 4.6 静态方法继承支持 cls.method()）
    return cls.from_csv_row(row, source)
```

#### 4.1.4 ItemConfigLoader · 装配（薄）

```gdscript
# Script/Data/Loaders/ItemConfigLoader.gd
class_name ItemConfigLoader extends RefCounted

const ITEMS_CSV := "res://Data/FromExcel/Item_Data.csv"

var _defs: Dictionary = {}  # int(id) → ItemDefinition

func load(source: CsvTableSource) -> void:
    var items: Dictionary = source.get_table(ITEMS_CSV)
    for id in items:
        _defs[id] = _assemble_def(int(id), items[id], source)

func _assemble_def(id: int, row: Dictionary, source: CsvTableSource) -> ItemDefinition:
    var def := ItemDefinition.new()
    def.item_id      = id
    def.display_name = CsvLoader.as_string(row, "Name")
    def.description  = CsvLoader.as_string(row, "Desc")
    def.icon_path    = CsvLoader.as_string(row, "Icon")
    def.consumable   = (CsvLoader.as_int(row, "Consumable") == 1)

    # 显式 Fragment（Fragment 列）
    var kinds := _parse_kind_list(CsvLoader.as_string(row, "Fragment"))
    for kind in kinds:
        var f := ItemFragmentFactory.build(kind, id, source)
        if f != null:
            def.fragments.append(f)

    # 隐式 Fragment（按主表字段自动构造，与显式 Fragment 等价）
    var stack: int = CsvLoader.as_int(row, "Stack")
    if stack > 0:
        var fs := Fragment_Stackable.new()
        fs.initial_count = stack
        def.fragments.append(fs)
    var rarity: int = CsvLoader.as_int(row, "Rarity")
    if rarity >= 1:
        var fq := Fragment_Quality.new()
        fq.rarity = rarity
        def.fragments.append(fq)

    return def

## 解析 "{Currency}" / "{Equip,GA,GE}" 为 Array[StringName]
static func _parse_kind_list(s: String) -> Array:
    var t := s.strip_edges()
    if t.is_empty(): return []
    if not (t.begins_with("{") and t.ends_with("}")):
        assert(false, "ItemConfigLoader: bad Fragment list '%s'" % s)
    var inner := t.substr(1, t.length() - 2)
    var parts := inner.split(",", false)
    var out: Array = []
    for p in parts:
        out.append(StringName(p.strip_edges()))
    return out

func get_by_id(id: int) -> ItemDefinition:
    return _defs.get(id, null)

func all() -> Dictionary:
    return _defs
```

#### 4.1.5 入口（ConfigCenter._bootstrap 内）

```gdscript
# 启动顺序
var source := CsvTableSource.new()
source.load_paths([ItemConfigLoader.ITEMS_CSV] + FragmentRegistry.get_all_csv_paths())
_item_loader = ItemConfigLoader.new()
_item_loader.load(source)
_affix_loader = AffixPlanLoader.new()
_affix_loader.load()
```

### 4.2 词条滚字时机 + 持久化契约

**核心规则（2026-05-23 修订）**：
- 装备**获取时滚字一次**（进入 InventoryComponent 那一刻）
- 滚到的词条**写入 `ItemInstance.stat_tags["affix_mods"]` 永久绑定**
- **后续装备/卸下/再装备 数值不变**（数值已固定在 instance 上）
- 关卡切换 / 退出读档 → stat_tags 持久化（详见 § 4.5）

**滚字结果以纯 Dictionary 数组形式存储**（不存 AttributeModifier 对象，便于 JSON 序列化）：

```gdscript
instance.stat_tags["affix_mods"] = [
    {"attribute": "health_base", "op": "add",      "magnitude": 20.0},
    {"attribute": "attack_bonus", "op": "multiply", "magnitude": 0.1 },
]
```

**滚字时机表**：

| 来源 | 时机 | 触发点 |
|---|---|---|
| 战利品掉落 | 拾取 → InventoryComponent.add() | LootSpawner → PickupArea → add() 内部创建 ItemInstance |
| 商店购买 | 加入背包 → add() | ShopUI 调 add() |
| 任务奖励 | 加入背包 → add() | QuestSystem → add() |
| 调试命令 add_by_id | 同上 | DebugConsole |
| **读档恢复** | **不滚字**，直接用存档里的 stat_tags 还原 | SaveGame |

```gdscript
# Script/Items/ItemInstance.gd（关键工厂方法）
class_name ItemInstance extends Resource

@export var def_id: int = 0       # 引用 Item_Data.id（持久化用 id 不存对象）
@export var stat_tags: Dictionary = {}

func get_def() -> ItemDefinition:
    var d := ConfigCenter.get_item_def(def_id)
    assert(d != null, "ItemInstance: def_id=%d not found" % def_id)
    return d

## 工厂：新获取物品时调（**会触发 Fragment.on_instance_created → 滚字 等**）
static func create_new(def: ItemDefinition) -> ItemInstance:
    var inst := ItemInstance.new()
    inst.def_id = def.item_id
    for f in def.fragments:
        f.on_instance_created(inst)
    return inst

## 工厂：从存档还原（**不触发 on_instance_created**）
static func from_save(def_id: int, saved_stat_tags: Dictionary) -> ItemInstance:
    var inst := ItemInstance.new()
    inst.def_id = def_id
    inst.stat_tags = saved_stat_tags.duplicate(true)
    return inst
```

```gdscript
# Script/Items/Fragments/Fragment_Equip.gd（在 on_instance_created 钩子里滚字）
class_name Fragment_Equip extends ItemFragment

var slot: int = 0
var num_main: int = 0
var affix_plan_main: int = 0
var num_sub: int = 0
var affix_plan_sub: int = 0

## 物品实例创建时（getNew 路径）触发滚字
func on_instance_created(instance: ItemInstance) -> void:
    var mods_main: Array = AffixRoller.roll_to_dicts(affix_plan_main, num_main)
    var mods_sub: Array  = AffixRoller.roll_to_dicts(affix_plan_sub,  num_sub)
    instance.stat_tags[&"affix_mods"] = mods_main + mods_sub
    GameLogger.info("Items", "Equip rolled: main=%d sub=%d" % [mods_main.size(), mods_sub.size()])
```

```gdscript
# Script/Items/AffixRoller.gd（输出纯 Dict 数组）
class_name AffixRoller extends RefCounted

## 从 plan_id 加权抽 count 条 → 输出 Array[Dictionary]，序列化友好
static func roll_to_dicts(plan_id: int, count: int) -> Array:
    if count <= 0:
        return []
    var plan: Dictionary = ConfigCenter.get_affix_plan(plan_id)
    assert(not plan.is_empty(), "AffixRoller: plan_id=%d not found" % plan_id)
    var pool: Array = (plan.get("sub_entries", []) as Array).duplicate()
    var picked: Array = []
    for i in count:
        if pool.is_empty():
            break
        var total: int = 0
        for e in pool:
            total += CsvLoader.as_int(e, "Weight")
        var roll_val: int = randi() % maxi(total, 1)
        var acc: int = 0
        for j in pool.size():
            acc += CsvLoader.as_int(pool[j], "Weight")
            if roll_val < acc:
                picked.append(pool[j])
                pool.remove_at(j)
                break
    var out: Array = []
    for p in picked:
        out.append({
            "attribute": CsvLoader.as_string(p, "Attr_Type"),
            "op":        CsvLoader.as_string(p, "Op", "add"),
            "magnitude": CsvLoader.as_float(p, "Val"),
        })
    return out

## 把存档里的 dict 数组还原为 AttributeModifier（装备时调）
static func dicts_to_modifiers(dicts: Array) -> Array[AttributeModifier]:
    var mods: Array[AttributeModifier] = []
    for d in dicts:
        var m := AttributeModifier.new()
        m.attribute = StringName(d["attribute"])
        m.op = _parse_op(d["op"])
        m.magnitude = float(d["magnitude"])
        mods.append(m)
    return mods
```

### 4.3 装备 / 卸下流程（钩子化）

**核心变化**（Issue 2/3 修订）：
- equip/unequip 主流程**只做 3 件事**：词条 GE rebuild + 触发 fragment.on_equipped 钩子链 + 同槽位替换
- GA / GE 的"授予/撤销"逻辑**搬到 Fragment_GA / Fragment_GE 自己内部**（高内聚）
- GA / GE 资源**启动期 preload**（CSV→Resource 转换在 Loader 期完成），运行时零 IO

```gdscript
# Script/Items/EquipmentComponent.gd

## 装备一件 instance（词条已固定，equip 不滚字）
func equip(instance: ItemInstance) -> bool:
    var def := instance.get_def()
    var fe := def.find_fragment(Fragment_Equip) as Fragment_Equip
    assert(fe != null, "equip: not equippable, item_id=%d" % def.item_id)
    assert(instance.stat_tags.has(&"affix_mods"),
        "equip: instance missing affix_mods (forgot to call ItemInstance.create_new?)")

    # 同槽位已有 → 先 unequip 放回背包
    if equipped.has(fe.slot):
        _unequip_internal(fe.slot, true)

    # 1. 词条 GE 挂载（这块逻辑只与 Fragment_Equip 相关，保留在 EquipmentComponent）
    _apply_affix_ge(def, instance)

    # 2. 触发所有 fragment 的 on_equipped 钩子（GA/GE 自处理）
    for f in def.fragments:
        f.on_equipped(owner_character, instance)

    equipped[fe.slot] = instance
    EventBus.equipment_changed.emit(owner_character, fe.slot)
    return true


func _unequip_internal(slot: int, put_back_to_inventory: bool) -> bool:
    if not equipped.has(slot):
        return false
    var instance: ItemInstance = equipped[slot]
    var def := instance.get_def()

    # 1. 撤销词条 GE（按 equip_tag 反查 active_effect）
    asc.remove_effects_with_granted_tag(_make_equip_tag(def.item_id))

    # 2. 触发所有 fragment 的 on_unequipped 钩子（GA/GE 自撤销）
    for f in def.fragments:
        f.on_unequipped(owner_character, instance)

    equipped.erase(slot)
    EventBus.equipment_changed.emit(owner_character, slot)

    # 3. 放回背包（instance 仍带原词条）
    if put_back_to_inventory:
        var inv := NodeFinder.find_first_child_of_type(owner_character, InventoryComponent) as InventoryComponent
        if inv != null:
            inv.add_instance(instance)
    return true


## 词条 GE 构造（局部封装，仅 Fragment_Equip 相关）
func _apply_affix_ge(def: ItemDefinition, instance: ItemInstance) -> void:
    var mods: Array[AttributeModifier] = AffixRoller.dicts_to_modifiers(
        instance.stat_tags[&"affix_mods"])
    var ge := GameplayEffect.new()
    ge.effect_type = GameplayEffect.EffectType.DURATION
    ge.duration = -1.0
    ge.modifiers = mods
    ge.granted_tags = [_make_equip_tag(def.item_id)]
    asc.apply_effect_to(asc, ge, owner_character)


func _make_equip_tag(item_id: int) -> StringName:
    return StringName("equip.%d" % item_id)
```

```gdscript
# Script/Items/Fragments/Fragment_GA.gd（自处理装备/卸下）
class_name Fragment_GA extends ItemFragment

## CSV 加载期 preload Ability 资源（运行时零 IO）
var abilities: Array[Ability] = []

static func from_csv_row(row: Dictionary, _source: CsvTableSource) -> ItemFragment:
    var f := Fragment_GA.new()
    var subs: Array = row.get("sub_entries", [])
    for s in subs:
        var path: String = CsvLoader.as_string(s, "GA_Path")
        if path.is_empty(): continue
        var ab := load(path) as Ability
        assert(ab != null, "Fragment_GA: failed to load %s" % path)
        f.abilities.append(ab)
    return f

func on_equipped(owner: BaseCharacter, _instance: ItemInstance) -> void:
    var asc: AbilitySystemComponent = owner.asc
    for ab in abilities:
        asc.grant_ability(ab)

func on_unequipped(owner: BaseCharacter, _instance: ItemInstance) -> void:
    var asc: AbilitySystemComponent = owner.asc
    for ab in abilities:
        asc.revoke_ability(ab.ability_id)
```

```gdscript
# Script/Items/Fragments/Fragment_GE.gd（同样模式）
class_name Fragment_GE extends ItemFragment

## CSV 加载期 preload GE 资源
var ge_resources: Array[GameplayEffect] = []

static func from_csv_row(row: Dictionary, _source: CsvTableSource) -> ItemFragment:
    var f := Fragment_GE.new()
    var subs: Array = row.get("sub_entries", [])
    for s in subs:
        var path: String = CsvLoader.as_string(s, "GE_Path")
        if path.is_empty(): continue
        var ge := load(path) as GameplayEffect
        assert(ge != null, "Fragment_GE: failed to load %s" % path)
        f.ge_resources.append(ge)
    return f

func on_equipped(owner: BaseCharacter, _instance: ItemInstance) -> void:
    var asc: AbilitySystemComponent = owner.asc
    for ge in ge_resources:
        asc.apply_effect_to(asc, ge, owner)
        # equip_tag 已由 EquipmentComponent._apply_affix_ge 那个 GE 携带；
        # Fragment_GE 的常驻 GE 通过自身 granted_tags 反查（约定每个常驻 GE 必须有自己的 granted_tags）

func on_unequipped(owner: BaseCharacter, _instance: ItemInstance) -> void:
    var asc: AbilitySystemComponent = owner.asc
    for ge in ge_resources:
        # 通过 GE 自身的 granted_tags 第一项反查并撤销
        if ge.granted_tags.size() > 0:
            asc.remove_effects_with_granted_tag(ge.granted_tags[0])
```

### 4.4 use() 路由（钩子化）

**核心变化**（Issue 2 修订）：use 路由完全交给 fragment 自处理，InventoryComponent 不再 if-else 分类型。

```gdscript
# Script/Items/InventoryComponent.gd

## 使用槽位中的物品。所有具体行为由 fragment.on_use 钩子决定。
func use(slot_index: int) -> bool:
    var s = slots[slot_index]
    if s == null: return false
    var def: ItemDefinition = s.def

    # 让所有 Fragment 决定使用行为
    # 任一 Fragment 返回 false → 阻断后续 consume
    var allow_consume := true
    for f in def.fragments:
        var ok: bool = f.on_use(owner_character, s.instance)
        if not ok:
            allow_consume = false

    # 通用消耗逻辑（Consumable=1 → 扣 1 个堆叠）
    if allow_consume and def.consumable:
        remove(slot_index, 1)
    return true
```

各 Fragment 的 on_use 实现：

```gdscript
# Fragment_Currency.gd  → 货币不响应 use
func on_use(_owner, _instance) -> bool:
    return false  # 阻断 consume

# Fragment_Quest.gd     → 任务道具发信号
var quest_id: int = 0

func on_use(owner: BaseCharacter, instance: ItemInstance) -> bool:
    EventBus.quest_item_used.emit(instance.def_id if instance else 0, quest_id, owner)
    return true

# Fragment_Equip.gd     → 装备（不消耗本体，由通用流程决定）
func on_use(owner: BaseCharacter, instance: ItemInstance) -> bool:
    var ec := NodeFinder.find_first_child_of_type(owner, EquipmentComponent) as EquipmentComponent
    if ec != null and instance != null:
        ec.equip(instance)
    return true
```

### 4.5 InventoryComponent.add() 双入口（含滚字时机 + 拦截钩子）

```gdscript
# Script/Items/InventoryComponent.gd

## 入口 1：按 def_id 加新物品（**会触发滚字**）。掉落 / 商店购买 / 任务奖励 / 调试命令走这里。
func add_by_id(def_id: int, count: int = 1) -> int:
    var def := ConfigCenter.get_item_def(def_id)
    assert(def != null, "InventoryComponent.add_by_id: def_id=%d not found" % def_id)
    return _add_internal(def, count)

## 入口 2：放回已存在的 instance（**不会重新滚字**）。卸下装备 / 读档恢复走这里。
func add_instance(instance: ItemInstance) -> int:
    assert(instance != null, "InventoryComponent.add_instance: null instance")
    return _add_existing_instance(instance)


func _add_internal(def: ItemDefinition, count: int) -> int:
    if def == null or count <= 0:
        return 0

    # 询问 Fragment：是否拦截入库？（Currency 路由到 CurrencyManager 等）
    for f in def.fragments:
        if f.intercepts_inventory_add(def, count):
            return f.handle_inventory_add(owner_character, def, count)

    # 装备类（每件独立 instance）→ count 强制 1，每件占独立槽，**进入背包时滚字**
    if def.has_fragment(Fragment_Equip):
        var added := 0
        for i in count:
            var slot_idx := _find_empty_slot()
            if slot_idx == -1:
                break
            var inst := ItemInstance.create_new(def)  # ★ 滚字在这里发生（Fragment_Equip.on_instance_created）
            slots[slot_idx] = {"def": def, "instance": inst, "count": 1}
            added += 1
        if added > 0:
            EventBus.inventory_changed.emit(owner_character)
            EventBus.item_added.emit(owner_character, def, added)
        return added

    # 简单堆叠类（药水/任务道具/材料）→ instance=null 节省内存
    return _add_stackable(def, count)


func _add_existing_instance(instance: ItemInstance) -> int:
    var def := instance.get_def()
    var slot_idx := _find_empty_slot()
    if slot_idx == -1:
        return 0
    slots[slot_idx] = {"def": def, "instance": instance, "count": 1}
    EventBus.inventory_changed.emit(owner_character)
    return 1


## 简单堆叠类的合并逻辑（用 def.get_max_stack() 而非直读字段）
func _add_stackable(def: ItemDefinition, count: int) -> int:
    var max_stack: int = def.get_max_stack()
    var remaining := count
    # 先填已有同 def 槽
    for i in range(max_slots):
        if remaining <= 0: break
        var s = slots[i]
        if s != null and s.def == def and s.count < max_stack:
            var fill: int = mini(max_stack - s.count, remaining)
            s.count += fill
            remaining -= fill
    # 再放空槽
    for i in range(max_slots):
        if remaining <= 0: break
        if slots[i] == null:
            var fill: int = mini(max_stack, remaining)
            slots[i] = {"def": def, "instance": null, "count": fill}
            remaining -= fill
    var added := count - remaining
    if added > 0:
        EventBus.inventory_changed.emit(owner_character)
        EventBus.item_added.emit(owner_character, def, added)
    return added
```

```gdscript
# Fragment_Currency.gd（拦截入库）
class_name Fragment_Currency extends ItemFragment

@export var icon_on_tip: String = ""

static func from_csv_row(row: Dictionary, _source: CsvTableSource) -> ItemFragment:
    var f := Fragment_Currency.new()
    f.icon_on_tip = CsvLoader.as_string(row, "Icon_On_Tip")
    return f

func intercepts_inventory_add(_def, _count) -> bool:
    return true

func handle_inventory_add(_owner: BaseCharacter, def: ItemDefinition, count: int) -> int:
    GameLogger.info("Items", "Currency %d (%s) += %d (CurrencyManager not impl yet)" % [
        def.item_id, def.display_name, count])
    # TODO Phase 2: GameInstance.currency_manager.add(def.item_id, count)
    return count
```

**关键不变性**：

| 路径 | 是否滚字 | 后续装备/卸下 数值会变吗 |
|---|---|---|
| `add_by_id(def_id)` | ✅ 滚 | ❌ 永不变 |
| `add_instance(inst)`（卸下回背包） | ❌ 不滚 | ❌ 永不变 |
| `from_save(...)`（读档） | ❌ 不滚 | ❌ 永不变 |

→ **同一件 instance 的词条数值在它的整个生命周期内不变**。

### 4.6 持久化契约

**SaveGame 序列化字段**（Phase 6 落地，但当前 Phase 1 设计已对齐）：

```gdscript
# 单个 Slot 的存档表示
{
  "def_id":    int,
  "count":     int,
  "instance":  null | {                    # 装备/有 stat_tags 的物品
    "def_id":    int,
    "stat_tags": Dictionary                # 关键：词条 + 耐久 + 后续 Fragment 状态
  }
}

# stat_tags 内容契约
{
  "affix_mods": [                          # Fragment_Equip 滚字结果
    {"attribute": "health_base", "op": "add",      "magnitude": 20.0},
    {"attribute": "attack_bonus", "op": "multiply", "magnitude": 0.1 }
  ],
  "durability": 87,                        # Phase 5+ Fragment_Durability
  # 未来 Fragment 自由扩展 key
}
```

**持久化要点**：
1. 只存 `def_id`（int），不存 def 对象引用 —— 还原时由 ConfigCenter 反查
2. `stat_tags` 内只有**纯标量 / 字符串 / Dict / Array**，无 Resource / Node 引用 → 任何序列化方案（JSON / `var_to_str` / SaveGame Resource）都可直接吃
3. **EquipmentComponent.equipped 同样持久化**：序列化为 `{slot_int: instance_save_dict}`
4. 还原入口统一为 `ItemInstance.from_save(def_id, stat_tags)` —— 不会触发 `on_instance_created` 钩子（避免重新滚字）

**Phase 6 SaveGame 改造点（提前布局）**：

```gdscript
# Script/Persistence/SaveGameSystem.gd（Phase 6）
func _serialize_inventory(inv: InventoryComponent) -> Array:
    var out: Array = []
    for s in inv.slots:
        if s == null:
            out.append(null)
            continue
        var slot_save := {
            "def_id": s.def.item_id,
            "count":  s.count,
            "instance": null,
        }
        if s.instance != null:
            slot_save["instance"] = {
                "def_id":    s.instance.def_id,
                "stat_tags": s.instance.stat_tags.duplicate(true),
            }
        out.append(slot_save)
    return out

func _deserialize_inventory(inv: InventoryComponent, saved: Array) -> void:
    inv.slots.resize(inv.max_slots)
    for i in saved.size():
        var s = saved[i]
        if s == null:
            inv.slots[i] = null
            continue
        var inst: ItemInstance = null
        if s.get("instance") != null:
            inst = ItemInstance.from_save(s["instance"]["def_id"], s["instance"]["stat_tags"])
        var def := ConfigCenter.get_item_def(s["def_id"])
        inv.slots[i] = {"def": def, "instance": inst, "count": s["count"]}
    EventBus.inventory_changed.emit(inv.owner_character)
```

---

## 五、规则合规性

| 规则 | 体现 |
|---|---|
| **R-DATA-01/02** | 数值全部在 CSV |
| **R-DATA-03**（CSV 路线） | 主表 + 6 张子表全部 CSV；.tres 仅承载 GE/GA Resource 引用 |
| **R-CODE-01** | 缺表 / 缺行 / Fragment 列填非法值 → assert 崩 |
| **R-CODE-02** | Fragment 路由用 `is_instance_of` + 显式 Fragment 类型清单，非反射 |
| **R-ARCH-02** | 不新增 Autoload；ItemConfigLoader 由 ConfigCenter 持有 |
| **R-ARCH-04** | 道具触发跨模块走 EventBus；装备改属性走 ASC.apply_effect_spec |
| **R-CHAR-01** | UI/组件查找走 NodeFinder |
| **R-EVENT-01** | quest_item_used 信号在 EventBus.gd 集中声明 |

---

## 六、美术资源约定

### 6.1 路径规范

```
Content/
├── Icons/
│   ├── Items/                    ← 道具图标（背包/Tooltip/拾取）
│   ├── Buffs/                    ← Buff/Debuff 图标
│   ├── Skills/                   ← 技能图标
│   └── HUD/                      ← HUD 通用图标
├── Sprites/                      ← 角色 SpriteFrames 用图（已有）
├── Audio/                        ← 音效 BGM（已有）
├── Shaders/                      ← Shader（已有）
└── Fonts/                        ← 字体
    └── Uranus_Pixel_11Px.ttf     ← 已迁移
```

### 6.2 命名规范

`Content/Icons/Items/` 命名：`<FragmentKind>_<英文标识>.png`

例：
- `Currency_Exp.png` / `Currency_Coin.png`
- `Quest_TestKey.png`
- `Equip_TestSword.png`
- `Placeholder.png`（缺图兜底）

### 6.3 规格

| 用途 | 尺寸 | 备注 |
|---|---|---|
| 背包/Tooltip 图标 | 64×64 | 透明 PNG，关闭 mipmap，nearest filter |
| HUD 货币栏 | 24×24 / 32×32 | 小尺寸 |
| 拾取飘字 | 32×32 | 配合 +1 文字 |

### 6.4 当前占位图

✅ Phase 1 占位资源已就位（2026-05-23 生成）：

| 文件 | 颜色 | 标签 |
|---|---|---|
| `Content/Icons/Items/Currency_Exp.png` | 蓝 #4A9EFF | "经验" |
| `Content/Icons/Items/Currency_Coin.png` | 黄 #FFC832 | "金币" |
| `Content/Icons/Items/Quest_TestKey.png` | 紫 #C864F0 | "任务" |
| `Content/Icons/Items/Equip_TestSword.png` | 红 #B43C3C | "装备" |
| `Content/Icons/Items/Placeholder.png` | 灰 #787878 | "?" |

**后续替换**：美术到位后按相同文件名直接覆盖，运行时无需改动。

---

## 七、Phase 1 落地任务清单

| # | 文件 | 动作 | 工期 |
|---|---|---|---|
| 1 | `Script/Items/ItemFragment.gd` | 新建基类 + 5 个虚钩子（on_instance_created / on_use / on_equipped / on_unequipped / intercepts_inventory_add + handle_inventory_add + 抽象 from_csv_row） | 0.15d |
| 2 | `Script/Items/ItemDefinition.gd` | 重构：删 max_stack / rarity 字段（改 get_max_stack / get_rarity 读 Fragment）+ 加 fragments / find_fragment | 0.15d |
| 3 | `Script/Items/ItemInstance.gd` | 新建（def_id + stat_tags + create_new / from_save 双工厂；不缓存 def） | 0.1d |
| 4 | `Script/Items/FragmentRegistry.gd` | **新增**：集中注册表（kind ↔ class ↔ csv_path） | 0.1d |
| 5 | `Script/Items/Fragments/Fragment_Currency.gd` | intercepts_inventory_add → CurrencyManager 占位 | 0.1d |
| 6 | `Script/Items/Fragments/Fragment_Equip.gd` | on_instance_created 滚字钩子；slot + plan_ids 字段 | 0.15d |
| 7 | `Script/Items/Fragments/Fragment_GA.gd` | preload abilities + on_equipped/unequipped 自处理 | 0.1d |
| 8 | `Script/Items/Fragments/Fragment_GE.gd` | preload ge_resources + on_equipped/unequipped 自处理 | 0.1d |
| 9 | `Script/Items/Fragments/Fragment_Quest.gd` | on_use → emit quest_item_used 信号 | 0.05d |
| 10 | `Script/Items/Fragments/Fragment_Quality.gd` | rarity 字段 | 0.05d |
| 11 | `Script/Items/Fragments/Fragment_Stackable.gd` | initial_count 字段 | 0.05d |
| 12 | `Script/Items/AffixRoller.gd` | 加权抽样不放回；roll_to_dicts / dicts_to_modifiers 双 API | 0.25d |
| 13 | `Script/Data/Loaders/CsvTableSource.gd` | **新增**：IO 层（load_paths + get_table） | 0.1d |
| 14 | `Script/Data/Loaders/ItemFragmentFactory.gd` | **新增**：路由层（kind → cls.from_csv_row） | 0.1d |
| 15 | `Script/Data/Loaders/ItemConfigLoader.gd` | 装配层（_assemble_def，调 Factory + 隐式 Fragment 构造） | 0.3d |
| 16 | `Script/Data/Loaders/AffixPlanLoader.gd` | CSV → plan dict | 0.1d |
| 17 | `Script/Core/ConfigCenter.gd` | 加 `get_item_def(id)` / `get_affix_plan(id)` API + _bootstrap 调 4 个 Loader | 0.2d |
| 18 | `Script/Core/EventBus.gd` | 加 `quest_item_used(def_id, quest_id, user)` / `item_added(owner, def, count)` 信号 | 0.05d |
| 19 | `Script/Items/InventoryComponent.gd` | `add_by_id` + `add_instance` 双入口；use 钩子化路由；intercepts 拦截 | 0.3d |
| 20 | `Script/Items/EquipmentComponent.gd` | equip 主流程 = _apply_affix_ge + 触发 fragment.on_equipped 钩子链；不再处理 GA/GE 细节 | 0.2d |
| 21 | `Script/Items/ConsumableDefinition.gd` | **删除**（继承式不再需要） | 0.05d |
| 22 | `Script/Items/EquipmentDefinition.gd` | **删除** | 0.05d |
| 23 | `Data/Items/Item_HealthPotion.tres` / `Item_IronSword.tres` | **删除**（彻底走 CSV） | 0.05d |
| 24 | `Tools/excel2Config` | 跑导出 → 7 张 CSV 落到 `Data/FromExcel/` | 0.1d |
| 25 | `Script/UI/InventoryUI.gd` | 适配新 slot 结构（{def, instance, count}）+ Stack=0 货币不显示 + 图标加载 | 0.3d |
| 26 | MCP 验证 + 开发日志 | restart → 验证 7 项验收 + 写 Plans/Dolphin设计/道具系统开发日志.md | 0.4d |

**总计**：约 **3.8d**（含验证 + 文档同步）。

### 7.1 关键依赖

- ✅ 美术占位（Step 1-3 已完成）
- ✅ Excel 路径修正（已完成）
- ✅ 设计文档（本文）
- ⏳ excel2Config 跑一次导出（Phase 1 Step 21）

### 7.2 测试场景

Phase 1 验收标准：

1. **启动游戏**：ConfigCenter 加载 Item_Data + 6 张子表 + attr_plan，无 assert 失败
2. **背包测试**：用调试命令
   - `inv.add_by_id(1, 5)` → 经验值 不应进背包网格（Stack=0，仅日志输出 currency 待 Phase 2 实装）
   - `inv.add_by_id(2, 100)` → 金币 同上
   - `inv.add_by_id(4, 1)` → 任务道具 进背包槽，count=1
   - `inv.add_by_id(5, 1)` → 测试装备 进背包槽，**控制台打印词条滚字结果**（例：`[health_base, add, 20] + [attack_base, add, 15]`）
3. **词条固定不变性测试**：
   - 第一次 `inv.add_by_id(5, 1)` 滚到词条 A → 截图记录
   - 第二次 `inv.add_by_id(5, 1)` 滚到词条 B（独立 instance，可能不同）→ 同时背包有两件装备，词条互不干扰
   - 装备槽 0 的装备 → 玩家属性变化匹配该 instance 的 stat_tags
   - 卸下 → 再次装备 → **属性变化值与第一次完全一致**（验证不重新滚字）
4. **任务道具**：use 任务道具 → 控制台打印 `EventBus.quest_item_used(4, 1100, Player)` + 堆叠 -1
5. **装备测试**：use 测试装备 → 临时 GA 学到（`asc.has_ability(...)` 为真）→ GE_PerfectBlockBuff 挂载（`asc.tags` 含 buff tag）→ 玩家属性按 instance.stat_tags 加成
6. **卸下**：再次 use 测试装备的装备槽 → 属性回滚 + GA 撤销 + GE 移除 + 装备实例放回背包（**stat_tags 仍带词条**）
7. **图标显示**：背包 UI 显示 64×64 占位图标 + Stack=0 货币不出现在网格

---

## 八、决策记录

| 日期 | 决策 | 决策人 |
|---|---|---|
| 2026-05-23 | 采纳 Lyra Fragment 架构（GDScript 翻译版） | 用户 |
| 2026-05-23 | 数据载体走 CSV 主导 + .tres 仅 Resource 引用 | 用户（同步更新 R-DATA-03） |
| 2026-05-23 | Buff 不独立成系统，统一走 GE（详见 GE与Buff合并方案_待办.md） | 用户 |
| 2026-05-23 | Fragment 词表 = 子表名去 Frag_ 前缀；Phase 1 锁定 5 显式 + 2 隐式 | 用户 |
| 2026-05-23 | Stack=0 = 货币不进背包网格；Consumable=1 = use 后扣 1 个 | 用户 |
| 2026-05-23 | 词条 Val 固定不滚范围；加权抽样不放回；Op 显式声明 | 用户 |
| 2026-05-23 | Frag_GA 临时学习；Frag_GE 装备常驻挂载 | 用户 |
| 2026-05-23 | 美术资源放 Content/Icons/Items/，命名 `<Kind>_<Name>.png`，64×64 | 用户（方案 B 占位） |
| 2026-05-23 | **词条滚字时机修订**：装备**获取时滚字**（add_by_id），写入 `ItemInstance.stat_tags["affix_mods"]` 永久绑定；equip/unequip 仅读取已固定词条，不再滚字。词条数据走纯 Dict 数组持久化（与 ARPG 标准行为一致：暗黑/POE/无主之地） | 用户 |
| 2026-05-23 | **SOLID 审核全盘修订**（接受 Issue 1+2+3+5+6+7+8）：① Loader 拆 3 层（CsvTableSource / ItemFragmentFactory / ItemConfigLoader）；② Fragment 加 5 个虚钩子（on_use / on_equipped / on_unequipped / intercepts_inventory_add / handle_inventory_add），InventoryComponent / EquipmentComponent 永不修改；③ GA/GE 资源启动期 preload；④ FragmentRegistry 集中表（kind ↔ class ↔ csv_path）；⑤ 删 ItemDefinition.rarity / max_stack 字段，改 get_rarity / get_max_stack 读 Fragment（单一真相源）；⑥ 删 ItemInstance._def_cache 微优化；详见 § 十二 | 用户 |

---

## 九、后续 Phase 路线图（参考）

| Phase | 内容 | 工期 | 触发条件 |
|---|---|---|---|
| **Phase 1** | Fragment 架构 + Excel CSV 工作流 + 4 件示例物品跑通 | 3.8d | **当前阶段** |
| **Phase 2** | 货币系统（CurrencyManager + HUD 货币栏） | 1.5d | Phase 1 完成 |
| **Phase 3** | 战利品掉落（LootTables.csv + LootSpawner） | 1.5d | Phase 2 完成 |
| **Phase 4** | 品质边框 UI + Tooltip + 拾取飘字 | 2d | 与 HUD Phase 3 合并 |
| **Phase 5** | Hotbar 快捷栏 + 拖拽 + 装备比较卡 | 2d | Phase 4 完成 |
| **Phase 6** | 持久化（与 DIR-10 SaveGame 同期）—— Phase 1 已对齐 stat_tags 纯 Dict 契约，本期主要补 SaveGame 序列化/反序列化代码 | 0.5d | DIR-10 启动时 |

---

## 十、相关文档

- `Plans/全局规则.md` § R-DATA-03（CSV 路线）
- `Plans/Dolphin设计/GE与Buff合并方案_待办.md`（Buff 不独立的论证 + GE 后续待办）
- `Plans/三期开发计划.md` § M10 Excel 工作流
- `Plans/_Inventory/08_开发方向.md` § DIR-3（M10 数据流）
- `addons/skill_editor/`（GA/GE 资源在 Skill Editor 维护）

---

## 十一、待澄清 / 风险（开工前最后确认）

无重大未决项。Phase 1 可以启动。

---

## 十二、SOLID + DRY 审核纪要（2026-05-23 接受全部建议）

### 12.1 审核结论

| 原则 | 评分 | 体现 |
|---|---|---|
| **SRP** 单一职责 | 🟢 | Loader 3 层拆分（IO / 工厂 / 装配），各司其职 |
| **OCP** 开闭原则 | 🟢 | Fragment 钩子化后，加新类型只动 FragmentRegistry + 新 .gd；InventoryComponent / EquipmentComponent 永不修改 |
| **LSP** 里氏替换 | 🟢 | Fragment 子类仅 override 关心的虚钩子，行为契约稳定 |
| **ISP** 接口隔离 | 🟢 | ItemFragment 基类极薄，5 个虚钩子按需 override |
| **DIP** 依赖倒置 | 🟡 | Autoload 直访（ConfigCenter / EventBus）属于 R-ARCH-03 项目级决策，不视为违反 |
| **DRY** | 🟢 | GA/GE 装备/卸下逻辑搬到 Fragment 自身，equip/unequip 主流程仅 3 件事 |

### 12.2 落地的 7 项修订

| Issue | 内容 | 落地节 |
|---|---|---|
| **1 (SRP)** | ItemConfigLoader 拆为 CsvTableSource + ItemFragmentFactory + ItemConfigLoader 三层 | § 4.1.1-4.1.5 |
| **2 (OCP)** | ItemFragment 加 on_use / on_equipped / on_unequipped 钩子；InventoryComponent.use 改钩子驱动；EquipmentComponent.equip 触发 fragment.on_equipped 链 | § 2.2 / § 4.3 / § 4.4 |
| **3 (DRY)** | GA/GE 路径在 Loader 期 preload，运行时由 Fragment_GA / Fragment_GE 自处理装备/卸下 | § 4.3 Fragment_GA / Fragment_GE 代码块 |
| **5 (DRY/OCP)** | Currency 不进背包从 if-else 改为 `intercepts_inventory_add` / `handle_inventory_add` 钩子 | § 4.5 |
| **6 (DRY)** | 新增 FragmentRegistry 集中表，避免 kind/class/csv_path 三处命名同步 | § 4.1.1 |
| **7 (KISS)** | ItemDefinition 删 rarity/max_stack 冗余字段，改 get_max_stack/get_rarity 读 Fragment（单一真相源） | § 2.3 |
| **8 (YAGNI)** | ItemInstance 删 _def_cache 微优化（ConfigCenter 本身 O(1) Dict 查询） | § 4.2 ItemInstance 代码块 |

### 12.3 关键架构性质

新架构满足以下"加新功能不动旧代码"的扩展场景：

| 扩展场景 | 改动文件 | InventoryComponent / EquipmentComponent |
|---|---|---|
| 加新 Fragment 类型（如 `Fragment_Hotbar`） | 新建 1 个 .gd + FragmentRegistry 加 1 行 + Excel 加 1 张子表 | **零改动** |
| 加新"使用行为"（如吃食物给好感度） | 在对应 Fragment 的 on_use override | **零改动** |
| 加新"装备效果"（如装备触发被动） | 在对应 Fragment 的 on_equipped override | **零改动** |
| 加新"入库拦截"（如自动卖出灰色装备） | 新 Fragment 的 intercepts_inventory_add | **零改动** |
| 加新数据源（如远程下发 JSON） | 新 CsvTableSource 子类 | Loader **零改动** |

### 12.4 不接受的建议

| Issue | 原因 |
|---|---|
| **4 (DIP)** Autoload 直访改注入 | 与 R-ARCH-03 项目级决策冲突；保持 ConfigCenter / EventBus 直访 |

---

**End of Document**
