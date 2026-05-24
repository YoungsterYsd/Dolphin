## 战利品分发工具（静态）。
##
## 提供两种发放模式：
##   - [method dispatch] / [method grant] · **直接进背包**（极简 ARPG / 任务奖励）
##   - [method dispatch_to_ground] / [method grant_to_ground] · **撒散到地面**（标准 ARPG 体验）
##
## **路由规则**（与 [InventoryComponent.add_by_id] 一致）：
##   - Currency 类（Stack=0）→ Fragment_Currency.intercepts_inventory_add 拦截入 CurrencyManager
##   - 装备类（含 Fragment_Equip）→ 进入装备槽，**进入背包时滚字**
##   - 简单堆叠类 → 合并到已有同 def 槽
##
## **撒散模式说明**（B Phase）：
##   - 在 [param world_pos] 周围半径 [member SCATTER_RADIUS] 内随机抛 PickupArea
##   - 每个 PickupArea 用代码组装（无独立 .tscn），按 def 类型决定外形：
##       Currency → 金/蓝小立方（按 def_id 区分色）
##       Equip    → 大立方 + 品质染色
##       其他     → 灰色立方
##   - 玩家走过去碰到自动 add_by_id（与原 PickupArea 行为一致）
##
## 失败语义（R-CODE-01）：
##   - drop_table_id <= 0：返回 0（业务侧用 0 表示"不掉落"，不视为错误）
##   - 玩家不存在：返回 0（warn；直接进背包模式）
##   - 撒散模式 parent 不存在：返回 0（warn）
##   - 抽样得到的 item_id 在 Item_Data 表里找不到：assert 崩（配置错误）
class_name LootSpawner
extends RefCounted

## 撒散半径（米）。
const SCATTER_RADIUS: float = 1.5

## 撒散竖直抛起初速（视觉用，落地后由 Area3D 静止）。
const SCATTER_HEIGHT_OFFSET: float = 0.3


# ─────────────────────────────────────────────────────────────
# 模式 A · 直接进背包（极简）
# ─────────────────────────────────────────────────────────────


## 跑一次掉落分发，**直接进背包**。返回实际进入背包的条目数。
##
## - [param drop_table_id]：[code]Drop_Rule.id[/code]；<= 0 直接返回 0。
## - [param caller]：用于查找 SceneTree 的上下文节点。
static func dispatch(drop_table_id: int, caller: Node) -> int:
	if drop_table_id <= 0:
		return 0
	var drops: Array = LootRoller.roll(drop_table_id)
	if drops.is_empty():
		return 0
	return _grant_to_player(drops, caller)


## 直接发放一组 [code]{item_id, count}[/code]（跳过 LootRoller，给单测 / cheat 用）。
static func grant(drops: Array, caller: Node) -> int:
	if drops.is_empty():
		return 0
	return _grant_to_player(drops, caller)


# ─────────────────────────────────────────────────────────────
# 模式 B · 撒散到地面（ARPG 标准）
# ─────────────────────────────────────────────────────────────


## 跑一次掉落，把每个 entry 都生成一个 PickupArea 撒在 [param world_pos] 周围。
## 玩家走过去自动拾取。返回撒出的 PickupArea 数量。
##
## - [param drop_table_id]：[code]Drop_Rule.id[/code]
## - [param world_pos]：撒落中心（一般传敌人死亡时的 global_position）
## - [param parent]：父节点（敌人 free 后 PickupArea 不能挂敌人，必须挂关卡 root）
static func dispatch_to_ground(drop_table_id: int, world_pos: Vector3, parent: Node) -> int:
	if drop_table_id <= 0:
		return 0
	var drops: Array = LootRoller.roll(drop_table_id)
	if drops.is_empty():
		return 0
	return grant_to_ground(drops, world_pos, parent)


## 把指定 drops 撒到 [param world_pos] 周围（跳过 LootRoller，给 cheat / 测试用）。
static func grant_to_ground(drops: Array, world_pos: Vector3, parent: Node) -> int:
	if drops.is_empty():
		return 0
	if parent == null or not is_instance_valid(parent):
		GameLogger.warn("Loot", "LootSpawner.grant_to_ground: parent invalid, drop %d entries skipped" % drops.size())
		return 0

	var spawned: int = 0
	for d in drops:
		var item_id: int = int(d.get("item_id", 0))
		var count: int = int(d.get("count", 0))
		if item_id <= 0 or count <= 0:
			continue
		var def: ItemDefinition = ConfigCenter.get_item_def(item_id)
		if def == null:
			assert(false, "LootSpawner.grant_to_ground: item_id=%d not in Item_Data" % item_id)
			continue
		var area := _build_pickup_area(def, item_id, count)
		parent.add_child(area)
		# 半径内随机散落（XZ 平面）
		var angle: float = randf() * TAU
		var dist: float = randf() * SCATTER_RADIUS
		var offset := Vector3(cos(angle) * dist, SCATTER_HEIGHT_OFFSET, sin(angle) * dist)
		area.global_position = world_pos + offset
		spawned += 1
		GameLogger.info("Loot", "LootSpawner: scattered item_id=%d count=%d at %s" % [item_id, count, str(area.global_position)])
	return spawned


# ─────────────────────────────────────────────────────────────
# 内部 · 直接进背包
# ─────────────────────────────────────────────────────────────


static func _grant_to_player(drops: Array, caller: Node) -> int:
	var player: PlayerCharacter = PlayerLocator.find_player(caller)
	if player == null:
		# 全局兜底（caller 已 free / 调用上下文丢 SceneTree）
		player = PlayerLocator.find_player_global()
	if player == null:
		GameLogger.warn("Loot", "LootSpawner.grant: player not found, drop %d entries skipped" % drops.size())
		return 0
	var inv: InventoryComponent = NodeFinder.find_first_child_of_type(player, InventoryComponent) as InventoryComponent
	if inv == null:
		GameLogger.warn("Loot", "LootSpawner.grant: player has no InventoryComponent")
		return 0

	var granted: int = 0
	for d in drops:
		var item_id: int = int(d.get("item_id", 0))
		var count: int = int(d.get("count", 0))
		if item_id <= 0 or count <= 0:
			continue
		var added: int = inv.add_by_id(item_id, count)
		if added > 0:
			granted += 1
			GameLogger.info("Loot", "LootSpawner: granted item_id=%d count=%d (added=%d)" % [item_id, count, added])
		else:
			GameLogger.warn("Loot", "LootSpawner: failed to add item_id=%d count=%d (inv full?)" % [item_id, count])
	return granted


# ─────────────────────────────────────────────────────────────
# 内部 · 撒散 PickupArea 工厂
# ─────────────────────────────────────────────────────────────


## 按 def 类型组装一个 PickupArea Node（外形按 Fragment 决定）。
static func _build_pickup_area(def: ItemDefinition, item_id: int, count: int) -> Area3D:
	var area := Area3D.new()
	area.set_script(load("res://Script/Items/PickupArea.gd"))
	area.name = "Pickup_%s_%d" % [def.get_display_name(), item_id]
	area.collision_layer = 32
	area.collision_mask = 2  # 玩家 hurtbox layer
	area.set("item_def_id", item_id)
	area.set("count", count)

	# 视觉 + 碰撞按品类决定
	var mesh := MeshInstance3D.new()
	var col := CollisionShape3D.new()

	if def.has_fragment(Fragment_Equip):
		# 装备：大立方 + 品质染色
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.5, 0.5)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		var rarity: int = def.get_rarity()
		var style: Dictionary = AffixFormatter.rarity_style(rarity)
		var c: Color = style.get("color", Color(0.85, 0.85, 0.2))
		mat.albedo_color = c
		mat.metallic = 0.5
		mat.roughness = 0.4
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 0.5
		mesh.material_override = mat
		mesh.position = Vector3(0, 0.25, 0)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.7, 1.0, 0.7)
		col.shape = shape
		col.position = Vector3(0, 0.5, 0)
	elif def.has_fragment(Fragment_Currency):
		# 货币：小扁立方（金=金色 / 经验=蓝色 / 其他=亮色）
		var box := BoxMesh.new()
		box.size = Vector3(0.35, 0.2, 0.35)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		var c: Color = Color(0.95, 0.75, 0.1) if item_id == 2 else Color(0.4, 0.85, 1.0)
		mat.albedo_color = c
		mat.metallic = 0.7
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 0.5
		mesh.material_override = mat
		mesh.position = Vector3(0, 0.1, 0)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.55, 0.5, 0.55)
		col.shape = shape
		col.position = Vector3(0, 0.25, 0)
	else:
		# 其他堆叠（药水 / 任务道具）：中型立方 + 灰
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.4, 0.4)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.6, 0.65)
		mat.roughness = 0.7
		mesh.material_override = mat
		mesh.position = Vector3(0, 0.2, 0)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6, 0.8, 0.6)
		col.shape = shape
		col.position = Vector3(0, 0.4, 0)

	area.add_child(mesh)
	area.add_child(col)
	return area
