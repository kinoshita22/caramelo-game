extends Control
## Window for slot-based collections: furniture (from the island) and the
## wardrobe (cosmetics). One section per slot that has items; each row shows
## the item's art and price.
##
## Items not yet owned can be tried first: "Try" previews the item on the
## island or on Caramelo through `preview`, and closing the window puts the
## equipped items back. Row state comes from rows_for(), which is pure.

signal closed

const UIKit := preload("res://scripts/components/ui_kit.gd")
const Localization := preload("res://scripts/systems/localization.gd")

const PANEL_SIZE := Vector2(1180, 760)
const ROW_HEIGHT := 104.0

var content: RefCounted
var collection: RefCounted
var progression: RefCounted
## Called as preview.call(slot_name, item_id) to show an item, and with an
## empty id to show the equipped one again.
var preview: Callable

var _title_text := ""
var _empty_text := ""
var _previewing := {}  # slot -> item id being tried
var _rows_box: VBoxContainer
var _bones_label: Label
var _title: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(content_data: RefCounted, items: RefCounted, progression_system: RefCounted,
		title: String, empty_text: String, preview_callable: Callable) -> void:
	content = content_data
	collection = items
	progression = progression_system
	preview = preview_callable
	_title_text = title
	_empty_text = empty_text
	_previewing.clear()
	if get_child_count() == 0:
		_build()
	_title.text = _title_text
	visible = true
	refresh()


func close() -> void:
	# Whatever was being tried goes back to what is equipped.
	for slot_name in _previewing:
		if preview.is_valid():
			preview.call(slot_name, "")
	_previewing.clear()
	visible = false
	closed.emit()


func _build() -> void:
	var column := UIKit.modal_panel(self, PANEL_SIZE)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	_title = UIKit.label("", 46)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
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
	var sections := sections_for(collection, progression.level, progression.bones, _previewing)
	if sections.is_empty():
		var empty := UIKit.label(_empty_text, 32, UIKit.MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.y = 200
		_rows_box.add_child(empty)
		return
	for section in sections:
		_rows_box.add_child(UIKit.label(section["label"], 34, UIKit.MUTED))
		for row in section["rows"]:
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
	margin.add_child(UIKit.icon(content, row["asset"], 96))
	box.add_child(margin)

	var name_label := UIKit.label(row["label"], 34)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(name_label)

	if not row["owned"] and row["cost"] > 0:
		box.add_child(UIKit.icon(content, "ui.currency_bone_single", 44))
		box.add_child(UIKit.label(str(row["cost"]), 32))

	if row["can_try"]:
		var try_button := UIKit.button(content, "Trying" if row["previewing"] else "Try", Vector2(170, 76))
		try_button.disabled = row["previewing"]
		try_button.pressed.connect(_on_try.bind(row["slot"], row["id"]))
		box.add_child(try_button)

	var action := UIKit.button(content, row["action_label"])
	action.disabled = not row["actionable"]
	action.pressed.connect(_on_action.bind(row["id"]))
	box.add_child(action)
	return panel


func _on_try(slot_name: String, id: String) -> void:
	_previewing[slot_name] = id
	if preview.is_valid():
		preview.call(slot_name, id)
	refresh()


func _on_action(id: String) -> void:
	var slot_name: String = collection.item(id)["slot"]
	if id in collection.owned:
		collection.equip(id)
	else:
		collection.buy(id, progression, progression.level)
	_previewing.erase(slot_name)
	if preview.is_valid():
		preview.call(slot_name, "")
	refresh()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## Sections (one per slot that has items), each with its rows. Pure.
static func sections_for(items: RefCounted, level: int, bones: int, previewing: Dictionary = {}) -> Array:
	var sections: Array = []
	for slot_name in items.slot_names():
		var ids: Array = items.items_for(slot_name)
		if ids.is_empty():
			continue
		var rows: Array = []
		for id in ids:
			var it: Dictionary = items.item(id)
			var owned: bool = id in items.owned
			var cost := int(it["cost"])
			var unlocked := level >= int(it.get("unlock_level", 1))
			var state := "owned"
			var action_label := "Use"
			var actionable := true
			if items.equipped.get(slot_name, "") == id:
				state = "in_use"
				action_label = "In use"
				actionable = false
			elif not owned and not unlocked:
				state = "locked"
				action_label = Localization.tr_format("Level %d", [int(it["unlock_level"])])
				actionable = false
			elif not owned:
				state = "affordable" if bones >= cost else "too_expensive"
				action_label = "Buy"
				actionable = bones >= cost
			rows.append({
				"id": id, "slot": slot_name, "label": it.get("label", id), "asset": it.get("asset", ""),
				"cost": cost, "owned": owned, "state": state, "action_label": action_label,
				"actionable": actionable, "can_try": not owned and unlocked,
				"previewing": previewing.get(slot_name, "") == id,
			})
		sections.append({"slot": slot_name, "label": items.slots[slot_name].get("label", slot_name), "rows": rows})
	return sections
