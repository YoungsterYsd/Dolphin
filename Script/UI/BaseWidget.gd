## HUD widget 基类。
##
## 所有 HUD 元素必须继承本类（Phase 2 迁移、Phase 3 新建均如此）。
## 提供统一的：
##   - 显隐生命周期（show/hide 钩子 + 入退场动画）
##   - 数据绑定（bind_data(provider) → refresh()）
##   - 输入策略（穿透 / 吸收 / 独占）
##   - 暂停策略（Always / Pausable / WhenPaused）
##   - 主题覆盖（theme_resource）
##
## 子类只需实现：
##   - [method bind_data]：把 provider 的数据接到本 widget 的视觉
##   - [method refresh]：被 provider.changed 信号回调时刷新
##   - 可选：在场景里挂一个名为 "AnimationPlayer" 的子节点，含 "show" / "hide" 动画
##
## R-HUD-01：HUD 不得写回业务数据。
## R-HUD-02：HUD 不得直接 cast 业务类，仅通过 data_provider 抽象访问。
## R-HUD-03：颜色 / 字号 / 像素 / 时长 全走 .tres，禁止硬编码。
class_name BaseWidget
extends Control

## 输入策略枚举。
enum InputMode {
	PASS,    ## 穿透（默认）：不拦截输入。
	ABSORB,  ## 吸收：吃掉点击但不阻塞下层热键。
	BLOCK,   ## 独占：阻塞下层一切输入。
}

## 暂停策略枚举（与 Node.PROCESS_MODE_* 对齐）。
enum PausePolicy {
	INHERIT,      ## 跟随父节点（默认；HUD_Main 各层会显式设）。
	ALWAYS,       ## 始终运行，即使游戏暂停。
	PAUSABLE,     ## 暂停时停止刷新。
	WHEN_PAUSED,  ## 仅在暂停时运行。
}


# ─────────────────────────────────────────────────────────────
# 字段
# ─────────────────────────────────────────────────────────────

## 唯一标识（在同一 HUDLayout 中唯一）。建议命名 widget_xxx。
@export var widget_id: StringName = &""

## 数据源 Resource。具体类型由子类约束（如 IAttributeReadable）。
## 注意：本字段是「初始 provider」；运行时可通过 [method bind_data] 替换。
@export var data_provider: Resource = null

## 输入策略。
@export var input_mode: InputMode = InputMode.PASS

## 暂停策略。
@export var pause_policy: PausePolicy = PausePolicy.INHERIT

## 主题覆盖（不设则继承父节点 / 全局 Theme）。
@export var theme_resource: Theme = null

## 是否在调试构建外可见。设 true 时仅 OS.is_debug_build() 才显示。
@export var debug_only: bool = false

## 是否为持久 widget。
##
## - [code]false[/code]（默认）：[method close] 走"播退场动画 + queue_free"，节点会被销毁。
##   适用于动态创建的一次性 widget（飘字 / 弹窗 / 加载屏 等）。
## - [code]true[/code]：[method close] 仅"播退场动画 + visible=false"，节点保留。
##   适用于关卡场景内的静态持久节点（InventoryUI / PauseMenu 等），可以被反复 open/close。
##
## 被 [HUDManager.pop_widget] 调用时，本字段决定节点命运：销毁 or 仅隐藏。
@export var persistent: bool = false


# ─────────────────────────────────────────────────────────────
# 信号
# ─────────────────────────────────────────────────────────────

## widget 关闭（隐藏动画结束）。
signal closed

## 数据源已绑定。
signal data_bound(provider: Resource)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

@onready var _anim_player: AnimationPlayer = get_node_or_null(^"AnimationPlayer")


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_apply_input_mode()
	_apply_pause_policy()
	_apply_theme()
	_apply_debug_only()
	if data_provider != null:
		bind_data(data_provider)
	_on_show()


# ─────────────────────────────────────────────────────────────
# 公开 API（子类可覆写）
# ─────────────────────────────────────────────────────────────

## 绑定数据源。子类应在此订阅 provider.changed 等信号，并立即 refresh()。
## 默认实现：保存引用 → 触发 refresh → 发 data_bound 信号。
func bind_data(provider: Resource) -> void:
	data_provider = provider
	if provider != null:
		data_bound.emit(provider)
	refresh()


## 刷新视觉。子类按需覆写，从 data_provider 取最新值并更新 UI。
func refresh() -> void:
	pass


## 入场。播 "show" 动画（若存在）。
func _on_show() -> void:
	if _anim_player and _anim_player.has_animation(&"show"):
		_anim_player.play(&"show")


## 退场。播 "hide" 动画（若存在），动画结束后发 closed 信号。
## 子类如有更复杂的退场逻辑，可覆写本方法。
func _on_hide() -> void:
	if _anim_player and _anim_player.has_animation(&"hide"):
		_anim_player.play(&"hide")
		await _anim_player.animation_finished
	closed.emit()


## 关闭 widget。
##
## 行为分支（由 [member persistent] 决定）：
##   - [code]persistent=false[/code]（默认）：播退场动画 → queue_free（节点销毁）
##   - [code]persistent=true[/code]：播退场动画 → visible=false（节点保留，可后续重新 [method open] 等）
##
## 被 [HUDManager.pop_widget] 在弹出栈顶时统一调用；调用方无需关心生命周期。
## 子类若有更复杂的关闭逻辑可覆写，但务必保留 persistent 分支语义（或自行处理 free）。
func close() -> void:
	await _on_hide()
	if persistent:
		visible = false
	else:
		queue_free()


# ─────────────────────────────────────────────────────────────
# 内部：策略应用
# ─────────────────────────────────────────────────────────────

func _apply_input_mode() -> void:
	match input_mode:
		InputMode.PASS:
			mouse_filter = Control.MOUSE_FILTER_PASS
		InputMode.ABSORB:
			mouse_filter = Control.MOUSE_FILTER_STOP
		InputMode.BLOCK:
			mouse_filter = Control.MOUSE_FILTER_STOP


func _apply_pause_policy() -> void:
	match pause_policy:
		PausePolicy.INHERIT:
			process_mode = Node.PROCESS_MODE_INHERIT
		PausePolicy.ALWAYS:
			process_mode = Node.PROCESS_MODE_ALWAYS
		PausePolicy.PAUSABLE:
			process_mode = Node.PROCESS_MODE_PAUSABLE
		PausePolicy.WHEN_PAUSED:
			process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _apply_theme() -> void:
	if theme_resource != null:
		theme = theme_resource


func _apply_debug_only() -> void:
	if debug_only and not OS.is_debug_build():
		visible = false
		set_process(false)
