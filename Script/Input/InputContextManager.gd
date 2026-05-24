## 输入上下文管理器（Autoload 单例）。
##
## 维护一个 [InputContext] 栈：
##   - 启动时压入默认上下文（Gameplay，allow_all=true）
##   - HUDStateMachine 进入 PanelOpen / Modal / Dialogue / Cutscene / Dead 时 push 对应上下文
##   - 退出状态时 pop 还原
##
## 对外 API：
##   [method push] / [method pop] / [method replace_top] / [method clear_to_default]
##   [method is_action_allowed]（[InputController] 在 emit 前查询）
##   [method get_current_id]
##
## 信号：
##   [signal context_changed]：栈顶切换时发射，HUDStateMachine 与 Debug 层订阅。
##
## R-INPUT-02：所有 InputMap action 在 emit 前必须经过本 Manager 鉴权（仅 ui_pause 由 GameInstance 直管）。
extends Node

## 默认上下文资源路径（全允许）。运行时若资源加载失败，会兜底构造一个 allow_all 的临时上下文。
const DEFAULT_CONTEXT_PATH: String = "res://Data/Config/InputContexts/Gameplay.tres"

## 栈顶上下文发生变化（push / pop / replace 都会触发）。
signal context_changed(old_id: StringName, new_id: StringName)

## 上下文栈。栈顶（数组末尾）为当前生效的上下文。
var _stack: Array[InputContext] = []


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暂停时仍可切换
	var default_ctx: InputContext = _load_default_context()
	_stack.append(default_ctx)
	GameLogger.info("Input", "InputContextManager ready (default=%s)" % default_ctx.context_id)


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 压入一个新上下文。若 ctx 为 null 静默忽略并打印警告。
func push(ctx: InputContext) -> void:
	if ctx == null:
		GameLogger.warn("Input", "push(null) ignored")
		return
	if _has_cycle(ctx):
		GameLogger.warn("Input", "push(%s) detected inheritance cycle, ignored" % ctx.context_id)
		return
	var old_id: StringName = get_current_id()
	_stack.append(ctx)
	context_changed.emit(old_id, ctx.context_id)
	EventBus.hud_input_context_changed.emit(old_id, ctx.context_id)
	GameLogger.info("Input", "push %s (depth=%d)" % [ctx.context_id, _stack.size()])


## 弹出栈顶。若栈中只剩默认上下文则不弹出（保护性）。
## 返回被弹出的上下文，若无操作返回 null。
func pop() -> InputContext:
	if _stack.size() <= 1:
		GameLogger.warn("Input", "pop ignored (only default context remains)")
		return null
	var old_id: StringName = get_current_id()
	var popped: InputContext = _stack.pop_back()
	var new_id: StringName = get_current_id()
	context_changed.emit(old_id, new_id)
	EventBus.hud_input_context_changed.emit(old_id, new_id)
	GameLogger.info("Input", "pop %s -> %s (depth=%d)" % [popped.context_id, new_id, _stack.size()])
	return popped


## 替换栈顶（不改变栈深度）。常用于「面板 A 切到面板 B」的同层切换。
func replace_top(ctx: InputContext) -> void:
	if ctx == null:
		return
	if _stack.is_empty():
		push(ctx)
		return
	if _has_cycle(ctx):
		GameLogger.warn("Input", "replace_top(%s) detected cycle, ignored" % ctx.context_id)
		return
	var old_id: StringName = get_current_id()
	_stack[_stack.size() - 1] = ctx
	context_changed.emit(old_id, ctx.context_id)
	EventBus.hud_input_context_changed.emit(old_id, ctx.context_id)


## 清空到只剩默认上下文。HUD 状态机切回 Gameplay 时调。
func clear_to_default() -> void:
	if _stack.size() <= 1:
		return
	var old_id: StringName = get_current_id()
	var default_ctx: InputContext = _stack[0]
	_stack.clear()
	_stack.append(default_ctx)
	context_changed.emit(old_id, default_ctx.context_id)
	EventBus.hud_input_context_changed.emit(old_id, default_ctx.context_id)
	GameLogger.info("Input", "clear_to_default")


## 当前栈顶上下文。永远非 null（启动时已压默认）。
func current() -> InputContext:
	return _stack[_stack.size() - 1] if not _stack.is_empty() else _make_fallback()


## 当前栈顶 context_id。
func get_current_id() -> StringName:
	return current().context_id


## 当前栈深度（用于 Debug 层）。
func get_depth() -> int:
	return _stack.size()


## 鉴权：当前栈顶上下文下，指定 action 是否允许。
## InputController 在 emit 前调本 API；返回 false 则 drop。
func is_action_allowed(action: StringName) -> bool:
	return current().is_action_allowed(action)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _load_default_context() -> InputContext:
	var ctx: InputContext = ResourceLoader.load(DEFAULT_CONTEXT_PATH) if ResourceLoader.exists(DEFAULT_CONTEXT_PATH) else null
	if ctx == null:
		GameLogger.warn("Input", "default InputContext not found at %s, using fallback allow_all" % DEFAULT_CONTEXT_PATH)
		ctx = _make_fallback()
	return ctx


func _make_fallback() -> InputContext:
	var ctx := InputContext.new()
	ctx.context_id = &"Gameplay"
	ctx.allow_all = true
	ctx.display_name = "Fallback Gameplay"
	return ctx


## 检测 inherit_from 链是否存在循环。
func _has_cycle(ctx: InputContext) -> bool:
	var visited: Array[InputContext] = []
	var node: InputContext = ctx
	while node != null:
		if visited.has(node):
			return true
		visited.append(node)
		node = node.inherit_from
	return false
