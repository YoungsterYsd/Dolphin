## 经验条。
##
## 通过 [member data_provider]（[IAttributeReadable]）取当前经验 / 上限，
## 平滑（Tween）填充进度条。
##
## ── 自治模式（默认）──
## 不依赖业务侧手动注入 Provider；本 widget 自动监听 [signal EventBus.character_initialized]，
## 当玩家初始化完成后自找 player.asc 构造 [AttributeProvider]（attribute_name=&"experience",
## max_attribute_name=&"xp_to_next"）并 bind_data。
##
## 选这条路而不是 HUD.gd 注入的原因：
##   - 与 [LevelUpWidget] / [PlayerAvatarWidget] 同模式（订阅 attribute_changed 自治）
##   - 不污染 HUD.gd（避免 widget 之间相互依赖）
##   - 多个布局（Default / BossRush / Cutscene）都能 work，无需各自配 binding
class_name ExperienceBarWidget
extends BaseWidget

## 平滑时长（实际值与上次差距大时按此时长 tween）。
@export var smooth_seconds: float = 0.4

@onready var bar: ProgressBar = $Bar
@onready var label: Label = $Bar/Label

var _smooth_tween: Tween = null


func _ready() -> void:
	super._ready()
	# 数据源未注入时显示空条
	if data_provider == null:
		bar.value = 0.0
		label.text = "0 / 0"
	# 自治：等 player 初始化完成后自动绑定
	EventBus.character_initialized.connect(_on_character_initialized)
	# 已经在场上的 player（layout 切换 / 重连场景时）兜底接入
	_try_auto_bind_existing_player()


# ─────────────────────────────────────────────────────────────
# BaseWidget 钩子
# ─────────────────────────────────────────────────────────────

func bind_data(provider: Resource) -> void:
	# 解绑旧 provider
	if data_provider != null and data_provider is IAttributeReadable:
		var old_p := data_provider as IAttributeReadable
		if old_p.value_changed.is_connected(_on_provider_changed):
			old_p.value_changed.disconnect(_on_provider_changed)
	super.bind_data(provider)
	if provider != null and provider is IAttributeReadable:
		(provider as IAttributeReadable).value_changed.connect(_on_provider_changed)
	refresh()


func refresh() -> void:
	if data_provider == null or not (data_provider is IAttributeReadable):
		return
	var p := data_provider as IAttributeReadable
	var cur := p.get_value()
	var maxv := p.get_max_value()
	# 满级（xp_to_next=0）：显示 "MAX" + 满进度
	if maxv <= 0.0:
		bar.max_value = 1.0
		_tween_to(1.0)
		label.text = "MAX"
		return
	bar.max_value = maxv
	_tween_to(cur)
	label.text = "%d / %d" % [int(cur), int(maxv)]


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _tween_to(target_value: float) -> void:
	if _smooth_tween != null and _smooth_tween.is_valid():
		_smooth_tween.kill()
	_smooth_tween = create_tween()
	_smooth_tween.tween_property(bar, ^"value", target_value, smooth_seconds)


func _on_provider_changed(_old: float, _new: float) -> void:
	refresh()


func _on_character_initialized(character: Node) -> void:
	# 仅响应玩家
	if character == null or not character.is_in_group(&"player"):
		return
	_bind_player(character)


func _try_auto_bind_existing_player() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var players: Array[Node] = tree.get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var player: Node = players[0]
	# 仅在 ASC 已就绪时绑定（character_initialized 派发过的场景）
	var asc_node: Node = player.get(&"asc") if &"asc" in player else null
	if asc_node == null:
		return
	if not (asc_node as AbilitySystemComponent).has_attribute(&"experience"):
		return  # ProgressionSet 还没接入；等 character_initialized
	_bind_player(player)


func _bind_player(player: Node) -> void:
	var asc_node: Node = player.get(&"asc") if &"asc" in player else null
	if asc_node == null:
		return
	var p := AttributeProvider.new()
	p.asc = asc_node as AbilitySystemComponent
	p.attribute_name = &"experience"
	p.max_attribute_name = &"xp_to_next"
	bind_data(p)
