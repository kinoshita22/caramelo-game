extends Control
## Upgrade window for the four stats, opened by clicking Caramelo.
##
## Every stat speeds the same loop up: more XP per workout, longer sessions,
## quicker reps, shorter rests. Costs and effects come from
## data/balance/upgrades.json.

signal closed

const UIKit := preload("res://scripts/components/ui_kit.gd")

const PANEL_SIZE := Vector2(1180, 700)
const ROW_HEIGHT := 112.0
## What each stat does, in the player's words.
const EFFECT_TEXT := {
	"strength": "More XP from every workout",
	"endurance": "Longer workout sessions",
	"speed": "Quicker repetitions",
	"recovery": "Shorter rests and meals",
}

var content: RefCounted
var economy: RefCounted
var progression: RefCounted

var _rows_box: VBoxContainer
var _bones_label: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(content_data: RefCounted, economy_system: RefCounted, progression_system: RefCounted) -> void:
	content = content_data
	economy = economy_system
	progression = progression_system
	if get_child_count() == 0:
		_build()
	visible = true
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	var column := UIKit.modal_panel(self, PANEL_SIZE)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)

	var title := UIKit.label("Training", 46)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(UIKit.icon(content, "ui.currency_bone_single", 52))
	_bones_label = UIKit.label("", 40)
	header.add_child(_bones_label)
	var close_button := UIKit.button(content, "Close")
	close_button.pressed.connect(close)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 12)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_box)


func refresh() -> void:
	_bones_label.text = str(progression.bones)
	for child in _rows_box.get_children():
		child.queue_free()
	for row in rows_for(economy, progression.bones):
		_rows_box.add_child(_build_row(row))


func _build_row(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.add_theme_stylebox_override("panel", UIKit.row_style(row["state"]))

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	if row["icon"] != "":
		margin.add_child(UIKit.icon(content, row["icon"], 84))
	box.add_child(margin)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 2)
	text_column.add_child(UIKit.label("%s   %d/%d" % [row["label"], row["level"], row["max_level"]], 34))
	text_column.add_child(UIKit.label(row["detail"], 26, UIKit.MUTED))
	box.add_child(text_column)

	if row["cost"] > 0:
		box.add_child(UIKit.icon(content, "ui.currency_bone_single", 44))
		box.add_child(UIKit.label(str(row["cost"]), 32))

	var action := UIKit.button(content, row["action_label"])
	action.disabled = not row["actionable"]
	action.pressed.connect(_on_row_pressed.bind(row["id"]))
	box.add_child(action)
	return panel


func _on_row_pressed(stat_name: String) -> void:
	economy.upgrade_stat(stat_name, progression)
	refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## One row per stat. Pure, so tests can check it without building nodes.
static func rows_for(economy_system: RefCounted, bones: int) -> Array:
	var rows: Array = []
	for stat_name in economy_system.STATS:
		var level: int = economy_system.stat_level(stat_name)
		var max_level: int = economy_system.max_stat_level()
		var cost: int = economy_system.stat_cost(stat_name)
		var maxed := level >= max_level
		var state := "locked" if maxed else ("owned" if bones >= cost else "row")
		rows.append({
			"id": stat_name,
			"label": stat_name.capitalize(),
			"detail": EFFECT_TEXT.get(stat_name, ""),
			"icon": economy_system.stat_icon(stat_name),
			"level": level,
			"max_level": max_level,
			"cost": 0 if maxed else cost,
			"state": state,
			"action_label": "Maxed" if maxed else "Train",
			"actionable": not maxed and bones >= cost,
		})
	return rows
