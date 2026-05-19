## 全局配置中心（Autoload 单例 #1）。
##
## 二期 M6 引入，统一管理所有数据驱动配置（角色实例表 / 属性成长表 / 技能数据 / HUD / 反馈 等）。
## R-ARCH-02：白名单 6 个 Autoload 之一。
## R-DATA-02：所有可调玩法数值都应通过本中心读取，禁止散落硬编码。
##
## 启动顺序：本 Autoload 排在 project.godot [autoload] 第 1 位，先于其它模块 _ready，
## 保证所有节点（包括 GameInstance）都能在 _ready 内安全调用 ConfigCenter API。
extends Node

# ─────────────────────────────────────────────────────────────
# 资源路径常量（R-DATA-02：路径也走常量集中管理）
# ─────────────────────────────────────────────────────────────

const CHARACTER_INSTANCES_PATH := "res://Data/Config/CharacterInstances.tres"
const GROWTH_TABLES_DIR := "res://Data/Config/AttributeGrowthTables"

# === M7 新增 ===
const SKILL_DAMAGE_TABLE_PATH := "res://Data/Config/SkillDamageTable.tres"
const SKILL_TIMELINES_DIR := "res://Data/Skills/Timelines"

# === M8 新增 ===
const HIT_FEEDBACK_CONFIG_PATH := "res://Data/Config/HitFeedbackConfig.tres"
const HEALTH_BAR_CONFIG_PATH := "res://Data/Config/HealthBarConfig.tres"
const SFX_BINDINGS_PATH := "res://Data/Config/SfxBindings.tres"

# 二期后续里程碑预留（M9 接入时补充）
# const CAMERA_CONFIG_PATH := "res://Data/Config/CameraConfig.tres"
# const LIGHTING_CONFIG_PATH := "res://Data/Config/LightingConfig.tres"
# const POST_PROCESS_CONFIG_PATH := "res://Data/Config/PostProcessConfig.tres"

# ─────────────────────────────────────────────────────────────
# 运行时缓存
# ─────────────────────────────────────────────────────────────

var _character_table: CharacterInstanceTable = null
var _growth_tables: Dictionary = {}  # StringName -> AttributeGrowthTable

# === M7 新增 ===
var _skill_damage_table: SkillDamageTable = null
var _skill_timelines: Dictionary = {}  # StringName(skill_id) -> SkillTimeline

# === M8 新增 ===
var _hit_feedback_config: HitFeedbackConfig = null
var _health_bar_config: HealthBarConfig = null
var _sfx_bindings: SfxBindings = null


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
	_character_table = null
	_growth_tables.clear()
	_skill_damage_table = null
	_skill_timelines.clear()
	_hit_feedback_config = null
	_health_bar_config = null
	_sfx_bindings = null
	_bootstrap()


# ─────────────────────────────────────────────────────────────
# 角色实例表 API
# ─────────────────────────────────────────────────────────────

## 取角色实例定义（按 id）。
func get_character_def(id: StringName) -> CharacterInstanceEntry:
	if _character_table == null:
		GameLogger.warn("Config", "CharacterInstanceTable not loaded")
		return null
	var def: CharacterInstanceEntry = _character_table.get_by_id(id)
	if def == null:
		GameLogger.warn("Config", "CharacterInstanceEntry not found: %s" % id)
	return def


## 取角色实例表（一般给 Editor 工具/调试使用）。
func get_character_table() -> CharacterInstanceTable:
	return _character_table


# ─────────────────────────────────────────────────────────────
# 属性成长表 API
# ─────────────────────────────────────────────────────────────

## 取属性成长表（按 id）。
func get_attribute_growth_table(id: StringName) -> AttributeGrowthTable:
	if not _growth_tables.has(id):
		GameLogger.warn("Config", "AttributeGrowthTable not found: %s" % id)
		return null
	return _growth_tables[id]


## 便捷方法：按 character id 直接解算最终属性 dict。
## 如果未指定 level，则用 CharacterInstanceEntry.level。
func resolve_character_attributes(character_id: StringName, level: int = -1) -> Dictionary:
	var def: CharacterInstanceEntry = get_character_def(character_id)
	if def == null:
		return {}
	var growth: AttributeGrowthTable = get_attribute_growth_table(def.growth_table_id)
	if growth == null:
		return {}
	var lv: int = level if level > 0 else def.level
	return AttributeResolver.resolve(growth, lv)


# ─────────────────────────────────────────────────────────────
# M7 · 技能资源 API
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
# M8 · 命中反馈 / 血条 / SFX 配置 API
# ─────────────────────────────────────────────────────────────

## 取命中反馈配置（震屏/冻帧/闪白/飘字 参数）。
func get_hit_feedback_config() -> HitFeedbackConfig:
	if _hit_feedback_config == null:
		# 兜底：返回一个默认实例，避免空指针
		_hit_feedback_config = HitFeedbackConfig.new()
	return _hit_feedback_config


## 取血条配置（Boss 分层 + 头顶血条 参数）。
func get_health_bar_config() -> HealthBarConfig:
	if _health_bar_config == null:
		_health_bar_config = HealthBarConfig.new()
	return _health_bar_config


## 取 SFX 绑定表（sfx_id → AudioStream）。
func get_sfx_bindings() -> SfxBindings:
	if _sfx_bindings == null:
		_sfx_bindings = SfxBindings.new()
	return _sfx_bindings


## 便捷方法：按 sfx_id 直接取 AudioStream。
func get_sfx_stream(sfx_id: StringName) -> AudioStream:
	var bindings: SfxBindings = get_sfx_bindings()
	return bindings.get_stream(sfx_id)


# ─────────────────────────────────────────────────────────────
# 内部 - 加载
# ─────────────────────────────────────────────────────────────

func _bootstrap() -> void:
	_load_character_table()
	_load_growth_tables()
	_load_skill_damage_table()
	_load_skill_timelines()
	# M8
	_load_hit_feedback_config()
	_load_health_bar_config()
	_load_sfx_bindings()
	GameLogger.info("Config", "ConfigCenter bootstrap done. characters=%d, growth_tables=%d, skill_timelines=%d, damage_skills=%d, sfx_bindings=%d" % [
		_character_table.entries.size() if _character_table != null else 0,
		_growth_tables.size(),
		_skill_timelines.size(),
		_skill_damage_table.table.size() if _skill_damage_table != null else 0,
		_sfx_bindings.bindings.size() if _sfx_bindings != null else 0,
	])


func _load_hit_feedback_config() -> void:
	if not ResourceLoader.exists(HIT_FEEDBACK_CONFIG_PATH):
		GameLogger.warn("Config", "HitFeedbackConfig.tres not found at %s, using defaults" % HIT_FEEDBACK_CONFIG_PATH)
		_hit_feedback_config = HitFeedbackConfig.new()
		return
	var res: Resource = load(HIT_FEEDBACK_CONFIG_PATH)
	if res is HitFeedbackConfig:
		_hit_feedback_config = res
	else:
		GameLogger.error("Config", "Resource at %s is not HitFeedbackConfig" % HIT_FEEDBACK_CONFIG_PATH)
		_hit_feedback_config = HitFeedbackConfig.new()


func _load_health_bar_config() -> void:
	if not ResourceLoader.exists(HEALTH_BAR_CONFIG_PATH):
		GameLogger.warn("Config", "HealthBarConfig.tres not found at %s, using defaults" % HEALTH_BAR_CONFIG_PATH)
		_health_bar_config = HealthBarConfig.new()
		return
	var res: Resource = load(HEALTH_BAR_CONFIG_PATH)
	if res is HealthBarConfig:
		_health_bar_config = res
	else:
		GameLogger.error("Config", "Resource at %s is not HealthBarConfig" % HEALTH_BAR_CONFIG_PATH)
		_health_bar_config = HealthBarConfig.new()


func _load_sfx_bindings() -> void:
	if not ResourceLoader.exists(SFX_BINDINGS_PATH):
		GameLogger.warn("Config", "SfxBindings.tres not found at %s, using empty" % SFX_BINDINGS_PATH)
		_sfx_bindings = SfxBindings.new()
		return
	var res: Resource = load(SFX_BINDINGS_PATH)
	if res is SfxBindings:
		_sfx_bindings = res
	else:
		GameLogger.error("Config", "Resource at %s is not SfxBindings" % SFX_BINDINGS_PATH)
		_sfx_bindings = SfxBindings.new()


func _load_character_table() -> void:
	if not ResourceLoader.exists(CHARACTER_INSTANCES_PATH):
		GameLogger.warn("Config", "CharacterInstances.tres not found at %s, using empty" % CHARACTER_INSTANCES_PATH)
		_character_table = CharacterInstanceTable.new()
		return
	var res: Resource = load(CHARACTER_INSTANCES_PATH)
	if res is CharacterInstanceTable:
		_character_table = res
	else:
		GameLogger.error("Config", "Resource at %s is not CharacterInstanceTable" % CHARACTER_INSTANCES_PATH)
		_character_table = CharacterInstanceTable.new()


func _load_growth_tables() -> void:
	var dir := DirAccess.open(GROWTH_TABLES_DIR)
	if dir == null:
		GameLogger.warn("Config", "Growth tables dir not found: %s" % GROWTH_TABLES_DIR)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and (name.ends_with(".tres") or name.ends_with(".res")):
			var path: String = GROWTH_TABLES_DIR + "/" + name
			var res: Resource = load(path)
			if res is AttributeGrowthTable:
				var table: AttributeGrowthTable = res
				if table.id == &"":
					GameLogger.warn("Config", "AttributeGrowthTable at %s has empty id, using filename" % path)
					table.id = StringName(name.get_basename())
				_growth_tables[table.id] = table
			else:
				GameLogger.warn("Config", "Skip non-AttributeGrowthTable resource: %s" % path)
		name = dir.get_next()
	dir.list_dir_end()


func _load_skill_damage_table() -> void:
	if not ResourceLoader.exists(SKILL_DAMAGE_TABLE_PATH):
		GameLogger.warn("Config", "SkillDamageTable.tres not found at %s, using empty" % SKILL_DAMAGE_TABLE_PATH)
		_skill_damage_table = SkillDamageTable.new()
		return
	var res: Resource = load(SKILL_DAMAGE_TABLE_PATH)
	if res is SkillDamageTable:
		_skill_damage_table = res
	else:
		GameLogger.error("Config", "Resource at %s is not SkillDamageTable" % SKILL_DAMAGE_TABLE_PATH)
		_skill_damage_table = SkillDamageTable.new()


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
