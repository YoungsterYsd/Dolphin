# Skill Timelines

技能时间轴 `.tres` 资源存放目录。

## 命名规范

`Timeline_<SkillName>.tres`，对应 `SkillTimeline.skill_id`。

## 加载

由 `ConfigCenter` 启动时扫描整个目录加载到 `_skill_timelines` 字典；
通过 `ConfigCenter.get_skill_timeline(skill_id)` 取用。

## 创建途径

- M7.1–M7.3 阶段：手写 .tres（用于验证运行时管线）
- M7.4–M7.5 阶段：通过技能编辑器 Plugin 可视化创建

## 关联

- 伤害节点配置：`res://Data/Config/SkillDamageTable.tres`（Hitbox.Enable 关键帧通过 `damage_node_index` 引用）
- 技能 Ability：`Ability_TimelineDriven.gd` + `Data/Abilities/Ability_*.tres`（`timeline_id` 字段引用本目录的 .tres）
