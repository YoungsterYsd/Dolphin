## 敌人角色。
##
## 继承 BaseCharacter；持 AIController 子节点驱动状态机。
## 启动时索敌指向场景里的 Player（按 group "player" 查找；找不到则 target=null）。
##
## M6 起：属性走数据驱动（ConfigCenter 解算）。场景里只配置 [member entity_id]（与 level 可选覆盖），
## 不再绑定具体 AttributeSet 资源。R-DATA-02 合规。
class_name EnemyCharacter
extends BaseCharacter

## 角色实例 id（指向 CharacterInstances.tres 中的一条 [CharacterInstanceEntry]）。
## 留空则跳过数据驱动注入，使用场景内 ASC 已配置的 attribute_set（兼容旧场景）。
@export var entity_id: StringName = &""

## 等级覆盖。> 0 时覆盖 CharacterInstanceEntry.level；<= 0 时沿用条目默认等级。
@export var level_override: int = -1

## 启动时授予 ASC 的技能集（敌人专属）。
@export var startup_ability_set: Array[Ability] = []

@onready var ai: AIController = $AIController as AIController


func _ready() -> void:
	super()

	# 自动加入 enemy 组，便于查询
	add_to_group(&"enemy")

	# M6：根据 entity_id 注入数据驱动属性
	_inject_data_driven_attributes()

	# 授予技能集
	if asc != null and not startup_ability_set.is_empty():
		for ab in startup_ability_set:
			if ab != null:
				(asc as AbilitySystemComponent).grant_ability(ab)
		GameLogger.info("Character", "%s granted %d abilities" % [name, startup_ability_set.size()])

	# 接 AI
	if ai != null:
		ai.enemy = self
		ai.target = _find_player()
		_register_default_states()
		ai.change_state(&"idle")

	# 受击事件：让 AI 进 HitState
	if hurtbox != null:
		hurtbox.damaged.connect(func(amount, source):
			if ai != null:
				ai.send_event(&"took_damage", {"amount": amount, "source": source})
		)

	# 监听自身 health 变化，HP=0 切 Dead
	EventBus.attribute_changed.connect(_on_attr_changed)

	# M8：通知 OverheadHealthBarManager 等订阅方"有新敌人生成"
	EventBus.enemy_spawned.emit(self)


func _physics_process(delta: float) -> void:
	super(delta)
	if ai != null:
		ai.tick(delta)
	_update_animation()


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

## M6：从 ConfigCenter 解算并注入属性 + 同步 MoveComponent.max_speed。
func _inject_data_driven_attributes() -> void:
	if entity_id == &"":
		# 兼容旧场景：未配置 entity_id 时沿用场景内 ASC 的 attribute_set
		return
	if asc == null:
		GameLogger.warn("Character", "%s entity_id=%s but ASC missing, skip" % [name, entity_id])
		return

	# 通过 /root 路径获取 ConfigCenter（避免某些情况下 GDScript 静态识别 Autoload 失败）
	var cfg: Node = get_tree().root.get_node_or_null(^"ConfigCenter")
	if cfg == null:
		GameLogger.warn("Character", "%s ConfigCenter autoload missing, skip data-driven inject" % name)
		return

	var def: CharacterInstanceEntry = cfg.get_character_def(entity_id)
	if def == null:
		# ConfigCenter 已打 warn，此处不重复
		return

	var lv: int = level_override if level_override > 0 else def.level
	var values: Dictionary = cfg.resolve_character_attributes(entity_id, lv)
	if values.is_empty():
		GameLogger.warn("Character", "%s resolve attributes empty (entity_id=%s lv=%d)" % [name, entity_id, lv])
		return

	# 确保 ASC 持有一个 AttributeSet 实例（即使场景里没配也兜底创建一个）
	var asc_node := asc as AbilitySystemComponent
	if asc_node.attribute_set == null:
		asc_node.attribute_set = CharacterAttributeSet.new()
		asc_node.attribute_set.owner_node = self

	if asc_node.attribute_set is CharacterAttributeSet:
		AttributeResolver.apply_to_attribute_set(values, asc_node.attribute_set as CharacterAttributeSet)
	else:
		GameLogger.warn("Character", "%s ASC.attribute_set is not CharacterAttributeSet, skip resolver" % name)

	# 同步移动速度：优先用条目里的 move_speed_override，否则用解算结果的 move_speed
	var final_speed: float = def.move_speed_override
	if final_speed < 0.0:
		final_speed = values.get(&"move_speed", -1.0)
	if final_speed >= 0.0 and move_comp != null:
		move_comp.max_speed = final_speed

	GameLogger.info("Character", "%s injected attrs from [%s] lv=%d (hp=%.0f atk=%.0f def=%.0f spd=%.0f)" % [
		name, entity_id, lv,
		values.get(&"max_health", -1.0),
		values.get(&"attack", -1.0),
		values.get(&"defense", -1.0),
		final_speed,
	])


func _find_player() -> Node:
	# 玩家加入 player 组（PlayerCharacter._ready 内）
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return null
	return players[0]


func _register_default_states() -> void:
	ai.register_state(&"idle", AIState_Idle.new())
	ai.register_state(&"chase", AIState_Chase.new())
	ai.register_state(&"attack", AIState_Attack.new())
	ai.register_state(&"hit", AIState_Hit.new())
	ai.register_state(&"dead", AIState_Dead.new())


func _on_attr_changed(owner_node: Node, attr_name: StringName, _old: float, new: float) -> void:
	if owner_node != self:
		return
	if attr_name == &"health":
		# Boss 阶段评估
		if ai is BossAI and asc != null:
			var max_hp: float = (asc as AbilitySystemComponent).attribute_set.get_attr(&"max_health")
			if max_hp > 0.0:
				(ai as BossAI).evaluate_phase(new / max_hp)
		# HP=0 切 dead
		if new <= 0.0:
			if ai != null and ai.current_state != null and ai.current_state.state_name != &"dead":
				ai.change_state(&"dead")


func _update_animation() -> void:
	if anim_comp == null or move_comp == null:
		return
	# 简化：移动时 run，否则 idle（敌人 sprite 用 default 动画即可，无 run/idle 区分时不报错）
	# AnimationComponent.play 内部会判 sprite_frames 是否有该动画
	pass
