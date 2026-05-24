## 道具系统测试关卡（Phase 1 + 2 + 4 + 撒散掉落）。
##
## 用途：
##   - Phase 1 装备：拾取 → 滚字 → 装备 → 属性变化 → 卸下回滚 → 再装备词条不变
##   - Phase 2 货币：拾取金币 / 经验 → CurrencyManager.add → HUD 货币栏数字增长
##   - Phase 4 UI：背包品质边框 / Tooltip 词条详情 / 拾取飘字 / 装备对比卡
##   - Phase 3 撒散：K 键模拟敌人死亡 → LootSpawner.dispatch_to_ground 在玩家面前撒散战利品
##
## 不含敌人 / 对话 / 任务 / Boss，纯道具流程。
##
## 操作指引（HUD InfoLabel 显示）：
##   ■ Phase 1+2：
##     1. 走到金色方块 → 拾取测试装备（id=5）
##     2. 走上金色硬币 / 蓝色方块 → 加货币
##     3. Tab 打开背包 → 双击装备 / 右键卸下；F1 看属性
##   ■ Phase 3+4：
##     4. K 键 → 在玩家面前撒落 drop_table=1 的战利品（金币 + 经验）
##     5. 拾取后右下飘字 + 拾取装备时中间弹对比卡
##   ■ R 键：reload 整个场景（连续测试）
extends Node3D


@onready var camera: CameraRig = $CameraRig as CameraRig
@onready var hud: HUD = $HUDLayer/HUD as HUD
@onready var inventory_ui: InventoryUI = $HUDLayer/InventoryUI as InventoryUI
@onready var info_label: Label = $HUDLayer/InfoLabel as Label

## 测试用 drop_table_id（Drop_Rule.csv 中含 exp + coin 的那张表）。
const TEST_DROP_TABLE_ID: int = 1

var _player: BaseCharacter = null


func _ready() -> void:
	GameLogger.info("Core", "ItemTestArena ready")
	GameInstance.change_state(GameInstance.GameState.PLAYING)

	_player = $Player as BaseCharacter
	if camera != null and _player != null:
		camera.target = _player
	if hud != null:
		hud.player = _player

	# 绑定 InventoryUI 到玩家
	if inventory_ui != null and _player != null:
		inventory_ui.inventory = _player.get_node_or_null("InventoryComponent") as InventoryComponent
		inventory_ui.equipment = _player.get_node_or_null("EquipmentComponent") as EquipmentComponent
		inventory_ui.refresh_all()

	EventBus.player_input_action_pressed.connect(_on_input_action_pressed)
	EventBus.item_added.connect(_on_item_added)

	if info_label != null:
		info_label.text = (
			"[道具系统测试场]\n\n"
			+ "■ Phase 1 装备测试：\n"
			+ "  走上金色方块 → 拾取测试装备 (id=5)\n"
			+ "  Tab → 背包 / 双击装 / 右键卸\n"
			+ "  F1 → 属性面板\n\n"
			+ "■ Phase 2 货币测试：\n"
			+ "  走上金色硬币 → +50 金币\n"
			+ "  走上蓝色方块 → +25 经验\n"
			+ "  右上角货币栏数字增长\n\n"
			+ "■ Phase 3 撒散掉落：\n"
			+ "  K 键 → 在玩家前方撒散战利品\n\n"
			+ "■ Phase 4 UI：\n"
			+ "  背包品质边框 / Tooltip / 飘字 / 对比卡\n\n"
			+ "■ R 键 → 重新加载场景"
		)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).keycode
		if key == KEY_R:
			_reload_scene()
		elif key == KEY_K:
			_simulate_loot_drop()


func _on_input_action_pressed(action: StringName) -> void:
	if action == &"ui_panel_build" and inventory_ui != null:
		inventory_ui.toggle()


func _on_item_added(_owner: Node, def: ItemDefinition, added: int) -> void:
	if def == null:
		return
	GameLogger.info("Core", "[ItemTestArena] picked up: %s (id=%d) +%d" % [def.display_name, def.item_id, added])


func _reload_scene() -> void:
	GameLogger.info("Core", "[ItemTestArena] reloading scene (R pressed)")
	get_tree().reload_current_scene()


## K 键 → 模拟敌人死亡，在玩家面前 2m 处撒散 drop_table=1 的战利品。
func _simulate_loot_drop() -> void:
	if not is_instance_valid(_player):
		return
	# 玩家面朝方向 2m 位置（Z 轴正向，避开玩家身位）
	var drop_pos: Vector3 = _player.global_position + Vector3(0, 0, 2.0)
	var spawned: int = LootSpawner.dispatch_to_ground(TEST_DROP_TABLE_ID, drop_pos, self)
	GameLogger.info("Core", "[ItemTestArena] simulated loot drop, table=%d → %d items at %s" % [
		TEST_DROP_TABLE_ID, spawned, str(drop_pos),
	])
