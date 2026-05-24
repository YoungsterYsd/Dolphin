## 「可读冷却」契约（Resource）。
##
## 用于技能槽 Hotbar 渲染冷却遮罩；widget 不直接持有 ASC，仅依赖本契约。
##
## 实现方应：
##   1) 在 [method get_cooldown_remaining] 返回剩余秒数（≤0 表示就绪）
##   2) 在 [method get_cooldown_max] 返回总冷却（用于计算遮罩比例）
##   3) 冷却开始 / 结束 / 进度变化时 emit 对应信号
##
## 现有 [AbilitySystemComponent.get_cooldown_remaining] 可被一层薄 Adapter 包装为本契约。
class_name ICooldownReadable
extends Resource

## 进入冷却（刚被触发）。
signal cooldown_started(max_seconds: float)

## 冷却结束（剩余 → 0）。
signal cooldown_ended

## 剩余冷却（秒）。≤ 0 表示就绪。
func get_cooldown_remaining() -> float:
	return 0.0

## 总冷却（秒）。
func get_cooldown_max() -> float:
	return 1.0

## 关联的能力 id（标签用）。
func get_ability_id() -> StringName:
	return &""

## 比例（0~1，1 = 满 CD）。
func get_ratio() -> float:
	var maxv := get_cooldown_max()
	if maxv <= 0.0:
		return 0.0
	return clampf(get_cooldown_remaining() / maxv, 0.0, 1.0)
