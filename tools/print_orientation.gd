extends SceneTree

func _init() -> void:
	print(ProjectSettings.get_setting("display/window/handheld/orientation"))
	quit()
