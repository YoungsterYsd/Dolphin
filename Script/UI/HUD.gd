## 玩家 HUD。
##
## 订阅 EventBus 信号驱动 UI 更新：
##   - attribute_changed：HP/MP 进度条
##   - ability_activated / ability_ended：技能槽高亮
## 每帧从 ASC 取 cooldown 渲染遮罩（CD 转圈/灰度）。
##
## 期望节点结构：
##   HUD (Control)
##     ├─ HPBar (ProgressBar)
##     ├─ HPLabel (Label)
##     ├─ MPBar (ProgressBar)
##     ├─ MPLabel (Label)
##     ├─ Slot1 (TextureRect/ColorRect 占位 + CDOverlay/Label)
##     └─ Slot2 (...)
class_name HUD
extends Control

## 玩家节点引用（一般为场景中的 Player 节点）。
@export var player: BaseCharacter = null


@onready var hp_bar: ProgressBar = $Panel/StatRow/HPBar
@onready var hp_label: Label = $Panel/StatRow/HPBar/HPLabel
@onready var mp_bar: ProgressBar = $Panel/StatRow/MPBar
@onready var mp_label: Label = $Panel/StatRow/MPBar/MPLabel

@onready var slot1_overlay: ColorRect = $Panel/SlotRow/Slot1/CDOverlay
@onready var slot1_label: Label = $Panel/SlotRow/Slot1/CDLabel
@onready var slot2_overlay: ColorRect = $Panel/SlotRow/Slot2/CDOverlay
@onready var slot2_label: Label = $Panel/SlotRow/Slot2/CDLabel


func _ready() -> void:
	EventBus.attribute_changed.connect(_on_attribute_changed)
	GameLogger.info("UI", "HUD ready")
	_refresh_attributes()


func _process(_delta: float) -> void:
	_refresh_cooldowns()


func _refresh_attributes() -> void:
	if player == null or player.asc == null:
		return
	var asc := player.asc as AbilitySystemComponent
	var attrs := asc.attribute_set
	if attrs == null:
		return
	hp_bar.max_value = attrs.get_attr(&"max_health")
	hp_bar.value = attrs.get_attr(&"health")
	hp_label.text = "%d / %d" % [attrs.get_attr(&"health"), attrs.get_attr(&"max_health")]
	mp_bar.max_value = attrs.get_attr(&"max_mana")
	mp_bar.value = attrs.get_attr(&"mana")
	mp_label.text = "%d / %d" % [attrs.get_attr(&"mana"), attrs.get_attr(&"max_mana")]


func _on_attribute_changed(owner_node: Node, _attr_name: StringName, _old_value: float, _new_value: float) -> void:
	if player == null or owner_node != player:
		return
	_refresh_attributes()


func _refresh_cooldowns() -> void:
	if player == null or player.asc == null:
		return
	var asc := player.asc as AbilitySystemComponent
	# Slot 1 → ability_1 → 玩家配置的 ability_slot_to_id[0]
	var pc := player as PlayerCharacter
	if pc == null:
		return
	_update_slot(asc, pc.ability_slot_to_id[0] if pc.ability_slot_to_id.size() > 0 else &"", slot1_overlay, slot1_label)
	_update_slot(asc, pc.ability_slot_to_id[1] if pc.ability_slot_to_id.size() > 1 else &"", slot2_overlay, slot2_label)


func _update_slot(asc: AbilitySystemComponent, ability_id: StringName, overlay: ColorRect, label: Label) -> void:
	if ability_id == &"":
		overlay.visible = true
		overlay.color = Color(0.0, 0.0, 0.0, 0.6)
		label.text = "—"
		return
	var cd: float = asc.get_cooldown_remaining(ability_id)
	var ab: Ability = asc.granted_abilities.get(ability_id, null)
	var max_cd: float = ab.cooldown if ab != null else 1.0
	if cd <= 0.0:
		overlay.visible = false
		label.text = ""
	else:
		overlay.visible = true
		# 透明度按剩余比例：CD 满时全黑半透，CD 接近 0 时透明
		var ratio: float = clampf(cd / max(max_cd, 0.0001), 0.0, 1.0)
		overlay.color = Color(0.0, 0.0, 0.0, 0.6 * ratio)
		label.text = "%.1f" % cd
