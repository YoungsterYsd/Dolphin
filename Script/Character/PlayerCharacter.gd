## 玩家角色。
##
## 继承 BaseCharacter，扩展：
##   - 启动时给 ASC 授予 AbilitySet（默认仅 BasicAttack；M4 加技能 2）
##   - 监听 InputComponent 的 ability_pressed 信号触发对应 Ability
##   - 朝向：根据移动方向翻转 AnimatedSprite2D（h_flip）
##
## R-CHAR-01：本类不暴露 2D 特定 API；翻转逻辑封装在 _update_facing 内部。
class_name PlayerCharacter
extends BaseCharacter

## 启动时按 InputAction 槽位绑定的 Ability id。
## index 0 = ability_1（鼠标左键 / 普攻）
## index 1 = ability_2（鼠标右键 / 技能 2，M4 实装）
@export var ability_slot_to_id: Array[StringName] = [&"basic_attack", &""]

## 启动技能集（包含本玩家所有可激活技能的 .tres）。
@export var startup_ability_set: Array[Ability] = []


func _ready() -> void:
	super()
	# 加入 player 组，方便敌人 AI 索敌
	add_to_group(&"player")

	# 授予技能集
	if asc != null and not startup_ability_set.is_empty():
		for ab in startup_ability_set:
			if ab != null:
				(asc as AbilitySystemComponent).grant_ability(ab)
		GameLogger.info("Character", "%s granted %d abilities" % [name, startup_ability_set.size()])

	# 绑定 ability_pressed 信号
	if input_comp != null:
		input_comp.ability_pressed.connect(_on_ability_pressed)
		input_comp.interact_pressed.connect(_on_interact_pressed)


func _physics_process(delta: float) -> void:
	super(delta)
	_update_facing()
	_update_animation()


# ─────────────────────────────────────────────────────────────
# 输入响应
# ─────────────────────────────────────────────────────────────

func _on_ability_pressed(slot: int) -> void:
	GameLogger.info("Character", "[PlayerCharacter] ability_pressed slot=%d" % slot)
	# slot=1 → index 0（ability_1）
	var idx := slot - 1
	if idx < 0 or idx >= ability_slot_to_id.size():
		GameLogger.warn("Character", "  → slot index out of range: %d" % idx)
		return
	var ab_id: StringName = ability_slot_to_id[idx]
	if ab_id == &"":
		GameLogger.info("Character", "  → ability slot %d not bound" % slot)
		return
	if asc == null:
		GameLogger.warn("Character", "  → ASC is null!")
		return
	GameLogger.info("Character", "  → try_activate(%s)" % ab_id)
	(asc as AbilitySystemComponent).try_activate(ab_id)


func _on_interact_pressed() -> void:
	# M5 实装拾取/对话
	GameLogger.info("Character", "%s interact (M5 实装)" % name)


# ─────────────────────────────────────────────────────────────
# 视觉更新
# ─────────────────────────────────────────────────────────────

func _update_facing() -> void:
	if move_comp == null:
		return
	var v := move_comp.get_velocity()
	if absf(v.x) < 1.0:
		return
	# 找到 AnimatedSprite2D 翻转
	var sprite := _find_sprite()
	if sprite != null:
		sprite.flip_h = v.x < 0.0


func _update_animation() -> void:
	if anim_comp == null or move_comp == null:
		return
	var v := move_comp.get_velocity()
	if v.length() > 1.0:
		anim_comp.play(&"run")
	else:
		anim_comp.play(&"idle")


func _find_sprite() -> AnimatedSprite2D:
	for child in get_children():
		if child is AnimatedSprite2D:
			return child
	return null
