## 角色基类（2D）。
##
## 收集子节点上的标准组件并暴露引用。所有 Player / Enemy / NPC 派生于此。
## R-CHAR-01：对外 public API 保持 2D/3D 通用，便于后续 3D 子类共享调用方。
##
## 期望子节点结构（顺序与名字不强制，按类型查找）：
##   [code]
##   BaseCharacter (CharacterBody2D)
##     ├─ AnimatedSprite2D
##     ├─ MoveComponent
##     ├─ AnimationComponent
##     ├─ HitboxComponent       (可选，攻击型角色才有)
##     ├─ HurtboxComponent      (可选，可受击角色才有)
##     ├─ InputComponent        (仅玩家)
##     └─ AbilitySystemComponent (M2 起)
##   [/code]
class_name BaseCharacter
extends CharacterBody2D

# 组件引用（_ready 自动收集）
var move_comp: MoveComponent = null
var anim_comp: AnimationComponent = null
var hitbox: HitboxComponent = null
var hurtbox: HurtboxComponent = null
var input_comp: InputComponent = null
# AbilitySystemComponent 在 M2 接入；此处用 Node 占位避免引用未定义类
var asc: Node = null


func _ready() -> void:
	_collect_components()
	_wire_components()
	GameLogger.info("Character", "%s ready (move=%s anim=%s hit=%s hurt=%s input=%s asc=%s)" % [
		name,
		move_comp != null,
		anim_comp != null,
		hitbox != null,
		hurtbox != null,
		input_comp != null,
		asc != null,
	])


func _physics_process(delta: float) -> void:
	if move_comp != null:
		move_comp.tick(delta)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _collect_components() -> void:
	for child in get_children():
		if child is MoveComponent:
			move_comp = child
		elif child is AnimationComponent:
			anim_comp = child
		elif child is HitboxComponent:
			hitbox = child
		elif child is HurtboxComponent:
			hurtbox = child
		elif child is InputComponent:
			input_comp = child
		elif child is AbilitySystemComponent:
			asc = child


func _wire_components() -> void:
	# 玩家：InputComponent 输入方向 → MoveComponent
	if input_comp != null and move_comp != null:
		input_comp.input_dir_changed.connect(move_comp.set_input_dir)
	# M7.3：Hitbox 命中 → HitDamageResolver（数据驱动伤害结算）
	if hitbox != null and asc != null:
		hitbox.hit_landed.connect(_on_hit_landed)


# 命中订阅：HitboxComponent 发出 hit_landed 时由 HitDamageResolver 统一结算。
# 旧版 Ability_BasicAttack 各自处理命中，M7.3 起所有 Ability_TimelineDriven 共用本路径。
func _on_hit_landed(target: Node) -> void:
	if asc == null:
		return
	var hurtbox_node: HurtboxComponent = target as HurtboxComponent
	if hurtbox_node == null:
		return
	HitDamageResolver.resolve_hit(asc as AbilitySystemComponent, hurtbox_node)
