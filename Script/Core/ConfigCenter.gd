## 全局配置中心（Autoload 单例 #1）。
##
## 统一管理所有数据驱动配置（角色实例表 / 属性成长表 / 技能数据 / HUD / 反馈 / 相机 / 光照 等）。
## R-ARCH-02：白名单 6 个 Autoload 之一。
## R-DATA-02：所有可调玩法数值都应通过本中心读取，禁止散落硬编码。
##
## 启动顺序：本 Autoload 排在 project.godot [autoload] 第 1 位，先于其它模块 _ready，
## 保证所有节点（包括 GameInstance）都能在 _ready 内安全调用 ConfigCenter API。
##
## 设计要点：
##   - R-CODE-01：必备资源缺失或类型不匹配 → assert 崩；禁兜底 new
##   - R-ARCH-03：业务侧统一 [code]ConfigCenter.xxx()[/code] 直访，不写 [code]get_node_or_null(^"ConfigCenter")[/code]
##   - 角色 / 属性数据来自 [code]Tools/Excel/*.xlsx[/code] 经 excel2Config 工具导出的 5 张 CSV
##     （Hero_Data / Monster_Data / Char_Attr / Monster_Attr / Attr_Data）
##   - 业务侧入口：[method resolve_character_attributes](kind, data_id, level) /
##     [method get_hero_data] / [method get_monster_data] / [method is_boss] / [method is_elite]
extends Node

# ─────────────────────────────────────────────────────────────
# 资源路径常量（R-DATA-02：路径也走常量集中管理）
# ─────────────────────────────────────────────────────────────

# 角色 / 属性（5 张 CSV，数据源 = Tools/Excel 经 excel2Config 工具导出）
const HERO_DATA_CSV     := "res://Data/FromExcel/Hero_Data.csv"
const MONSTER_DATA_CSV  := "res://Data/FromExcel/Monster_Data.csv"
const CHAR_ATTR_CSV     := "res://Data/FromExcel/Char_Attr.csv"
const MONSTER_ATTR_CSV  := "res://Data/FromExcel/Monster_Attr.csv"
const ATTR_DATA_CSV     := "res://Data/FromExcel/Attr_Data.csv"

# 玩家升级表（独立 CSV，仅玩家用；怪物等级在 Monster_Data.csv.level 配死）
const HERO_LEV_CSV      := "res://Data/FromExcel/Hero_Lev.csv"

# 技能资源
const SKILL_DAMAGE_TABLE_PATH := "res://Data/Config/SkillDamageTable.tres"
const SKILL_TIMELINES_DIR := "res://Data/Skills/Timelines"

# 命中反馈 / 血条 / SFX
const HIT_FEEDBACK_CONFIG_PATH := "res://Data/Config/HitFeedbackConfig.tres"
const HEALTH_BAR_CONFIG_PATH := "res://Data/Config/HealthBarConfig.tres"
const SFX_BINDINGS_PATH := "res://Data/Config/SfxBindings.tres"

# GameplayEffect 资源目录
const EFFECTS_DIR := "res://Data/Effects"

# 相机 / 光照 / 后处理
const CAMERA_CONFIG_PATH := "res://Data/Config/CameraConfig.tres"
const LIGHTING_CONFIG_PATH := "res://Data/Config/LightingConfig.tres"
const POST_PROCESS_CONFIG_PATH := "res://Data/Config/PostProcessConfig.tres"

# 战斗平衡
const COMBAT_BALANCE_CONFIG_PATH := "res://Data/Config/CombatBalanceConfig.tres"

# 对话 / 立绘
const DIALOGUE_CONFIG_PATH := "res://Data/Manual/Config/DialogueConfig.tres"
const PORTRAITS_CONFIG_PATH := "res://Data/Manual/Config/PortraitsConfig.tres"

# ─────────────────────────────────────────────────────────────
# 运行时缓存
# ─────────────────────────────────────────────────────────────

# 角色 / 属性
# Hero_Data:    int(hero_id)    -> { id, Hero_name, attr_id, ... }
# Monster_Data: int(monster_id) -> { id, name, type, attr_id, level, ... }
# Char_Attr:    int(attr_id)    -> { id, health_base, attack_base, ... }
# Monster_Attr: int(attr_id)    -> { id, health_base, ... }
# Attr_Data:    int(attr_id)    -> { id, Name, Var_Name }   (UI 翻译表 + 字段白名单)
var _hero_data: Dictionary = {}
var _monster_data: Dictionary = {}
var _char_attr: Dictionary = {}
var _monster_attr: Dictionary = {}
var _attr_data: Dictionary = {}

## Var_Name → Attr_Data row（反向索引，给"白名单/UI 翻译"两个用途）
var _attr_data_by_var: Dictionary = {}

# 玩家升级表（仅玩家用；怪物等级在 Monster_Data.csv.level 静态配死）
var _level_table: LevelTable = null

# 技能资源
var _skill_damage_table: SkillDamageTable = null
var _skill_timelines: Dictionary = {}  # StringName(skill_id) -> SkillTimeline

# GameplayEffect 库（按 ge_id → GameplayEffect Resource 索引；ge_id 来自文件名 GE_* 去掉 .tres 与 GE_ 前缀）
# 例：GE_HealthRegen.tres → ge_id = &"HealthRegen"；运行时调 ConfigCenter.get_ge(&"HealthRegen")
var _gameplay_effects: Dictionary = {}

# 命中反馈 / 血条 / SFX
var _hit_feedback_config: HitFeedbackConfig = null
var _health_bar_config: HealthBarConfig = null
var _sfx_bindings: SfxBindings = null

# 相机 / 光照 / 后处理
var _camera_config: CameraConfig = null
var _lighting_config: LightingConfig = null
var _post_process_config: PostProcessConfig = null

# 战斗平衡
var _combat_balance_config: CombatBalanceConfig = null

# 对话系统配置（惰性加载，不在 _bootstrap 内预读）
var _dialogue_config: DialogueConfig = null
var _portraits_config: PortraitsConfig = null

# 道具系统（Phase 1）：Fragment 架构 + Excel CSV 工作流
var _item_loader: ItemConfigLoader = null
var _affix_plan_loader: AffixPlanLoader = null

# 战利品掉落（Phase 1.5）：Drop_Rule.csv → LootRoller 抽样
var _loot_table_loader: LootTableLoader = null

# NPC / 对话 / 任务 / 触发条件（M12 阶段；与 LootTableLoader 同模式）
var _npc_loader: NPCConfigLoader = null
var _dialogue_csv_loader: DialogueCsvLoader = null
var _quest_loader: QuestLoader = null
var _condition_loader: ConditionLoader = null


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameLogger.info("Config", "ConfigCenter ready, bootstrapping...")
	_bootstrap()


## 重新加载所有配置（Editor 调试用，运行时谨慎使用）。
func reload_all() -> void:
	GameLogger.info("Config", "ConfigCenter reload_all")
	_hero_data.clear()
	_monster_data.clear()
	_char_attr.clear()
	_monster_attr.clear()
	_attr_data.clear()
	_attr_data_by_var.clear()
	_level_table = null
	_skill_damage_table = null
	_skill_timelines.clear()
	_gameplay_effects.clear()
	_hit_feedback_config = null
	_health_bar_config = null
	_sfx_bindings = null
	_camera_config = null
	_lighting_config = null
	_post_process_config = null
	_combat_balance_config = null
	_dialogue_config = null
	_portraits_config = null
	_dialogue_graph_cache.clear()
	_item_loader = null
	_affix_plan_loader = null
	_loot_table_loader = null
	_npc_loader = null
	_dialogue_csv_loader = null
	_quest_loader = null
	_condition_loader = null
	_bootstrap()


# ─────────────────────────────────────────────────────────────
# 角色实例表 API
# ─────────────────────────────────────────────────────────────

## 角色种类。BaseCharacter 用 [code]kind + data_id[/code] 二元组定位实例。
enum CharacterKind { HERO, MONSTER }


## 取英雄数据（按 hero_id）。找不到返回空 dict。
func get_hero_data(hero_id: int) -> Dictionary:
	if not _hero_data.has(hero_id):
		GameLogger.warn("Config", "Hero_Data not found: %d" % hero_id)
		return {}
	return _hero_data[hero_id]


## 取怪物数据（按 monster_id）。找不到返回空 dict。
func get_monster_data(monster_id: int) -> Dictionary:
	if not _monster_data.has(monster_id):
		GameLogger.warn("Config", "Monster_Data not found: %d" % monster_id)
		return {}
	return _monster_data[monster_id]


## 取玩家属性表行（按 attr_id）。
func get_char_attr(attr_id: int) -> Dictionary:
	if not _char_attr.has(attr_id):
		GameLogger.warn("Config", "Char_Attr not found: %d" % attr_id)
		return {}
	return _char_attr[attr_id]


## 取怪物属性表行（按 attr_id）。
func get_monster_attr(attr_id: int) -> Dictionary:
	if not _monster_attr.has(attr_id):
		GameLogger.warn("Config", "Monster_Attr not found: %d" % attr_id)
		return {}
	return _monster_attr[attr_id]


## 取属性元信息（Attr_Data：UI 翻译 + 字段白名单），按 attr 主键 id。
func get_attr_meta(attr_id: int) -> Dictionary:
	return _attr_data.get(attr_id, {})


## 按 [code]Var_Name[/code]（如 [code]&"attack_base"[/code]）反查属性元信息。
##
## 用途：
## - X：UI 翻译（拿中文 Name 显示在角色面板）
## - Z：白名单（CSV 表头里出现的字段名都应能在 Attr_Data 里找到，否则属于"未声明属性"）
func get_attr_meta_by_var(var_name: StringName) -> Dictionary:
	return _attr_data_by_var.get(var_name, {})


## Boss 判定：怪物的 type 字段是否为 "Boss"。
##
## 数据来源唯一为 [code]Monster_Data.type[/code]（用户决策 Q3：唯一来源）。
## Hero 永远返回 false。
func is_boss(kind: int, data_id: int) -> bool:
	if kind != CharacterKind.MONSTER:
		return false
	var row: Dictionary = get_monster_data(data_id)
	if row.is_empty():
		return false
	return CsvLoader.as_string(row, "type", "") == "Boss"


## 精英判定：怪物 type == "Elite"。
func is_elite(kind: int, data_id: int) -> bool:
	if kind != CharacterKind.MONSTER:
		return false
	var row: Dictionary = get_monster_data(data_id)
	if row.is_empty():
		return false
	return CsvLoader.as_string(row, "type", "") == "Elite"


## 取实例的「应用等级」。
##
## - HERO：Hero_Data 暂未配 level 列；走传入的 level_override，<=0 时硬编 1
##   （备忘：等接入等级经验系统后改读 [PlayerProfile.level] 或类似）
## - MONSTER：用 Monster_Data.level；level_override > 0 时覆盖
func resolve_level(kind: int, data_id: int, level_override: int = -1) -> int:
	if kind == CharacterKind.HERO:
		# Hero_Data 不含 level 列；玩家初始化时按 1 级解算 Char_Attr，
		# 由 LevelComponent 在 character_initialized 后接管 ProgressionSet，
		# 升级时通过 ASC.recompute_level_attributes 重算 Char_Attr（保留 HP 比例）。
		return level_override if level_override > 0 else 1
	# MONSTER
	var row: Dictionary = get_monster_data(data_id)
	if row.is_empty():
		return max(1, level_override)
	if level_override > 0:
		return level_override
	return CsvLoader.as_int(row, "level", 1)


## 便捷方法：按 (kind, data_id, level) 直接解算最终属性 dict。
##
## 解算路径：
##   HERO    → Hero_Data[data_id].attr_id    → Char_Attr[attr_id]    + level → 属性 dict
##   MONSTER → Monster_Data[data_id].attr_id → Monster_Attr[attr_id] + level → 属性 dict
func resolve_character_attributes(kind: int, data_id: int, level: int) -> Dictionary:
	var attr_id: int = 0
	var attr_row: Dictionary = {}
	if kind == CharacterKind.HERO:
		var hero_row: Dictionary = get_hero_data(data_id)
		if hero_row.is_empty():
			return {}
		attr_id = CsvLoader.as_int(hero_row, "attr_id", 0)
		attr_row = get_char_attr(attr_id)
	elif kind == CharacterKind.MONSTER:
		var mon_row: Dictionary = get_monster_data(data_id)
		if mon_row.is_empty():
			return {}
		attr_id = CsvLoader.as_int(mon_row, "attr_id", 0)
		attr_row = get_monster_attr(attr_id)
	else:
		GameLogger.warn("Config", "resolve_character_attributes: unknown kind %d" % kind)
		return {}

	if attr_row.is_empty():
		GameLogger.warn("Config", "Attr row not found: kind=%d data_id=%d attr_id=%d" % [kind, data_id, attr_id])
		return {}

	return AttributeResolver.resolve_row(attr_row, max(1, level))


# ─────────────────────────────────────────────────────────────
# 玩家升级表 API（仅玩家用；怪物等级在 Monster_Data.csv.level 配死）
# ─────────────────────────────────────────────────────────────


## 取从 [param level] 升到 [param level]+1 所需经验。
##
## 满级（level >= max_level）时返回 0；调用方据此判定是否拒绝继续累加经验。
## 等级 < 1 或漏配 → LevelTable 内部 assert 崩（R-CODE-01）。
func get_xp_to_next(level: int) -> int:
	return _level_table.get_xp_to_next(level)


## 玩家最大可达等级（=Hero_Lev.csv 最大 Lev + 1）。
func get_max_level() -> int:
	return _level_table.max_level


# ─────────────────────────────────────────────────────────────
# 技能资源 API
# ─────────────────────────────────────────────────────────────

## 取技能时间轴（按 skill_id）。未找到返回 null（已打 warn）。
func get_skill_timeline(skill_id: StringName) -> SkillTimeline:
	if not _skill_timelines.has(skill_id):
		GameLogger.warn("Config", "SkillTimeline not found: %s" % skill_id)
		return null
	return _skill_timelines[skill_id]


## 取技能伤害表（全局唯一）。
func get_skill_damage_table() -> SkillDamageTable:
	return _skill_damage_table


## 便捷方法：取某技能的某个伤害节点（命中时使用）。
func get_damage_node(skill_id: StringName, index: int) -> DamageNode:
	if _skill_damage_table == null:
		return null
	return _skill_damage_table.get_node_at(skill_id, index)


# ─────────────────────────────────────────────────────────────
# GameplayEffect 库 API
# ─────────────────────────────────────────────────────────────

## 按 ge_id 取 GameplayEffect 资源。
##
## ge_id 命名约定：取自文件名去掉 .tres 与 GE_ 前缀。例：
## - GE_HealthRegen.tres → [code]get_ge(&"HealthRegen")[/code]
## - GE_DamageInstant.tres → [code]get_ge(&"DamageInstant")[/code]
## - GE_PerfectBlockBuff.tres → [code]get_ge(&"PerfectBlockBuff")[/code]
##
## 找不到返回 null（已 push_warning）。
func get_ge(ge_id: StringName) -> GameplayEffect:
	if not _gameplay_effects.has(ge_id):
		GameLogger.warn("Config", "GameplayEffect not found: %s" % ge_id)
		return null
	return _gameplay_effects[ge_id]


## 检查是否注册（用于 grep 调用密度 / 调试）。
func has_ge(ge_id: StringName) -> bool:
	return _gameplay_effects.has(ge_id)


# ─────────────────────────────────────────────────────────────
# 命中反馈 / 血条 / SFX 配置 API
# ─────────────────────────────────────────────────────────────

## 取命中反馈配置。R-Core 后必返回非空（启动时已断言加载）。
func get_hit_feedback_config() -> HitFeedbackConfig:
	return _hit_feedback_config


## 取血条配置。R-Core 后必返回非空（启动时已断言加载）。
func get_health_bar_config() -> HealthBarConfig:
	return _health_bar_config


## 取 SFX 绑定表。R-Core 后必返回非空（启动时已断言加载）。
func get_sfx_bindings() -> SfxBindings:
	return _sfx_bindings


## 便捷方法：按 sfx_id 直接取 AudioStream。
func get_sfx_stream(sfx_id: StringName) -> AudioStream:
	return _sfx_bindings.get_stream(sfx_id)


# ─────────────────────────────────────────────────────────────
# 相机 / 光照 / 后处理 配置 API（R-Core 后必返回非空）
# ─────────────────────────────────────────────────────────────

func get_camera_config() -> CameraConfig:
	return _camera_config


func get_lighting_config() -> LightingConfig:
	return _lighting_config


func get_post_process_config() -> PostProcessConfig:
	return _post_process_config


## 战斗平衡配置（DamagePipeline 等使用）。
func get_combat_balance_config() -> CombatBalanceConfig:
	return _combat_balance_config


# ─────────────────────────────────────────────────────────────
# 对话图 API（M11；按需加载，不在 bootstrap 内预加载所有图）
# ─────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────
# 对话图 API（M12；按需构造 + 缓存；DRY: 与 get_dialogue_config 同惰性模式）
# ─────────────────────────────────────────────────────────────

# graph_id(int) → DialogueGraph 缓存（运行时复用，避免每次 start 重新构图）
var _dialogue_graph_cache: Dictionary = {}


## 取对话图（按 graph_id；CSV 现场构图 + 缓存）。找不到返回 null。
func get_dialogue_graph(graph_id: int) -> DialogueGraph:
	if graph_id <= 0:
		return null
	if _dialogue_graph_cache.has(graph_id):
		return _dialogue_graph_cache[graph_id]
	var g: DialogueGraph = DialogueGraphFactory.build(graph_id)
	if g == null:
		GameLogger.warn("Dialogue", "DialogueGraph not found: %d" % graph_id)
		return null
	_dialogue_graph_cache[graph_id] = g
	return g


func get_dialogue_config() -> DialogueConfig:
	# 单次惰性加载并缓存（轻量 Resource，启动期不必预读）
	if _dialogue_config == null:
		_dialogue_config = _load_resource_typed_optional(DIALOGUE_CONFIG_PATH, DialogueConfig) as DialogueConfig
		if _dialogue_config == null:
			# 该配置可选；缺失时给空实例（业务侧用默认行为）
			_dialogue_config = DialogueConfig.new()
	return _dialogue_config


func get_portraits_config() -> PortraitsConfig:
	if _portraits_config == null:
		_portraits_config = _load_resource_typed_optional(PORTRAITS_CONFIG_PATH, PortraitsConfig) as PortraitsConfig
		if _portraits_config == null:
			_portraits_config = PortraitsConfig.new()
	return _portraits_config


# ─────────────────────────────────────────────────────────────
# 道具系统 API（Phase 1：Fragment 架构 + Excel CSV）
# ─────────────────────────────────────────────────────────────


## 取道具定义（按 item_id；对应 Item_Data.id）。找不到返回 null。
func get_item_def(item_id: int) -> ItemDefinition:
	if _item_loader == null:
		GameLogger.warn("Items", "get_item_def called before _item_loader ready")
		return null
	return _item_loader.get_by_id(item_id)


## 取所有 ItemDefinition（int(id) → ItemDefinition）。调试 / UI 列表用。
func get_all_item_defs() -> Dictionary:
	if _item_loader == null:
		return {}
	return _item_loader.all()


## 取词条池（按 plan_id；对应 attr_plan.id）。
##
## 返回 dict 格式：[code]{ id: int, sub_id: null, sub_entries: [候选词条 dict ...] }[/code]。
## 找不到返回空 dict（AffixRoller 内部 assert 崩）。
func get_affix_plan(plan_id: int) -> Dictionary:
	if _affix_plan_loader == null:
		return {}
	return _affix_plan_loader.get_plan(plan_id)


## 取掉落表（按 drop_table_id；对应 [code]Drop_Rule.id[/code]）。
##
## 返回 dict 格式：[code]{ id, sub_id, sub_entries: [{Type, Weight, Item_ID, Item_Num}, ...] }[/code]。
## 找不到 / 未配 → 返回空 dict（[LootRoller] 自行 warn 并返回空数组）。
func get_drop_rule(drop_table_id: int) -> Dictionary:
	if _loot_table_loader == null:
		return {}
	return _loot_table_loader.get_table(drop_table_id)


## 是否存在该掉落表（含至少一条规则）。
func has_drop_rule(drop_table_id: int) -> bool:
	if _loot_table_loader == null:
		return false
	return _loot_table_loader.has_table(drop_table_id)


# ─────────────────────────────────────────────────────────────
# NPC / 对话 / 任务 / 触发条件 API（M12）
# ─────────────────────────────────────────────────────────────


## 取 NPC 元信息（按 npc_id）。
func get_npc_def(npc_id: int) -> Dictionary:
	if _npc_loader == null:
		return {}
	return _npc_loader.get_npc(npc_id)


## 取对话包的全部选项（按 diapack_id）。
func get_diapack_entries(diapack_id: int) -> Array:
	if _npc_loader == null:
		return []
	return _npc_loader.get_diapack_entries(diapack_id)


## 取对话 graph 的全部节点（按 graph_id；按 sub_id 升序）。
func get_dialogue_nodes(graph_id: int) -> Array:
	if _dialogue_csv_loader == null:
		return []
	return _dialogue_csv_loader.get_nodes(graph_id)


## 是否存在该对话 graph。
func has_dialogue_graph(graph_id: int) -> bool:
	if _dialogue_csv_loader == null:
		return false
	return _dialogue_csv_loader.has_graph(graph_id)


## 取任务系列的某一步。找不到返回空 dict。
func get_quest_step(quest_id: int, sub_id: int) -> Dictionary:
	if _quest_loader == null:
		return {}
	return _quest_loader.get_step(quest_id, sub_id)


## 任务系列是否存在该步骤。
func has_quest_step(quest_id: int, sub_id: int) -> bool:
	if _quest_loader == null:
		return false
	return _quest_loader.has_step(quest_id, sub_id)


## 反查：哪些 (quest_id, sub_id) 的 Deliver_Dialogue_ID 等于此 graph_id。
func find_quest_steps_by_deliver_dialogue(graph_id: int) -> Array:
	if _quest_loader == null:
		return []
	return _quest_loader.find_steps_by_deliver_dialogue(graph_id)


## 取条件集合（sub_entries 数组；同 cond_id 多 sub = AND 组合）。
func get_condition_set(cond_id: int) -> Array:
	if _condition_loader == null:
		return []
	return _condition_loader.get_set(cond_id)


# ─────────────────────────────────────────────────────────────
# 内部 - 启动加载
# ─────────────────────────────────────────────────────────────

func _bootstrap() -> void:
	# 必备配置（按 R-CODE-01：缺失/类型不匹配直接 assert 崩）
	_skill_damage_table = _load_resource_typed(SKILL_DAMAGE_TABLE_PATH, SkillDamageTable) as SkillDamageTable
	_hit_feedback_config = _load_resource_typed(HIT_FEEDBACK_CONFIG_PATH, HitFeedbackConfig) as HitFeedbackConfig
	_health_bar_config = _load_resource_typed(HEALTH_BAR_CONFIG_PATH, HealthBarConfig) as HealthBarConfig
	_sfx_bindings = _load_resource_typed(SFX_BINDINGS_PATH, SfxBindings) as SfxBindings
	_camera_config = _load_resource_typed(CAMERA_CONFIG_PATH, CameraConfig) as CameraConfig
	_lighting_config = _load_resource_typed(LIGHTING_CONFIG_PATH, LightingConfig) as LightingConfig
	_post_process_config = _load_resource_typed(POST_PROCESS_CONFIG_PATH, PostProcessConfig) as PostProcessConfig
	_combat_balance_config = _load_resource_typed(COMBAT_BALANCE_CONFIG_PATH, CombatBalanceConfig) as CombatBalanceConfig

	# CSV 数据驱动表：所有角色/属性元数据来自 Tools/Excel 经 excel2Config 工具导出的 CSV，
	# 缺失视为致命错误（assert 崩；策划应保证 5 张表都存在）。
	_load_csv_tables()

	# 目录扫描类（生产期间允许目录缺失，仅 warn）
	_load_skill_timelines()
	_load_gameplay_effects()

	# 道具系统（Phase 1）：Item_Data + 5 张 Frag_*.csv + attr_plan.csv
	_load_items_and_affix_plans()

	# 战利品掉落（Phase 1.5）：Drop_Rule.csv
	_load_loot_tables()

	# NPC / 对话 / 任务 / 触发条件（M12）
	_load_npc_dialogue_quest_condition()

	GameLogger.info("Config", "ConfigCenter bootstrap done. heroes=%d, monsters=%d, char_attr=%d, monster_attr=%d, attrs=%d, max_level=%d, skill_timelines=%d, damage_skills=%d, sfx_bindings=%d, ges=%d, items=%d, affix_plans=%d, loot_tables=%d, npcs=%d, diapacks=%d, dialogues=%d, quests=%d, conditions=%d" % [
		_hero_data.size(),
		_monster_data.size(),
		_char_attr.size(),
		_monster_attr.size(),
		_attr_data.size(),
		_level_table.max_level if _level_table != null else 0,
		_skill_timelines.size(),
		_skill_damage_table.table.size(),
		_sfx_bindings.bindings.size(),
		_gameplay_effects.size(),
		_item_loader.count() if _item_loader != null else 0,
		_affix_plan_loader.count() if _affix_plan_loader != null else 0,
		_loot_table_loader.count() if _loot_table_loader != null else 0,
		_npc_loader.npc_count() if _npc_loader != null else 0,
		_npc_loader.diapack_count() if _npc_loader != null else 0,
		_dialogue_csv_loader.count() if _dialogue_csv_loader != null else 0,
		_quest_loader.quest_count() if _quest_loader != null else 0,
		_condition_loader.count() if _condition_loader != null else 0,
	])


## 通用资源加载模板（必备配置）。
##
## 按 R-CODE-01：路径不存在 / 加载失败 / 类型不匹配 → 直接 assert 崩。
## 这些都是配置错误，应在开发期就暴露而不是悄悄用默认值跑下去。
##
## - [param path]：res:// 资源路径
## - [param expected_class]：期望的 [Resource] 子类（用 class_name 直接传，例如 [code]HealthBarConfig[/code]）
##
## 返回加载完成的资源。调用方需 [code]as XxxConfig[/code] 获得静态类型。
func _load_resource_typed(path: String, expected_class: Variant) -> Resource:
	assert(ResourceLoader.exists(path),
		"ConfigCenter: required resource missing at %s" % path)
	var res: Resource = load(path)
	assert(res != null, "ConfigCenter: failed to load %s" % path)
	assert(is_instance_of(res, expected_class),
		"ConfigCenter: type mismatch at %s (got %s)" % [path, res.get_class()])
	return res


## 可选资源加载（缺失时返回 null，不崩）。
##
## 用于 [DialogueConfig] / [PortraitsConfig] 这种"可缺省"配置。
## 加载到但类型不匹配时仍 assert 崩（属于配置错误而非缺省）。
func _load_resource_typed_optional(path: String, expected_class: Variant) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	assert(res != null, "ConfigCenter: failed to load %s" % path)
	assert(is_instance_of(res, expected_class),
		"ConfigCenter: type mismatch at %s (got %s)" % [path, res.get_class()])
	return res


## 从 5 张 CSV 加载角色/属性数据。
##
## 路径错误时直接 assert 崩（与 _load_resource_typed 同语义；这些都是必备表）。
func _load_csv_tables() -> void:
	# 主键 = id 列；4 张「实例 / 属性」表都没有子行，aggregate_subs 仍传 true 不影响
	_hero_data    = CsvLoader.load_table(HERO_DATA_CSV)
	_monster_data = CsvLoader.load_table(MONSTER_DATA_CSV)
	_char_attr    = CsvLoader.load_table(CHAR_ATTR_CSV)
	_monster_attr = CsvLoader.load_table(MONSTER_ATTR_CSV)
	_attr_data    = CsvLoader.load_table(ATTR_DATA_CSV)

	# 反向索引：Var_Name → Attr_Data row
	_attr_data_by_var.clear()
	for id_key in _attr_data.keys():
		var row: Dictionary = _attr_data[id_key]
		var var_name: StringName = CsvLoader.as_string_name(row, "Var_Name")
		if var_name != &"":
			_attr_data_by_var[var_name] = row

	# 玩家升级表（独立）
	_level_table = LevelTable.new()
	_level_table.load_from_csv(HERO_LEV_CSV)


func _load_skill_timelines() -> void:
	var dir := DirAccess.open(SKILL_TIMELINES_DIR)
	if dir == null:
		GameLogger.warn("Config", "Skill timelines dir not found: %s (will create on demand)" % SKILL_TIMELINES_DIR)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and (name.ends_with(".tres") or name.ends_with(".res")):
			var path: String = SKILL_TIMELINES_DIR + "/" + name
			var res: Resource = load(path)
			if res is SkillTimeline:
				var timeline: SkillTimeline = res
				if timeline.skill_id == &"":
					GameLogger.warn("Config", "SkillTimeline at %s has empty skill_id, using filename" % path)
					timeline.skill_id = StringName(name.get_basename())
				_skill_timelines[timeline.skill_id] = timeline
			else:
				GameLogger.warn("Config", "Skip non-SkillTimeline resource: %s" % path)
		name = dir.get_next()
	dir.list_dir_end()


## 扫描 Data/Effects/ 目录加载所有 GameplayEffect 资源。
##
## ge_id 命名约定：取文件名 basename 去掉 GE_ 前缀。例：
## - GE_HealthRegen.tres → ge_id = &"HealthRegen"
## - GE_BasicDamage.tres → ge_id = &"BasicDamage"
##
## 历史遗留资源（GE_BasicDamage / GE_Burning_3s / GE_Cleanse / GE_Heal30 / GE_Stun_2s 等）一并入库。
func _load_gameplay_effects() -> void:
	var dir := DirAccess.open(EFFECTS_DIR)
	if dir == null:
		GameLogger.warn("Config", "Effects dir not found: %s" % EFFECTS_DIR)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and (name.ends_with(".tres") or name.ends_with(".res")):
			var path: String = EFFECTS_DIR + "/" + name
			var res: Resource = load(path)
			if res is GameplayEffect:
				# 文件名 → ge_id：去掉 .tres/.res 扩展名，再去掉 GE_ 前缀
				var basename: String = name.get_basename()
				var ge_id: StringName = StringName(basename.trim_prefix("GE_"))
				_gameplay_effects[ge_id] = res
			else:
				GameLogger.warn("Config", "Skip non-GameplayEffect resource: %s" % path)
		name = dir.get_next()
	dir.list_dir_end()


## 加载道具系统（Phase 1）：CsvTableSource 一次性读 Item_Data + 5 张 Frag_*.csv，
## ItemConfigLoader 装配 ItemDefinition；AffixPlanLoader 加载 attr_plan.csv。
##
## 失败语义（R-CODE-01）：任一必备 CSV 缺失 → CsvLoader 内部 assert 崩。
func _load_items_and_affix_plans() -> void:
	# 词条池（独立加载，路径固定）
	_affix_plan_loader = AffixPlanLoader.new()
	_affix_plan_loader.load()

	# 道具：用 CsvTableSource 一次性加载 Item_Data + Fragment 子表
	var source := CsvTableSource.new()
	var paths: Array = [ItemConfigLoader.ITEMS_CSV]
	paths.append_array(FragmentRegistry.get_all_csv_paths())
	source.load_paths(paths)

	_item_loader = ItemConfigLoader.new()
	_item_loader.load_from(source)


## 加载战利品掉落表（Drop_Rule.csv）。
##
## 缺失允许（早期项目阶段没配掉落也能跑），LootTableLoader 自行 warn。
func _load_loot_tables() -> void:
	_loot_table_loader = LootTableLoader.new()
	_loot_table_loader.load()


## 加载 NPC / 对话 / 任务 / 触发条件 4 张 csv（M12）。
##
## 必备语义（R-CODE-01）：CSV 缺失 → CsvLoader assert 崩。
## 与 [LootTableLoader] 同模式，每个 Loader 单一职责（SRP）。
func _load_npc_dialogue_quest_condition() -> void:
	_npc_loader = NPCConfigLoader.new()
	_npc_loader.load()
	_dialogue_csv_loader = DialogueCsvLoader.new()
	_dialogue_csv_loader.load()
	_quest_loader = QuestLoader.new()
	_quest_loader.load()
	_condition_loader = ConditionLoader.new()
	_condition_loader.load()
