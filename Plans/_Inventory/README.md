# Plans/_Inventory · 项目盘点台账

> **生成日期**：2026-05-21
> **生成者**：主 agent（执行 C0-T1 ~ C0-T6）
> **用途**：对当前 Dolphin 项目（Godot 4.6 RPG + BossRush）做一次完整盘点，作为后续整理（C1–C4）/ 重构（第三步）的事实基线。
> **维护规则**：本目录文件由整理阶段生成与维护，不在三期开发期间手工编辑；后续若代码层有大变动（新增/删除模块），由主 agent 重新 `regenerate_inventory` 更新。

## 文件清单

| # | 文件 | 内容 | 来源 todo |
|---|---|---|---|
| 01 | `01_代码清单.md` | Script + Scenes 下全部 .gd 文件总览 | C0-T1 |
| 02 | `02_资源清单.md` | Data 下全部 .tres 资源总览 | C0-T2 |
| 03 | `03_场景清单.md` | Scenes + addons/skill_editor 下全部 .tscn | C0-T3 |
| 04 | `04_Autoload现状.md` | project.godot [autoload] 段解析 | C0-T4 |
| 05 | `05_EventBus信号.md` | EventBus.gd 全部 signal 台账 | C0-T5 |
| 06 | `06_待整理项.md` | 死代码 / 0 引用 / TODO / FIXME | C0-T6 |

## 与三步路线的关系

```
本盘点（_Inventory/）
    │
    ├─→ C1–C3 整理阶段直接消费（哪些归档/哪些删除）
    │
    ├─→ 第二步 开发方向梳理（基于 06_待整理项.md 的 TODO/FIXME 反推欠账）
    │
    └─→ 第三步 重构方向（基于 04_Autoload现状.md 与 05_EventBus信号.md 反推依赖图）
```
