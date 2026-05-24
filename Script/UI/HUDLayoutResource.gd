## HUD 布局集（Resource）。
##
## 描述「在某个游戏阶段，哪些 widget 挂在哪个 Slot 上」。
## 由 [UIExtensionSubsystem.reload_layout] 加载并批量注册到对应槽位。
##
## 一份 .tres 描述一份完整布局，例如：
##   - HUDLayout_Default.tres：主世界默认布局
##   - HUDLayout_BossRush.tres：BossRush 模式（隐藏 Minimap，显示 WaveCounter）
##   - HUDLayout_Cutscene.tres：过场（仅保留字幕）
##
## 注意：本 Resource 仅做「数据声明」；真正的实例化与挂载由 UIExtensionSubsystem 负责。
class_name HUDLayoutResource
extends Resource


## 调试名（编辑器显示）。
@export var layout_name: String = ""

## widget 列表。每个条目独立配置 slot / priority / enabled。
## 元素类型见 [HUDWidgetMount]。
@export var mounts: Array[HUDWidgetMount] = []
