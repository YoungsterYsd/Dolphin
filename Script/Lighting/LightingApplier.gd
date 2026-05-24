## 光照/后处理配置应用器。
##
## 挂在 3D 关卡场景的子节点（一般在 WorldEnvironment 旁），_ready 时从 ConfigCenter 读取
## LightingConfig + PostProcessConfig 并写入同场景下的 WorldEnvironment + DirectionalLight3D。
##
## 这样关卡 .tscn 里的 WorldEnvironment 只是占位，真正参数由 .tres 配置驱动（R-DATA-02）。
##
## 用法：
##   - 关卡场景挂一个 LightingApplier 节点（不需要参数）
##   - 关卡里至少有 WorldEnvironment 节点（路径可在 _resolve_targets 自动查）
##   - 改 Data/Config/LightingConfig.tres / PostProcessConfig.tres 后调 reload() 即可
class_name LightingApplier
extends Node


@export var auto_apply_on_ready: bool = true


func _ready() -> void:
	if auto_apply_on_ready:
		# defer 一帧确保 WorldEnvironment 已 ready
		call_deferred(&"apply")


## 主动重新应用配置（运行时调试用）。
func apply() -> void:
	# R-Core：ConfigCenter 走 class_name 强类型直访
	var lighting_cfg: LightingConfig = ConfigCenter.get_lighting_config()
	var pp_cfg: PostProcessConfig = ConfigCenter.get_post_process_config()
	_apply_lighting(lighting_cfg)
	_apply_post_process(pp_cfg)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _apply_lighting(cfg: LightingConfig) -> void:
	if cfg == null:
		return
	# 找当前场景下的 DirectionalLight3D + WorldEnvironment
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var dir_light: DirectionalLight3D = _find_first(scene, &"DirectionalLight3D") as DirectionalLight3D
	var world_env: WorldEnvironment = _find_first(scene, &"WorldEnvironment") as WorldEnvironment
	# DirectionalLight3D
	if dir_light != null:
		dir_light.light_color = cfg.main_light_color
		dir_light.light_energy = cfg.main_light_energy
		dir_light.shadow_enabled = cfg.shadow_enabled
		dir_light.rotation_degrees = cfg.main_light_rotation_deg
	# WorldEnvironment 环境
	if world_env != null and world_env.environment != null:
		var env: Environment = world_env.environment
		env.ambient_light_color = cfg.ambient_color
		env.ambient_light_energy = cfg.ambient_energy
		# Sky（如果用的是 ProceduralSkyMaterial）
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky_mat: ProceduralSkyMaterial = env.sky.sky_material
			sky_mat.sky_horizon_color = cfg.sky_horizon_color
			sky_mat.sky_top_color = cfg.sky_top_color
		# Fog
		env.fog_enabled = cfg.fog_enabled
		env.fog_density = cfg.fog_density
		env.fog_light_color = cfg.fog_light_color


func _apply_post_process(cfg: PostProcessConfig) -> void:
	if cfg == null:
		return
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var world_env: WorldEnvironment = _find_first(scene, &"WorldEnvironment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment
	# DOF：Godot 4.x 移到 CameraAttributesPractical 上；本里程碑先跳过 DOF（PostProcessConfig 的 dof_* 字段保留以备后续）。
	# SSAO
	env.ssao_enabled = cfg.ssao_enabled
	env.ssao_intensity = cfg.ssao_intensity
	env.ssao_radius = cfg.ssao_radius
	env.ssao_power = cfg.ssao_power
	# Bloom (Glow)
	env.glow_enabled = cfg.bloom_enabled
	env.glow_intensity = cfg.bloom_intensity
	env.glow_strength = cfg.bloom_strength
	env.glow_hdr_threshold = cfg.bloom_threshold
	# Tonemap
	env.tonemap_mode = cfg.tonemap_mode
	env.tonemap_exposure = cfg.tonemap_exposure
	env.tonemap_white = cfg.tonemap_white


func _find_first(root: Node, type_name: StringName) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_class() == String(type_name):
			return n
		for c in n.get_children():
			stack.push_back(c)
	return null
