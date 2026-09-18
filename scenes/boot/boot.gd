extends Control
## Entry scene. Opens the main scene when the content catalog loaded and
## validated; otherwise shows the errors in a normal window.

const MAIN_SCENE := "res://scenes/main/main.tscn"

@onready var _label: Label = $Label


func _ready() -> void:
	if ContentCatalog.data.is_valid():
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
		return
	PlatformService.enter_windowed(Vector2i(1280, 720), Color("#202020"), -1)
	_label.text = "Content data failed validation:\n" + "\n".join(ContentCatalog.data.errors.slice(0, 20))
