# Data 目录

数据驱动配置（`.tres` Resource 文件）集中存放区。

## 子目录

| 目录 | 内容 | 引入里程碑 |
|---|---|---|
| `Attributes/` | `AttributeSet` 配置（玩家/怪物属性数值） | M2 |
| `Abilities/` | `Ability` 资源（普攻、技能） | M2 |
| `Effects/` | `GameplayEffect` 资源（伤害、治疗、Buff） | M2 |
| `Tags/` | `GameplayTagRegistry.tres`（全局 Tag 注册表） | M2 |
| `Items/` | 物品定义（消耗品、装备） | M5 |
| `Enemies/` | 怪物定义（含场景、属性、AI 配置） | M4 |
| `Levels/` | 关卡定义（含场景、BGM、Boss） | M5 |

> 规则 R-DATA-01：玩家可见数值一律走本目录的 `.tres`，禁止脚本魔数。
> 规则 R-GAS-03：Ability / GE 必须 Resource 化。
