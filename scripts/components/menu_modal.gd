extends Control
## Menu window: display options, and quitting. An overlay has no title bar,
## so this is the way out of the game.
##
## Toggles show their current state in the label ("Always on top: On") and
## report the change; the main scene applies and saves it.

signal closed
signal mode_toggle_requested
signal size_cycle_requested
signal option_toggled(option: String)
signal quit_requested

const UIKit := preload("res://scripts/components/ui_kit.gd")

const PANEL_SIZE := Vector2(820, 760)
const CLOSE_SIZE := 76.0
## Options that are on until the player turns them off.
const DEFAULT_ON := ["drag_to_move"]
## Option key -> label.
const OPTIONS := {
	"drag_to_move": "Drag to move",
	"always_on_top": "Always on top",
	"fps_cap_30": "30 FPS cap",
	"start_with_os": "Start with the computer",
}

var content: RefCounted
var _mode_button: Button
var _size_button: Button
var _option_buttons := {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## settings: the saved option values; unavailable: option -> reason it is
## greyed out.
func open(content_data: RefCounted, mode: String, settings: Dictionary, unavailable: Dictionary = {},
		size_name: String = "medium") -> void:
	content = content_data
	if get_child_count() == 0:
		_build()
	_mode_button.text = "Switch to window" if mode == "overlay" else "Switch to overlay"
	_size_button.text = size_label(size_name)
	_size_button.disabled = mode != "overlay"
	for option in OPTIONS:
		var button: Button = _option_buttons[option]
		var value := bool(settings.get(option, option in DEFAULT_ON))
		button.text = option_label(option, value, unavailable.get(option, ""))
		button.disabled = unavailable.has(option)
	# These only mean something for the overlay.
	_option_buttons["always_on_top"].disabled = mode != "overlay"
	_option_buttons["drag_to_move"].disabled = mode != "overlay"
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	var column := UIKit.modal_panel(self, PANEL_SIZE)
	column.add_theme_constant_override("separation", 20)
	column.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := UIKit.label("Menu", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var wide := Vector2(640, 80)
	_mode_button = UIKit.button(content, "", wide)
	_mode_button.pressed.connect(func() -> void: mode_toggle_requested.emit())
	column.add_child(_mode_button)

	_size_button = UIKit.button(content, "", wide)
	_size_button.pressed.connect(func() -> void: size_cycle_requested.emit())
	column.add_child(_size_button)

	for option in OPTIONS:
		var button := UIKit.button(content, "", wide)
		button.pressed.connect(func() -> void: option_toggled.emit(option))
		column.add_child(button)
		_option_buttons[option] = button

	var quit := UIKit.button(content, "Quit game", wide)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit)

	# X in the panel's top-right corner closes the menu.
	var close_button := UIKit.button(content, "X", Vector2(CLOSE_SIZE, CLOSE_SIZE))
	close_button.set_anchors_preset(Control.PRESET_CENTER)
	close_button.position = Vector2(PANEL_SIZE.x / 2.0 - CLOSE_SIZE - 22.0, -PANEL_SIZE.y / 2.0 + 22.0)
	close_button.pressed.connect(close)
	add_child(close_button)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## "Size: Medium". Pure.
static func size_label(size_name: String) -> String:
	return "Size: %s" % size_name.capitalize()


## "Always on top: On", or the reason it is unavailable. Pure.
static func option_label(option: String, value: bool, unavailable_reason: String = "") -> String:
	if unavailable_reason != "":
		return "%s: %s" % [OPTIONS.get(option, option), unavailable_reason]
	return "%s: %s" % [OPTIONS.get(option, option), "On" if value else "Off"]
