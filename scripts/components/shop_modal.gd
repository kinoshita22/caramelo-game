extends Control
## Purchase window for dumbbell tiers or meals.
##
## Opened by clicking the dumbbell rack or the food station on the island.
## Each row shows the item's own art, what it does and its price. Owned rows
## carry a distinct background, and the one in use is marked.
##
## Row state comes from rows_for(), which is pure and covered by tests.

signal closed

const EQUIPMENT := "shop_equipment"
const FOOD := "shop_food"

# Palette taken from the UI art: cream panel, green trim, gold buttons.
const CREAM := Color("f3e3bd")
const OWNED_BG := Color("bfe3a8")      # distinct background for bought items
const IN_USE_BG := Color("8fd06a")
const LOCKED_BG := Color("cfc6ae")
const ROW_BG := Color("fdf6e3")
const TEXT := Color("4a3a1c")
const MUTED := Color("8a7a58")

const PANEL_SIZE := Vector2(1180, 760)
const ROW_HEIGHT := 104.0
## Height the button art is baked to; margins below are in these pixels.
const BUTTON_ART_HEIGHT := 96

var content: RefCounted
var economy: RefCounted
var progression: RefCounted
var kind := EQUIPMENT

var _rows_box: VBoxContainer
var _bones_label: Label
var _title: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func open(content_data: RefCounted, economy_system: RefCounted, progression_system: RefCounted, shop_kind: String) -> void:
	content = content_data
	economy = economy_system
	progression = progression_system
	kind = shop_kind
	if get_child_count() == 0:
		_build()
	_title.text = "Dumbbells" if kind == EQUIPMENT else "Food"
	visible = true
	refresh()


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = PANEL_SIZE
	panel.size = PANEL_SIZE
	panel.position = -PANEL_SIZE / 2.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)

	_title = _label("", 46, TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(_icon("ui.currency_bone_single", 52))
	_bones_label = _label("", 40, TEXT)
	header.add_child(_bones_label)
	var close_button := _button("Close")
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
	for row in rows_for(kind, economy, progression.level, progression.bones):
		_rows_box.add_child(_build_row(row))


func _build_row(row: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = ROW_HEIGHT
	panel.add_theme_stylebox_override("panel", _row_style(row["state"]))

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_child(_icon(row["asset"], 96))
	box.add_child(margin)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 2)
	text_column.add_child(_label(row["label"], 34, TEXT))
	text_column.add_child(_label(row["detail"], 26, MUTED))
	box.add_child(text_column)

	if row["cost"] > 0 and not row["owned"]:
		box.add_child(_icon("ui.currency_bone_single", 44))
		box.add_child(_label(str(row["cost"]), 32, TEXT))
	elif row["state"] == "locked":
		box.add_child(_icon("ui.state_locked_icon", 44))

	var action := _button(row["action_label"])
	action.disabled = not row["actionable"]
	action.pressed.connect(_on_row_pressed.bind(row["id"]))
	box.add_child(action)
	return panel


func _on_row_pressed(tier_id: String) -> void:
	var level: int = progression.level
	if kind == EQUIPMENT:
		if tier_id in economy.owned_equipment:
			economy.equip(tier_id)
		else:
			economy.buy_equipment(tier_id, progression, level)
	else:
		if tier_id in economy.owned_food:
			economy.set_active_food(tier_id)
		else:
			economy.buy_food(tier_id, progression, level)
	refresh()


func _gui_input(event: InputEvent) -> void:
	# A click on the dimmed area outside the panel closes the window.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


## One row per tier, with everything the view needs. Pure, so tests can
## check the states without building any nodes.
static func rows_for(shop_kind: String, economy_system: RefCounted, level: int, bones: int) -> Array:
	var equipment := shop_kind == EQUIPMENT
	var ids: Array = economy_system.equipment_ids() if equipment else economy_system.food_ids()
	var owned: Array = economy_system.owned_equipment if equipment else economy_system.owned_food
	var in_use: String = economy_system.equipped_equipment if equipment else economy_system.active_food
	var rows: Array = []
	for id in ids:
		var tier: Dictionary = economy_system.equipment_tier(id) if equipment else economy_system.food_tier(id)
		var cost := int(tier["cost"])
		var is_owned: bool = id in owned
		var state := "owned"
		var action_label := "Use"
		var actionable := true
		if id == in_use:
			state = "in_use"
			action_label = "In use"
			actionable = false
		elif not is_owned and level < int(tier["unlock_level"]):
			state = "locked"
			action_label = "Level %d" % int(tier["unlock_level"])
			actionable = false
		elif not is_owned:
			state = "affordable" if bones >= cost else "too_expensive"
			action_label = "Buy"
			actionable = bones >= cost
		rows.append({
			"id": id,
			"label": tier.get("label", id),
			"detail": _detail(tier, equipment),
			"asset": tier.get("asset", ""),
			"cost": cost,
			"owned": is_owned,
			"state": state,
			"action_label": action_label,
			"actionable": actionable,
		})
	return rows


static func _detail(tier: Dictionary, equipment: bool) -> String:
	if equipment:
		return "XP x%.2f" % float(tier.get("xp_multiplier", 1.0))
	return "Fills x%.2f, eats x%.2f" % [float(tier.get("satiety_multiplier", 1.0)), float(tier.get("eating_speed", 1.0))]


func _row_style(state: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	match state:
		"in_use":
			style.bg_color = IN_USE_BG
		"owned":
			style.bg_color = OWNED_BG
		"locked":
			style.bg_color = LOCKED_BG
		_:
			style.bg_color = ROW_BG
	style.set_corner_radius_all(18)
	style.set_border_width_all(3)
	style.border_color = Color(0, 0, 0, 0.18)
	style.set_content_margin_all(10)
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(28)
	style.set_border_width_all(8)
	style.border_color = Color("3f7d2f")
	return style


## Button drawn with the button-state art from the UI pack.
func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(210, 76)
	button.add_theme_font_size_override("font_size", 32)
	for pair in [["normal", "button_state.button_normal"], ["hover", "button_state.button_hover"],
			["pressed", "button_state.button_pressed"], ["disabled", "button_state.button_disabled"],
			["focus", "button_state.button_keyboard_focus"]]:
		var texture: Texture2D = content.ui_texture(pair[1], BUTTON_ART_HEIGHT)
		if texture != null:
			button.add_theme_stylebox_override(pair[0], _button_style(texture))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, TEXT)
	button.add_theme_color_override("font_disabled_color", MUTED)
	return button


## Keeps the pill's rounded caps and stretches its flat middle.
func _button_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	var height := texture.get_height()
	style.set_texture_margin(SIDE_LEFT, height * 0.45)
	style.set_texture_margin(SIDE_RIGHT, height * 0.45)
	style.set_texture_margin(SIDE_TOP, height * 0.34)
	style.set_texture_margin(SIDE_BOTTOM, height * 0.34)
	style.set_content_margin(SIDE_LEFT, 20)
	style.set_content_margin(SIDE_RIGHT, 20)
	style.set_content_margin(SIDE_TOP, 8)
	style.set_content_margin(SIDE_BOTTOM, 8)
	return style


func _icon(asset_id: String, box: float) -> Control:
	var rect := TextureRect.new()
	rect.texture = content.icon_texture(asset_id)
	rect.custom_minimum_size = Vector2(box, box)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
