extends Control
## "While you were away": what Caramelo did while the game was closed.

signal closed

const UIKit := preload("res://scripts/components/ui_kit.gd")
const OfflineProgress := preload("res://scripts/systems/offline_progress.gd")
const Localization := preload("res://scripts/systems/localization.gd")

const PANEL_SIZE := Vector2(820, 560)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(content: RefCounted, summary: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	var column := UIKit.modal_panel(self, PANEL_SIZE)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 20)
	var title := UIKit.label("While you were away", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for line in lines_for(summary):
		var label := UIKit.label(line, 32)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	var ok := UIKit.button(content, "Great!", Vector2(300, 84))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close)
	column.add_child(ok)
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## Whether a summary is worth showing at all.
static func worth_showing(summary: Dictionary) -> bool:
	return not summary.is_empty() and (int(summary.get("workouts", 0)) > 0 or summary.get("clock_rollback", false))


## The sentences shown. Pure, so tests can check them.
static func lines_for(summary: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if summary.get("clock_rollback", false):
		lines.append(Localization.tr_format("The clock went backwards, so no time was counted."))
		return lines
	var duration := OfflineProgress.describe_duration(summary["counted_seconds"])
	lines.append(Localization.tr_format("Caramelo trained for %s.", [duration]))
	lines.append(Localization.tr_format("%d workouts, +%d bones.", [summary["workouts"], summary["bones_gained"]]))
	if summary["levels_gained"] > 0:
		lines.append(Localization.tr_format("Level %d → %d!", [summary["from_level"], summary["to_level"]]))
	if summary["to_form"] != summary["from_form"]:
		lines.append(Localization.tr_format("He evolved into form %d!", [summary["to_form"]]))
	if summary.get("capped", false):
		lines.append(Localization.tr_format("(Only the first %s counts while away.)", [duration]))
	return lines
