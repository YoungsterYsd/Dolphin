## Boss AI（M5）。
##
## 继承 AIController，多加一个阶段机：HP 跌破 phase_thresholds（如 [0.7, 0.3]）
## 时切到下一阶段，emit boss_phase_changed，每阶段切换 attack_range / hit_stun。
##
## 阶段配置示例（默认）：
##   phase 0 (HP 100% - 70%): attack_range=70  / cd by ability
##   phase 1 (HP 70% - 30%):  attack_range=80  / 加快移动
##   phase 2 (HP 30% - 0%):   attack_range=100 / 狂暴
class_name BossAI
extends AIController

## HP 阈值（按比例 0.0-1.0），降序。HP 跌破即进入下一 phase。
@export var phase_thresholds: Array[float] = [0.7, 0.3]

## 各阶段移动速度倍率。
@export var phase_speed_mult: Array[float] = [1.0, 1.3, 1.6]

var current_phase: int = 0


func _ready() -> void:
	super()


## EnemyCharacter 在 attribute_changed 回调里调用本方法（health 变化时）。
func evaluate_phase(current_hp_ratio: float) -> void:
	var new_phase: int = 0
	for i in range(phase_thresholds.size()):
		if current_hp_ratio < phase_thresholds[i]:
			new_phase = i + 1
	if new_phase != current_phase:
		current_phase = new_phase
		_apply_phase()
		EventBus.boss_phase_changed.emit(enemy, current_phase)
		GameLogger.info("AI", "[%s] phase -> %d (HP %.0f%%)" % [enemy.name if enemy else "?", current_phase, current_hp_ratio * 100.0])


func _apply_phase() -> void:
	if enemy == null or enemy.move_comp == null:
		return
	# 调整移动速度
	if current_phase < phase_speed_mult.size():
		var base: float = enemy.move_comp.max_speed
		# 第一次改前先记住基础速度
		if not enemy.has_meta("base_speed"):
			enemy.set_meta("base_speed", base)
		enemy.move_comp.max_speed = enemy.get_meta("base_speed") * phase_speed_mult[current_phase]
