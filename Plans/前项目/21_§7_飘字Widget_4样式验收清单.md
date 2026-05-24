# §7 飘字 Widget 4 样式验收清单

> **任务**：在 Editor 完善 `WBP_RPG_DamageNumber` 蓝图，让它根据传入的 `Amount / bIsCrit / bIsBlocked` 渲染**普通 / 暴击 / 治疗 / 格挡** 4 种样式 + 飘动动画 + 1 秒后自动销毁。
>
> **依赖**：A3-8 DamageNumberSubsystem（已 ✅）、`WBP_RPG_DamageNumber` 占位 Widget（已 ✅）
>
> **预计耗时**：60 分钟（首次完整 4 样式 + 动画）
>
> **当前状态**：基础链路已通（Subsystem 订阅、广播、Widget 创建、屏幕投影都成功）。Init Damage Popup 蓝图函数还需要按 **方案 A 3 段 Branch** 实现样式分支。

---

## 1. 测试入口（关键）

A3 阶段还没武器/技能链路触发伤害，**必须用蓝图手动广播一条假 `RPG.Message.Damage.Popup` 消息**作为测试输入。两种方式任选其一：

### 1.1 方式 A：在 BP_TempInitTester 加 P 键测试节点（推荐）

如果你已经建了 `BP_TempInitTester` 测试蓝图（详见 `19_A3_主理人配置清单.md` §6），直接加键盘事件触发：

```
[Pressed P]
  ↓
[Make RPGDamagePopupMessage]
   - Instigator   = Get Player Pawn
   - Target       = Get Player Pawn
   - Amount       = 99.0          ← 测试值
   - bIsCrit      = ✅            ← 测试暴击样式
   - bIsBlocked   = ❌
   - HitLocation  = (Get Player Pawn) → GetActorLocation
  ↓
[Broadcast Message]
   - Channel = Make Literal Gameplay Tag → "RPG.Message.Damage.Popup"
   - Message = (上一节点 struct)
```

按 P → 屏幕上玩家位置出现飘字（+ Output Log 出 `[A3-8] DamagePopup: ...`）

### 1.2 方式 B：4 个测试键覆盖 4 种样式

最完整的验收方式 —— 按 P/H/B/N 分别测试 4 种样式。在 BP_TempInitTester 里加 4 组：

| 键 | 样式 | bIsCrit | bIsBlocked | Amount |
|---|---|---|---|---|
| **N** | 普通 | false | false | 25 |
| **P** | 暴击（Power） | **true** | false | 99 |
| **H** | 治疗（Heal） | false | false | **-30**（负数表示治疗） |
| **B** | 格挡（Block） | false | **true** | 50 |

每个键的节点链跟 1.1 同样，只改 Make RPGDamagePopupMessage 里的 4 个参数即可。**复制粘贴 4 份**，每份接到不同的键事件。

> 这是 4 样式验收的唯一正确入口；不依赖武器/技能就能完整验证。

---

## 2. 4 样式视觉规格

### 2.1 视觉设计规则（来自 `02_战斗操作与能量决策.md` 设计 + 通用 ARPG 惯例）

| 样式 | 触发条件 | 文字内容 | 颜色 | 字号 | 描边 | 动画 |
|---|---|---|---|---|---|---|
| **普通** | bIsCrit=false, Amount>0, bIsBlocked=false | `{Amount}`（如 `25`） | **白色** (1, 1, 1, 1) | 28 | 黑色 1px | 上飘 +50px / 1.0s 淡出 |
| **暴击** | bIsCrit=true | `{Amount}!`（如 `99!`） | **金黄** (1, 0.84, 0, 1) | **40**（更大） | **黑色 2px**（更粗） | **上飘 +80px**（更高）+ 0.1s **缩放 0→1.3→1.0 弹性** |
| **治疗** | Amount<0 | `+{Abs(Amount)}`（如 `+30`） | **绿色** (0.2, 0.9, 0.3, 1) | 28 | 黑色 1px | 上飘 +50px / 1.2s 淡出（略慢） |
| **格挡** | bIsBlocked=true | `BLOCK` | **灰色** (0.6, 0.6, 0.6, 1) | 24 | 黑色 1px | 上飘 +30px / 0.8s 淡出（更快更短） |

### 2.2 判定优先级

> ⚠️ **顺序很重要**：先判暴击（最高），再判治疗，再判格挡，最后默认普通。

```
if (bIsCrit) → Crit
else if (Amount < 0) → Healing
else if (bIsBlocked) → Block
else → Normal
```

---

## 3. WBP_RPG_DamageNumber 蓝图结构

### 3.1 控件树（Hierarchy）

```
[Canvas Panel] (Anchor=Center, AutoSize=true)
└─ [Text_Damage] (UCommonTextBlock / Common Text)
    - SizeBoxOverride: Width=Auto, Height=Auto
    - Anchor=Center
    - Justification=Center
```

> `Common Text` 的 SetText / SetColorAndOpacity / SetFont API 与 TextBlock 1:1 兼容，节点连法不变。

### 3.2 Animation（蓝图动画）

新建 1 个 Animation 资产：**Anim_FloatUp**（在 Animations 窗口）

**Track 1：Translation Y**
- 关键帧 0s: `Y = 0`
- 关键帧 1s: `Y = -50`（普通/治疗）/ `Y = -80`（暴击）/ `Y = -30`（格挡）

> **简化做法**：动画只做"上飘 + 淡出"通用版，4 样式区别仅用 `SetRenderTranslation` 节点修改终点偏移量。

**Track 2：Render Opacity**
- 关键帧 0s: `1.0`
- 关键帧 0.7s: `1.0`（前 70% 保持不透明）
- 关键帧 1.0s: `0.0`（最后 30% 淡出）

> **进阶（暴击专用）**：再加一个 Track 3 RenderTransform.Scale，0s=0, 0.1s=1.3, 0.2s=1.0（弹性放大）。普通/治疗/格挡跳过这一段。

### 3.3 Init Damage Popup 实现（BlueprintImplementableEvent）

> 这是 C++ 调用的入口，由 `URPGDamagePopupWidget::InitDamagePopup(Amount, bIsCrit, bIsBlocked, StyleHint)` 触发。

#### 节点连法（按方案 A 3 段 Branch）

```
[Init Damage Popup]
  ↓ exec
┌─────────────────────────────────────────────────┐
│ Branch 1: bIsCrit ?                             │
│   True ──> [Crit 样式]                           │
│             - Set Text: Format Text "{0}!" + Amount
│             - Set Color: Gold (1, 0.84, 0, 1)
│             - Set Font Size: 40 (Slate Font Info)
│   False ↓                                       │
└─────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────┐
│ Branch 2: Amount < 0 ?                          │
│   True ──> [Healing 样式]                        │
│             - Set Text: Format Text "+{0}" + Abs(Amount)
│             - Set Color: Green (0.2, 0.9, 0.3, 1)
│             - Set Font Size: 28
│   False ↓                                       │
└─────────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────────┐
│ Branch 3: bIsBlocked ?                          │
│   True ──> [Blocked 样式]                        │
│             - Set Text: "BLOCK" (Make Literal Text)
│             - Set Color: Gray (0.6, 0.6, 0.6, 1)
│             - Set Font Size: 24
│   False ──> [Normal 样式]                        │
│             - Set Text: Conv_FloatToText(Amount)
│             - Set Color: White (1, 1, 1, 1)
│             - Set Font Size: 28
└─────────────────────────────────────────────────┘
              ↓ 4 路汇合
[Play Animation: Anim_FloatUp]
              ↓
[Set Timer by Function Name]
   - FunctionName: "RemoveSelf"
   - Time: 1.0
              ↓
(Init 函数结束)

(另外定义自定义函数 RemoveSelf：)
  Self → Remove from Parent
```

#### 关键节点搜索关键字

| 需要的节点 | 搜索关键字 |
|---|---|
| 拼字符串（暴击/治疗用） | `Format Text` |
| 取绝对值 | `Abs (Float)` |
| float → Text | `To Text (Float)` 或自动转换 |
| 设字色 | `Set Color And Opacity` |
| 设字号 | `Set Font` → 拖入 SlateFontInfo（在 Make Slate Font Info 节点设 Size） |
| 文本字面量 | `Make Literal Text` |
| 播动画 | `Play Animation` |
| 定时回调 | `Set Timer by Function Name` |
| 自销毁 | `Remove from Parent` |

---

## 4. 验收清单（D-1 ~ D-10）

按测试键依次执行 4 次，每次记录：

### 4.1 普通样式（按 N 键，Amount=25）

- [ ] **D-1** 屏幕玩家位置出现 **白色** `25` 文字
- [ ] **D-2** 文字向上飘约 50 像素，**1 秒后**淡出消失

### 4.2 暴击样式（按 P 键，Amount=99, bIsCrit=true）

- [ ] **D-3** 屏幕玩家位置出现 **金黄色** `99!` 文字（带感叹号）
- [ ] **D-4** 字号明显比普通样式**大**（40 vs 28）
- [ ] **D-5**（进阶）出现弹性放大动画（0→1.3→1.0）

### 4.3 治疗样式（按 H 键，Amount=-30）

- [ ] **D-6** 屏幕玩家位置出现 **绿色** `+30` 文字（带加号，绝对值，无负号）
- [ ] **D-7** 上飘速度比普通样式略慢（1.2s vs 1.0s）

### 4.4 格挡样式（按 B 键，bIsBlocked=true）

- [ ] **D-8** 屏幕玩家位置出现 **灰色** `BLOCK` 文字
- [ ] **D-9** 字号比普通样式**小**（24 vs 28）
- [ ] **D-10** 飘动距离比普通样式**短**（30px vs 50px）

### 4.5 通用项

- [ ] **D-11** Output Log 每按一次键，出现 `[A3-8] DamagePopup: style=... amount=...` 一行（4 次按键应有 4 条不同 style 的 log）
- [ ] **D-12** Widget 不会堆积（每次按键创建后 1s 自销毁，连续按 P 键 10 次屏幕上不应同时有 10 个飘字）

---

## 5. 常见问题

### Q1：Output Log 出 `[A3-8] DamagePopup:` 但屏幕没飘字

**根因**：`DamageNumberWidgetClass` 在 `URPGDamageNumberSubsystem` CDO 上没配，导致 SoftClassPtr.Get() 返回 null，跳过 CreateWidget。

**修复**：
1. 打开 `Project Settings`
2. 找 **`Game/Damage Popup`** 类别（或搜 `URPGDamageNumberSubsystem`）
3. 把 `Damage Number Widget Class` 设为 `WBP_RPG_DamageNumber`

或者通过 `DefaultGame.ini`：

```ini
[/Script/RPGGame.RPGDamageNumberSubsystem]
DamageNumberWidgetClass=/Game/UI/Damage/WBP_RPG_DamageNumber.WBP_RPG_DamageNumber_C
```

### Q2：屏幕上出现 Widget 但位置在屏幕角落不在玩家头顶

**根因**：HitLocation 传错了世界坐标，或 PlayerController.ProjectWorldLocationToScreen 返回 false。

**修复**：在 BP_TempInitTester 测试节点里把 `HitLocation` 引脚改为 `Get Player Pawn → GetActorLocation` + `Add Vector (0, 0, 100)`（往头顶上抬 100cm）。

### Q3：暴击/治疗的 Format Text 节点没找到 `{0}` 引脚

**修复**：节点中部的 **Format** 输入框先填 `{0}!` 或 `+{0}`（带花括号），下方会自动出现以数字命名的输入引脚。手输 `{0}` 但没写花括号 → 不会自动生成 pin。

### Q4：连续按测试键，飘字越叠越多不消失

**根因**：Set Timer by Function Name 没接对，或 RemoveSelf 函数没正确实现。

**修复**：在 RemoveSelf 函数里直接连：`Self → Remove from Parent`（不需要 Cast）。Set Timer 的 Time = 1.0，bLooping = false。

### Q5：动画播完后 Widget 还卡在屏幕上不消失

**根因**：动画完成事件没接 RemoveFromParent。

**修复方式 1（推荐）**：用 Set Timer 1.0s 后 RemoveFromParent，**不依赖动画结束事件**。  
**修复方式 2**：Animation 资产里加事件回调 `OnAnimationFinished` → 节点 `Remove From Parent`。

---

## 6. 未来切换到方案 C（A6 美化）

> 当前方案 A（3 段 Branch）满足 A3 验收。A6 美化阶段需要新增第 5+ 种样式（MISS / Immune / Debuff Tick）时切换到 Switch on GameplayTag。详见 `19_A3_主理人配置清单.md` §7.6。

---

## 7. A3 出货判定

✅ D-1 ~ D-12 全部勾选 → 飘字 4 样式已达成。
✅ 联动 A3-DOD V3.10（"飘字消息广播 / Subsystem 收到 / 4 样式可视化"）。
✅ 转 A4 EnhancedInput 接入。

> **本指南版本**：v1（2026-05-15）
