## 角色基类（3D，HD-2D Sprite Billboard 风格）。
##
## 职责（重构 R1 后，仅 4 件事）：
##   1. 物理身体根（[CharacterBody3D]）
##   2. 组件聚合：[code]_collect_components[/code] 把同级子节点收集成 typed 引用
##   3. 数据驱动属性 Bootstrap：调 [method AbilitySystemComponent.bootstrap_from_entity]，
##      由子类通过虚函数 [method _get_required_attribute_set_classes] / [method _should_skip_regens]
##      表达"自己需要哪些 Set / 是否跳过 Regen"
##   4. 组件接线：把 hitbox.hit_landed → HitDamageResolver.resolve_hit
##
## 不再承担（已下沉到组件 / ASC）：
##   - sprite_ground_offset / 朝向 / 动画切换 → [VisualComponent]
##   - 8 步初始化第 3/5/6/8 步（GE_HealthInit_Full / Regen / emit）→ [AbilitySystemComponent.bootstrap_from_entity]
##   - 输入路由（move + 技能槽）→ [InputComponent]
##   - 交互检测 → [InteractorComponent]
##
## R-CHAR-01：对外 public API 平台无关（仅 Vector3）。
## R-CHAR-02：根 [CharacterBody3D]；视觉走 [SpriteBase3D]（[AnimatedSprite3D] / [Sprite3D]）。
## R-DATA-02：属性数值走 ConfigCenter，场景内不绑 AttributeSet 资源。
##
## 期望子节点结构：
## [codeblock]
## BaseCharacter (CharacterBody3D)
##   ├─ AnimatedSprite3D / Sprite3D / MeshInstance3D（视觉，可选）
##   ├─ CollisionShape3D（必需）
##   ├─ MoveComponent（必需）
##   ├─ AnimationComponent（可选；与 VisualComponent 联动）
##   ├─ VisualComponent（可选；建议玩家/敌人都挂）
##   ├─ HitboxComponent（可选；攻击方需要）
##   ├─ HurtboxComponent（可选；可被打的需要）
##   ├─ AbilitySystemComponent（必需）
##   └─ 子类组件（InputComponent / InteractorComponent / BlockComponent 等）
## [/codeblock]
class_name BaseCharacter
extends CharacterBody3D


## 角色实例定位（R-Excel 重构 2026-05-23）：
## [code]kind + data_id[/code] 二元组定位 CSV 中的实例：
## - HERO    → [code]ConfigCenter.get_hero_data(data_id)[/code]
## - MONSTER → [code]ConfigCenter.get_monster_data(data_id)[/code]
##
## [member data_id] = 0 时跳过数据驱动属性注入（仅适用于无 ASC 的特殊场景；正常角色必须填）。
@export var kind: ConfigCenter.CharacterKind = ConfigCenter.CharacterKind.MONSTER

## 数据表主键 id（指向 Hero_Data.id 或 Monster_Data.id）。0 = 跳过 Bootstrap。
@export var data_id: int = 0

## 等级覆盖。> 0 时覆盖数据表中的 level；<= 0 时沿用：
## - HERO    → 暂硬编 1（备忘：等级经验系统接入后改读 PlayerProfile）
## - MONSTER → Monster_Data.level
@export var level_override: int = -1

## 启动时一次性授予 ASC 的技能集（玩家普攻/敌人普攻等都通过它配）。
@export var startup_ability_set: Array[Ability] = []

## 角色基础硬度等级（0~6）。不在释放任何 GA 时使用。
##
## [InterruptResolver] 在判定打断时取 [method AbilitySystemComponent.get_current_poise_level]：
## - 有激活中 GA → 取所有激活中 GA 的 [member Ability.cast_poise] 最大值
## - 否则 → 取本字段
##
## 设计参考：
## - 0：玩家 / 普通杂兵（裸站受击会被打断）
## - 1~2：重甲杂兵 / 精英怪
## - 3+：Boss 类（站撸时也抗轻击）
@export var base_poise: int = 0


# 组件引用（_ready 时通过 _collect_components 自动收集）
var move_comp: MoveComponent = null
var anim_comp: AnimationComponent = null
var hitbox: HitboxComponent = null
var hurtbox: HurtboxComponent = null
var asc: AbilitySystemComponent = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_collect_components()
	_wire_components()
	_bootstrap_attributes()
	_grant_startup_abilities()
	GameLogger.info("Character", "%s ready (move=%s anim=%s hit=%s hurt=%s asc=%s kind=%d data_id=%d)" % [
		name, move_comp != null, anim_comp != null,
		hitbox != null, hurtbox != null, asc != null, kind, data_id,
	])


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if move_comp != null:
		move_comp.tick(delta)


# ─────────────────────────────────────────────────────────────
# 子类钩子（虚函数）
# ─────────────────────────────────────────────────────────────

## 返回本角色必备的 [AttributeSet] 类列表（如 [code][HealthSet, PrimaryAttributeSet, CombatSet][/code]）。
##
## 默认空数组 = 不做属性 Bootstrap（适用于无属性的特殊角色）。
## 子类应覆盖此方法。
func _get_required_attribute_set_classes() -> Array:
	return []


## 是否在 8 步初始化序列中跳过 Stamina/Block Regen。
##
## 玩家覆盖返回 false（挂全套 Regen）；敌人覆盖返回 true（仅 HealthRegen）。
func _should_skip_regens() -> bool:
	return false


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _collect_components() -> void:
	# 用 NodeFinder 统一查找；多类型时优先级以 Inspector 子节点顺序为准
	move_comp = NodeFinder.find_first_child_of_type(self, MoveComponent) as MoveComponent
	anim_comp = NodeFinder.find_first_child_of_type(self, AnimationComponent) as AnimationComponent
	hitbox = NodeFinder.find_first_child_of_type(self, HitboxComponent) as HitboxComponent
	hurtbox = NodeFinder.find_first_child_of_type(self, HurtboxComponent) as HurtboxComponent
	asc = NodeFinder.find_first_child_of_type(self, AbilitySystemComponent) as AbilitySystemComponent


func _wire_components() -> void:
	# Hitbox 命中 → HitDamageResolver 数据驱动伤害结算
	if hitbox != null and asc != null:
		hitbox.hit_landed.connect(_on_hit_landed)


func _on_hit_landed(target: Node) -> void:
	var hurtbox_node: HurtboxComponent = target as HurtboxComponent
	if hurtbox_node == null:
		return
	HitDamageResolver.resolve_hit(asc, hurtbox_node)


func _bootstrap_attributes() -> void:
	# data_id = 0 = 跳过（特殊场景，例如纯展示用 dummy 角色）
	if data_id <= 0:
		return
	# 非 0 时，ASC 必须存在；不存在直接崩
	assert(asc != null,
		"%s has data_id=%d but no AbilitySystemComponent in children" % [name, data_id])
	var required: Array = _get_required_attribute_set_classes()
	# 子类必须声明，否则崩
	assert(not required.is_empty(),
		"%s must override _get_required_attribute_set_classes()" % name)
	var values: Dictionary = asc.bootstrap_from_entity(
		kind,
		data_id,
		level_override,
		required,
		_should_skip_regens()
	)
	# 同步移动速度：用解算结果的 move_speed_base
	# 如需"同 attr_id 不同移速"的变体，策划在 Hero_Data/Monster_Data 上加 move_speed_override 列再处理
	if move_comp != null and values.has(&"move_speed_base"):
		move_comp.max_speed = float(values[&"move_speed_base"])


func _grant_startup_abilities() -> void:
	if asc == null or startup_ability_set.is_empty():
		return
	for ab in startup_ability_set:
		if ab != null:
			asc.grant_ability(ab)
	GameLogger.info("Character", "%s granted %d abilities" % [name, startup_ability_set.size()])
