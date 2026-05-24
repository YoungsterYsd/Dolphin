## 「可读属性」契约（Resource）。
##
## HUD widget（血条 / 蓝条 / 经验条 / Buff 时长 等）通过本契约访问业务属性，
## 不需要知道具体的 AttributeSet / Component / 业务类（R-HUD-02）。
##
## 实现方应：
##   1) 在 [method get_value] 返回当前数值
##   2) 在 [method get_max_value] 返回上限（如不适用返回 1.0，让 widget 显示纯数值）
##   3) 当数值变化时 emit [signal value_changed]
##
## 注：信号名用 `value_changed` 而非 `changed`，避免与 Resource 基类自带的 `changed` 信号冲突。
##
## 典型 Provider 实现样例（Phase 2/3 落地时具化）：
##   - AttributeProvider：包一个 AttributeSet + 属性名
##   - StatProvider：直接持几个数值字段（用于 Mock / Showcase 喂假数据）
class_name IAttributeReadable
extends Resource

## 数值变化（旧 / 新）。HUD 订阅此信号刷新。
signal value_changed(old_value: float, new_value: float)

## 当前值。
func get_value() -> float:
	return 0.0

## 上限。无上限时返回 1.0。
func get_max_value() -> float:
	return 1.0

## 关联的属性名（调试 / 标签用，可选）。
func get_attribute_name() -> StringName:
	return &""

## 比例（0~1）。默认实现：value / max；max <= 0 时返回 0。
func get_ratio() -> float:
	var maxv := get_max_value()
	if maxv <= 0.0:
		return 0.0
	return clampf(get_value() / maxv, 0.0, 1.0)
