## 敌人角色（LimboAI 版）。
##
## 职责：
##   - 加入 [code]enemy[/code] 组，emit [signal EventBus.enemy_spawned]
##   - 声明必备 AttributeSet：HealthSet + CombatSet（不挂 PrimaryAttributeSet）
##   - 启动时找 [code]player[/code] 组首个节点，写到 BTPlayer 黑板键 [code]target[/code]
##   - 监听 hurtbox.damaged → 写 BTPlayer 黑板键 [code]event_took_damage[/code]
##   - 订阅 [signal EventBus.poise_broken]（仅自己）→ 写黑板键 [code]event_poise_broken[/code]
##   - 监听自身 health=0 → 抢断 BTPlayer + 死亡视觉淡出 + queue_free
##
## **场景接线约定**：
##   - 子节点 `BTPlayer`（脚本：LimboAI 原生 `BTPlayer`）
##     - `behavior_tree`：在 Inspector 注入 BTAsset_Slime.tres / BTAsset_Boss.tres
##     - `agent_node`：留空（_ready 时本类用 NodePath(".") 自动指向自身）
##     - `autostart`：true
##
## 不再承担（已下沉）：
##   - 属性 Bootstrap → [AbilitySystemComponent.bootstrap_from_entity]
##   - Boss 阶段评估（基于 health 比例切换） → BTAsset 内 [BTCondition_SelfHealthBelow] + [code]BTAction_ApplyPhaseSpeed[/code]
class_name EnemyCharacter
extends BaseCharacter


## BTPlayer 节点（子节点名固定为 "BTPlayer"）。
@onready var bt_player: Node = $BTPlayer


# ─────────────────────────────────────────────────────────────
# 韧性 / 破韧（S4 削韧链路）
# ─────────────────────────────────────────────────────────────

## 韧性上限。普攻 [DamageNode.poise_damage] 默认 10，[code]poise_max=100[/code] 即 10 次普攻破一次。
@export var poise_max: float = 100.0

## 当前韧性。_ready 时初始化为 [member poise_max]；归零时触发破韧并重置满。
var poise_current: float = 0.0

## 全程破韧次数累计。供 [BTCondition_PoiseBrokenCount]（window_sec=0）读取。
var poise_broken_count: int = 0

## 破韧时间戳（毫秒）数组。供 [BTCondition_PoiseBrokenCount]（window_sec>0）滑动窗口判定。
var _poise_broken_history: Array[int] = []


# ─────────────────────────────────────────────────────────────
# 死亡视觉
# ─────────────────────────────────────────────────────────────

const DEATH_FADE_DURATION: float = 0.5

var _is_dead: bool = false
var _death_elapsed: float = 0.0


func _ready() -> void:
	# 敌人强制为 MONSTER kind（场景里仍可改 data_id）
	kind = ConfigCenter.CharacterKind.MONSTER
	add_to_group(&"enemy")
	super()
	poise_current = poise_max
	_setup_ai()
	_wire_damage_to_ai()
	# 监听自身 HP 变化做 dead 判定
	EventBus.attribute_changed.connect(_on_attr_changed)
	# 订阅 poise_broken：写自己 BTPlayer 黑板（用字符串风格 connect 兼容 EditorScript）
	EventBus.connect(&"poise_broken", _on_poise_broken_signal)
	EventBus.enemy_spawned.emit(self)


func _physics_process(delta: float) -> void:
	super(delta)
	if _is_dead:
		_tick_death(delta)


func _exit_tree() -> void:
	# 防止信号连接泄漏
	if EventBus.is_connected(&"poise_broken", _on_poise_broken_signal):
		EventBus.disconnect(&"poise_broken", _on_poise_broken_signal)


# ─────────────────────────────────────────────────────────────
# BaseCharacter 钩子覆盖
# ─────────────────────────────────────────────────────────────

func _get_required_attribute_set_classes() -> Array:
	# 与 Player 共用 PrimaryAttributeSet：让 attack_base / armor_base / crit_chance 等
	# CSV 里配置的字段能正常路由进 ASC（Char_Attr / Monster_Attr 共用同一套字段名）。
	# 副作用：敌人会多挂 16 个字段（暴击/吸血/穿透等），但都默认 0，DamagePipeline 取值时无影响。
	return [HealthSet, PrimaryAttributeSet, CombatSet]


func _should_skip_regens() -> bool:
	# 敌人不挂 Stamina/Block Regen
	return true


# ─────────────────────────────────────────────────────────────
# AI 接入（LimboAI BTPlayer）
# ─────────────────────────────────────────────────────────────

func _setup_ai() -> void:
	if bt_player == null:
		GameLogger.warn("AI", "[%s] no BTPlayer node child" % name)
		return
	# agent_node 留空：LimboAI 默认 agent = BTPlayer.get_parent()，正好是 EnemyCharacter 自身
	# （之前显式 set NodePath(".") 会把 agent 指向 BTPlayer 节点本身，导致所有 BTAction
	#  的 `agent.get(&"move_comp")` / `agent.get(&"asc")` 都拿到 null，BT 跑得起来但所有
	#  Action 都失败 → 看起来"完全不动"）
	# 把 player target 写到黑板，供 BTAction 子类 fallback 使用（任务自身也会用 group 兜底）
	var player: Node = _find_player()
	if player != null and bt_player.has_method(&"get_blackboard"):
		# LimboAI Blackboard 继承自 RefCounted（非 Resource），用 Object 静态类型兜底
		var bb: Object = bt_player.call(&"get_blackboard")
		if bb != null and bb.has_method(&"set_var"):
			bb.call(&"set_var", &"target", player)


func _wire_damage_to_ai() -> void:
	if hurtbox == null or bt_player == null:
		return
	hurtbox.damaged.connect(_on_hurtbox_damaged)


func _on_hurtbox_damaged(amount: float, source: Node) -> void:
	if bt_player == null or _is_dead:
		return
	# 写 BTPlayer 黑板键（payload 含 attacker_poise_level 接口预留给硬度系统）
	if bt_player.has_method(&"get_blackboard"):
		var bb: Object = bt_player.call(&"get_blackboard")
		if bb != null and bb.has_method(&"set_var"):
			bb.call(&"set_var", &"event_took_damage", {
				"amount": amount,
				"source": source,
				"attacker_poise_level": -1,  # 硬度系统接入后由 attacker.Ability 填入
			})


func _on_poise_broken_signal(broken_target: Node) -> void:
	# 仅响应"我自己"的破韧事件
	if broken_target != self:
		return
	if bt_player == null:
		return
	if bt_player.has_method(&"get_blackboard"):
		var bb: Object = bt_player.call(&"get_blackboard")
		if bb != null and bb.has_method(&"set_var"):
			bb.call(&"set_var", &"event_poise_broken", true)


func _on_attr_changed(owner_node: Node, attr_name: StringName, _old: float, new_value: float) -> void:
	if owner_node != self:
		return
	if attr_name != &"health":
		return
	if new_value <= 0.0 and not _is_dead:
		_handle_death()


func _find_player() -> Node:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return null
	return players[0]


# ─────────────────────────────────────────────────────────────
# 死亡处理
# ─────────────────────────────────────────────────────────────

func _handle_death() -> void:
	_is_dead = true
	_death_elapsed = 0.0
	# 停止移动
	if move_comp != null:
		move_comp.set_input_dir(Vector3.ZERO)
	# 关闭碰撞
	if hitbox != null:
		hitbox.enabled = false
	if hurtbox != null:
		hurtbox.monitoring = false
		hurtbox.monitorable = false
	# 抢断 BTPlayer：active=false 让它停 tick
	if bt_player != null and bt_player.has_method(&"set_active"):
		bt_player.call(&"set_active", false)
	# 战利品掉落：从 Monster_Data.drop_id 读取掉落表 id；缺列 / 0 → 不掉落
	_dispatch_loot_on_death()
	# 广播一次
	EventBus.enemy_died.emit(self)
	GameLogger.info("AI", "[%s] died" % name)


## 读 [code]Monster_Data.drop_id[/code]（缺列默认 0 → 不掉落），调 [LootSpawner.dispatch]。
##
## 加列方式：在 [code]Tools/Excel/怪物表.xlsx[/code] 的 Monster_Data sheet 末尾增列
## [code]drop_id[/code]（类型 [code]Int[/code]），值 = [code]Drop_Rule.id[/code]；
## 重新跑 excel2Config 导出后即生效。
func _dispatch_loot_on_death() -> void:
	if kind != ConfigCenter.CharacterKind.MONSTER or data_id <= 0:
		return
	var row: Dictionary = ConfigCenter.get_monster_data(data_id)
	if row.is_empty():
		return
	var drop_id: int = CsvLoader.as_int(row, "drop_id", 0)
	if drop_id <= 0:
		return
	LootSpawner.dispatch(drop_id, self)


func _tick_death(delta: float) -> void:
	_death_elapsed += delta
	# 淡出 modulate
	var alpha: float = clampf(1.0 - _death_elapsed / DEATH_FADE_DURATION, 0.0, 1.0)
	for child in get_children():
		if child is SpriteBase3D:
			(child as SpriteBase3D).modulate = Color(1.0, 1.0, 1.0, alpha)
		elif child is CanvasItem:
			(child as CanvasItem).modulate = Color(1.0, 1.0, 1.0, alpha)
		elif child is MeshInstance3D:
			(child as MeshInstance3D).transparency = 1.0 - alpha
	if _death_elapsed >= DEATH_FADE_DURATION:
		queue_free()


# ─────────────────────────────────────────────────────────────
# 韧性 / 破韧 API
# ─────────────────────────────────────────────────────────────

## 削韧入口（由 [DamagePipeline] 第 12 步调）。
##
## Q1 决策：破韧期间（持有 [code]Status.PoiseBroken[/code] tag）不再削韧、不重置 5s 计时；
## 视觉抖动与伤害结算由调用链上游 [HitFlashController] / [DamagePipeline] 主流程处理。
func apply_poise_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	if _is_dead:
		return
	# Q1：破韧期间早退
	if asc != null and asc.has_tag(&"Status.PoiseBroken"):
		return
	poise_current -= amount
	GameLogger.info("AI", "[%s] poise %.1f -> %.1f (-%.1f)" % [name, poise_current + amount, poise_current, amount])
	if poise_current <= 0.0:
		_trigger_poise_broken()


## 触发破韧。
##
## 流程：
##   1. 加 ASC tag [code]Status.PoiseBroken[/code]（DamagePipeline 第 5.5 步据此施加易伤倍率）
##   2. 累计 [member poise_broken_count] + 1
##   3. 追加时间戳到 [member _poise_broken_history]
##   4. emit [signal EventBus.poise_broken]（本类 _on_poise_broken_signal 写黑板）
##   5. 韧性重置满（避免 5s 内再次触发）
##
## 注：tag 移除与 [signal EventBus.poise_recovered] 由 [BTAction_EnterPoiseBroken]._exit 负责（5s 后）。
func _trigger_poise_broken() -> void:
	if asc != null:
		asc.add_tag(&"Status.PoiseBroken")
	poise_broken_count += 1
	_poise_broken_history.append(Time.get_ticks_msec())
	poise_current = poise_max  # 重置满
	GameLogger.info("AI", "[%s] POISE BROKEN! count=%d" % [name, poise_broken_count])
	# 字符串风格 emit_signal 兼容 EditorScript placeholder（运行时行为等价）
	EventBus.emit_signal(&"poise_broken", self)
