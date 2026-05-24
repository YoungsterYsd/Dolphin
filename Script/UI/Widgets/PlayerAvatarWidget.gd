## 玩家头像 + 等级数字。
##
## 显示左上角小方块（头像占位）+ 右下角等级数字。
## 等级数据：监听 [signal EventBus.attribute_changed] 中 [code]attr == &"level"[/code] 的事件。
##
## **前置依赖**：当前 AttributeSet 体系没有 [code]level[/code] 属性，
## 暂时显示占位 "Lv.1"；等等级系统接入后自动连通。
##
## 头像图：
##   - 业务侧可通过 set_avatar_texture(tex) 注入
##   - 没有图时显示纯色矩形占位
class_name PlayerAvatarWidget
extends BaseWidget

## 占位级别（无 level 属性时显示）。
@export var fallback_level: int = 1

@onready var avatar_rect: TextureRect = $AvatarRect
@onready var fallback: ColorRect = $Fallback
@onready var level_label: Label = $LevelLabel


func _ready() -> void:
	super._ready()
	level_label.text = "Lv.%d" % fallback_level
	EventBus.attribute_changed.connect(_on_attribute_changed)


func _on_attribute_changed(owner_node: Node, attr_name: StringName, _old_value: float, new_value: float) -> void:
	if owner_node == null or not owner_node.is_in_group(&"player"):
		return
	if attr_name != &"level":
		return
	level_label.text = "Lv.%d" % int(new_value)


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 业务侧可注入头像图（如换装系统切换皮肤）。
func set_avatar_texture(tex: Texture2D) -> void:
	if tex == null:
		avatar_rect.texture = null
		avatar_rect.visible = false
		fallback.visible = true
	else:
		avatar_rect.texture = tex
		avatar_rect.visible = true
		fallback.visible = false
