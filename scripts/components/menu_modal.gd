extends Control
## Menu window: switch between the desktop overlay and a normal window, and
## quit. An overlay has no title bar, so this is the way out of the game.

signal closed
signal mode_toggle_requested
signal quit_requested

const UIKit := preload("res://scripts/components/ui_kit.gd")

const PANEL_SIZE := Vector2(760, 470)

var content: RefCounted
var _mode_button: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(content_data: RefCounted, mode: String) -> void:
	content = content_data
	if get_child_count() == 0:
		_build()
	_mode_button.text = "Windowed" if mode == "overlay" else "Overlay"
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	var column := UIKit.modal_panel(self, PANEL_SIZE)
	column.add_theme_constant_override("separation", 26)
	column.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := UIKit.label("Menu", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var wide := Vector2(560, 84)
	_mode_button = UIKit.button(content, "Windowed", wide)
	_mode_button.pressed.connect(func() -> void: mode_toggle_requested.emit())
	column.add_child(_mode_button)

	var resume := UIKit.button(content, "Back to Caramelo", wide)
	resume.pressed.connect(close)
	column.add_child(resume)

	var quit := UIKit.button(content, "Quit game", wide)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
