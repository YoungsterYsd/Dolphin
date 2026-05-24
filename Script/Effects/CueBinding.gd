## CueBinding。
##
## 一条 cue tag 到具体表现层动作的绑定。由 [CueManager] 持有；
## 由 [CueBindings] 资源（Dictionary[StringName, CueBinding]）批量配置。
##
## 设计要点：
## - **不持有节点引用**：CueBinding 是 Resource，运行时被多个 instigator 共享
## - **多手段叠加**：sfx_id / vfx_scene_path / camera_shake / hit_stop_ms 可同时填写，execute 时叠加发出
## - **生命周期**：ONE_SHOT 走 [method execute]；LOOPING 走 [method add_active]/[method cleanup]（持续粒子资源后续接入后才完整可用）
##
## R-DATA-02：所有可调参数（数值、路径）走 .tres 配置；本脚本无硬编码业务数值。
class_name CueBinding
extends Resource

## Cue 生命周期。
enum CueLifetime {
	ONE_SHOT,   # 一次性：暴击音、命中震屏、伤害飘字 等
	LOOPING,    # 持续：buff 火焰特效、晕眩眩晕粒子（占位接口，实际持续粒子资源后续补）
}

## Cue 的 tag（仅作自记录，CueManager 内部按 Dictionary key 索引；本字段便于 .tres 检视）。
@export var cue_tag: StringName = &""

## 生命周期。
@export var lifetime: CueLifetime = CueLifetime.ONE_SHOT

## 表现手段 1：音效 ID（查 SfxBindings.tres）。空表示不发声。
@export var sfx_id: StringName = &""

## 表现手段 2：VFX 场景路径（res://Content/VFX/...tscn）。空表示不生成 VFX。
@export var vfx_scene_path: String = ""

## VFX 偏移（3D）。caster 为 Node3D 时使用。
@export var vfx_offset_3d: Vector3 = Vector3.ZERO

## VFX 偏移（2D 兼容）。caster 为 Node2D 时使用。
@export var vfx_offset_2d: Vector2 = Vector2.ZERO

## VFX 自动销毁时长（秒）。VFXSpawner.DEFAULT_LIFETIME 默认 1.5s；此处可覆盖。
## <= 0 时使用 VFXSpawner 默认值。
@export var vfx_lifetime: float = -1.0

## 表现手段 3：屏幕震动。x = intensity, y = duration（秒）。Vector2.ZERO 表示不震屏。
@export var camera_shake: Vector2 = Vector2.ZERO

## 表现手段 4：冻帧时长（毫秒）。<= 0 表示不冻帧。
@export var hit_stop_ms: float = 0.0


# ─────────────────────────────────────────────────────────────
# 公开 API（由 CueManager 调用）
# ─────────────────────────────────────────────────────────────

## 触发一次 ONE_SHOT cue。按字段非空依次发对应 EventBus 信号。
##
## CueManager 调用本方法前已做了 Tag 父匹配，本方法只负责具体派发。
##
## payload 由调用方传入（如 DamagePipeline 第 13 步携带 dealt/is_crit）；
## 内部仅在需要时把字段塞入 payload 副本（避免污染调用方 dict）。
func execute(instigator: Node, payload: Dictionary) -> void:
	# 1) 音效
	if sfx_id != &"":
		EventBus.skill_event_sfx.emit(sfx_id, instigator, payload)

	# 2) VFX
	if not vfx_scene_path.is_empty():
		var vfx_payload := payload.duplicate()
		vfx_payload["vfx_scene_path"] = vfx_scene_path
		if vfx_offset_3d != Vector3.ZERO:
			vfx_payload["offset_3d"] = vfx_offset_3d
		if vfx_offset_2d != Vector2.ZERO:
			vfx_payload["offset_2d"] = vfx_offset_2d
		if vfx_lifetime > 0.0:
			vfx_payload["lifetime"] = vfx_lifetime
		EventBus.skill_event_vfx.emit(&"", instigator, vfx_payload)

	# 3) 屏幕震动
	if camera_shake != Vector2.ZERO:
		EventBus.skill_event_camera_shake.emit(camera_shake.x, camera_shake.y, instigator)

	# 4) 冻帧
	if hit_stop_ms > 0.0:
		EventBus.skill_event_hit_stop.emit(hit_stop_ms, instigator)


## 启动一个 LOOPING cue（持续表现）。返回一个 handle Dictionary 由 CueManager 持有。
##
## 当前实现为占位：暂时与 ONE_SHOT 等价；未来"持续粒子 / 持续音效循环 / 持续 buff 视觉"
## 三类资源接入后再实装。
func add_active(instigator: Node, payload: Dictionary) -> Dictionary:
	# 占位：仅触发一次表现 + 返回最小 handle（cleanup 时无副作用）
	execute(instigator, payload)
	return {
		"cue_tag": cue_tag,
		"instigator_id": instigator.get_instance_id() if instigator != null else 0,
	}


## 停止 LOOPING cue。当前占位实现：无副作用。
func cleanup_handle(_handle: Dictionary) -> void:
	# 占位：未来接持续粒子销毁逻辑
	pass
