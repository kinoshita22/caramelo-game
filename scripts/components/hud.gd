extends Control
## The always-visible strip: level badge, XP bar, bone counter and the
## buttons that open the training, wardrobe and menu windows.
##
## It sits low over the island so it stays inside the window's clickable
## region; everything outside that region passes clicks to the desktop.
## Wallpaper mode (Phase 11) hides it.

signal upgrades_requested
signal wardrobe_requested
signal menu_requested

const UIKit := preload("res://scripts/components/ui_kit.gd")

## Strip height and how far it sits above the bottom of the window.
const STRIP_HEIGHT := 120.0
const BOTTOM_MARGIN := 28.0
const BAR_SIZE := Vector2(460, 54)
const BADGE := 96.0
const ICON_BUTTON := 88.0

var content: RefCounted
var progression: RefCounted

var _level_label: Label
var _xp_bar: TextureProgressBar
var _bones_label: Label


func _init() -> void:
	# A strip across the bottom of the window, over the island's ground, so
	# it stays inside the region that takes clicks.
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE, true)
	offset_top = -(STRIP_HEIGHT + BOTTOM_MARGIN)
	offset_bottom = -BOTTOM_MARGIN
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

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
	row.add_child(badge)

	_xp_bar = TextureProgressBar.new()
	_xp_bar.texture_under = content.ui_texture("ui.progress_bar_frame_empty", int(BAR_SIZE.y))
	_xp_bar.texture_progress = content.ui_texture("ui.progress_bar_fill_green", int(BAR_SIZE.y * 0.66))
	_xp_bar.nine_patch_stretch = true
	_xp_bar.stretch_margin_left = 20
	_xp_bar.stretch_margin_right = 20
	_xp_bar.custom_minimum_size = BAR_SIZE
	_xp_bar.max_value = 1.0
	_xp_bar.step = 0.0
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_xp_bar)

	row.add_child(UIKit.icon(content, "ui.currency_bone_stack", 72))
	_bones_label = UIKit.label("0", 38)
	_bones_label.add_theme_color_override("font_color", Color.WHITE)
	_bones_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_bones_label.add_theme_constant_override("outline_size", 8)
	_bones_label.custom_minimum_size.x = 150
	row.add_child(_bones_label)

	for pair in [["ui.stat_strength_icon", upgrades_requested], ["ui.nav_wardrobe_icon", wardrobe_requested]]:
		var button := UIKit.icon_button(content, pair[0], ICON_BUTTON)
		button.pressed.connect(func() -> void: pair[1].emit())
		row.add_child(button)
	var menu_button := UIKit.button(content, "Menu", Vector2(170, ICON_BUTTON))
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	row.add_child(menu_button)


func refresh() -> void:
	_level_label.text = str(progression.level)
	var needed: float = progression.xp_to_next(progression.level)
	_xp_bar.value = 1.0 if needed <= 0.0 else clampf(progression.xp / needed, 0.0, 1.0)
	_bones_label.text = str(progression.bones)
