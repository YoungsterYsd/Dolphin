## 肖像表（Resource）。
##
## 落库到 `Data/Manual/Config/PortraitsConfig.tres`。
## DialogueWidget 通过 [method get_texture_path] 把 SpeechNode.portrait_id 解析为 Texture2D 资源 path。
class_name PortraitsConfig
extends Resource

## portrait_id (StringName) → texture_path (String)
@export var portrait_paths: Dictionary = {}


## 解析 portrait_id 对应的纹理路径。
## 找不到时返回空字符串（DialogueWidget 应回退到 DialogueConfig.default_portrait_path）。
func get_texture_path(portrait_id: StringName) -> String:
	return portrait_paths.get(portrait_id, "")
