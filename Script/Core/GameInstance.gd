## 游戏全局实例（Autoload 单例）。
##
## 职责：
##   1. 跨场景持久数据（玩家档案、运行时配置）
##   2. 顶层游戏状态机：BOOT → MENU → PLAYING ⇄ PAUSED / GAME_OVER
##   3. 启动时加载 GameplayTagRegistry
##   4. 实例化技能子系统主机（SkillTimelinePlayerHost / HitStopHost / VFXSpawner）
##
## 状态切换通过 [method change_state]，会广播 [signal EventBus.game_state_changed]。
extends Node

enum GameState {
	BOOT,
	MENU,
	PLAYING,
	PAUSED,
	GAME_OVER,
}

## 当前游戏状态（只读，外部请用 change_state 修改）。
var current_state: int = GameState.BOOT

## 跨场景持久数据（玩家档案、当前金币等）。
var persistent_data: Dictionary = {}

## 全局 GameplayTag 注册表。
var tag_registry: GameplayTagRegistry = null

## 技能时间轴播放器（全局单例语义；挂在自身子节点 SkillTimelinePlayerHost）。
## 通过 GameInstance.skill_timeline_player.play(...) 调用。
var skill_timeline_player: SkillTimelinePlayerHost = null

## 冻帧主机（挂在自身子节点 HitStopHost）。
var hit_stop_host: HitStopHost = null

## 特效生成器（挂在自身子节点 VFXSpawner）。
var vfx_spawner: VFXSpawner = null

## 表现层 Cue 派发中心（挂在自身子节点 CueManager）。
## 通过 GameInstance.cue_manager.execute_cue(...) 调用。
var cue_manager: CueManager = null

## 战斗状态服务（挂在自身子节点 CombatStateService）。
## 唯一发射 [signal EventBus.combat_state_changed] 的源；HUD-AttackTimer 等订阅本信号。
var combat_state_service: CombatStateService = null

## 货币管理器（挂在自身子节点 CurrencyManager）。
## 唯一发射 [signal EventBus.currency_changed] 的源；CurrencyBarWidget / 商店 UI 等订阅本信号。
## 接入：[Fragment_Currency.handle_inventory_add] → currency_manager.add(...)。
var currency_manager: CurrencyManager = null

## 对话全局变量（M11）。key: StringName → value: Variant；参与存档（D5 SaveSystem 落地后自动续上）。
## 业务侧请用 [method set_dialogue_var] / [method get_dialogue_var] 读写；DialogueExpr 评估
## `Var.X` 时会查本表。
var dialogue_vars: Dictionary = {}

## 任务运行时状态（M11 任务系统）。
## key: quest_id (StringName)
## value: Dictionary {
##   "state": &"active" / &"completed" / &"abandoned",
##   "objectives": { objective_id -> current_count: int },
##   "started_at": int (unix ms),
## }
## 参与存档（D5 SaveSystem 落地后自动续上）。
## 业务侧请用 QuestSystem 的 API 读写，不要直接改本表。
var quest_states: Dictionary = {}

const TAG_REGISTRY_PATH := "res://Data/Tags/GameplayTags.tres"


func _ready() -> void:
	# 暂停期间仍处理：让本 Autoload 能在游戏暂停时仍响应 ESC 切回
	process_mode = Node.PROCESS_MODE_ALWAYS

	GameLogger.info("Core", "GameInstance ready, state=%s" % _state_name(current_state))
	_load_tag_registry()
	_setup_skill_subsystems()
	# 启动后立即进入 MENU；MainScene 进入后切到 PLAYING。
	change_state(GameState.MENU)


## 实例化技能子系统主机为本 Autoload 的子节点。
func _setup_skill_subsystems() -> void:
	skill_timeline_player = SkillTimelinePlayerHost.new()
	skill_timeline_player.name = "SkillTimelinePlayerHost"
	add_child(skill_timeline_player)

	hit_stop_host = HitStopHost.new()
	hit_stop_host.name = "HitStopHost"
	add_child(hit_stop_host)

	vfx_spawner = VFXSpawner.new()
	vfx_spawner.name = "VFXSpawner"
	add_child(vfx_spawner)

	# CueManager 收编 cue 派发（挂 GameInstance 子节点，不占 Autoload 名额）
	cue_manager = CueManager.new()
	cue_manager.name = "CueManager"
	add_child(cue_manager)

	# CombatStateService 战斗状态服务（同上，GameInstance 子节点）
	combat_state_service = CombatStateService.new()
	combat_state_service.name = "CombatStateService"
	add_child(combat_state_service)

	# CurrencyManager 货币管理器（同上，GameInstance 子节点；R-ARCH-02 不增 Autoload）
	currency_manager = CurrencyManager.new()
	currency_manager.name = "CurrencyManager"
	add_child(currency_manager)

	# F1 调试 widget（27+ 属性面板）— 挂自身 CanvasLayer 子节点，全场景可用
	_setup_attribute_debug_widget()


## 接管全局 ESC 暂停：本节点 ALWAYS 处理。
## 玩家/UI 等节点保持 INHERIT 走 paused 流程。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_pause"):
		toggle_pause()
	# GAME_OVER 时按 R 重开：因为本 Autoload ALWAYS，paused 也能收到
	elif current_state == GameState.GAME_OVER:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
			GameLogger.info("Core", "Restart requested (R key)")
			# 重置 paused 让 reload 后场景正常
			get_tree().paused = false
			change_state(GameState.PLAYING)
			get_tree().reload_current_scene()


func toggle_pause() -> void:
	if current_state == GameState.PLAYING:
		change_state(GameState.PAUSED)
		get_tree().paused = true
	elif current_state == GameState.PAUSED:
		change_state(GameState.PLAYING)
		get_tree().paused = false


func _load_tag_registry() -> void:
	# R-CODE-01：tag registry 是必备资源，缺失 / 类型错误直接 assert 崩
	assert(ResourceLoader.exists(TAG_REGISTRY_PATH),
		"GameInstance: GameplayTagRegistry missing at %s" % TAG_REGISTRY_PATH)
	tag_registry = load(TAG_REGISTRY_PATH) as GameplayTagRegistry
	assert(tag_registry != null,
		"GameInstance: failed to load GameplayTagRegistry at %s" % TAG_REGISTRY_PATH)
	GameLogger.info("GAS", "GameplayTagRegistry loaded, %d tags registered" % tag_registry.tags.size())


## 切换到新状态，广播 game_state_changed 信号。
func change_state(new_state: int) -> void:
	if new_state == current_state:
		return
	var old_state := current_state
	current_state = new_state
	GameLogger.info("Core", "GameInstance state: %s -> %s" % [_state_name(old_state), _state_name(new_state)])
	EventBus.game_state_changed.emit(old_state, new_state)


## 返回当前状态名（调试用）。
func get_state_name() -> String:
	return _state_name(current_state)


func _state_name(s: int) -> String:
	match s:
		GameState.BOOT: return "BOOT"
		GameState.MENU: return "MENU"
		GameState.PLAYING: return "PLAYING"
		GameState.PAUSED: return "PAUSED"
		GameState.GAME_OVER: return "GAME_OVER"
		_: return "?"


# ─────────────────────────────────────────────────────────────
# 对话变量 API（M11；供 DialogueRunner / Handler / 文本插值用）
# ─────────────────────────────────────────────────────────────

## 设置对话变量。value 支持 int / float / bool / String / StringName。
func set_dialogue_var(key: StringName, value: Variant) -> void:
	dialogue_vars[key] = value


## 读取对话变量。不存在时返回 default。
func get_dialogue_var(key: StringName, default_value: Variant = null) -> Variant:
	return dialogue_vars.get(key, default_value)


## 是否存在对话变量。
func has_dialogue_var(key: StringName) -> bool:
	return dialogue_vars.has(key)


# ─────────────────────────────────────────────────────────────
# F1 调试 widget（27+ 属性面板）
# ─────────────────────────────────────────────────────────────

## 创建 AttributeDebugWidget 挂在 GameInstance 自身 CanvasLayer 子节点下，
## 这样不依赖任何具体场景，F1 全场景可用。
func _setup_attribute_debug_widget() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "DebugLayer"
	canvas.layer = 100  # 高于普通 HUD（HUD 一般 1-10）
	add_child(canvas)

	var widget: AttributeDebugWidget = AttributeDebugWidget.new()
	widget.name = "AttributeDebugWidget"
	canvas.add_child(widget)
	GameLogger.info("Core", "AttributeDebugWidget ready (F1 to toggle)")
