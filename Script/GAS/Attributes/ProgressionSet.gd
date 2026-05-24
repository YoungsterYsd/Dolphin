## ProgressionSet（玩家挂载，敌人不挂）。
##
## 等级 / 经验 / 升级所需经验三件套；为 HUD 经验条 + LevelUp 横幅 + PlayerAvatar 等级数字
## 提供数据载体，业务逻辑（累加经验 / 升级判定 / 多级跨越 / Char_Attr 重算）由 [LevelComponent] 处理。
##
## ── 字段（共 3）──
## [member level]：当前等级，初始 1。
## [member experience]：朝下一级的进度（0 ~ xp_to_next；升级后清零并保留溢出）。
## [member xp_to_next]：达到下一级所需经验（数据来自 [code]Hero_Lev.csv[/code]，
##   由 [LevelComponent] 在初始化 / 升级时写入；满级后置 0）。
##
## ── 与怪物等级机制的差异（设计统一性说明）──
## 项目里"等级"在玩家与怪物上是两套独立机制：
##   - **怪物等级**：来自 [code]Monster_Data.csv.level[/code]，刷出来时一次性按该等级解算
##     [code]Monster_Attr[/code] 成长曲线，**永不变化**；
##   - **玩家等级**：本 Set 维护，运行时随经验累积升级，由 [LevelComponent] 在升级时调
##     [method AbilitySystemComponent.recompute_level_attributes] 重算 [code]Char_Attr[/code]
##     成长曲线（保留 HP/体力比例）。
## 二者共享底层入口 [method ConfigCenter.resolve_character_attributes]，
## 但变化语义完全不同——故仅玩家挂 ProgressionSet。
##
## ── 设计要点 ──
## 不放 ProgressionSet 内做"超过 xp_to_next 自动升级"逻辑：
##   1) AttributeSet 应是数据容器，业务逻辑外置；
##   2) 一次 add_experience 可能跨多级，循环判定逻辑放在 LevelComponent 更清晰；
##   3) 升级还需重算 Char_Attr 属性 + 派发横幅信号，跨多个系统的协调不应在 Set 里做。
##
## ── 信号驱动 ──
## 任何字段变更走 [method set_attr] → 经 EventBus.attribute_changed 广播：
##   - LevelUpWidget 监听 [code]&"level"[/code] new>old 时显示 "LEVEL UP"
##   - PlayerAvatarWidget 监听 [code]&"level"[/code] 刷新左上角 "Lv.N"
##   - ExperienceBarWidget 通过 AttributeProvider 监听 [code]&"experience" / &"xp_to_next"[/code]
class_name ProgressionSet
extends AttributeSet


## 当前等级（初始 1）。
@export var level: float = 1.0

## 当前经验（朝下一级的进度，升级后清零并保留溢出；满级后停在 0）。
@export var experience: float = 0.0

## 达到下一级所需经验（满级时为 0）。
##
## 业务侧（LevelComponent）在角色初始化 / 升级后通过 [method set_attr] 写入；
## ExperienceBarWidget 通过 AttributeProvider(max_attribute_name=&"xp_to_next") 读取上限。
@export var xp_to_next: float = 0.0


## 钩子：
## - level：clamp_min=1（不会出现 0 级）；上限不在 Set 里管，由 LevelComponent 卡 max_level
## - experience：clamp_min=0；不绑 max_attr（多级跨越时 LevelComponent 会临时写很大的中间值
##   做循环结算，绑 max=xp_to_next 会被钳掉导致溢出经验丢失）
## - xp_to_next：clamp_min=0
func _get_attribute_hooks() -> Dictionary:
	return {
		&"level":       {"clamp_min": 1.0, "clamp_max": INF},
		&"experience":  {"clamp_min": 0.0, "clamp_max": INF},
		&"xp_to_next":  {"clamp_min": 0.0, "clamp_max": INF},
	}
