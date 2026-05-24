# 端到端验证报告 · R-Core / R-ASC / R-PreChange / R-Data（角色属性部分）

**日期**：2026-05-22  
**对应改动**：批次 1 重构全部完成（4 个阶段）  
**前置文档**：
- `Plans/Refactor/重构进度_R-Core_20260522.md`
- `Plans/Refactor/重构进度_R-ASC_PreChange_Data部分_20260522.md`

---

## 1. 自动化通过的项目（MCP 验证）

### 1.1 静态层 · 编辑器 0 Parse Error
- 重启编辑器后日志唯一 [Error] 是 Boss/Visual/AnimationPlayer 编辑器内置错误（已知无害）
- lint 0 Error / 0 Warning（覆盖整个 `Script/` 目录）
- 4 阶段完成后总改动：21（R-Core）+ 11（R-ASC/PreChange）+ 6 增 6 删（R-Data）= **44 个文件改动**

### 1.2 R-Data JSON 解算数学正确性（execute_editor_script 静态验证）

调用 `AttributeResolver.resolve(table, lv)` 跑 9 组样本，全部通过：

| 角色 | lv1 | lv5 | lv10 |
|---|---|---|---|
| Player | health=100 atk=10 armor=5 spd=5.0 | health=140 atk=14 armor=7 | health=190 atk=19 armor=9.5 |
| Boss | health=200 atk=12 armor=4 spd=2.5 | health=400 atk=20 armor=8 | health=650 atk=30 armor=13 |
| Slime | health=30 atk=5 armor=2 spd=2.0 | health=50 atk=9 armor=4 | health=90 atk=14 armor=6.5 |

**回归校验**：Player lv1（health=100/atk=10/armor=5/spd=5.0）与重构前 `Growth_Player.tres` 的 base 值字面量一致 ✅；分段成长（lv5/lv10 用 segments[0].per_level=10）数学也对得上。

### 1.3 启动期 ASC bootstrap（运行时日志）

`run_project` 后的关键启动日志（取自 R-Data 完成后的最后一次自测）：

```
ConfigCenter bootstrap done. characters=4, growth_tables=3, ges=15
[Player] health_healing: 0.00 -> 999999.00
HealthRegen tick on Player
StaminaRegen tick on Player
[Player] bootstrap_from_entity done: entity=player_lv1 lv=1 sets=3
TrainingDummy: ASC ready, sets=1
HUDManager: registered Widget BigBannerWidget / ToastWidget / ... (9 个)
```

每行都是端到端链路的关键节点：
- `growth_tables=3` ← R-Data 三份 JSON 全加载成功
- `sets=3` ← R-ASC 删 attribute_set 老接口后 attribute_sets 数组维持 HealthSet+PrimaryAttributeSet+CombatSet
- `health_healing 0→999999 → health=100` ← R-PreChange 元属性管道（声明式 hook 表）走通
- HUDManager 9 个 Widget 全部注册 ← R-Core 30 处 has_signal 删除后 Widget 订阅正常

---

## 2. MCP 自动化做不到的项目（需要手测）

### 2.1 限制原因

godot-mcp 的 `execute_script` 用 `Expression` 类，运行在**编辑器进程**上下文；拿不到 `run_project` 启动的**游戏子进程**的 SceneTree。因此**所有运行时交互验证（按键、鼠标、伤害、动画）都得手动跑游戏**。

### 2.2 必跑的 8 项手测清单

#### A. 移动 / 相机（基线）
- [ ] **A1**：WASD 移动正常，玩家朝向 / 移动速度看起来正常（spd=5.0 是预期值）
- [ ] **A2**：鼠标移动相机 OK；摄像机不会卡墙

#### B. 普攻 / 受击（R-ASC + R-PreChange 的核心验证点）
- [ ] **B1**：站到 TrainingDummy 旁边按普攻键（默认鼠标左键 / 配置里的对应 InputAction）→ Dummy 受击动画 + 飘字数字 + 血条下降
- [ ] **B2**：连续打 5-10 次到死 → Dummy 死亡（`enemy_died` 信号 → BigBanner 应该不会触发，KillFeed 应该有一行）
- [ ] **B3**：打另一个 Slime（如果场景里有），观察 Slime lv1 health=30 与 .tres 时代是否一致（≤4 次普攻应该死，按 atk_base=10 + Slime armor_base=2 算）

#### C. 格挡 / 破防（R-ASC 重点：EventBus.block_broken 解耦）
- [ ] **C1**：按 D 键举盾，HUD 上 stamina 进度条进入"格挡显示"状态
- [ ] **C2**：让 Boss/敌人多次打你（撑着不松开 D），观察 stamina 持续消耗
- [ ] **C3**：stamina 归零瞬间 → **关键验证点**：
  - 玩家自动松盾（BlockComponent 收到 `EventBus.block_broken` 信号执行 `stop_block`）
  - `Combat.Block.Broken` tag 上身（应有 1.2s 硬直，无法举盾 / 无法攻击）
  - 1.2s 后 tag 消失，玩家恢复正常
- [ ] **C4**：格挡期间精确格挡（提前一帧抬起再压下？或者首次受击瞬间）→ `block_perfect_triggered` 信号 → buff Cue / 屏幕特效

#### D. UI 健康度（R-Core 删 has_signal 后所有 Widget 订阅没掉）
- [ ] **D1**：HP 进度条受击时实时下降；血量回满
- [ ] **D2**：飘字数字（DamagePopup）正常出现
- [ ] **D3**：KillFeed 杀敌后有提示
- [ ] **D4**：QuestTracker 如果有正在进行的任务，UI 正常显示

#### E. 性能基线
- [ ] **E1**：移动 + 多敌人在场时 FPS 看起来正常（不掉到 30 以下就行）
- [ ] **E2**：游戏运行期间 console 无新增 Error/Warning（只有已知的 sfx_id not bound 之类 info）

### 2.3 手测出 bug 时的回滚信号

如果 C3 出现以下情况之一，是 R-ASC 改动引发的回归：
- stamina 归零后玩家不松盾 → `EventBus.block_broken` 信号没连上（检查 BlockComponent._ready）
- 1.2s 硬直没生效 → `CombatBalanceConfig.block_broken_stun_sec` 配置缺失或读不到
- 1.2s 后 tag 没移除 → `_trigger_block_broken` 内部 timer 没起或 callback 没执行

报回我后，我会在 1 轮内修复。

---

## 3. 已知非阻塞警告（不需要管）

| 警告 | 出处 | 状态 |
|---|---|---|
| `Visual/AnimationPlayer not found (relative to .../Boss)` | 编辑器视图 SceneTree 搜索 | 已知，与重构无关 |
| `OverheadHealthBarManager: Visual/AnimationPlayer not found` | 同上 | 同上 |
| `sfx_id not bound in SfxBindings.tres: <id>` | 部分 SFX 还没接入 | 不阻塞，按 R-CODE-01 §保留 warn 场景之 #2 |

---

## 4. 总结

| 维度 | 状态 |
|---|---|
| **静态正确性** | ✅ lint=0 / 编辑器 0 Parse Error / JSON 解算 9/9 通过 |
| **启动期完整性** | ✅ ConfigCenter / GameInstance / ASC / HUDManager 全链路启动 |
| **运行时数学** | ✅（间接证据：bootstrap sets=3 + Regen 三件套 + HealthInit_Full 全跑通） |
| **运行时交互** | ⚠️ 待手测（C 节 8 项是关键） |
| **回归风险** | 低（数学层零回归 + 启动期零异常；只剩交互层未验证） |

**推荐下一步**：按手测清单跑一轮（约 5-10 分钟）。无问题则批次 1 重构正式收尾，可以进 §5 的下一步选择。

---

## 5. 下一步选项（手测通过后）

- **A**：R-Data 剩余的 GameConfig 顶层聚合（9 份子配置整合）
- **B**：Phase 2 GAS 巨型类拆分（ASC 631 行 → 拆 EffectExecutor + AbilityScheduler + TagBookkeeper）
- **C**：Phase 3 UI 巨型类拆分（HUDManager 502 行）
- **D**：本轮经验沉淀到 3 条新规则 R-ARCH-04 / R-CODE-02 / R-DATA-03（已起草，见 `Plans/Refactor/规则提案_2026-05-22.md`）

我推荐 **D + A** —— 先把规则锁死避免后续模块再犯同类错误，然后继续推 Roadmap。
