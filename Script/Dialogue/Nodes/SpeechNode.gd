## 说话节点（Resource）。
##
## 显示一段对白；玩家按 combat_interact 推进。
## 文本支持 {var:x} / {tag:x} / {player_name} 占位符（由 [DialogueRunner._resolve_text] 解析）。
class_name SpeechNode
extends DialogueNode

## 说话者名（UI Speaker Label 显示）。
@export var speaker: StringName = &""

## 肖像 id（PortraitsConfig 解析为纹理路径；空 → 无肖像）。
@export var portrait_id: StringName = &""

## 对白文本。
@export_multiline var text: String = ""

## 语音 id（AudioManager 解析；空 → 无语音）。
@export var voice_id: StringName = &""


func get_node_kind() -> StringName:
	return &"speech"
