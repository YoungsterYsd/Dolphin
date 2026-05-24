## 攻击判定盒（3D）。
##
## 挂在攻击方角色下，命中目标的 [HurtboxComponent] 时通过自身信号通知所有者。
## enabled 切到 true 时除了 area_entered，还要主动检查"已在范围内"的 hurtbox（贴脸攻击修复，与 2D 版一致）。
class_name HitboxComponent
extends Area3D

## 命中目标（一般为对方的 [HurtboxComponent]）。
signal hit_landed(target: Node)

## Hitbox 是否启用（默认关闭，由 Ability 在攻击窗口期开启）。
@export var enabled: bool = false:
	set(v):
		var old: bool = enabled
		enabled = v
		monitoring = v
		monitorable = v
		# 关闭→开启 时主动检查已重叠的 hurtbox（贴脸攻击）
		if v and not old and is_inside_tree():
			_scan_existing_overlaps_deferred()


func _ready() -> void:
	monitoring = enabled
	monitorable = enabled
	area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area3D) -> void:
	if not enabled:
		return
	if area is HurtboxComponent:
		GameLogger.info("Character", "[Hitbox %s] hit (entered): %s" % [_owner_name(), area.get_parent().name])
		hit_landed.emit(area)


## 延迟到物理空间更新后扫描已重叠的 hurtbox。
func _scan_existing_overlaps_deferred() -> void:
	# 等下一帧物理空间稳定再 query（Godot 物理对 enable/disable 是 deferred 的）
	await get_tree().physics_frame
	if not enabled:
		return
	for area in get_overlapping_areas():
		if area is HurtboxComponent:
			GameLogger.info("Character", "[Hitbox %s] hit (overlap): %s" % [_owner_name(), area.get_parent().name])
			hit_landed.emit(area)


func _owner_name() -> String:
	var p := get_parent()
	return p.name if p != null else "?"
