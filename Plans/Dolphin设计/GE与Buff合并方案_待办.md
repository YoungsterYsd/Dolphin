# GE 与 Buff 系统 · 合并方案（不分系统）

> 创建日期：2026-05-23
> 决策：**Buff 不独立成系统**，统一走 `GameplayEffect`。本文记录后续 GE 演进时的待办增强。
> 核心结论：[完整论证见 2026-05-23 对话纪要]，UE GAS / Lyra 均不分 BuffSystem，Buff 是 GE 的"使用约定"。

---

## 一、当前 GE 系统覆盖能力

| 期望能力 | GE 字段/机制 | 状态 |
|---|---|---|
| 持续时长 | `EffectType.DURATION` + `duration` | ✅ |
| 周期生效 | `EffectType.PERIODIC` + `period` | ✅ |
| 加状态标记 | `granted_tags` + GameplayTagContainer 计数 | ✅ |
| 数值修正 | `modifiers: Array[AttributeModifier]` | ✅ |
| 视听表现 | `cue_tags_while_active` + CueManager add/remove | ✅ |
| 净化驱散 | `removed_tags` + `remove_effects_with_granted_tag` | ✅ |
| 免疫某类 buff | `application_blocked_tags` | ✅ |
| 条件触发 | `application_required_tags` | ✅ |
| 来源溯源 | `GameplayEffectSpec.source` | ✅ |
| 运行时数据注入 | `GameplayEffectSpec.set_by_caller_data` | ✅ |
| 自动到期清理 | `_tick_active_effects` + `_detach_active` | ✅ |
| UI 订阅 | `EventBus.effect_applied / effect_removed` | ✅ |

**结论**：GE 系统已经是 GE+Buff 合体形态，不需要再造 BuffSystem。

---

## 二、后续 GE 设计待办（用户 2026-05-23 确认稍后处理）

### 待办 1 · Tag 命名约定（零代码）
**优先级**：随时可做（建议下次清理 GameplayTags.tres 时一并落）
**内容**：
- `Status.Buff.<name>` → 增益（StrengthUp / SpeedUp / Shield）
- `Status.Debuff.<name>` → 减益（Burning / Poison / Slow）
- `Status.Crowd.<name>` → 控制（Stun / Silence / Root / Sleep）
- `Status.Block.*` → 格挡相关（已有 Combat.Block.Broken，未来可统一到 Status.Block.*）

**作用**：UI Buff 列表 widget 按前缀过滤渲染；策划/程序看 tag 即知道这是 buff 还是 debuff。

---

### 待办 2 · Stack 叠加策略（约 80 行代码）
**优先级**：YAGNI 原则——**等到第一个真的需要叠层数的 buff 出现时再做**（如"中毒 x5"、"冰冻积累 x3 触发 freeze"）
**内容**：GameplayEffect 资源新增字段：

```gdscript
enum StackPolicy {
    APPLY_NEW,           # 默认：每次施加都新建一份 active_effect（当前行为）
    REFRESH_DURATION,    # 同 GE 已存在 → 刷新 duration，不新建
    STACK_COUNT,         # 同 GE 已存在 → stack +1（modifier × stacks）
    IGNORE_IF_PRESENT,   # 已存在则跳过
}

@export var stack_policy: StackPolicy = StackPolicy.APPLY_NEW
@export var max_stacks: int = 1                         # STACK_COUNT 用
@export var stack_by_source: bool = false               # true=同源才合并
```

**改动点**：
- `AbilitySystemComponent.apply_effect_spec()` 入口：按 stack_policy 路由查找已有 active_effect
- `_attach_active()` handle 加 `stacks: int` 字段
- `_apply_modifiers()` 应用时按 stacks 倍率
- UI 订阅 `effect_stacked(target, ge, new_stacks)` 新增信号

---

### 待办 3 · UI 元数据字段（约 5 行代码 + UI Widget）
**优先级**：与 HUD Phase 3 合并（DIR-1.3 P3-T4/T5 Buff/Debuff List Widget）
**内容**：GameplayEffect 资源新增字段（仅 UI 用，不影响逻辑）：

```gdscript
@export var ui_icon: Texture2D = null              # Buff 图标
@export var ui_show_in_hud: bool = false           # 是否在 HUD Buff 栏显示
@export var ui_category: StringName = &""          # buff / debuff / crowd_control / hidden
@export var ui_display_name: String = ""           # Tooltip 显示名（可与 display_name 区分）
@export var ui_tooltip_desc: String = ""           # Tooltip 描述
```

**配套 UI**：HUD Phase 3 落地 Buff/Debuff List Widget，订阅 `EventBus.effect_applied / removed`，过滤 `ui_show_in_hud=true` + `granted_tags` 命中 `Status.Buff.*` / `Status.Debuff.*` 渲染。

---

## 三、不做（明确排除）

| 项 | 排除原因 |
|---|---|
| 独立 `BuffDefinition.gd` 资源类 | 与 GameplayEffect 90% 重叠，会引发"什么时候用 GE 什么时候用 Buff"的设计抉择灾难 |
| 独立 `BuffComponent.gd` | ASC 已经管理 active_effects 列表，能力完全够用 |
| 独立 `BuffManager.gd` Autoload | R-ARCH-02 上限 6 已满；ASC 本身就是各角色的 buff manager |
| 把"Buff 列表展示"做成新模块 | 是 HUD 工作（DIR-1.3）；按 GE granted_tags 过滤即可 |

---

## 四、决策记录

- 2026-05-23 用户拍板：**不分系统**，Buff 走 GE
- 2026-05-23 待办 2/3 暂记本文档，后续 GE 设计推进时再开 Sprint
- 不阻塞当前 Fragment 道具系统 Phase 1 落地
