## 游戏全局实例（Autoload 单例）。
##
## 职责：
##   1. 跨场景持久数据（玩家档案、运行时配置）
##   2. 顶层游戏状态机：BOOT → MENU → PLAYING ⇄ PAUSED / GAME_OVER
##   3. M2 起：在启动时加载 GameplayTagRegistry
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

## 跨场景持久数据。M2+ 玩家档案、当前金币等放这里。
var persistent_data: Dictionary = {}

## 全局 GameplayTag 注册表（M2 起加载）。
var tag_registry: GameplayTagRegistry = null

## M7：技能时间轴播放器（全局单例语义；挂在自身子节点 SkillTimelinePlayerHost）。
## 通过 GameInstance.skill_timeline_player.play(...) 调用。
var skill_timeline_player: SkillTimelinePlayerHost = null

## M7：冻帧主机（挂在自身子节点 HitStopHost）。
var hit_stop_host: HitStopHost = null

## M8：特效生成器（挂在自身子节点 VFXSpawner）。
var vfx_spawner: VFXSpawner = null

const TAG_REGISTRY_PATH := "res://Data/Tags/GameplayTags.tres"


func _ready() -> void:
	# 暂停期间仍处理：让本 Autoload 能在游戏暂停时仍响应 ESC 切回
	process_mode = Node.PROCESS_MODE_ALWAYS

	GameLogger.info("Core", "GameInstance ready, state=%s" % _state_name(current_state))
	_load_tag_registry()
	_setup_skill_subsystems()
	# M1 阶段：启动后立即进入 MENU；M3 起 MainScene 进入 PLAYING。
	change_state(GameState.MENU)


## M7：实例化技能子系统主机为本 Autoload 的子节点。
func _setup_skill_subsystems() -> void:
	skill_timeline_player = SkillTimelinePlayerHost.new()
	skill_timeline_player.name = "SkillTimelinePlayerHost"
	add_child(skill_timeline_player)

	hit_stop_host = HitStopHost.new()
	hit_stop_host.name = "HitStopHost"
	add_child(hit_stop_host)

	# M8：特效生成器
	vfx_spawner = VFXSpawner.new()
	vfx_spawner.name = "VFXSpawner"
	add_child(vfx_spawner)


## 接管全局 ESC 暂停：本节点 ALWAYS 处理。
## 玩家/UI 等节点保持 INHERIT 走 paused 流程。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
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
	if not ResourceLoader.exists(TAG_REGISTRY_PATH):
		GameLogger.warn("GAS", "GameplayTagRegistry not found at %s, will use empty registry" % TAG_REGISTRY_PATH)
		tag_registry = GameplayTagRegistry.new()
		return
	tag_registry = load(TAG_REGISTRY_PATH) as GameplayTagRegistry
	if tag_registry == null:
		GameLogger.error("GAS", "Failed to load GameplayTagRegistry as GameplayTagRegistry type")
		tag_registry = GameplayTagRegistry.new()
		return
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
