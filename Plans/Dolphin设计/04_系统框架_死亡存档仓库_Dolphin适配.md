# 系统框架 · 死亡 / 存档 / 武器仓库（Dolphin 适配版 · 上）

> **来源**：前项目 `03_死亡惩罚与存档点设计.md` v1.2 签字版（§1~§9）。
> **本文定位**：Dolphin 落地的「状态回档式死亡 + 多角色 + 多存档槽 + 武器仓库 + 自动存档」**架构与数据结构**部分，对应里程碑 **D5**。
> **下文（part 2）**：D5 任务分解、铁律清单、UI 规格、验收清单 → 见 `04B`。
> **状态**：架构 / 数据结构 / 触发流程 / 字段全部锁定；存档点数量、关卡间隔等数值挂起。

---

## 0. UE → Godot 等价物映射表

| 前项目（UE） | Dolphin（Godot 4.6） |
|---|---|
| `USaveGame` 子类 | `Script/Save/RunSnapshot.gd` / `MetaSaveData.gd` / `GlobalSettings.gd`（Resource）|
| `UGameplayStatics::SaveGameToSlot` | 自定义 JSON 写入 + `FileAccess` |
| `FFastArraySerializer` 仓库列表 | Dictionary + Array（Demo 单机不需要 FastArray）|
| `UGameInstance` | Dolphin `GameInstance.gd` Autoload |
| `IPickupable / UPickupableStatics` | `EventBus.pickup_requested` + `InventoryComponent.try_pickup(item)` |
| `Lyra Checkpoint Volume` | `Scenes/Levels/Checkpoint.tscn`（Area3D + 视觉 + G 交互） |
| `OS.get_unique_id()` 不跨设备 → 自实现 UUIDv4 | `Script/Save/UUID.gd`（v4 实现） |
| `ULyraLoadingScreenSubsystem` | Dolphin 现有 LoadingScreen 占位 |

**关键差异**：单机 Demo → 不要 Replicate / FastArray；序列化推荐 **JSON + .bak 备份**（不用 Godot 二进制 Resource）便于人肉调试 + 版本兼容。路径用 `user://`（Windows 实际 `%APPDATA%/Godot/app_userdata/<proj>/`）。

---

## 1. 总体架构（v1.2 锁定）

```
user://saves/
├─ global_settings.json          ← 账号级跨角色共享（KeyBindings/Audio）
├─ global_settings.json.bak
└─ characters/
    ├─ <CharacterID_A>/
    │   ├─ character.json        ← MetaSaveData（永久；含仓库）
    │   ├─ character.json.bak
    │   ├─ run_snapshot.json     ← RunSnapshot（最近存档点，死亡读这个）
    │   ├─ run_snapshot.json.bak
    │   ├─ auto_save.json        ← AutoSaveSlot（异常保护，启动读这个）
    │   └─ auto_save.json.bak
    └─ <CharacterID_B>/
```

3 类存档严格分离：

| 存档 | 触发 | 死亡时读取 | 启动时读取 |
|---|---|---|---|
| **MetaSaveData** | 武器入库 / 击败 Boss / 解锁副本 / 成就 | ❌ | ✅ 始终加载 |
| **RunSnapshot** | 玩家在存档点按 G | ✅ 死亡回档主路径 | ❌ |
| **AutoSaveSlot** | 5 触发点（退出 / 关卡切 / Boss 房前 / 角色切前 / 互传到达后）| ❌ | ✅（与 RunSnapshot 取较新） |

---

## 2. 数据结构（结构锁定）

### 2.1 GlobalSettings（账号级，1 份）

```gdscript
# Script/Save/GlobalSettings.gd
extends Resource
class_name GlobalSettings

@export var key_bindings: Dictionary = {}        # action -> Array[event_dict]
@export var audio_settings: Dictionary = {}      # {master, music, sfx}
@export var video_settings: Dictionary = {}      # {resolution, vsync, quality}
@export var last_played_character_id: String = ""
@export var schema_version: int = 1
```

### 2.2 MetaSaveData（每角色 1 份）

```gdscript
# Script/Save/MetaSaveData.gd
extends Resource
class_name MetaSaveData

@export var character_id: String                 # UUIDv4
@export var display_name: String
@export var character_class_id: StringName       # ⏸️ Demo 单职业可占位
@export var created_at_unix: int
@export var last_played_at_unix: int

# ── 永久持有 ──
@export var weapon_storage: Array = []           # Array[Dict] = WeaponInstance.to_dict() 列表
@export var weapon_storage_capacity: int = -1    # -1 = 无上限（Demo）

# ── 永久解锁 ──
@export var unlocked_weapon_defs: Dictionary = {}     # def_id -> {first_unlock_unix, source}
@export var unlocked_dungeons: Array[StringName] = []
@export var save_points_unlocked: Array = []          # Array[Dict]：{id, dungeon_id, first_unlock_unix}
@export var unlocked_boons: Array[StringName] = []    # 已见过的 Boon（图鉴用）
@export var unlocked_cosmetics: Array[StringName] = []
@export var owned_meta_upgrades: Dictionary = {}      # 类 Hades 镜子升级

# ── 剧情 / 成就 / 图鉴 ──
@export var story_flags: Dictionary = {}              # 主线节点
@export var achievement_progress: Dictionary = {}
@export var enemy_codex: Dictionary = {}              # 已击杀过的怪 ID -> {first_kill_unix, count}
@export var item_codex: Dictionary = {}

# ── 永久货币（角色独立钱包）──
@export var permanent_currency: Dictionary = {        # 多币种
    "imprint": 0,                                     # 乐园印记（永久）
}

# ── 统计 ──
@export var total_death_count: int = 0
@export var total_run_count: int = 0
@export var total_kill_count: int = 0
@export var boss_kill_counts: Dictionary = {}

# ── 指针 ──
@export var last_active_checkpoint_id: StringName = &""
@export var last_save_unix: int = 0

@export var schema_version: int = 1
```

### 2.3 RunSnapshot（每角色 1 份，存档点写）

完全对应前项目 §6.1，分 6 组共 30+ 字段：

```gdscript
# Script/Save/RunSnapshot.gd
extends Resource
class_name RunSnapshot

# (1) 角色状态
@export var current_health: float
@export var max_health: float
@export var current_mana: float
@export var max_mana: float
@export var current_block_durability: float
@export var current_switch_energy: float
@export var level: int
@export var experience: float
@export var primary_attributes: Dictionary       # str/dex/int/vit
@export var secondary_attributes: Dictionary     # 衍生缓存（含本局词条加成）
@export var active_buffs: Array                  # GE 列表（含剩余持续）

# (2) 装备与背包
@export var equipped_main: Dictionary = {}       # WeaponInstance.to_dict()，含 current_ult_energy
@export var equipped_off:  Dictionary = {}
@export var inventory: Array = []
@export var currency_run: Dictionary = {         # 三层货币的 Run 部分
    "gold": 0, "key": 0, "soul": 0
}

# (3) 局内 Build
@export var acquired_boons: Array = []           # BoonInstance.to_dict() 列表
@export var weapon_upgrades: Array = []
@export var temporary_affixes: Array = []

# (4) 关卡状态
@export var current_stage_id: StringName
@export var current_room_id: StringName
@export var room_random_seeds: Dictionary = {}   # room_id -> seed（防宝箱 cheese）
@export var killed_unique_enemy_ids: Array = []  # 已死的精英 / Boss
@export var opened_chests: Array = []
@export var activated_altars: Array = []

# (5) 本局统计
@export var current_run_kill_count: int = 0
@export var current_run_hit_taken: int = 0
@export var current_run_collected_items: int = 0
@export var current_run_death_count: int = 0
@export var current_run_stage_progress: int = 0
@export var current_run_start_unix: int = 0
@export var current_run_elapsed_sec: float = 0.0

# (6) NPC / 对话
@export var dialog_choices: Dictionary = {}
@export var npc_disposition_local: Dictionary = {}
@export var quest_progress_local: Dictionary = {}

@export var schema_version: int = 1
@export var saved_at_unix: int = 0
@export var saved_at_checkpoint_id: StringName = &""
```

### 2.4 AutoSaveSlot

字段结构与 `RunSnapshot` **完全一致**（这样读写代码可复用），物理文件独立。多写一个字段：

```gdscript
@export var trigger_source: StringName = &""    # "Quit"/"LevelChange"/"BeforeBoss"/"BeforeCharSwap"/"AfterTeleport"
```

---

## 3. SaveSystem 主类（GameInstance 子节点）

```gdscript
# Script/Save/SaveSystem.gd
extends Node
class_name SaveSystem

const SAVE_ROOT := "user://saves/"
const GLOBAL_PATH := SAVE_ROOT + "global_settings.json"

var current_character_id: String = ""
var current_meta: MetaSaveData = null
var current_run: RunSnapshot = null
var _autosave_min_interval_sec := 10.0    # 防抖
var _last_autosave_unix := 0

# === 全局设置 ===
func load_global_settings() -> GlobalSettings: ...
func save_global_settings(g: GlobalSettings) -> void: ...

# === 角色管理 ===
func list_characters() -> Array[Dictionary]: ...    # 主菜单角色选择列表
func create_new_character(display_name: String, class_id: StringName) -> String:
    # 返回新生成的 character_id（UUIDv4）
    # 1. 在 user://saves/characters/<uuid>/ 创建目录
    # 2. 初始化 MetaSaveData：起始仓库空、起始货币按 R5 只写本档
    # 3. 不写 RunSnapshot / AutoSaveSlot
    pass
func load_character(character_id: String) -> bool: ...
func delete_character(character_id: String, confirm_name: String) -> bool: 
    # 二次确认：玩家输入角色名匹配才删
    # 整档销毁（R9）：删 .json + .bak + run_snapshot + auto_save
    pass

# === 主动存档（存档点 G）===
func capture_snapshot_at_save_point(checkpoint_id: StringName) -> void:
    # 1. 从 PlayerCharacter / EquipmentComponent / EnergyComponent / LevelManager / RoomGenerator 取数据
    # 2. 序列化到 RunSnapshot
    # 3. 原子写入：先写 .tmp → fsync → 改名为 .json，旧 .json 改名为 .bak
    # 4. 更新 MetaSaveData.last_active_checkpoint_id + 加入 save_points_unlocked
    # 5. 写 MetaSaveData（独立事务，R7）
    # 6. emit EventBus.run_snapshot_saved
    pass

# === 死亡回档 ===
func load_last_active_snapshot() -> bool:
    # 读 RunSnapshot，恢复角色状态、装备、本局货币、Boon、关卡
    # 注意：不读 AutoSaveSlot（R6）
    pass

# === 自动存档 ===
func trigger_auto_save(source: StringName) -> void:
    var now = Time.get_unix_time_from_system()
    if now - _last_autosave_unix < _autosave_min_interval_sec:
        return  # 防抖
    # 异步：放进 WorkerThreadPool
    # 写入 auto_save.json + .bak
    # UI 角落淡出 1s "已自动保存"
    _last_autosave_unix = now

func load_auto_save_if_exists() -> bool: ...

# === 启动决策 ===
func decide_load_path_on_startup() -> StringName:
    # 比较 RunSnapshot.saved_at_unix vs AutoSaveSlot.saved_at_unix
    # 较新的且来源 = "Quit"  → 直接加载（用户预期"上次离开位"）
    # 较新的来源是其它 AutoSave → 弹窗"检测到异常退出快照，是否恢复？"
    # 较旧 → 加载 RunSnapshot
    return &"RunSnapshot" or &"AutoSaveSlot"

# === 互传 ===
func teleport_to_save_point(target_id: StringName) -> void:
    # 不写 RunSnapshot（R6）；可选 trigger_auto_save("AfterTeleport")
    # 玩家保留全部本局状态（血量 / 能量 / 背包 / Boon），仅物理位置切换
    pass
```

---

## 4. 武器仓库系统

```gdscript
# Script/Save/WeaponStorageManager.gd  （SaveSystem 的辅助类，不是 Autoload）
class_name WeaponStorageManager

# === 入库 ===
static func deposit(meta: MetaSaveData, inst: WeaponInstance) -> bool:
    # 铁律 R2：必须玩家主动触发（背包满不自动溢出）
    # 铁律 R3：入库瞬间 UltEnergy 强制归零
    inst.reset_ult_energy()
    # 铁律 R8：装备 / 入库是"移动"非"复制"——调用方负责把 EquipmentComponent 的对应 slot 设为 null
    var d = inst.to_dict()
    meta.weapon_storage.append(d)
    return true

# === 出库装回 ===
static func withdraw(meta: MetaSaveData, instance_uuid: String, slot: StringName) -> WeaponInstance:
    var idx = -1
    for i in range(meta.weapon_storage.size()):
        if meta.weapon_storage[i]["uuid"] == instance_uuid:
            idx = i; break
    if idx < 0: return null
    var d = meta.weapon_storage[idx]
    meta.weapon_storage.remove_at(idx)
    var inst = WeaponInstance.from_dict(d)
    inst.reset_ult_energy()    # R3 校验：从仓库读出仍 0
    return inst                  # 调用方再 EquipmentComponent.equip_to_slot(slot, inst)

# === 丢弃（销毁）===
static func discard(meta: MetaSaveData, instance_uuid: String) -> bool: ...

# === 不允许跨角色转移（铁律 R4）===
# 故意不实现 transfer_to_character() 接口
```

仓库内存结构：

```
MetaSaveData.weapon_storage: Array[Dictionary]
  [
    {uuid, def_id, ult: 0, affixes: [...], seed, acquired_at, acquired_src},
    ...
  ]
```

---

## 5. Checkpoint Actor + LevelManager 接入

### 5.1 Checkpoint.tscn 结构

```
Checkpoint (Area3D)
├─ Visual (Node3D)
│   ├─ Pillar (MeshInstance3D)        # 占位石柱
│   ├─ Light (OmniLight3D)            # 金色光晕
│   └─ Particles (GPUParticles3D)     # 漂浮粒子
├─ InteractZone (Area3D + CollisionShape3D)   # 半径 2.0m
└─ Script: Checkpoint.gd
```

```gdscript
# Scenes/Levels/Checkpoint.gd
extends Area3D
class_name Checkpoint

@export var checkpoint_id: StringName        # 全局唯一
@export var display_name: String
@export var dungeon_id: StringName           # 所属副本

func _on_player_entered(body):
    if not body.is_in_group("Player"): return
    EventBus.checkpoint_in_range.emit(self)

func _on_player_exited(body):
    if not body.is_in_group("Player"): return
    EventBus.checkpoint_out_of_range.emit(self)

func interact():
    # 玩家按 G 触发
    SaveSystem.capture_snapshot_at_save_point(checkpoint_id)
    var meta = SaveSystem.current_meta
    if not meta.save_points_unlocked.any(func(e): return e.id == checkpoint_id):
        meta.save_points_unlocked.append({
            "id": checkpoint_id,
            "dungeon_id": dungeon_id,
            "first_unlock_unix": Time.get_unix_time_from_system(),
        })
    meta.last_active_checkpoint_id = checkpoint_id
    # 回血 + 切换池 +25
    var p = get_tree().get_first_node_in_group("Player")
    p.asc.apply_effect(load("res://Data/GameData/GE/GE_HealthInit_Full.tres"))
    p.energy_comp.add_switch_energy(25)
    # UI 1.5s "已存档"动画
    EventBus.checkpoint_save_completed.emit(self)
```

### 5.2 死亡回档流程（替代当前 R 键重开）

```
EventBus.player_died (M4 当前由 PlayerCharacter.die 发)
      ↓
GameInstance.on_player_died：
  1. 禁所有 combat_* InputAction（防回档过程中误操作）
  2. 角色播死亡动画 1.2s
  3. UI ScreenFade.fade_to_black(0.5s) + 白色"复苏"文案
  4. await SaveSystem.load_last_active_snapshot()
        ├─ 加载 RunSnapshot → 恢复 30+ 字段
        ├─ LevelManager.change_to(stage_id, room_id, room_random_seeds)
        ├─ EquipmentComponent.equip_to_slot(MAIN, WeaponInstance.from_dict(snap.equipped_main))
        ├─ EquipmentComponent.equip_to_slot(OFF,  WeaponInstance.from_dict(snap.equipped_off))
        ├─ EnergyComponent.switch_energy = snap.current_switch_energy
        ├─ ASC 还原 active_buffs（带剩余持续）
        ├─ MetaSaveData.total_death_count += 1
        └─ MetaSaveData.last_save_unix = now
  5. UI ScreenFade.fade_in(0.5s) + 玩家在存档点苏醒动画 1.0s
  6. 解禁 combat_* InputAction
  7. EventBus.respawned_at_checkpoint.emit(checkpoint_id)
```

总时长目标 4~6 秒（前项目 §5.1 锁定）。

---

## 6. 自动存档触发器（5 个事件点）

```gdscript
# Script/Save/AutoSaveTrigger.gd（GameInstance 子节点）
extends Node

func _ready():
    # P0 必做 5 点
    EventBus.app_quit_requested.connect(_on_quit)              # 退出游戏
    EventBus.level_changing.connect(_on_level_change)          # 关卡切换
    EventBus.before_boss_room_entered.connect(_on_before_boss) # Boss 房前
    EventBus.before_character_swap.connect(_on_before_swap)    # 角色切换前
    EventBus.teleport_arrived.connect(_on_teleport_done)       # 互传到达后

func _on_quit():        SaveSystem.trigger_auto_save(&"Quit")
func _on_level_change(): SaveSystem.trigger_auto_save(&"LevelChange")
func _on_before_boss():  SaveSystem.trigger_auto_save(&"BeforeBoss")
func _on_before_swap():  SaveSystem.trigger_auto_save(&"BeforeCharSwap")
func _on_teleport_done(): SaveSystem.trigger_auto_save(&"AfterTeleport")
```

约束：
- **非阻塞**：写入用 `WorkerThreadPool.add_task` 异步
- **防抖**：两次自动存档间隔 ≥10s
- **静默失败**：异常只记日志，不弹窗
- **始终保留 .bak**：写新 auto_save.json 前 mv 旧的 → .bak

---

## 7. 互传 UI（Q6 锁定 = Demo 必做）

详细规则见前项目 §13 Q6.1~Q6.5：
- 入口：存档点 G 后子页"快速旅行"
- 数据源：`MetaSaveData.save_points_unlocked`
- 战斗状态禁用（按 CombatStateService）
- 免费（保留 `FastTravelCost_SwitchEnergy` 配置字段，默认 0）
- **不写 RunSnapshot**；触发 `trigger_auto_save("AfterTeleport")`
- 玩家本局状态全部不变（血/能量/Boon），仅物理位置切换

---

## 8. 与现有 Dolphin 系统的衔接

| Dolphin 现有系统 | 改动点 |
|---|---|
| `Script/Core/GameInstance.gd` | 把当前 R 键重开 cheat 改为暂停菜单的"重置当前 Run（Debug）"项；正常死亡走 SaveSystem.load_last_active_snapshot |
| `Script/GameFramework/LevelManager.gd` | 新增 `change_to(stage_id, room_id, seeds)` API；emit `level_changing` 信号供 AutoSaveTrigger |
| `Script/Core/SettingsManager.gd` | save / load 走 SaveSystem.GlobalSettings 而非独立 cfg |
| `Script/Items/EquipmentComponent.gd`（D4 重构） | 序列化时调 WeaponInstance.to_dict()；反序列 from_dict |
| `Script/Character/Components/EnergyComponent.gd` | 暴露 switch_energy / 大招池接口供 RunSnapshot 写读 |
| `Scenes/Main/main_scene.tscn` | 主菜单加入「角色选择」按钮 |
| 现有飘字 / Cue（M8）| 死亡 1.2s 动画期间禁飘字与 Cue 注入新事件 |

---

## 9. 配置字段（可热改）

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| MaxRunSnapshotSizeKB | int | 500 | 单写入大小报警阈值 |
| CheckpointInteractionRange | float | 2.0 | G 交互半径（m）|
| CheckpointSaveAnimDuration | float | 1.5 | 存档动画 |
| CheckpointHealRatio | float | 1.0 | 1.0 = 全血 |
| CheckpointRestoreSwitchEnergy | float | 25 | 存档点回切换池值 |
| CheckpointRestoreUltEnergy_Main | float | 0 | Demo 不回送，工程预留 |
| DeathAnimDuration | float | 1.2 | — |
| RespawnFadeOutDuration | float | 0.5 | — |
| RespawnFadeInDuration | float | 0.5 | — |
| RespawnAtCheckpointAnimDuration | float | 1.0 | — |
| BossRoomReentryFullReset | bool | true | Demo 锁定 |
| EliteKilledStaysKilled | bool | true | 防卡 bug |
| ChestRandomSeedStableWithinSnapshot | bool | true | 防刷宝箱 cheese |
| EnableFastTravelToHub | bool | true | 互传开关 |
| FastTravelCost_SwitchEnergy | float | 0 | Demo 免费 |
| AutoSaveMinIntervalSec | float | 10 | 自动存档防抖 |

放到 `Data/Config/SaveSystemConfig.tres`。

---

## 10. 衔接下文

- D5 任务分解（10 项）/ 10 条铁律工程 checklist / 角色选择 UI 规格 / 仓库 UI 规格 / 验收清单 → **04B 文档**
- 与战斗 / 武器系统的协议（卸装清空、ASC 序列化、ult/switch 池写读） → **02 / 03 文档**
- 与输入系统的协议（死亡 / 黑屏期间禁 combat_*） → **01 文档**

---

## 11. 变更日志

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-05-20 | 从前项目 03 v1.2 §1~§9 萃取，加 UE→Godot 等价物映射、3 类存档目录树、GlobalSettings/MetaSaveData/RunSnapshot/AutoSaveSlot 完整字段、SaveSystem/WeaponStorageManager/Checkpoint/AutoSaveTrigger 骨架、死亡回档 7 步流程、5 个自动存档触发点、与 Dolphin 现有系统的衔接表。**铁律 / 任务分解 / 验收清单见 04B 文档**。|
