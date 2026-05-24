## 可交互对象接口（M11 NPC 系统）。
##
## 任何可被玩家按 G（combat_interact）触发的 Actor 都应该 [code]extends InteractableTarget[/code]
## 或者鸭子类型实现下列方法 / 信号。
##
## 标准接入步骤：
##   1. 子类挂 Area3D 检测玩家进入 → emit [signal player_entered_range]
##   2. 玩家按 G 时 [PlayerCharacter] 找最近可交互目标，调 [method interact]
##   3. interact 内部派发对话 / 商店 / 拾取等业务流程
##
## 设计原则（R-HUD-02 同源）：
##   - 业务侧不依赖 NPC 具体类型，只依赖本接口
##   - 接口只暴露行为（交互），不强制数据结构（NPC / 物体 / 触发器都可实现）
class_name InteractableTarget
extends Node3D


# ─────────────────────────────────────────────────────────────
# 信号
# ─────────────────────────────────────────────────────────────

## 玩家进入交互范围。HUD 订阅 → 显示 [InteractionPromptWidget]。
signal player_entered_range(target: InteractableTarget)

## 玩家离开交互范围。HUD 订阅 → 隐藏提示。
signal player_left_range(target: InteractableTarget)


# ─────────────────────────────────────────────────────────────
# 公开属性（子类配置）
# ─────────────────────────────────────────────────────────────

## 显示名（HUD 提示用）。
@export var display_name: String = "目标"

## 提示文本。例：「[G] 对话」「[G] 拾取」「[G] 打开」。
@export var prompt_text: String = "[G] 交互"

## 是否当前可交互（业务侧可动态切，比如完成任务前不可交互）。
@export var enabled: bool = true


# ─────────────────────────────────────────────────────────────
# 公开 API（子类必须实现 [method interact]）
# ─────────────────────────────────────────────────────────────

## 玩家按 G 触发的入口。子类覆盖。
func interact(_player: Node) -> void:
	push_warning("InteractableTarget.interact() not overridden by %s" % name)


## 玩家是否能立刻看到这个目标。子类可覆盖（默认 enabled）。
func is_interactable() -> bool:
	return enabled


# ─────────────────────────────────────────────────────────────
# 工具：取头顶提示锚点（IndicatorSystem / WorldProjector 用）
# ─────────────────────────────────────────────────────────────

## 头顶提示锚点（默认自身位置 + 1.8m 高度）。
## 子类可覆盖返回更精确的位置（如头部骨骼）。
func get_prompt_anchor() -> Vector3:
	return global_position + Vector3.UP * 1.8
