extends RefCounted
## Shared look for the interface, built from the UI pack art.
##
## The art is painted far larger than it is shown and a style box takes its
## minimum size from the source pixels, so buttons and frames are baked down
## to interface size first (see ContentData.ui_texture).

# Palette taken from the art: cream panel, green trim, gold buttons.
const CREAM := Color("f3e3bd")
const PANEL_BORDER := Color("3f7d2f")
const OWNED_BG := Color("bfe3a8")
const IN_USE_BG := Color("8fd06a")
const LOCKED_BG := Color("cfc6ae")
const ROW_BG := Color("fdf6e3")
const TEXT := Color("4a3a1c")
const MUTED := Color("8a7a58")

const BUTTON_ART_HEIGHT := 96
const BUTTON_STATES := {
	"normal": "button_state.button_normal",
	"hover": "button_state.button_hover",
	"pressed": "button_state.button_pressed",
	"disabled": "button_state.button_disabled",
	"focus": "button_state.button_keyboard_focus",
}


static func label(text: String, size: int, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node


## Item or icon art, cropped to its visible bounds so it fills the box.
static func icon(content: RefCounted, asset_id: String, box: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = content.icon_texture(asset_id)
	rect.custom_minimum_size = Vector2(box, box)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func button(content: RefCounted, text: String, min_size := Vector2(210, 76)) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = min_size
	node.add_theme_font_size_override("font_size", 32)
	for state in BUTTON_STATES:
		var texture: Texture2D = content.ui_texture(BUTTON_STATES[state], BUTTON_ART_HEIGHT)
		if texture != null:
			node.add_theme_stylebox_override(state, button_style(texture))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(key, TEXT)
	node.add_theme_color_override("font_disabled_color", MUTED)
	return node


## A round button showing an icon, for the HUD.
static func icon_button(content: RefCounted, asset_id: String, box: float) -> Button:
	var node := button(content, "", Vector2(box, box))
	var art := icon(content, asset_id, box * 0.62)
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(art)
	return node


## Keeps the pill's rounded caps and stretches its flat middle.
static func button_style(texture: Texture2D) -> StyleBoxTexture:
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


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.set_corner_radius_all(28)
	style.set_border_width_all(8)
	style.border_color = PANEL_BORDER
	return style


static func row_style(state: String) -> StyleBoxFlat:
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


## Dimmed backdrop plus a centred panel; returns the column to fill.
static func modal_panel(host: Control, size: Vector2) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = size
	panel.size = size
	panel.position = -size / 2.0
	panel.add_theme_stylebox_override("panel", panel_style())
	host.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	return column
