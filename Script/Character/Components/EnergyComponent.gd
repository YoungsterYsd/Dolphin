## EnergyComponent（D2.C 新增，仅玩家挂载）。
##
## 02 文档 §1.4 / §4 锁定的双池能量系统中"切换池"的数据载体。
##
## 双池设计：
## - **大招池**（每武器各 1 个，上限 100）：存储在 [code]WeaponInstance.current_ult_energy[/code]，D4 武器系统实装
## - **切换池**（角色级，上限 50）：存储在本组件
##
## D2.C 阶段：仅做"数据 + 信号"骨架，命中钩子留 stub（D2.D 接通 [signal EventBus.damage_dealt_v2]）。
##
## 不挂 ASC.attribute_sets 而独立管理的原因（02 文档 §1.4）：
## 能量是"游戏机制"而非"角色属性"，与 RPG 主属性体系解耦；同时切换池有独立的 HUD 表现（武器切换条）。
class_name EnergyComponent
extends Node

## 切换池上限（02 文档锁定 50）。
@export var switch_energy_max: float = 50.0

## 切换池当前值（0 ~ switch_energy_max）。
var switch_energy: float = 0.0


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 增加切换池能量；自动 clamp 到 [0, switch_energy_max]，并广播信号。
func add_switch_energy(amount: float) -> void:
	var old := switch_energy
	switch_energy = clampf(switch_energy + amount, 0.0, switch_energy_max)
	if not is_equal_approx(switch_energy, old):
		EventBus.switch_energy_changed.emit(get_parent(), switch_energy, switch_energy_max)


## 消耗切换池（满切=50，裸切=0）。返回是否成功消耗。
##
## 不足时返回 false 不扣（外部决定走"裸切"或拒绝）。
func consume_switch_energy(amount: float) -> bool:
	if switch_energy < amount:
		return false
	switch_energy -= amount
	EventBus.switch_energy_changed.emit(get_parent(), switch_energy, switch_energy_max)
	return true


## 当前主手大招池能量（D4 武器系统实装时改读 EquipmentComponent.main_hand.current_ult_energy）。
##
## D2.C 阶段返回 0.0 占位 —— 让 HUD 大招槽 widget 能正常 query 不爆栈。
func get_current_main_ult_energy() -> float:
	# D4 实装路径：
	#   var equip := get_parent().get_node_or_null(^"EquipmentComponent")
	#   return equip.main_hand.current_ult_energy if equip and equip.main_hand else 0.0
	return 0.0


## 占位常量：D2.D 默认每次命中给 1 切换池能量（D6 时改读 EnergyGainTable.tres 按行为分类）。
const _DEFAULT_GAIN_PER_HIT: float = 1.0


# ─────────────────────────────────────────────────────────────
# 命中钩子（D2.D 接通）
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	# D2.D 实装：接通 EventBus.damage_dealt_v2 → 命中加能量
	EventBus.damage_dealt_v2.connect(_on_damage_dealt)


## 命中加能量逻辑（D2.D 实装）。
##
## 02 文档 §4.1 锁定流程：
## 1. 取 EnergyGainTable 配置（按 命中类型：主普攻 / 主技能 / 副技能 / 完美闪避 / 完美格挡 等）
##    ← D6 时实装；当前阶段固定 [_DEFAULT_GAIN_PER_HIT]
## 2. 应用 PrimaryAttributeSet.energy_gain_mul 充能倍率
## 3. _prob_round 概率取整
## 4. 同时给主手大招池（武器实例）和切换池加值
##    ← 大招池 D4 武器系统实装；当前仅给切换池
func _on_damage_dealt(source: Node, _target: Node, _amount: float, _damage_node: Resource, _is_crit: bool) -> void:
	# 仅响应"自己作为施法者"的伤害事件（不是被击命中加能量）
	if source != get_parent():
		return
	# 取充能倍率
	var asc: Node = null
	var parent := get_parent()
	if parent != null and &"asc" in parent:
		asc = parent.get(&"asc")
	var mul: float = 0.0
	if asc != null and asc.has_method(&"get_attribute"):
		mul = asc.call(&"get_attribute", &"energy_gain_mul", 0.0)
	# 概率取整
	var gain: int = _prob_round(_DEFAULT_GAIN_PER_HIT * (1.0 + mul))
	if gain > 0:
		add_switch_energy(float(gain))


## 概率取整（02 文档 F.9 锁定）：x = 4.5 → 50% 4 / 50% 5。
static func _prob_round(x: float) -> int:
	var f := floori(x)
	return f + (1 if randf() < (x - f) else 0)
