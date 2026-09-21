extends Control
## The always-visible interface:
## - over the tree (display only): hunger and sleep bars, placed by
##   place_needs() from the island layout;
## - bottom strip, left to right: level badge, XP bar, bone count, and the
##   buttons that open the training, wardrobe and menu windows.
##
## The strip sits low over the island so its buttons stay inside the
## window's clickable region. The corner takes no clicks, so it can float
## over the transparent sky.
## Wallpaper mode (Phase 11) hides it.

signal upgrades_requested
signal wardrobe_requested
signal menu_requested

const UIKit := preload("res://scripts/components/ui_kit.gd")

## Strip height and how far it sits above the bottom of the window.
const STRIP_HEIGHT := 120.0
const BOTTOM_MARGIN := 28.0
const BAR_SIZE := Vector2(460, 27)
const BADGE := 96.0
const ICON_BUTTON := 88.0
## Icon buttons are wider than they are tall.
const ICON_BUTTON_WIDTH := 118.0
## Hunger and sleep bars: satiety and energy from the behaviour loop.
const NEED_BAR_SIZE := Vector2(220, 20)
const NEED_ICON := 44.0
const HUNGER_TINT := Color("ffb347")
const SLEEP_TINT := Color("8ab4ff")
## How far the buttons sit above the rest of the strip. A margin at the
## bottom of their container shifts the centred row up by half of it.
const BUTTON_LIFT := 44.0
## Same trick for the level, XP and bone count: 20 lifts them by 10.
const STATUS_LIFT := 20.0

var content: RefCounted
var progression: RefCounted

## The behaviour loop whose satiety and energy fill the need bars; null
## while previewing a single animation.
var needs: RefCounted

var _level_label: Label
var _need_column: VBoxContainer
var _hunger_bar: TextureProgressBar
var _sleep_bar: TextureProgressBar
var _xp_bar: TextureProgressBar
var _bones_label: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(content_data: RefCounted, progression_system: RefCounted) -> void:
	content = content_data
	progression = progression_system
	_build()
	progression.xp_changed.connect(func(_xp: float, _needed: float) -> void: refresh())
	progression.bones_changed.connect(func(_total: int) -> void: refresh())
	progression.leveled_up.connect(func(_level: int) -> void: refresh())
	refresh()


func _build() -> void:
	# Bottom strip, over the island's ground, inside the clickable region.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE, true)
	row.offset_top = -(STRIP_HEIGHT + BOTTOM_MARGIN)
	row.offset_bottom = -BOTTOM_MARGIN
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	# Level badge, then the XP bar and the bone count side by side.
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 16)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Level badge with the number written over it.
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(BADGE, BADGE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_art := UIKit.icon(content, "ui.level_badge_blank", BADGE)
	badge_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(badge_art)
	_level_label = UIKit.label("1", 40, Color.WHITE)
	_level_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_level_label.add_theme_constant_override("outline_size", 6)
	badge.add_child(_level_label)
	var status_lift := MarginContainer.new()
	status_lift.add_theme_constant_override("margin_bottom", int(STATUS_LIFT))
	status_lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status_lift)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 20)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_lift.add_child(status)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.add_child(badge)
	status.add_child(stats)

	# Hunger and sleep, stacked, each an icon and a bar; place_needs() puts
	# them over the tree.
	_need_column = VBoxContainer.new()
	_need_column.add_theme_constant_override("separation", 8)
	_need_column.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	_need_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_need_column)
	var need_column := _need_column
	_hunger_bar = _need_row(need_column, "ui.stat_hunger_icon", HUNGER_TINT)
	_sleep_bar = _need_row(need_column, "ui.stat_sleep_icon", SLEEP_TINT)

	_xp_bar = TextureProgressBar.new()
	_xp_bar.texture_under = content.ui_texture("ui.progress_bar_frame_empty", int(BAR_SIZE.y))
	_xp_bar.texture_progress = content.ui_texture("ui.progress_bar_fill_green", int(BAR_SIZE.y * 0.7))
	_xp_bar.nine_patch_stretch = true
	_xp_bar.stretch_margin_left = 20
	_xp_bar.stretch_margin_right = 20
	_xp_bar.custom_minimum_size = BAR_SIZE
	_xp_bar.max_value = 1.0
	_xp_bar.step = 0.0
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Without this the bar stretches to the height of the whole strip.
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats.add_child(_xp_bar)

	var bones_line := HBoxContainer.new()
	bones_line.add_theme_constant_override("separation", 10)
	bones_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(bones_line)
	bones_line.add_child(UIKit.icon(content, "ui.currency_bone_stack", 56))
	_bones_label = UIKit.label("0", 38)
	_bones_label.add_theme_color_override("font_color", Color.WHITE)
	_bones_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_bones_label.add_theme_constant_override("outline_size", 8)
	_bones_label.custom_minimum_size.x = 150
	bones_line.add_child(_bones_label)

	# The buttons ride a little higher than the level and bone count.
	var lift := MarginContainer.new()
	lift.add_theme_constant_override("margin_bottom", int(BUTTON_LIFT))
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lift)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lift.add_child(buttons)

	for pair in [["ui.stat_strength_icon", upgrades_requested], ["ui.nav_wardrobe_icon", wardrobe_requested]]:
		var button := UIKit.icon_button(content, pair[0], ICON_BUTTON, ICON_BUTTON_WIDTH)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void: pair[1].emit())
		buttons.add_child(button)
	var menu_button := UIKit.button(content, "Menu", Vector2(170, ICON_BUTTON))
	menu_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	buttons.add_child(menu_button)


func _need_row(parent: Control, icon_id: String, tint: Color) -> TextureProgressBar:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	line.add_child(UIKit.icon(content, icon_id, NEED_ICON))
	var bar := _bar(NEED_BAR_SIZE, true)
	bar.tint_progress = tint
	line.add_child(bar)
	return bar


## Frame-and-fill bar from the UI pack art, sized to `bar_size`. A tintable
## bar gets a greyscale fill so tint_progress shows its true colour.
func _bar(bar_size: Vector2, tintable: bool = false) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.texture_under = content.ui_texture("ui.progress_bar_frame_empty", int(bar_size.y))
	bar.texture_progress = content.ui_texture("ui.progress_bar_fill_green", int(bar_size.y * 0.7), tintable)
	bar.nine_patch_stretch = true
	bar.stretch_margin_left = int(bar_size.y * 0.75)
	bar.stretch_margin_right = int(bar_size.y * 0.75)
	bar.custom_minimum_size = bar_size
	bar.max_value = 1.0
	bar.step = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


## Centres the hunger and sleep bars horizontally on `top_center` (HUD
## coordinates) with their top edge there.
func place_needs(top_center: Vector2) -> void:
	var size := _need_column.get_combined_minimum_size()
	_need_column.position = top_center - Vector2(size.x / 2.0, 0.0)


func _process(_delta: float) -> void:
	# Satiety and energy change every frame, so the need bars follow them live.
	if needs == null:
		_hunger_bar.visible = false
		_sleep_bar.visible = false
		return
	_hunger_bar.visible = true
	_sleep_bar.visible = true
	_hunger_bar.value = clampf(needs.satiety / 100.0, 0.0, 1.0)
	_sleep_bar.value = clampf(needs.energy / 100.0, 0.0, 1.0)


## Centre of the bone count, in HUD coordinates (for effects).
func bone_counter_centre() -> Vector2:
	return _bones_label.get_global_rect().get_center()


func refresh() -> void:
	_level_label.text = str(progression.level)
	var needed: float = progression.xp_to_next(progression.level)
	_xp_bar.value = 1.0 if needed <= 0.0 else clampf(progression.xp / needed, 0.0, 1.0)
	_bones_label.text = str(progression.bones)
