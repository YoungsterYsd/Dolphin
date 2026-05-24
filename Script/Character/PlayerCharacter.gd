## 玩家角色。
##
## 职责（重构 R1 后）：仅声明"我是玩家"语义。
##   - 加入 [code]player[/code] 组，便于敌人 AI 索敌
##   - 声明必备 AttributeSet：HealthSet + PrimaryAttributeSet + CombatSet
##   - 声明使用全套 Regen（HealthRegen + StaminaRegen + BlockRegen）
##
## 不再承担（已下沉到组件）：
##   - 视觉（朝向 / idle-run）→ [VisualComponent]
##   - 输入路由（move + 技能槽）→ [InputComponent]
##   - 交互检测（按 G 找最近 InteractableTarget）→ [InteractorComponent]
##   - 属性 Bootstrap（数据驱动注入）→ [AbilitySystemComponent.bootstrap_from_entity]
##
## 默认 [code]kind = HERO, data_id = 1[/code]（小狐狸），但子场景可覆盖。
class_name PlayerCharacter
extends BaseCharacter


func _ready() -> void:
	# 玩家默认 (HERO, 1)（场景未填时回退）
	kind = ConfigCenter.CharacterKind.HERO
	if data_id <= 0:
		data_id = 1
	add_to_group(&"player")
	super()


# ─────────────────────────────────────────────────────────────
# BaseCharacter 钩子覆盖
# ─────────────────────────────────────────────────────────────

func _get_required_attribute_set_classes() -> Array:
	return [HealthSet, PrimaryAttributeSet, CombatSet, ProgressionSet]


func _should_skip_regens() -> bool:
	# 玩家挂全套 Regen
	return false
