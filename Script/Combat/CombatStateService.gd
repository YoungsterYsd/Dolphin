## CombatStateService（D2.D 新增，挂 GameInstance 子节点）。
##
## 02 文档 §1.6 / §2 GE_CombatActive 锁定的"战斗状态判定"：
## - 玩家受/造成伤害时刷 5s 战斗活跃期
## - 5s 内未受/未造成 + 8m 内无敌人 → 退出战斗
## - 战斗期间 [signal EventBus.combat_state_changed.emit(true)]，HUD-AttackTimer 等订阅方进入战斗 UI
## - 战斗期间 GE_HealthRegen / GE_BlockRegen 等带 [code]application_blocked_tags=[State.Combat.Active][/code] 的 GE 自动屏蔽
##
## ⚠️ 复用决策（02B §5.1.4）：HUD 已有 [signal EventBus.combat_state_changed]，本服务作为该信号的**唯一发射源**。
## 现有 HUD 订阅方 0 改动。
##
## 同时：本服务对玩家 ASC 应用 GE_CombatActive（granted_tags=[State.Combat.Active]，DURATION 5s 自动续期），
## 让 ASC tag 系统也能查询战斗状态（例如 Regen GE 通过 application_blocked_tags 屏蔽）。
class_name CombatStateService
extends Node

## 战斗活跃期持续时长（秒）。受/造成伤害事件刷新本计时。
const COMBAT_ACTIVE_DURATION: float = 5.0

## 仇恨距离（米）。脱战判定：5s 内无伤害事件 AND 8m 内无敌人。
const COMBAT_AGGRO_RADIUS: float = 8.0

## 当前是否处于战斗状态。
var _is_in_combat: bool = false

## 上次伤害事件时间戳（秒，Time.get_ticks_msec / 1000）。
var _last_combat_event_at: float = -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.damage_dealt_v2.connect(_on_damage)
	GameLogger.info("Combat", "CombatStateService ready")


func _physics_process(_delta: float) -> void:
	if not _is_in_combat:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = now - _last_combat_event_at
	if elapsed > COMBAT_ACTIVE_DURATION and not _has_enemies_nearby():
		_set_combat(false)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _on_damage(source: Node, target: Node, _amount: float, _damage_node: Resource, _is_crit: bool) -> void:
	# 任意伤害事件涉及到玩家（作为施法者或受害者）就刷新战斗期
	if not _involves_player(source, target):
		return
	_last_combat_event_at = Time.get_ticks_msec() / 1000.0
	_set_combat(true)


func _involves_player(source: Node, target: Node) -> bool:
	# 玩家通过 group "player" 标记
	if source != null and source.is_in_group(&"player"):
		return true
	if target != null and target.is_in_group(&"player"):
		return true
	return false


func _set_combat(active: bool) -> void:
	if _is_in_combat == active:
		return
	_is_in_combat = active
	EventBus.combat_state_changed.emit(active)
	GameLogger.info("Combat", "combat_state_changed → %s" % active)

	# 同步 ASC tag：active=true 时 apply GE_CombatActive；active=false 时找 handle detach
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	if not (&"asc" in player):
		return
	var asc: AbilitySystemComponent = player.get(&"asc") as AbilitySystemComponent
	if asc == null:
		return

	if active:
		# R-Core：ConfigCenter 走 class_name 强类型直访
		var ge: GameplayEffect = ConfigCenter.get_ge(&"CombatActive")
		if ge != null:
			asc.apply_effect_to(asc, ge, player)
	else:
		# 撤销所有 granted State.Combat.Active 的 active_effect
		# R-Core：用 ASC 公共 API 替代越权调用 _detach_active
		asc.remove_effects_with_granted_tag(&"State.Combat.Active")


func _has_enemies_nearby() -> bool:
	var player: Node = get_tree().get_first_node_in_group(&"player")
	if player == null or not (&"global_position" in player):
		return false
	var p_pos: Vector3 = player.get(&"global_position")
	for enemy in get_tree().get_nodes_in_group(&"enemy"):
		if enemy == null or not (&"global_position" in enemy):
			continue
		var e_pos: Vector3 = enemy.get(&"global_position")
		if p_pos.distance_to(e_pos) < COMBAT_AGGRO_RADIUS:
			return true
	return false


# ─────────────────────────────────────────────────────────────
# 公开 API（HUD / Debug 查询用）
# ─────────────────────────────────────────────────────────────

func is_in_combat() -> bool:
	return _is_in_combat
