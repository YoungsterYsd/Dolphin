## HUD 单个 widget 挂载条目（Resource）。
##
## 描述「某个 widget 场景挂在哪个 Slot 上、优先级、是否启用」。
## 由 [HUDLayoutResource.mounts] 数组持有，由 [UIExtensionSubsystem] 解析挂载。
##
## 拆为独立 class_name 是为了让 .tres 能用 sub_resource 直接序列化
## （Godot 不能很好地序列化 inner class）。
class_name HUDWidgetMount
extends Resource

## 要实例化的 widget 场景。
@export var widget_scene: PackedScene

## 要挂到的 Slot（必须是 HUDManager.SLOT_TAGS 之一：
##   TopLeft / TopCenter / TopRight / BottomLeft / BottomCenter / BottomRight / Center）。
@export var slot_tag: StringName = &""

## 同槽位排序优先级（越大越靠前）。
@export var priority: int = 0

## 是否启用（false 时本条目跳过挂载，可配合调试快速 disable）。
@export var enabled: bool = true
