extends Control
## Menu window: display options, and quitting. An overlay has no title bar,
## so this is the way out of the game.
##
## Toggles show their current state in the label ("Always on top: On") and
## report the change; the main scene applies and saves it.
##
## Starting over is the one thing here that destroys something, so it asks
## first: the button opens a panel over the menu and only that panel's yes
## reports it. Anything else -- its no, a click beside it, Escape -- leaves
## the game alone.

signal closed
signal mode_toggle_requested
signal size_cycle_requested
signal language_cycle_requested
signal option_toggled(option: String)
signal reset_requested
signal quit_requested

const UIKit := preload("res://scripts/components/ui_kit.gd")
const Localization := preload("res://scripts/systems/localization.gd")

const PANEL_SIZE := Vector2(820, 960)
const CONFIRM_SIZE := Vector2(760, 520)
const CLOSE_SIZE := 76.0
const RESET_LABEL := "Reset game"
const CONFIRM_TITLE := "Start over?"
const CONFIRM_BODY := "Level, bones, upgrades, dumbbells, food, furniture and outfits all go back to the beginning. Your window settings stay as they are. This cannot be undone."
const CONFIRM_YES := "Yes, start over"
const CONFIRM_NO := "Keep my game"
## Everything this window shows that is not an option label, for the
## translation check.
const PHRASES := [RESET_LABEL, CONFIRM_TITLE, CONFIRM_BODY, CONFIRM_YES, CONFIRM_NO]
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
var _language_button: Button
var _option_buttons := {}
## Covers the menu while the reset is being confirmed.
var _confirm: Control


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
	_language_button.text = language_label(TranslationServer.get_locale())
	_size_button.disabled = mode != "overlay"
	for option in OPTIONS:
		var button: Button = _option_buttons[option]
		var value := bool(settings.get(option, option in DEFAULT_ON))
		button.text = option_label(option, value, unavailable.get(option, ""))
		button.disabled = unavailable.has(option)
	# These only mean something for the overlay.
	_option_buttons["always_on_top"].disabled = mode != "overlay"
	_option_buttons["drag_to_move"].disabled = mode != "overlay"
	_confirm.visible = false
	visible = true


func close() -> void:
	_confirm.visible = false
	visible = false
	closed.emit()


## Puts the question about starting over on screen. Only its yes button
## reports anything.
func ask_reset() -> void:
	_confirm.visible = true


## True while the window is asking whether to start over.
func confirming_reset() -> bool:
	return _confirm != null and _confirm.visible


func _build() -> void:
	# Ten rows and a title have to fit inside the 1080-unit canvas at any
	# window size, so they are a little tighter than the other windows'.
	var column := UIKit.modal_panel(self, PANEL_SIZE)
	column.add_theme_constant_override("separation", 12)
	column.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := UIKit.label("Menu", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var wide := Vector2(640, 72)
	_mode_button = UIKit.button(content, "", wide)
	_mode_button.pressed.connect(func() -> void: mode_toggle_requested.emit())
	column.add_child(_mode_button)

	_size_button = UIKit.button(content, "", wide)
	_size_button.pressed.connect(func() -> void: size_cycle_requested.emit())
	column.add_child(_size_button)

	_language_button = UIKit.button(content, "", wide)
	_language_button.pressed.connect(func() -> void: language_cycle_requested.emit())
	column.add_child(_language_button)

	for option in OPTIONS:
		var button := UIKit.button(content, "", wide)
		button.pressed.connect(func() -> void: option_toggled.emit(option))
		column.add_child(button)
		_option_buttons[option] = button

	var reset := UIKit.button(content, TranslationServer.translate(RESET_LABEL), wide)
	reset.pressed.connect(ask_reset)
	column.add_child(reset)

	var quit := UIKit.button(content, "Quit game", wide)
	quit.pressed.connect(func() -> void: quit_requested.emit())
	column.add_child(quit)

	# X in the panel's top-right corner closes the menu.
	var close_button := UIKit.button(content, "X", Vector2(CLOSE_SIZE, CLOSE_SIZE))
	close_button.set_anchors_preset(Control.PRESET_CENTER)
	close_button.position = Vector2(PANEL_SIZE.x / 2.0 - CLOSE_SIZE - 22.0, -PANEL_SIZE.y / 2.0 + 22.0)
	close_button.pressed.connect(close)
	add_child(close_button)
	# Last, so it covers the menu and takes the clicks meant for it.
	_build_confirm()


## The step between the reset button and anything actually happening.
func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.name = "ConfirmReset"
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.visible = false
	# A click beside the panel means no.
	_confirm.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_confirm.visible = false)
	add_child(_confirm)

	var column := UIKit.modal_panel(_confirm, CONFIRM_SIZE)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UIKit.label(TranslationServer.translate(CONFIRM_TITLE), 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var body := UIKit.label(TranslationServer.translate(CONFIRM_BODY), 28)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.custom_minimum_size = Vector2(CONFIRM_SIZE.x - 90.0, 150.0)
	column.add_child(body)

	var wide := Vector2(600, 80)
	var yes := UIKit.button(content, TranslationServer.translate(CONFIRM_YES), wide)
	yes.pressed.connect(func() -> void:
		_confirm.visible = false
		reset_requested.emit())
	column.add_child(yes)

	var no := UIKit.button(content, TranslationServer.translate(CONFIRM_NO), wide)
	no.pressed.connect(func() -> void: _confirm.visible = false)
	column.add_child(no)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## "Size: Medium", translated. Pure.
static func size_label(size_name: String) -> String:
	return "%s: %s" % [TranslationServer.translate("Size"), TranslationServer.translate(size_name.capitalize())]


## "Language: Português". Language names stay in their own language.
static func language_label(locale: String) -> String:
	var code := "pt_BR" if locale.begins_with("pt") else "en"
	return "%s: %s" % [TranslationServer.translate("Language"), Localization.LANGUAGE_NAMES[code]]


## "Always on top: On", or the reason it is unavailable. Pure.
static func option_label(option: String, value: bool, unavailable_reason: String = "") -> String:
	var name := TranslationServer.translate(OPTIONS.get(option, option))
	if unavailable_reason != "":
		return "%s: %s" % [name, TranslationServer.translate(unavailable_reason)]
	return "%s: %s" % [name, TranslationServer.translate("On" if value else "Off")]
