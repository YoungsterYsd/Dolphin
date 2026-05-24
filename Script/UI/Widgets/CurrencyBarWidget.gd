## 货币栏 widget（HUD 右上）。
##
## 数据驱动：启动时遍历 [ConfigCenter.get_all_item_defs] 找出所有含
## [Fragment_Currency] 的物品，按 item_id 升序生成对应的 Icon+Label 行。
## 新增货币 = 改 [code]Item_Data.csv[/code] + [code]Frag_Currency.csv[/code]，**不改本类一行代码**（OCP）。
##
## 订阅：[signal EventBus.currency_changed](currency_id, new_amount)
##   → 找到对应 currency_id 的 Label，更新数字
##
## 同步显示初始余额：bind 阶段从 [CurrencyManager.get_amount] 拉一次。
##
## R-HUD-01：HUD 不写回业务数据 ✅
## R-HUD-02：HUD 不直接 cast 业务类，仅通过 EventBus / Autoload API ✅
## R-EVENT-02：信号订阅走 named method ✅
class_name CurrencyBarWidget
extends BaseWidget

## 字号
@export var font_size: int = 16
## 图标尺寸（正方形）
@export var icon_size: int = 24
## 单元间距（图标 ↔ 数字）
@export var inner_pad: int = 4
## 货币间间距（金币 ↔ 经验）
@export var entry_pad: int = 12

@onready var hbox: HBoxContainer = $HBox

# currency_id(int) → Label 节点（用于增量更新）
var _id_to_label: Dictionary = {}


func _ready() -> void:
	super._ready()
	_build_entries()
	EventBus.currency_changed.connect(_on_currency_changed)
	# 拉一次当前余额（避免 widget 上线时已有金币但显示 0）
	_pull_initial_amounts()


func _on_currency_changed(currency_id: int, new_amount: int) -> void:
	var lbl: Label = _id_to_label.get(currency_id, null)
	if lbl != null and is_instance_valid(lbl):
		lbl.text = _format_amount(new_amount)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

## 启动时按 ConfigCenter 内所有 Currency 物品生成 entry 行。
func _build_entries() -> void:
	# 容错：bootstrap 期 ConfigCenter 可能尚未加载完
	var defs: Dictionary = {}
	if ConfigCenter != null and ConfigCenter.has_method(&"get_all_item_defs"):
		defs = ConfigCenter.get_all_item_defs()
	if defs.is_empty():
		GameLogger.warn("UI", "CurrencyBarWidget: get_all_item_defs empty (called before bootstrap?)")
		return

	# 按 item_id 升序
	var ids: Array = defs.keys()
	ids.sort()
	for id_v in ids:
		var def: ItemDefinition = defs[id_v] as ItemDefinition
		if def == null or not def.has_fragment(Fragment_Currency):
			continue
		_add_entry(def)


## 加一行：[Icon][Label][间距]
func _add_entry(def: ItemDefinition) -> void:
	# 容器：Icon + Label
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override(&"separation", inner_pad)

	# 图标（优先 Fragment_Currency.icon_on_tip，回退 def.icon_path）
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_icon: String = ""
	var fc: Fragment_Currency = def.find_fragment(Fragment_Currency) as Fragment_Currency
	if fc != null and fc.icon_on_tip != "":
		tip_icon = fc.icon_on_tip
	if tip_icon == "":
		tip_icon = def.icon_path
	if tip_icon != "" and ResourceLoader.exists(tip_icon):
		icon.texture = load(tip_icon) as Texture2D
	entry.add_child(icon)

	# 数字
	var lbl := Label.new()
	lbl.add_theme_font_size_override(&"font_size", font_size)
	lbl.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override(&"outline_size", 4)
	lbl.text = "0"
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(lbl)

	hbox.add_child(entry)
	# 后续条目前置间距
	if hbox.get_child_count() > 1:
		hbox.add_theme_constant_override(&"separation", entry_pad)

	_id_to_label[def.item_id] = lbl


## 启动时对所有已注册的货币拉一次当前余额。
func _pull_initial_amounts() -> void:
	if GameInstance == null or GameInstance.currency_manager == null:
		return
	var cm: CurrencyManager = GameInstance.currency_manager
	for cid in _id_to_label.keys():
		var amt: int = cm.get_amount(int(cid))
		var lbl: Label = _id_to_label[cid]
		if is_instance_valid(lbl):
			lbl.text = _format_amount(amt)


## 数字格式化（千位分隔；超过 1M 显示 1.2M）。
static func _format_amount(n: int) -> String:
	if n >= 1_000_000:
		return "%.1fM" % (n / 1_000_000.0)
	if n >= 10_000:
		return "%.1fK" % (n / 1_000.0)
	# 千位分隔
	var s: String = str(n)
	var result: String = ""
	var cnt: int = 0
	for i in range(s.length() - 1, -1, -1):
		if cnt > 0 and cnt % 3 == 0:
			result = "," + result
		result = s[i] + result
		cnt += 1
	return result
