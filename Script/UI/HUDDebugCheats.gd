## HUD 调试快捷键（仅 Debug Build）。
##
## 通过派发 EventBus 信号触发各 widget，便于美术 / 策划独立预览：
##   - F1  → ToastWidget（"自动存档..."）
##   - F2  → 派发 hud_big_banner_requested(&"victory")
##   - F3  → 派发 player_died → BigBanner "YOU DIED"
##   - F4  → 派发 hud_big_banner_requested(&"level_up") + 模拟连续 5 个 combo
##   - F5  → 派发 pickup_displayed × 3（金币 / 草药 / 钥匙）
##   - F6  → 派发 enemy_died（虚拟 enemy）+ quest_objective_changed
##   - F10 → 启动测试对话（DialogueRunner.start(1001, 1) — 村长接任务对话）
##   - F12 → 强制结束当前对话（DialogueRunner.force_end）
##   - Shift+F7 → 强制完成 quest_id=1 当前 active 步骤（任务系统调试）
##   - Shift+L  → 切到 BossRush 布局（HUDLayout 热切验证）
##   - Shift+O  → 切回 Default 布局
##   - F9       → 给玩家 inventory.add_by_id(5, 1)（测试装备滚字 / Phase 1 验证）
##   - Shift+F9 → LootSpawner.dispatch(drop_table_id=1)（掉落系统验证：Weighted 抽 1 + Random 独立判定）
##   - Shift+X  → 给玩家 +25 经验（走 LevelComponent 完整升级链路）
##   - Shift+Z  → 给玩家 +1000 经验（一次喂满，验证多级跨越 + 满级钳制）
##   - F8       → **PR1 验收**：玩家 SuperArmor 切换（Combat.SuperArmor tag on/off）
##
## 注：避开 Godot 编辑器内置快捷键 F5(运行)/F6/F7/F8(停止)/F11(全屏)。
##     本 Autoload 在 release 构建中 _ready 直接退出（debug_only）。
extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		set_process_unhandled_input(false)
		queue_free()
		return
	GameLogger.info("UI", "HUDDebugCheats ready (F1~F6/F10/F12 enabled)")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = (event as InputEventKey).keycode
	match key:
		KEY_F1:
			EventBus.hud_toast_requested.emit("自动存档完成", 2.0)
		KEY_F2:
			EventBus.hud_big_banner_requested.emit(&"victory")
		KEY_F3:
			EventBus.player_died.emit()
		KEY_F4:
			EventBus.hud_big_banner_requested.emit(&"level_up")
			# 模拟连续 5 hit
			for i in range(5):
				EventBus.combo_changed.emit(i + 1)
		KEY_F5:
			if (event as InputEventKey).shift_pressed:
				# Shift+F5 切到 Boss 房
				if LevelManager != null:
					var lvl: Resource = load("res://Data/Levels/LevelDef_BossRoom_01.tres")
					if lvl != null:
						LevelManager.load_level(lvl)
			else:
				EventBus.pickup_displayed.emit(&"金币", 5)
				EventBus.pickup_displayed.emit(&"草药", 1)
				EventBus.pickup_displayed.emit(&"钥匙", 1)
		KEY_F6:
			if (event as InputEventKey).shift_pressed:
				# Shift+F6 切回 TestArena
				if LevelManager != null:
					var lvl: Resource = load("res://Data/Levels/LevelDef_TestArena.tres")
					if lvl != null:
						LevelManager.load_level(lvl)
			else:
				# 虚拟敌人对象（KillFeed 用 name；用 set_meta 注入 display_name）
				var fake := Node.new()
				fake.name = "TestEnemy"
				fake.set_meta(&"display_name", "测试史莱姆")
				get_tree().root.add_child(fake)
				EventBus.enemy_died.emit(fake)
				fake.queue_free()
				# Quest mock：派发 quest_step_progress（M12 新签名）
				EventBus.quest_step_progress.emit(1, 2, 1, 3)
		KEY_F10:
			# 启动测试对话（M12 数据驱动：graph_id=1001 来自 Dialogue.csv）
			if DialogueRunner != null:
				DialogueRunner.start(1001, 1)  # graph_id=1001, npc_id=1（村长）
		KEY_F12:
			# 强制结束当前对话
			if DialogueRunner != null and DialogueRunner.has_method(&"force_end"):
				DialogueRunner.force_end()
		KEY_F8:
			# Shift+F8 GM：bulk_accept quest_id=1（M12 任务系统测试入口；模拟关卡初始化批量接取）
			if (event as InputEventKey).shift_pressed:
				if QuestSystem != null:
					QuestSystem.bulk_accept([1])
			else:
				# PR1 验收：玩家 SuperArmor 切换
				_toggle_player_super_armor()
		KEY_F7:
			# Shift+F7 强制完成 quest_id=1 的当前 active 步骤（GM 命令）
			if (event as InputEventKey).shift_pressed:
				if QuestSystem != null:
					QuestSystem.complete_current_step(1)
		KEY_L:
			# Shift+L 切到 BossRush 布局
			if (event as InputEventKey).shift_pressed:
				_switch_hud_layout("res://Data/Config/HUDLayout_BossRush.tres", "BossRush")
		KEY_O:
			# Shift+O 切回 Default 布局
			if (event as InputEventKey).shift_pressed:
				_switch_hud_layout("res://Data/Config/HUDLayout_Default.tres", "Default")
		KEY_F9:
			# F9 给玩家 add_by_id(5, 1) —— 道具系统 Phase 1 滚字验证
			# Shift+F9 跑一次 Drop_Rule[1] 抽样并发放（Loot 系统验证）
			if (event as InputEventKey).shift_pressed:
				_debug_dispatch_loot(1)
			else:
				_debug_add_item_by_id(5, 1)
		KEY_X:
			# Shift+X 给玩家 +25 经验（走 LevelComponent 完整升级链路）
			if (event as InputEventKey).shift_pressed:
				_debug_add_experience(25)
		KEY_Z:
			# Shift+Z 给玩家 +1000 经验（验证多级跨越 + 满级钳制）
			if (event as InputEventKey).shift_pressed:
				_debug_add_experience(1000)


## 调试：给当前玩家的 LevelComponent 喂经验。
func _debug_add_experience(amount: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var players: Array[Node] = tree.get_nodes_in_group(&"player")
	if players.is_empty():
		GameLogger.warn("UI", "Shift+X/Z add_experience: no player in scene")
		return
	var player: Node = players[0]
	var lvl: Node = player.get_node_or_null(^"LevelComponent")
	if lvl == null or not lvl.has_method(&"add_experience"):
		GameLogger.warn("UI", "Shift+X/Z add_experience: LevelComponent not found on %s" % player.name)
		return
	lvl.call(&"add_experience", amount)
	EventBus.hud_toast_requested.emit("+%d EXP" % amount, 1.2)


## 调试：给当前玩家的 InventoryComponent 喂一个道具（触发 fragment.on_instance_created → 滚字）。
func _debug_add_item_by_id(def_id: int, count: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var players: Array[Node] = tree.get_nodes_in_group(&"player")
	if players.is_empty():
		GameLogger.warn("UI", "F9 add_by_id: no player in scene")
		return
	var player: Node = players[0]
	var inv: Node = player.get_node_or_null(^"InventoryComponent")
	if inv == null or not inv.has_method(&"add_by_id"):
		GameLogger.warn("UI", "F9 add_by_id: InventoryComponent not found on %s" % player.name)
		return
	var added: int = inv.call(&"add_by_id", def_id, count)
	GameLogger.info("UI", "F9 add_by_id(%d, %d) -> added=%d" % [def_id, count, added])
	EventBus.hud_toast_requested.emit("add_by_id(%d,%d) → %d" % [def_id, count, added], 1.5)


## 调试：跑一次 Drop_Rule[drop_table_id] 抽样并发放给玩家。
##
## 用于验证：
##   - Weighted 池每轮抽 1 条（多次按 Shift+F9 应在 id=1 的两条 Weighted 间分布）
##   - Random 每条独立判定（id=1 现无 Random 子行；改 drop_table_id=2 / 3 可单独测）
func _debug_dispatch_loot(drop_table_id: int) -> void:
	var granted: int = LootSpawner.dispatch(drop_table_id, self)
	GameLogger.info("UI", "Shift+F9 LootSpawner.dispatch(%d) -> granted_entries=%d" % [drop_table_id, granted])
	EventBus.hud_toast_requested.emit("Loot[%d] → %d entries" % [drop_table_id, granted], 1.5)


## 切换 HUD 布局。复用 UIExtensionSubsystem.reload_layout。
func _switch_hud_layout(path: String, label: String) -> void:
	if not ResourceLoader.exists(path):
		GameLogger.warn("UI", "switch HUD layout: not found %s" % path)
		return
	var ues: Node = Engine.get_main_loop().root.get_node_or_null(^"UIExtensionSubsystem")
	if ues == null or not ues.has_method(&"reload_layout"):
		return
	var layout: Resource = load(path)
	ues.reload_layout(layout)
	EventBus.hud_toast_requested.emit("HUD 布局: %s" % label, 1.5)
	GameLogger.info("UI", "HUD layout switched -> %s" % label)


## PR1 验收：玩家 SuperArmor 切换。
##
## 给玩家 ASC 加/移除 [code]Combat.SuperArmor[/code] tag —— [method
## AbilitySystemComponent.get_current_poise_level] 持有时返回 INT_MAX，任何 hit_poise 都打不断。
##
## 使用流程：
## 1. 进入 TestArena，正常被 Slime 打几下感受打断
## 2. 按 F8 → toast "SuperArmor ON"
## 3. 再被 Slime 打 → 不再被打断（控制台无 [DBG] Player 被 ... 打断）
## 4. 按 F8 → toast "SuperArmor OFF"
func _toggle_player_super_armor() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var players: Array[Node] = tree.get_nodes_in_group(&"player")
	if players.is_empty():
		GameLogger.warn("UI", "F8 SuperArmor: no player in scene")
		return
	var player: Node = players[0]
	var asc: AbilitySystemComponent = player.get(&"asc") as AbilitySystemComponent
	if asc == null:
		GameLogger.warn("UI", "F8 SuperArmor: player has no asc")
		return
	if asc.has_tag(&"Combat.SuperArmor"):
		asc.remove_tag(&"Combat.SuperArmor")
		EventBus.hud_toast_requested.emit("SuperArmor OFF", 1.5)
		GameLogger.info("UI", "F8 SuperArmor OFF")
	else:
		asc.add_tag(&"Combat.SuperArmor")
		EventBus.hud_toast_requested.emit("SuperArmor ON", 1.5)
		GameLogger.info("UI", "F8 SuperArmor ON")
