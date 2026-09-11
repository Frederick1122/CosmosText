@tool
extends EditorPlugin

const DOCK_SCRIPT := preload("res://addons/content_studio/ContentStudio.gd")

var dock: Control


func _enter_tree() -> void:
	dock = DOCK_SCRIPT.new()
	dock.name = "CosmoTextContentStudio"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
