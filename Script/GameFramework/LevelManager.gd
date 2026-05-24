## 关卡管理器（Autoload 单例）。
##
## 异步切关流程：
##   1. 拒绝同时多次切关（[member _is_loading]）
##   2. emit [signal EventBus.level_loading_started](from, to)
##   3. HUDStateMachine.change_state(LEVEL_TRANSITION) → 自动 push Cutscene InputContext
##   4. LoadingScreenWidget.begin_fade_out → 等 fade 完成
##   5. AudioManager.play_bgm（如 LevelDef.bgm 不为空）
##   6. get_tree().change_scene_to_packed → 等下一帧
##   7. 把玩家 teleport 到 LevelSpawnMarker（按 spawn_marker_id 找 group "level_spawn"）
##   8. emit EventBus.level_changed
##   9. LoadingScreenWidget.begin_fade_in
##   10. HUDStateMachine.change_state(GAMEPLAY) → 自动 pop InputContext
##   11. emit EventBus.level_loading_finished
##
## 跨关持久数据：
##   - GameInstance（Autoload）：dialogue_vars / quest_states / 玩家档案
##   - InventoryComponent / ASC：随玩家场景实例随场景重建（D5 SaveSystem 接入后从存档还原）
##   - 当前阶段：Player 是关卡内节点，切关会重建。**位置**通过 LevelSpawnMarker 重置；
##     **属性 / 库存**目前会重置（D5 落地后自动续上）。
extends Node


## 当前关卡 id（GameInstance 持久层；ConfigCenter / Quest 等查询用）。
var current_level_id: StringName = &""

## 加载中标志（避免重复触发）。
var _is_loading: bool = false


func _ready() -> void:
	GameLogger.info("Level", "LevelManager ready")


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 异步加载指定关卡。重复调用在 loading 期间直接 return。
func load_level(level: LevelDef) -> void:
	if _is_loading:
		GameLogger.warn("Level", "load_level: already loading, ignored")
		return
	if level == null or level.scene == null:
		GameLogger.warn("Level", "load_level: invalid LevelDef")
		return
	_is_loading = true
	_run_load(level)


## 同步重载当前场景（用于死亡复活等快速重置）。
func reload_current() -> void:
	get_tree().reload_current_scene()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _run_load(level: LevelDef) -> void:
	var from_id: StringName = current_level_id
	var to_id: StringName = level.level_id
	GameLogger.info("Level", "loading: %s -> %s" % [from_id, to_id])
	EventBus.level_loading_started.emit(from_id, to_id)

	# 1. 切到 LEVEL_TRANSITION 状态（屏蔽输入；R-ARCH-03 直访 Autoload + R-CODE-02 强类型枚举）
	HUDStateMachine.change_state(HUDStateMachine.State.LEVEL_TRANSITION)

	# 2. fade out
	var loading := _get_loading_widget()
	if loading != null:
		var title: String = "正在加载...%s" % level.display_name
		await loading.begin_fade_out(level.fade_out_seconds, level.fade_color, title, level.loading_tip)
	else:
		# 容错：等一帧也比直切好（loading widget 可能还没注册）
		await get_tree().process_frame

	# 3. BGM 切（fade out 期间切 BGM 听感最好）
	if level.bgm != null:
		AudioManager.play_bgm(level.bgm, 0.4)

	# 4. 切场景（注意：本调用会延迟到下一帧切换）
	var err := get_tree().change_scene_to_packed(level.scene)
	if err != OK:
		GameLogger.error("Level", "change_scene_to_packed failed: %s" % err)
		_is_loading = false
		return

	# 5. 等场景就绪（change_scene_to_packed 是 deferred，至少等 2 帧）
	await get_tree().process_frame
	await get_tree().process_frame

	current_level_id = to_id

	# 6. 把玩家 teleport 到 spawn marker
	if level.spawn_marker_id != &"":
		_teleport_player_to_marker(level.spawn_marker_id)

	EventBus.level_changed.emit(to_id)

	# A3：关卡初始化时批量接取任务（M12；QuestSystem 自动推进 sub_id=1）
	if level.init_quest_ids.size() > 0:
		var quest_arr: Array = []
		for qid in level.init_quest_ids:
			quest_arr.append(int(qid))
		QuestSystem.bulk_accept(quest_arr)

	# 7. fade in
	if loading != null:
		await loading.begin_fade_in(level.fade_in_seconds)

	# 8. 切回 GAMEPLAY
	HUDStateMachine.change_state(HUDStateMachine.State.GAMEPLAY)

	EventBus.level_loading_finished.emit(to_id)
	_is_loading = false
	GameLogger.info("Level", "loaded: %s" % to_id)


## 查找 LoadingScreenWidget。优先 group &"loading_screen"，回退到 HUDManager L6_Loading 层。
func _get_loading_widget() -> LoadingScreenWidget:
	# 优先：group 查找（LoadingScreenWidget 自身 add_to_group）
	for n in get_tree().get_nodes_in_group(&"loading_screen"):
		if n is LoadingScreenWidget:
			return n
	# 回退：按 class 在 L6_Loading 层下找（widget 还没 add_to_group 的早期场景）
	var layer: Node = HUDManager.get_layer(&"L6_Loading")
	if layer == null:
		return null
	return NodeFinder.find_first_child_of_type(layer, LoadingScreenWidget) as LoadingScreenWidget


func _teleport_player_to_marker(spawn_id: StringName) -> void:
	var marker: LevelSpawnMarker = null
	for n in get_tree().get_nodes_in_group(&"level_spawn"):
		if n is LevelSpawnMarker and (n as LevelSpawnMarker).spawn_id == spawn_id:
			marker = n
			break
	if marker == null:
		GameLogger.warn("Level", "spawn marker not found: %s" % spawn_id)
		return
	# 找 player（R-CHAR-01：用 PlayerLocator 强类型）
	var player := PlayerLocator.find_player(self)
	if player == null:
		GameLogger.warn("Level", "player not found for teleport")
		return
	player.global_position = marker.global_position
	# 朝向：保留 marker 自身 rotation（如果有）
	if marker.global_rotation != Vector3.ZERO:
		player.global_rotation.y = marker.global_rotation.y
	GameLogger.info("Level", "player teleported to %s @ %s" % [spawn_id, str(marker.global_position)])
