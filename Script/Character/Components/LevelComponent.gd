## LevelComponent（玩家专属，敌人不挂）。
##
## ── 职责 ──
## 玩家等级 / 经验业务逻辑：
##   1. 接管 [ProgressionSet] 三件套（level / experience / xp_to_next）的初始化
##   2. 提供 [method add_experience] 公共 API（任务奖励 / 击杀掉落经验 / 调试键全部走它）
##   3. 升级判定 + 多级跨越循环结算
##   4. 升级时调 [method AbilitySystemComponent.recompute_level_attributes] 重算 Char_Attr，
##      并按"保留比例"策略调整当前 HP / 体力（升级前 50% HP，升级后仍是新 max 的 50%）
##   5. 派发 [signal EventBus.player_leveled_up] + [signal EventBus.hud_big_banner_requested(&"level_up")]
##
## ── 与怪物等级机制的对比 ──
## 怪物等级在 [code]Monster_Data.csv[/code] 静态定死，永不变化；本组件**仅玩家挂载**。
##
## ── 时序 ──
## ASC.bootstrap_from_entity 完成后会 emit [signal EventBus.character_initialized]，
## 本组件订阅它，在 callback 里把 ProgressionSet 初始化为 (level=1, experience=0, xp_to_next=Hero_Lev[1].Exp)。
##
## ── 节点接线约定 ──
## 作为 [PlayerCharacter] 的子节点挂载，与 [InventoryComponent] / [EnergyComponent] 同级。
## _ready 时通过 NodeFinder 找到父节点的 ASC，并订阅 character_initialized。
class_name LevelComponent
extends Node


# ─────────────────────────────────────────────────────────────
# 运行时缓存（_ready 后只读，避免每帧 find）
# ─────────────────────────────────────────────────────────────

var _asc: AbilitySystemComponent = null
var _kind: int = -1
var _data_id: int = 0


# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	# 订阅角色 8 步初始化完成事件，在那之后接管 ProgressionSet
	EventBus.character_initialized.connect(_on_character_initialized)


# ─────────────────────────────────────────────────────────────
# 公共 API
# ─────────────────────────────────────────────────────────────

## 累加经验（任务奖励 / 击杀掉落 / 调试键统一入口）。
##
## 自动处理：
## - 满级时拒绝累加（直接 return，打 info 日志）
## - 跨多级时连续派发多次 [signal EventBus.player_leveled_up]
## - 升级后调 ASC.recompute_level_attributes 重算 Char_Attr，按比例保留 HP/体力
##
## [param amount] 必须 >= 0；负数视为参数错误（assert 崩）。
func add_experience(amount: int) -> void:
	assert(amount >= 0, "LevelComponent.add_experience: amount must be >= 0, got %d" % amount)
	if amount == 0:
		return
	if _asc == null:
		# character_initialized 还没派发；按"丢弃 + warn"处理（业务侧应等初始化完成再喂经验）
		GameLogger.warn("Progression", "add_experience called before init, amount=%d dropped" % amount)
		return

	# 满级：拒绝累加
	var current_level: int = int(_asc.get_attribute(&"level", 1.0))
	if current_level >= ConfigCenter.get_max_level():
		GameLogger.info("Progression", "add_experience(%d) ignored: already max level (%d)" % [
			amount, current_level
		])
		return

	# 累加到 experience 字段（先做累加，再走升级循环）
	var new_exp: float = _asc.get_attribute(&"experience", 0.0) + float(amount)
	_asc.set_attribute(&"experience", new_exp)

	# 升级循环：experience >= xp_to_next 时连跳
	_settle_levelups()


# ─────────────────────────────────────────────────────────────
# 内部 - 初始化
# ─────────────────────────────────────────────────────────────

func _on_character_initialized(character: Node) -> void:
	# 仅响应"我自己父节点"的初始化
	var parent := get_parent()
	if character != parent:
		return
	# 缓存 ASC + 角色定位（kind/data_id）以便升级时调 recompute
	_asc = parent.get(&"asc") as AbilitySystemComponent if &"asc" in parent else null
	if _asc == null:
		GameLogger.error("Progression", "LevelComponent: parent has no asc field, abort init")
		return
	# kind/data_id 来自 BaseCharacter 的 export 字段
	_kind = int(parent.get(&"kind"))
	_data_id = int(parent.get(&"data_id"))

	# 如果父节点没挂 ProgressionSet（如非玩家误用本组件），跳过初始化
	if not _asc.has_attribute(&"level"):
		GameLogger.warn("Progression", "LevelComponent: ASC has no ProgressionSet, abort init")
		_asc = null
		return

	# 初始化三件套
	_asc.set_attribute(&"level", 1.0)
	_asc.set_attribute(&"experience", 0.0)
	var first_xp: int = ConfigCenter.get_xp_to_next(1)
	_asc.set_attribute(&"xp_to_next", float(first_xp))

	GameLogger.info("Progression", "[%s] LevelComponent init: lv=1 xp_to_next=%d max_level=%d" % [
		parent.name, first_xp, ConfigCenter.get_max_level()
	])


# ─────────────────────────────────────────────────────────────
# 内部 - 升级循环
# ─────────────────────────────────────────────────────────────

## 把 experience 朝 xp_to_next 比对一直循环升级，直到 experience < xp_to_next 或满级。
## 每升一级都按"保留比例"重算 Char_Attr，并派发信号；HUD 横幅由 BigBannerWidget
## 订阅 [signal EventBus.hud_big_banner_requested(&"level_up")] 显示，仅每个 add_experience
## 调用末尾派发一次（多级跨越只闪一次横幅，避免视觉刷屏）。
func _settle_levelups() -> void:
	var did_levelup: bool = false
	var max_lv: int = ConfigCenter.get_max_level()

	while true:
		var current_level: int = int(_asc.get_attribute(&"level", 1.0))
		if current_level >= max_lv:
			# 满级：清掉溢出经验（不允许"满级时仍有经验"歧义状态）
			if _asc.get_attribute(&"experience", 0.0) > 0.0:
				_asc.set_attribute(&"experience", 0.0)
			if _asc.get_attribute(&"xp_to_next", 0.0) > 0.0:
				_asc.set_attribute(&"xp_to_next", 0.0)
			break

		var current_exp: float = _asc.get_attribute(&"experience", 0.0)
		var need: float = _asc.get_attribute(&"xp_to_next", 0.0)
		if need <= 0.0 or current_exp < need:
			break

		# 升一级：扣经验 → 改等级 → 写新 xp_to_next → 重算属性 → 派发信号
		_apply_one_levelup(current_level, current_exp - need)
		did_levelup = true

	if did_levelup:
		# 多级跨越只闪一次横幅
		EventBus.hud_big_banner_requested.emit(&"level_up")


## 单次升级核心步骤。
## [param old_level]：升级前等级
## [param remaining_exp]：扣减 xp_to_next 后的剩余经验（带入下一级）
func _apply_one_levelup(old_level: int, remaining_exp: float) -> void:
	var new_level: int = old_level + 1

	# 1) 升级前记 HP / 体力比例（保留比例策略）
	var hp_ratio: float = _safe_ratio(_asc.get_attribute(&"health", 0.0),
		_asc.get_attribute(&"max_health", 0.0))
	var stamina_ratio: float = _safe_ratio(_asc.get_attribute(&"stamina_current", 0.0),
		_asc.get_attribute(&"stamina_max", 0.0))

	# 2) 改等级（先改，让 attribute_changed 让 LevelUpWidget / PlayerAvatar 立刻刷）
	_asc.set_attribute(&"level", float(new_level))

	# 3) 重算 Char_Attr 成长属性（不动 GE，不拉满当前值）
	_asc.recompute_level_attributes(_kind, _data_id, new_level)

	# 4) 按比例同步当前 HP / 体力到新上限
	var new_max_hp: float = _asc.get_attribute(&"max_health", 0.0)
	if new_max_hp > 0.0:
		_asc.set_attribute(&"health", new_max_hp * hp_ratio)
	var new_max_stamina: float = _asc.get_attribute(&"stamina_max", 0.0)
	if new_max_stamina > 0.0:
		_asc.set_attribute(&"stamina_current", new_max_stamina * stamina_ratio)

	# 5) 写新等级的 xp_to_next（满级时返回 0）
	var new_need: int = ConfigCenter.get_xp_to_next(new_level)
	_asc.set_attribute(&"xp_to_next", float(new_need))

	# 6) 写溢出经验到下一级进度
	_asc.set_attribute(&"experience", remaining_exp)

	# 7) 派发"升级语义"信号
	EventBus.player_leveled_up.emit(get_parent(), old_level, new_level)
	GameLogger.info("Progression", "[%s] LEVEL UP: %d -> %d, max_hp=%.1f new_xp_to_next=%d" % [
		get_parent().name, old_level, new_level, new_max_hp, new_need
	])


# ─────────────────────────────────────────────────────────────
# 工具
# ─────────────────────────────────────────────────────────────

static func _safe_ratio(numer: float, denom: float) -> float:
	if denom <= 0.0:
		return 1.0  # 升级前没有 max（异常）→ 拉满处理
	return clampf(numer / denom, 0.0, 1.0)
