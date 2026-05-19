## 受击闪白控制器（M8 引入）。
##
## 挂在角色根节点下；监听父节点的 HurtboxComponent.damaged 信号 → 给同级 sprite 设
## flash_strength=1.0，Tween 在 `default_flash_duration` 秒内回 0。
##
## R-DATA-02：闪白颜色 / 时长 走 HitFeedbackConfig；不硬编码。
## R-CHAR-01：sprite 自动查（AnimatedSprite2D / Sprite2D / AnimatedSprite3D / Sprite3D 都支持）；
##   M9 切 3D 时无需改本类，只需准备一个 spatial 版 HitFlash3D.gdshader。
class_name HitFlashController
extends Node

const HIT_FLASH_SHADER_2D := "res://Content/Shaders/HitFlash.gdshader"
const HIT_FLASH_SHADER_3D := "res://Content/Shaders/HitFlash3D.gdshader"  # M9 创建

## 自定义 sprite 引用（不填则自动查父节点子树第一个 AnimatedSprite*/Sprite*）。
@export var sprite_override: CanvasItem = null

## 自定义 hurtbox 引用（不填则自动查父节点 ^"HurtboxComponent"）。
@export var hurtbox_override: HurtboxComponent = null

var _sprite_2d: CanvasItem = null
var _sprite_3d: VisualInstance3D = null  # M9 时用 Sprite3D
var _hurtbox: HurtboxComponent = null
var _material: ShaderMaterial = null
var _tween: Tween = null

# 从 ConfigCenter 取的参数（缓存）
var _flash_color: Color = Color.WHITE
var _flash_duration: float = 0.08


func _ready() -> void:
	_resolve_sprite()
	_resolve_hurtbox()
	_apply_shader_material()
	_pull_config()
	if _hurtbox != null:
		_hurtbox.damaged.connect(_on_damaged)
	else:
		GameLogger.warn("Character", "%s HitFlashController: no Hurtbox found, flash disabled" % get_parent().name)


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 主动触发一次闪白（外部代码可调，如格挡 / 治疗反向闪绿）。
func flash(color: Color = Color.WHITE, duration: float = -1.0) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"flash_color", color)
	_material.set_shader_parameter(&"flash_strength", 1.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var d: float = duration if duration > 0.0 else _flash_duration
	_tween.tween_property(_material, "shader_parameter/flash_strength", 0.0, d)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _on_damaged(_amount: float, _source: Node) -> void:
	flash(_flash_color, _flash_duration)


func _pull_config() -> void:
	var cfg_node: Node = get_tree().root.get_node_or_null(^"ConfigCenter")
	if cfg_node == null:
		return
	var cfg = cfg_node.get_hit_feedback_config()
	if cfg != null:
		_flash_color = cfg.default_flash_color
		_flash_duration = cfg.default_flash_duration


func _resolve_sprite() -> void:
	if sprite_override != null:
		_sprite_2d = sprite_override
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	# 深度优先找第一个 sprite
	var stack: Array = [parent]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		# 2D
		if n is AnimatedSprite2D or n is Sprite2D:
			_sprite_2d = n
			return
		# 3D（M9）
		if n is AnimatedSprite3D or n is Sprite3D:
			_sprite_3d = n
			return
		for c in n.get_children():
			stack.push_back(c)


func _resolve_hurtbox() -> void:
	if hurtbox_override != null:
		_hurtbox = hurtbox_override
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var direct: Node = parent.get_node_or_null(^"HurtboxComponent")
	if direct is HurtboxComponent:
		_hurtbox = direct


func _apply_shader_material() -> void:
	if _sprite_2d != null:
		var shader_res: Shader = load(HIT_FLASH_SHADER_2D) as Shader
		if shader_res == null:
			GameLogger.warn("Character", "HitFlashController: shader not found at %s" % HIT_FLASH_SHADER_2D)
			return
		# 若 sprite 已有 ShaderMaterial 且 shader 一致，复用；否则新建
		if _sprite_2d.material is ShaderMaterial and (_sprite_2d.material as ShaderMaterial).shader == shader_res:
			_material = _sprite_2d.material
		else:
			_material = ShaderMaterial.new()
			_material.shader = shader_res
			_sprite_2d.material = _material
		_material.set_shader_parameter(&"flash_strength", 0.0)
	elif _sprite_3d != null:
		# M9 时实装：加载 spatial shader 并挂到 sprite_3d.material_override
		var shader_3d: Shader = null
		if ResourceLoader.exists(HIT_FLASH_SHADER_3D):
			shader_3d = load(HIT_FLASH_SHADER_3D) as Shader
		if shader_3d == null:
			# M9 前 spatial shader 不存在 → 跳过，不报错
			return
		_material = ShaderMaterial.new()
		_material.shader = shader_3d
		# Sprite3D / MeshInstance3D 都有 material_override
		if _sprite_3d.has_method(&"set_material_override"):
			_sprite_3d.call(&"set_material_override", _material)
		_material.set_shader_parameter(&"flash_strength", 0.0)
