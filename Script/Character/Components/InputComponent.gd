## 输入组件（玩家专用）。
##
## 职责（一站式输入路由）：
##   1. **持续输入**：订阅 [signal EventBus.player_move_vector_changed]，把 Vector2 移动向量
##      转为 Vector3(XZ 平面) 写到 [MoveComponent.set_input_dir]
##   2. **离散输入**：订阅 [signal EventBus.player_input_action_pressed]，按 [member action_to_slot]
##      路由到对应 ability_id，调 [method AbilitySystemComponent.try_activate]
##
## 输入源：[InputController]（也是组件，但全局只有一个，由场景挂载）。InputController 桥接
## InputMap → EventBus 信号；本组件作为玩家侧的"消费者"。这样：
##   - 移动 / 技能键的实际派发都集中在 EventBus
##   - 替换输入设备 / 接 InputContextManager 等都不影响本组件
##   - 移动**不**做成 Ability（原因见 重构经验文档：移动是持续状态，Ability 是离散动作）
##
## R-CHAR-01：对外不暴露 2D/3D 节点类型；输出 Vector3。
##
## 参考：Plans/Dolphin设计/01_战斗框架_输入映射_Dolphin适配.md
class_name InputComponent
extends Node


## 输入方向变化信号（兼容老订阅方；新代码可直接订 EventBus）。
signal input_dir_changed(dir: Vector3)

## 启用开关。设为 false 后忽略所有输入派发（移动方向归零、技能键不响应）。
@export var enabled: bool = true

## InputMap action 名 → ability_slot_to_id 索引。
## consumable / interact / dodge / block 不走槽位（由其它组件直接订阅 EventBus）。
@export var action_to_slot: Dictionary = {
	&"combat_attack":   0,
	&"combat_skill_q":  1,
	&"combat_skill_w":  2,
	&"combat_skill_e":  3,
	&"combat_skill_r":  4,
	&"combat_ultimate": 5,
	&"combat_swap":     6,
}

## 槽位 → Ability id 映射。索引含义：
##   0=combat_attack（普攻）
##   1=combat_skill_q  2=combat_skill_w  3=combat_skill_e  4=combat_skill_r
##   5=combat_ultimate（大招）
##   6=combat_swap（武器切换）
@export var ability_slot_to_id: Array[StringName] = [
	&"basic_attack", &"", &"", &"", &"", &"", &"",
]


# 缓存的同级组件
var _move_comp: MoveComponent = null
var _asc: AbilitySystemComponent = null


func _ready() -> void:
	_move_comp = NodeFinder.find_first_child_of_type(get_parent(), MoveComponent) as MoveComponent
	_asc = NodeFinder.find_first_child_of_type(get_parent(), AbilitySystemComponent) as AbilitySystemComponent

	# 订阅持续输入（移动）
	EventBus.player_move_vector_changed.connect(_on_move_vector_changed)
	# 订阅离散输入（技能/普攻/大招/Swap）
	EventBus.player_input_action_pressed.connect(_on_input_action_pressed)


# ─────────────────────────────────────────────────────────────
# 持续输入（移动方向）
# ─────────────────────────────────────────────────────────────

func _on_move_vector_changed(v: Vector2) -> void:
	if not enabled:
		# 主动归零，避免按住时禁用导致角色"持续滑动"
		_emit_dir(Vector3.ZERO)
		return
	# v.x → 世界 X 轴；v.y → 世界 Z 轴（向前 = -z；InputController 已用 move_up=向前 = -y 的语义）
	# 这里直接把 v.y 投到 z 轴；MoveComponent 只看 dir.x / dir.z。
	_emit_dir(Vector3(v.x, 0.0, v.y))


func _emit_dir(dir: Vector3) -> void:
	if _move_comp != null:
		_move_comp.set_input_dir(dir)
	input_dir_changed.emit(dir)


# ─────────────────────────────────────────────────────────────
# 离散输入（技能槽路由）
# ─────────────────────────────────────────────────────────────

func _on_input_action_pressed(action: StringName) -> void:
	if not enabled:
		return
	if not action_to_slot.has(action):
		return  # 非槽位动作（interact / consumable / dodge / block / ui_*）由其它组件订阅
	_try_activate_slot(action, action_to_slot[action] as int)


func _try_activate_slot(action: StringName, slot_index: int) -> void:
	# 配置错误就崩，便于定位（Q2 路线：移除兜底，崩溃式失败）
	assert(slot_index >= 0 and slot_index < ability_slot_to_id.size(),
		"InputComponent: %s slot index OOR: %d (size=%d)" % [action, slot_index, ability_slot_to_id.size()])
	var ab_id: StringName = ability_slot_to_id[slot_index]
	if ab_id == &"":
		# 槽位未绑定：仅 info（这是合理的，比如 Q/W/E/R 还没解锁）
		GameLogger.info("Input", "[Player] %s (slot %d) not bound" % [action, slot_index])
		return
	# ASC 必须存在；不存在说明场景配置错误，直接崩
	assert(_asc != null, "InputComponent: ASC not found under %s" % str(get_parent()))
	GameLogger.info("Input", "[Player] %s -> try_activate(%s)" % [action, ab_id])
	_asc.try_activate(ab_id)
