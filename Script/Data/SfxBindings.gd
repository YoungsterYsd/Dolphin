## SFX 音效绑定表（M8 引入）。
##
## sfx_id → AudioStream 映射。AudioManager 启动时加载。
## EventKeyframe.SFX_PLAY 的 payload 必须含 `{sfx_id: StringName}` 走查表（M8 起强制）。
class_name SfxBindings
extends Resource

## sfx_id → AudioStream（Dictionary[StringName, AudioStream]）。
## Inspector 直接编辑：Add Element → Key 填 StringName，Value 拖 AudioStream 资源。
@export var bindings: Dictionary = {}


## 查表。未找到返回 null。
func get_stream(sfx_id: StringName) -> AudioStream:
	if not bindings.has(sfx_id):
		return null
	var v = bindings[sfx_id]
	if v is AudioStream:
		return v
	return null


## 取所有已注册的 sfx_id（用于调试 / 编辑器列表）。
func get_all_ids() -> Array[StringName]:
	var arr: Array[StringName] = []
	for k in bindings.keys():
		if k is StringName:
			arr.append(k)
		else:
			arr.append(StringName(str(k)))
	return arr
