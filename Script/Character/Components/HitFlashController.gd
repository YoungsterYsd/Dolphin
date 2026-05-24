## 受击反馈控制器（HD-2D / 3D Sprite Billboard 路径）。
##
## 监听 [HurtboxComponent.damaged] 信号，给同级 [SpriteBase3D] 做"染色 → 还原" tween。
##
## 实现策略：
##   - 直接 tween [member SpriteBase3D.modulate] 染色再复原；不挂 material_override，
##     保持 SpriteBase3D 原生渲染管线（保证 billboard + 阴影正常）。
##   - 注：3D 下纯白闪不可实现（modulate 是乘法，无法把彩色贴图变白），改用红染。
##
## R-DATA-02：颜色 / 时长 走 [HitFeedbackConfig]。
## R-CHAR-02：仅 3D 路径，已删除 2D ShaderMaterial 兼容代码。
class_name HitFlashController
extends Node


## 自定义 sprite 引用（不填则从父节点子树自动查找首个 [SpriteBase3D]）。
@export var sprite_override: SpriteBase3D = null

## 自定义 hurtbox 引用（不填则查父节点 ^"HurtboxComponent"）。
@export var hurtbox_override: HurtboxComponent = null

# 视觉节点（仅 3D 路径）
var _sprite: SpriteBase3D = null
var _hurtbox: HurtboxComponent = null
var _tween: Tween = null

# ConfigCenter 缓存
var _flash_color: Color = Color.WHITE
var _flash_duration: float = 0.08
# tween 还原终点
var _orig_modulate: Color = Color.WHITE


func _ready() -> void:
	_resolve_sprite()
	_resolve_hurtbox()
	_pull_config()
	if _hurtbox != null:
		_hurtbox.damaged.connect(_on_damaged)
	else:
		GameLogger.warn("Character", "%s HitFlashController: no Hurtbox found, flash disabled" %
			(get_parent().name if get_parent() != null else "?"))


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

func flash(color: Color = Color.WHITE, duration: float = -1.0) -> void:
	if _sprite == null:
		return
	var d: float = duration if duration > 0.0 else _flash_duration
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_sprite.modulate = color
	_tween = create_tween()
	_tween.tween_property(_sprite, "modulate", _orig_modulate, d)


# ─────────────────────────────────────────────────────────────
# 内部
# ─────────────────────────────────────────────────────────────

func _on_damaged(_amount: float, _source: Node) -> void:
	flash(_flash_color, _flash_duration)


func _pull_config() -> void:
	# R-Core：ConfigCenter 走 class_name 强类型直访，配置启动期已 assert 加载
	var cfg: HitFeedbackConfig = ConfigCenter.get_hit_feedback_config()
	_flash_color = cfg.default_flash_color
	_flash_duration = cfg.default_flash_duration


func _resolve_sprite() -> void:
	if sprite_override != null:
		_sprite = sprite_override
	else:
		_sprite = NodeFinder.find_first_of_type(get_parent(), SpriteBase3D) as SpriteBase3D
	if _sprite != null:
		_orig_modulate = _sprite.modulate


func _resolve_hurtbox() -> void:
	if hurtbox_override != null:
		_hurtbox = hurtbox_override
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	_hurtbox = NodeFinder.find_first_child_of_type(parent, HurtboxComponent) as HurtboxComponent
