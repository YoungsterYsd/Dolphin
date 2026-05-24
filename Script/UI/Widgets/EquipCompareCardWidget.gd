## 装备比较卡（自治模式）。
##
## 拾取装备时自动弹出比较卡（拾取项 vs 已装备）。
##
## **数据流（Phase 4 接入）**：
##   1. 玩家拾取装备 → InventoryComponent emit [signal EventBus.item_added]
##   2. 本 widget 订阅 item_added → 检查 def 含 [Fragment_Equip]
##   3. 找玩家 EquipmentComponent.equipped[fe.slot] → 构造 dict 调 [method show_compare]
##   4. 同 instance 取最新词条；空槽 → equipped_item = {}
##
## 数据用 Dictionary 解耦业务类（R-HUD-02）：
##   item_data = {
##     "name": "锈剑",
##     "rarity_label": "稀有",
##     "rarity_color": Color,
##     "mods": Array[Dictionary]  # affix mods 原 dict 数组
##   }
##
## **R-EVENT-02**：信号订阅走 named method ✅
class_name EquipCompareCardWidget
extends BaseWidget

@export var auto_hide_seconds: float = 5.0

@onready var new_label: RichTextLabel = $HBox/New/Label
@onready var equipped_label: RichTextLabel = $HBox/Equipped/Label

var _hide_tween: Tween = null


func _ready() -> void:
	super._ready()
	visible = false
	# Phase 4 自治：订阅拾取事件，自动弹卡
	EventBus.item_added.connect(_on_item_added)


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 唤起比较卡。
## new_item / equipped_item：见类注释中的 dict 结构。equipped_item 可空 dict。
func show_compare(new_item: Dictionary, equipped_item: Dictionary = {}) -> void:
	if new_label != null:
		new_label.text = _format(new_item)
	if equipped_label != null:
		equipped_label.text = _format(equipped_item) if not equipped_item.is_empty() else "[i](当前空)[/i]"
	visible = true
	modulate.a = 1.0
	if _hide_tween != null and _hide_tween.is_valid():
		_hide_tween.kill()
	_hide_tween = create_tween()
	_hide_tween.tween_interval(auto_hide_seconds)
	_hide_tween.tween_property(self, ^"modulate:a", 0.0, 0.4)
	_hide_tween.tween_callback(func():
		if is_instance_valid(self):
			visible = false
	)


# ─────────────────────────────────────────────────────────────
# 自治订阅
# ─────────────────────────────────────────────────────────────

func _on_item_added(_owner: Node, def: ItemDefinition, added: int) -> void:
	if def == null or added <= 0:
		return
	var fe: Fragment_Equip = def.find_fragment(Fragment_Equip) as Fragment_Equip
	if fe == null:
		# 非装备类（货币 / 任务道具 / 消耗品）→ 不弹卡
		return

	# 查玩家最新拾取的那件 instance（在 inventory 里找第一个 def == def 的实例）
	var player: Node = PlayerLocator.find_player_global() if PlayerLocator else null
	if player == null:
		return
	var inv: InventoryComponent = NodeFinder.find_first_child_of_type(player, InventoryComponent) as InventoryComponent
	var equipment: EquipmentComponent = NodeFinder.find_first_child_of_type(player, EquipmentComponent) as EquipmentComponent
	if inv == null:
		return

	# 找新拾取的 instance（背包里第一个匹配 def 且有 instance 的）
	var new_inst: ItemInstance = null
	for slot_data in inv.slots:
		if slot_data == null:
			continue
		if slot_data.def == def and slot_data.instance != null:
			new_inst = slot_data.instance
			break

	# 已装备同槽位（可能 null = 空）
	var equipped_inst: ItemInstance = null
	if equipment != null and equipment.equipped.has(fe.slot):
		equipped_inst = equipment.equipped[fe.slot]

	var new_data: Dictionary = _build_compare_data(def, new_inst)
	var equipped_data: Dictionary = {}
	if equipped_inst != null:
		equipped_data = _build_compare_data(equipped_inst.get_def(), equipped_inst)
	show_compare(new_data, equipped_data)


# ─────────────────────────────────────────────────────────────
# 内部：dict 构造 + 格式化
# ─────────────────────────────────────────────────────────────

static func _build_compare_data(def: ItemDefinition, instance: ItemInstance) -> Dictionary:
	var rarity: int = def.get_rarity() if def != null else 0
	var style: Dictionary = AffixFormatter.rarity_style(rarity)
	var mods: Array = []
	if instance != null:
		mods = instance.stat_tags.get(&"affix_mods", [])
	return {
		"name": def.get_display_name() if def != null else "?",
		"rarity_label": style.get("label", ""),
		"rarity_color": style.get("color", Color.WHITE),
		"mods": mods,
	}


static func _format(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	var lines: PackedStringArray = []
	var name_str: String = item.get("name", "?")
	var rarity_label: String = item.get("rarity_label", "")
	var rarity_color: Color = item.get("rarity_color", Color.WHITE)
	var color_hex: String = "#%02X%02X%02X" % [
		int(rarity_color.r * 255),
		int(rarity_color.g * 255),
		int(rarity_color.b * 255),
	]
	lines.append("[color=%s][b]%s[/b][/color]  [i]%s[/i]" % [color_hex, name_str, rarity_label])
	var mods: Array = item.get("mods", [])
	if not mods.is_empty():
		lines.append(AffixFormatter.format_mods_block(mods))
	return "\n".join(lines)
