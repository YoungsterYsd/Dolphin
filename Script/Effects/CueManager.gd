## CueManager。
##
## 表现层 Cue 派发中心。借鉴 Lyra UGameplayCueManager 的"Tag → 表现"概念，
## 但**不引入完整 Lyra 体系**（GCN Notify Actor / 异步加载 / 网络复制 等 80% 用不上）。
##
## 设计要点：
## - **挂 GameInstance 子节点**，对外通过 [code]GameInstance.cue_manager[/code] 访问；
##   不新增 Autoload，**不破坏 R-ARCH-02 上限 6**。
## - **Tag 父匹配路由**：
##   [code]&"Cue.Damage.Fire.Hit"[/code] 注册表无该 tag 时 → 退化到 [code]&"Cue.Damage.Fire"[/code] →
##   [code]&"Cue.Damage"[/code] → [code]&"Cue"[/code]，命中即用。
## - **生命周期**：
##   - ONE_SHOT：[method execute_cue]，发完即忘
##   - LOOPING：[method add_active_cue] / [method remove_active_cue]，按 (instigator, cue_tag) 维护实例
## - **向后兼容**：本类**订阅**老的 [signal EventBus.skill_event_*] 信号？—— **不做反向桥接**，
##   仅承接"新代码主动调 execute_cue"的路径；老代码继续用 EventBus 直发，互不干扰。
##
## 用法：
## [codeblock]
## # 一次性 cue
## GameInstance.cue_manager.execute_cue(&"Cue.Damage.Default.Hit", attacker, {dealt: 30.0, is_crit: true})
##
## # 持续 cue（持续粒子资源后续接入后才真正可用）
## GameInstance.cue_manager.add_active_cue(&"Cue.Buff.Burning.Active", target, {})
## # ... 一段时间后 ...
## GameInstance.cue_manager.remove_active_cue(&"Cue.Buff.Burning.Active", target)
## [/codeblock]
class_name CueManager
extends Node

## CueBindings.tres 路径常量。
const BINDINGS_PATH := "res://Data/Config/CueBindings.tres"

## cue_tag → CueBinding 注册表（从 [CueBindings.tres] bootstrap 时加载）。
var _bindings: Dictionary = {}

## 持续 cue 实例表：key = [instigator_instance_id, cue_tag]，value = handle Dictionary。
var _active_cues: Dictionary = {}


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_bindings()
	GameLogger.info("Cue", "CueManager ready, bindings=%d" % _bindings.size())


## 重新加载注册表（编辑器调试用）。
func reload_bindings() -> void:
	_bindings.clear()
	_load_bindings()
	GameLogger.info("Cue", "CueManager reload_bindings done, bindings=%d" % _bindings.size())


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 触发一次 ONE_SHOT cue。
##
## - cue_tag：按 Tag 父匹配路由查找绑定（如 &"Cue.Damage.Fire.Hit" → &"Cue.Damage.Fire" → &"Cue.Damage"）
## - instigator：发起者节点（一般是 attacker / target / owner Character）；可为 null（全屏 UI cue 等）
## - payload：调用方携带的运行时数据（如 {dealt: 30.0, is_crit: true}）；可为空 dict
##
## 找不到任何匹配 binding 时仅打 info 日志（不 warn，避免日志过载），并广播 [signal EventBus.cue_executed]。
func execute_cue(cue_tag: StringName, instigator: Node, payload: Dictionary = {}) -> void:
	var binding: CueBinding = _resolve_binding(cue_tag)
	if binding != null:
		binding.execute(instigator, payload)
	else:
		# 仍 emit cue_executed 信号便于 grep / 调试，但表现层无动作
		GameLogger.info("Cue", "execute_cue(%s) no binding (silent)" % cue_tag)
	EventBus.cue_executed.emit(cue_tag, instigator, payload)


## 启动一个持续 cue。
## 当前阶段：与 [method execute_cue] 几乎等价（CueBinding 持续资源后续接入后才真正可用）。
func add_active_cue(cue_tag: StringName, instigator: Node, payload: Dictionary = {}) -> void:
	if instigator == null:
		GameLogger.warn("Cue", "add_active_cue(%s) needs non-null instigator, skip" % cue_tag)
		return
	var key: Array = [instigator.get_instance_id(), cue_tag]
	if _active_cues.has(key):
		# 重复添加：当前阶段忽略（D6 时若需多层叠加再改 stack 设计）
		return
	var binding: CueBinding = _resolve_binding(cue_tag)
	if binding == null:
		GameLogger.info("Cue", "add_active_cue(%s) no binding (silent)" % cue_tag)
		return
	var handle: Dictionary = binding.add_active(instigator, payload)
	handle["binding"] = binding
	_active_cues[key] = handle


## 停止一个持续 cue。
func remove_active_cue(cue_tag: StringName, instigator: Node) -> void:
	if instigator == null:
		return
	var key: Array = [instigator.get_instance_id(), cue_tag]
	if not _active_cues.has(key):
		return
	var handle: Dictionary = _active_cues[key]
	var binding: CueBinding = handle.get("binding", null)
	if binding != null:
		binding.cleanup_handle(handle)
	_active_cues.erase(key)


# ─────────────────────────────────────────────────────────────
# 内部：Tag 父匹配路由
# ─────────────────────────────────────────────────────────────

## 把 [code]&"Cue.Damage.Fire.Hit"[/code] 这类 tag 按层级降级查找绑定。
##
## 1. 先查精确匹配
## 2. 不命中则去掉最后一段（&"Cue.Damage.Fire.Hit" → &"Cue.Damage.Fire"）
## 3. 直到查到 binding 或 tag 已退化到根（&"Cue"）
##
## 找不到返回 null。
func _resolve_binding(cue_tag: StringName) -> CueBinding:
	if _bindings.has(cue_tag):
		return _bindings[cue_tag]
	var parts: PackedStringArray = String(cue_tag).split(".")
	while parts.size() > 1:
		parts.remove_at(parts.size() - 1)
		var parent_tag := StringName(".".join(parts))
		if _bindings.has(parent_tag):
			return _bindings[parent_tag]
	return null


# ─────────────────────────────────────────────────────────────
# 内部：加载
# ─────────────────────────────────────────────────────────────

func _load_bindings() -> void:
	if not ResourceLoader.exists(BINDINGS_PATH):
		# 路径缺失允许（开发早期 Cue 资源还没填）；类型不匹配视为配置 bug
		GameLogger.warn("Cue", "CueBindings.tres not found at %s, using empty registry" % BINDINGS_PATH)
		return
	var res: Resource = load(BINDINGS_PATH)
	# R-CODE-01：类型不匹配是配置错误，应崩出来
	assert(res is CueBindings,
		"CueManager: resource at %s is not CueBindings (got %s)" % [BINDINGS_PATH, str(res)])
	_bindings = (res as CueBindings).to_dict()
