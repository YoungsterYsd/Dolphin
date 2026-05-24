# 系统框架 · 铁律 / 任务分解 / 验收（Dolphin 适配版 · 下）

> **来源**：前项目 `03_死亡惩罚与存档点设计.md` v1.2 §11.3 / §12 / §13 / §14。
> **本文定位**：D5 里程碑「死亡 / 存档 / 仓库」的工程实施清单——10 条铁律 + 10 项任务 + UI 规格 + 验收。**架构与数据结构见 04 文档（part 1）**。

---

## 1. 10 条铁律（工程评审 checklist，全部 P0）

| # | 铁律 | 防止的 Cheese / 风险 | Dolphin 落地校验 |
|---|---|---|---|
| **R1** | Meta 档不受任何"死亡回档"路径触及 | 仓库刷武器 / AutoSave 恶意读档 | `SaveSystem.load_last_active_snapshot()` 内**不读不写** `MetaSaveData`；写 RunSnapshot 走独立函数 |
| **R2** | 仓库写入必须玩家主动触发；**禁止背包满自动溢出进仓库** | 拾即刷 Meta，死后回档重刷同 Boss | `WeaponStorageManager.deposit()` 仅由 UI 按钮 / 存档点 UI 调用；`InventoryComponent` 满了不自动入库（弹窗让玩家选丢弃 / 替换） |
| **R3** | 仓库内武器 `current_ult_energy = 0`（入库瞬间 + 出库瞬间双校验）| 入库出库保值大招池 | `WeaponStorageManager.deposit / withdraw` 内强制 `inst.reset_ult_energy()` |
| **R4** | CharacterID 用 UUIDv4、不可变、删除后不复用；**跨角色资源转移 UI 一律不提供**（Demo） | 跨角色刷资源 | `Script/Save/UUID.gd` v4 实现；`SaveSystem` 不暴露 `transfer_*` API |
| **R5** | 新建角色初始资源**只写入该角色 MetaSaveData**，不影响 GlobalSettings 或其它角色档 | 删档刷初始资源 | `SaveSystem.create_new_character` 只创建一份新 .json，初始资源在新档内分配 |
| **R6** | AutoSaveSlot 与 RunSnapshot **物理独立文件**；**死亡走 RunSnapshot、启动走 AutoSaveSlot**；**玩家不提供任何 UI 手动读 AutoSaveSlot** | AutoSave 被恶意读档 | `load_last_active_snapshot` 只读 `run_snapshot.json`；`load_auto_save_if_exists` 仅在 `_ready` 启动期内被调用 |
| **R7** | Meta 写入与 Run 写入是**独立事务** | 混存档损坏 | `_write_atomic_meta()` / `_write_atomic_run()` 各自先写 .tmp → fsync → rename，旧文件先 mv .bak |
| **R8** | 装备 / 入库是"移动"不是"复制"；UUID 不与身上武器冲突 | 武器复制 cheese | `WeaponInstance.instance_uuid` UUIDv4 在 `_init` 生成；`equip_to_slot` 调用前要求 `withdraw` 必须先把仓库列表移除 |
| **R9** | 删除角色 = 整档销毁（.json + .bak + run_snapshot + auto_save 全删） | 删了还能恢复 | `SaveSystem.delete_character` 用 `DirAccess.remove_recursive`，删之前要求二次确认（输入角色名） |
| **R10** | 角色切换前的自动存档**强制性**（切角色 UI 确认后才能真正切，不允许 skip） | 切换丢进度 | 角色选择界面"切换"按钮先 `await SaveSystem.trigger_auto_save("BeforeCharSwap")`，写完才进 `load_character` |

---

## 2. D5 任务分解（10 项）

| # | 任务 | 落地点 | 工时 | 依赖 |
|---|---|---|---|---|
| D5.1 | SaveSystem 主类 + UUID + 全局设置读写 | `Script/Save/SaveSystem.gd` + `UUID.gd` + `GlobalSettings.gd` | 0.5d | — |
| D5.2 | 18 个数据结构（GlobalSettings/MetaSaveData/RunSnapshot/AutoSaveSlot + 子结构）| `Script/Save/*.gd` | 1.5d | D5.1 |
| D5.3 | 多角色目录架构 + 文件原子读写（.tmp/.bak + JSON 序列化） | SaveSystem 内部 + `_io.gd` 工具 | 0.5d | D5.2 |
| D5.4 | 角色选择 UI（CharacterSelectScreen.tscn）| `Scenes/UI/CharacterSelectScreen.tscn` + `.gd` | 1.0d | D5.1 |
| D5.5 | Checkpoint Actor + Scene + 交互 | `Scenes/Levels/Checkpoint.tscn` + `Checkpoint.gd` | 0.5d | D5.2 |
| D5.6 | 死亡回档流程（替换 R 键重开） | `GameInstance.on_player_died` + ScreenFade UI | 1.5d | D5.5、D4 武器序列化 |
| D5.7 | AutoSaveTrigger（5 触发点 + 防抖 + 异步） | `Script/Save/AutoSaveTrigger.gd` | 0.5d | D5.1 |
| D5.8 | 武器仓库 UI + WeaponStorageManager | `Scenes/UI/WeaponStorageScreen.tscn` + `WeaponStorageManager.gd` | 1.0d | D4 WeaponInstance |
| D5.9 | 互传 UI（FastTravelScreen） + teleport 流程 | `Scenes/UI/FastTravelScreen.tscn` + SaveSystem.teleport_to_save_point | 0.7d | D5.5、D5.7 |
| D5.10 | 10 条铁律工程校验 + 启动时 RunSnapshot vs AutoSave 较新者读取决策 | `SaveSystem.decide_load_path_on_startup` + 单元测试脚本 | 0.3d | 全部 |

**合计：8.0 工作日**（前项目 03 文档预估 7~8d 一致）。

---

## 3. UI 规格（文字描述，UI 设计师参考）

### 3.1 角色选择界面（启动后默认进入）

```
┌─── 选择角色 · 无限乐园 ──────────────────────┐
│                                              │
│  [ A · 林岚 - Lv.15 - 最后游玩 2026-05-19 ]   │
│    职业：[占位]    已解锁副本：2              │
│    仓库：12 把武器                            │
│                                              │
│  [ B · 顾承 - Lv.3  - 最后游玩 2026-05-15 ]   │
│    职业：[占位]    已解锁副本：0              │
│    仓库：3 把武器                             │
│                                              │
│  [ + 新建角色 ]   （Demo 上限 3 个）          │
│  [ - 删除选中 ]   （需输入角色名确认）        │
│                                              │
│  [G 进入游戏]  [Esc 返回主菜单]               │
└──────────────────────────────────────────────┘
```

操作：
- 方向键上下选；G = 进入；Del = 删除（弹二次确认）；+ 新建（弹输入框）

### 3.2 武器仓库界面（观测塔仓库台 G 触发）

```
┌─── 武器仓库 ─────────────────────────────────┐
│  当前装备                                    │
│   主手：[剑 · 灰锋]  大招池 80/100  附魔×2   │
│   副手：[弓 · 雀鸣]  大招池 30/100  附魔×1   │
│  ─────────────────────────────────────────── │
│  仓库（12 把 / 无上限）                      │
│   ▶ [枪 · 寒铁]   附魔×2   首次获得 2026-05-15│
│     [杖 · 月引]   附魔×0   首次获得 2026-05-16│
│     ...                                      │
│  ─────────────────────────────────────────── │
│  操作：                                       │
│   [G 装备到主手]  [F 装备到副手]              │
│   [Del 丢弃（二次确认）]                      │
│   [Esc 返回]                                  │
└──────────────────────────────────────────────┘
```

铁律提示：
- 装备到主 / 副手 = 把当前对应槽位武器**自动入库**（R3 清池）
- 丢弃 = 永久销毁（不可恢复）
- 仓库内武器 UI 池子永远显示 0/100（R3）

### 3.3 快速旅行界面（存档点 G 后子页）

```
┌─── 快速旅行 ─────────────────────────────────┐
│                                              │
│  【观测塔】                                   │
│   ✓ 中央枢纽（首次解锁 Day1 12:00）  当前位置 │
│                                              │
│  【破碎钟楼】                                 │
│   ✓ 钟楼入口    （Day1 13:20）               │
│   ✓ 钟楼中段    （Day1 14:05）               │
│   ✗ Boss前节点  （未抵达）                   │
│                                              │
│  【锈蚀工厂】                                 │
│   ✗ 工厂入口    （未抵达）                   │
│                                              │
│  [方向键选择]  [G 确认传送]  [Esc 返回]       │
└──────────────────────────────────────────────┘
```

操作：
- 战斗中按钮灰色 + 提示"战斗中无法传送"
- 已点亮的可传，未点亮的不可
- 传送后**不写 RunSnapshot**，仅 trigger_auto_save("AfterTeleport")

---

## 4. 启动流程（GameInstance._ready 最终版）

```
GameInstance._ready():
  1. 加载 GlobalSettings.json（缺失则建默认）
  2. 应用 KeyBindings / Audio / Video
  3. 切到主菜单 main_scene
       └─ 玩家点"角色选择"或"继续上次"
  
"继续上次"流程：
  1. SaveSystem.load_character(GlobalSettings.last_played_character_id)
  2. 决定加载路径：
       run_t = RunSnapshot.saved_at_unix
       auto_t = AutoSaveSlot.saved_at_unix
       if auto_t > run_t and AutoSaveSlot.trigger_source == "Quit":
           # 用户上次正常退出 → 直接读 AutoSaveSlot（"上次离开位"语义）
           load AutoSaveSlot
       elif auto_t > run_t:
           # 异常退出 → 弹窗"检测到异常退出快照，是否恢复？"
           if 玩家确认: load AutoSaveSlot
           else:        load RunSnapshot
       else:
           load RunSnapshot
  3. LevelManager.change_to(stage_id, room_id, room_random_seeds)
  4. 玩家在最近存档点 / 上次离开位 spawn

"角色选择"流程：
  1. 显示 list_characters()
  2. 玩家选角色 + G → load_character(id)
  3. 进入"继续上次"流程的第 2 步
```

---

## 5. 验收清单（D5 完成时，对应前项目 §12 十条）

- [ ] **存档点流畅**：走到 Checkpoint → UI 提示 → 按 G → 1.5s 动画 → 全血 + 切换池 +25 + "已存档"反馈，全流程 ≤ 3s。
- [ ] **死亡回档流畅**：死亡到玩家重新获控制权 ≤ 6s；中间无卡顿、无黑屏卡死。
- [ ] **状态完全回滚**：在存档点 A 存档 → 进房间打怪 → 死亡 → 验证 5 字段（health/inventory/acquired_boons/currency_run/current_run_kill_count）与 A 完全一致。
- [ ] **Meta 不受影响**：连死 10 次后 `total_death_count += 10`；其它 Meta 字段（unlocked_*, weapon_storage, achievement_progress）零变化。
- [ ] **宝箱种子稳定**：同一 RunSnapshot 内宝箱无论死多少次开出内容一致（room_random_seeds 字段实际接入 Roll）。
- [ ] **Boss 战完全重置**：Boss 战死 → 回最近 Checkpoint → Boss 血量、房间状态、临时物品全重置。
- [ ] **卸装清空与回档协同**：A 处武器 W1 ult=80 → 在 A 存档 → 进 B 房用商店换装把 W1 卸下 → W1 ult 立即 0 → 死亡 → 回 A → W1 重回身上、ult 回到 80。
- [ ] **铁律 R3 强校验**：把 W1 入库 → 立刻读出 → ult 仍是 0；中间手工改 .json 把 ult 改成 99 → 启动加载后 ult 强制归 0。
- [ ] **铁律 R6 强校验**：连续手工删 RunSnapshot 文件后启动 → 系统能从 AutoSaveSlot 兜底（弹窗确认）；正常死亡时**不**读 AutoSave。
- [ ] **铁律 R9 强校验**：删除角色后再次列出 → 该角色不出现；目录 `characters/<uuid>/` 完全消失。
- [ ] **多角色隔离**：角色 A 仓库有 W1，切到角色 B 后仓库为空；切回 A 后 W1 仍在；A 的 unlocked_dungeons 不影响 B。
- [ ] **AutoSave 触发 5 点**：退出 / 关卡切换 / Boss 房前 / 角色切前 / 互传到达后各能在 `auto_save.json` 看到对应 `trigger_source`；防抖 10s 生效（密集触发只写一次）。
- [ ] **互传**：从观测塔互传到钟楼入口 → 玩家位置切换、血量/能量/Boon **完全不变**；战斗状态下按钮灰色。
- [ ] **存档大小**：单角色 character.json < 2MB、run_snapshot.json < 500KB（前项目 §6.3 阈值）。
- [ ] **崩溃保护**：用 SIGTERM 强杀 Godot 进程后再启动 → 启动期检测 AutoSave 较新且非 Quit → 弹窗"检测到异常退出快照"。
- [ ] **玩家反馈采样**：3 名 tester 死 5 次后 ≥ 70% 反馈"死了不痛苦，想再试"。

---

## 6. 与其它文档的衔接

- 死亡 / 黑屏期间禁 combat_* → **01_战斗框架_输入映射_Dolphin适配.md** §2.2
- 双池 ult/switch 字段写入 RunSnapshot.equipped_main.ult / current_switch_energy → **02_战斗框架_属性公式_Dolphin适配.md** §4
- WeaponInstance.to_dict / from_dict 序列化结构 → **03_战斗框架_武器切换_Dolphin适配.md** §2.2
- F 切换不清池但卸装清池的语义 → **03_战斗框架_武器切换_Dolphin适配.md** §1.5

---

## 7. 变更日志

| 版本 | 日期 | 变更 |
|---|---|---|
| v0.1 | 2026-05-20 | 从前项目 03 v1.2 §11.3（10 条铁律）+ §12（验收）+ §13 Q6（互传 UI）+ §6.4.7（角色 UI）萃取，加 D5 10 任务分解、3 套 UI 文字规格、启动流程伪代码、15 项验收清单。**与 04（part 1）合并构成 D5 完整施工方案**。|
