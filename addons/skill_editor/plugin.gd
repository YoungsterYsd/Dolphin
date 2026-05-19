@tool
## Skill Editor 插件入口（M7.4）。
##
## 功能：
##   - 在编辑器底部面板注册 [code]SkillEditorDock[/code]
##   - 通过 [method _handles] / [method _edit] / [method _make_visible] 让 [SkillTimeline] 资源
##     双击时自动切到本面板
##
## 启用方式：项目设置 → 插件 → Skill Editor 勾选启用。
##
## R-LOG-01 例外说明：本目录下的 @tool 脚本运行在编辑器进程，
## 无法访问 GameLogger（因依赖运行时 Autoload）。改用原生 push_error / push_warning。
extends EditorPlugin

# 不用 preload（编辑器首次启用插件时 .tscn 可能还没被 ResourceFilesystem 扫描，会 Parse Error）；
# 改为 _enter_tree 中 runtime load。
const DOCK_SCENE_PATH: String = "res://addons/skill_editor/dock/SkillEditorDock.tscn"
const BOTTOM_PANEL_TITLE: String = "Skill Editor"

var _dock: Control = null
var _bottom_panel_button: Button = null


func _enter_tree() -> void:
	var dock_scene: PackedScene = load(DOCK_SCENE_PATH) as PackedScene
	if dock_scene == null:
		push_error("[SkillEditor] DOCK_SCENE not found at %s" % DOCK_SCENE_PATH)
		return
	_dock = dock_scene.instantiate()
	_bottom_panel_button = add_control_to_bottom_panel(_dock, BOTTOM_PANEL_TITLE)
	# 注入 EditorInterface（Dock 自身在编辑器外不应依赖此引用）
	if _dock.has_method(&"_inject_editor_interface"):
		_dock.call(&"_inject_editor_interface", get_editor_interface(), get_undo_redo())


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null
	_bottom_panel_button = null


# ─────────────────────────────────────────────────────────────
# 双击资源时自动切到本面板
# ─────────────────────────────────────────────────────────────

func _handles(object: Object) -> bool:
	return object is SkillTimeline


func _edit(object: Object) -> void:
	if _dock == null:
		return
	if object is SkillTimeline:
		_dock.call(&"open_timeline", object as SkillTimeline)


func _make_visible(visible: bool) -> void:
	if _bottom_panel_button == null or _dock == null:
		return
	if visible:
		make_bottom_panel_item_visible(_dock)
