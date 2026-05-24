## 玩家 HUD（旧版，Phase 2 临时保留并接入 BaseWidget；Phase 3 拆分为 PlayerInfoWidget + HotbarWidget）。
##
## 订阅 EventBus 信号驱动 UI 更新：
##   - attribute_changed：HP/MP 进度条
## 每帧从 ASC 取 cooldown 渲染遮罩（CD 转圈/灰度）。
##
## 期望节点结构（HF-1 后 6 槽）：
##   HUD (Control)
##     └─ Panel/VBox
##         ├─ StatRow: HPBar/HPLabel, MPBar/MPLabel
##         └─ SlotRow: SlotA, SlotQ, SlotW, SlotE, SlotR, SlotX
##              每个 Slot：Panel
##                ├─ KeyLabel (按键字母，右下角)
##                ├─ CDOverlay (ColorRect，CD 遮罩)
##                └─ CDLabel (CD 数字)
##
## 槽位 → ability_slot_to_id 索引：
##   SlotA=0 (普攻), SlotQ=1, SlotW=2, SlotE=3, SlotR=4, SlotX=5 (大招)
##
## 重构 R1：ability_slot_to_id 从 PlayerCharacter 移到 InputComponent；本类按 InputComponent 子节点查找。
class_name HUD
extends BaseWidget

## 玩家节点引用（一般为场景中的 Player 节点）。
@export var player: BaseCharacter = null


# ─────────────────────────────────────────────────────────────
# 槽位元数据：索引 → 节点名
# 索引对应 InputComponent.ability_slot_to_id 的下标
# ─────────────────────────────────────────────────────────────
const SLOT_NODES: Array[StringName] = [
	&"SlotA",  # 0 普攻
	&"SlotQ",  # 1
	&"SlotW",  # 2
	&"SlotE",  # 3
	&"SlotR",  # 4
	&"SlotX",  # 5 大招
]


@onready var hp_bar: ProgressBar = $Panel/VBox/StatRow/HPBar
@onready var hp_label: Label = $Panel/VBox/StatRow/HPBar/HPLabel

@onready var slot_row: HBoxContainer = $Panel/VBox/SlotRow

# 缓存：索引 → (CDOverlay, CDLabel)
var _slot_overlays: Array[ColorRect] = []
var _slot_labels: Array[Label] = []
# 重构 R1：缓存 InputComponent 引用，避免每帧查找
var _input_comp: InputComponent = null


func _ready() -> void:
	super._ready()  # BaseWidget 钩子：应用 input/pause/theme + _on_show
	_cache_slots()
	EventBus.attribute_changed.connect(_on_attribute_changed)
	GameLogger.info("UI", "HUD ready (%d slots)" % SLOT_NODES.size())
	_refresh_attributes()


func _process(_delta: float) -> void:
	_refresh_cooldowns()


# ─────────────────────────────────────────────────────────────
# 槽位
# ─────────────────────────────────────────────────────────────

func _cache_slots() -> void:
	_slot_overlays.clear()
	_slot_labels.clear()
	for slot_name in SLOT_NODES:
		var slot_node: Panel = slot_row.get_node_or_null(NodePath(String(slot_name))) as Panel
		if slot_node == null:
			GameLogger.warn("UI", "[HUD] missing slot node: %s" % slot_name)
			_slot_overlays.append(null)
			_slot_labels.append(null)
			continue
		_slot_overlays.append(slot_node.get_node_or_null(^"CDOverlay") as ColorRect)
		_slot_labels.append(slot_node.get_node_or_null(^"CDLabel") as Label)


# ─────────────────────────────────────────────────────────────
# 属性
# ─────────────────────────────────────────────────────────────

func _refresh_attributes() -> void:
	if player == null or player.asc == null:
		return
	var asc := player.asc as AbilitySystemComponent
	# R-ASC 重构：删 attribute_set 老接口；统一用 ASC.get_attribute 跨 Set 查找
	# 重构 R-Attr：删除 MP 进度条（旧案没有 mana 概念；HealthSet 已删 mana/max_mana）
	var max_hp: float = asc.get_attribute(&"max_health", 0.0)
	var cur_hp: float = asc.get_attribute(&"health", 0.0)
	hp_bar.max_value = max_hp
	hp_bar.value = cur_hp
	hp_label.text = "%d / %d" % [cur_hp, max_hp]


func _on_attribute_changed(owner_node: Node, _attr_name: StringName, _old_value: float, _new_value: float) -> void:
	if player == null or owner_node != player:
		return
	_refresh_attributes()


# ─────────────────────────────────────────────────────────────
# 技能 CD
# ─────────────────────────────────────────────────────────────

func _refresh_cooldowns() -> void:
	if player == null or player.asc == null:
		return
	# 懒查找 InputComponent（玩家场景挂载顺序由 .tscn 控制；HUD 比 player 后 ready 时可能 null）
	if _input_comp == null:
		_input_comp = NodeFinder.find_first_child_of_type(player, InputComponent) as InputComponent
		if _input_comp == null:
			return
	var asc := player.asc as AbilitySystemComponent
	var slot_to_id: Array = _input_comp.ability_slot_to_id
	for i in range(SLOT_NODES.size()):
		var ability_id: StringName = slot_to_id[i] if i < slot_to_id.size() else &""
		_update_slot(asc, ability_id, _slot_overlays[i], _slot_labels[i])


func _update_slot(asc: AbilitySystemComponent, ability_id: StringName, overlay: ColorRect, label: Label) -> void:
	if overlay == null or label == null:
		return
	# 未绑定 ability：槽位常驻半透灰 + 显示 "—"
	if ability_id == &"":
		overlay.visible = true
		overlay.color = Color(0.0, 0.0, 0.0, 0.6)
		label.text = "—"
		return
	var cd: float = asc.get_cooldown_remaining(ability_id)
	var ab: Ability = asc.granted_abilities.get(ability_id, null)
	var max_cd: float = ab.cooldown if ab != null else 1.0
	if cd <= 0.0:
		# CD 就绪：去除遮罩
		overlay.visible = false
		label.text = ""
	else:
		# CD 中：遮罩透明度按剩余比例
		overlay.visible = true
		var ratio: float = clampf(cd / max(max_cd, 0.0001), 0.0, 1.0)
		overlay.color = Color(0.0, 0.0, 0.0, 0.6 * ratio)
		label.text = "%.1f" % cd
