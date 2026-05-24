@tool
## 技能编辑器预览舞台配置。
##
## 编辑器内嵌预览的可调参数全部走配置表（R-DATA-02 合规）。
## 仅供 [code]addons/skill_editor/dock/preview/*[/code] 读写；运行时不依赖。
##
## 持久化：编辑器内静音/拖拽 SpriteFrames 后由 PreviewStage 调 [code]ResourceSaver.save[/code] 写回。
class_name PreviewStageConfig
extends Resource

## 上次拖入的 SpriteFrames 资源路径（重启编辑器后自动恢复）。
@export var last_sprite_frames_path: String = ""

## 是否静音音效预览。
@export var mute_audio: bool = false

## SubViewport 像素尺寸。
@export var viewport_size: Vector2i = Vector2i(512, 288)

## 预览相机 zoom（默认 1=1:1，越小越远）。
@export_range(0.25, 4.0, 0.05) var camera_zoom: float = 1.0

## VFX 场景默认存活时间（payload 未提供 lifetime 时兜底）。
@export_range(0.1, 10.0, 0.1) var default_vfx_lifetime: float = 1.5

## CameraShake 衰减来回数（数值越大越平滑越长）。
@export_range(2, 12, 1) var camera_shake_steps: int = 4

## 是否在 TimelineView 渲染 hitbox 区间色带。
@export var show_hitbox_band: bool = true

## hitbox 区间色带颜色。
@export var hitbox_band_color: Color = Color(1.0, 0.25, 0.25, 0.18)
