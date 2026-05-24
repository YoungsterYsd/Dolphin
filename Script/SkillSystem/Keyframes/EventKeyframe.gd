@tool
## 事件关键帧。
##
## 8 种 Kind 共用一个类，按 [member kind] 字段区分行为；具体参数放 [member payload]。
##
## kind 取值见 [SkillEventKind]，禁止用字面量字符串（R-DATA-02）。
##
## payload 约定（按 kind 不同）：
## - HITBOX_ENABLE: `{"node_path": "HitboxComponent", "damage_node_index": 0}`
## - HITBOX_DISABLE: `{"node_path": "HitboxComponent"}`
## - SFX_PLAY: `{"sfx_id": &"hit_01"}`
## - VFX_SPAWN: `{"vfx_id": &"slash_blue", "offset": Vector3.ZERO}`
## - PROJECTILE_SPAWN: `{"projectile_id": &"fireball", "direction": Vector3.RIGHT, "speed": 800.0}`
## - CAMERA_SHAKE: `{"intensity": 4.0, "duration": 0.15}`
## - HIT_STOP: `{"duration_ms": 80.0}`
## - CUSTOM_SIGNAL: `{"signal_name": &"my_event", "data": {...}}`
class_name EventKeyframe
extends SkillKeyframe

## 事件 Kind，取值见 [SkillEventKind]。
@export var kind: StringName = SkillEventKind.SFX_PLAY

## 事件参数。结构按 kind 不同（详见类注释）。
## 在编辑器内 Inspector 难以可视化编辑 Dictionary，编辑器会按 kind 提供专门 form。
@export var payload: Dictionary = {}
