extends Node
## Autoload: the only code that changes the OS window. Simulation and scenes
## ask for a mode; this decides how the platform provides it.
##
## Overlay: borderless, per-pixel transparent window sized to the stage and
## placed in a screen corner; clicks outside the hit polygon reach the desktop.
## Windowed: a normal decorated, opaque window (fallback and debugging).

const CORNERS := ["top_left", "top_right", "bottom_left", "bottom_right"]

var mode := ""


func transparency_available() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_WINDOW_TRANSPARENCY) \
			and DisplayServer.is_window_transparency_available()


## Screen index to use: -1 means the primary screen.
func resolve_screen(screen: int) -> int:
	return DisplayServer.get_primary_screen() if screen < 0 or screen >= DisplayServer.get_screen_count() else screen


func enter_overlay(rect: Rect2i, always_on_top: bool) -> void:
	mode = "overlay"
	var root := get_tree().root
	root.transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, always_on_top)
	DisplayServer.window_set_size(rect.size)
	DisplayServer.window_set_position(rect.position)


func enter_windowed(size: Vector2i, background: Color, screen: int) -> void:
	mode = "windowed"
	var root := get_tree().root
	root.transparent_bg = false
	RenderingServer.set_default_clear_color(background)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_size(size)
	var usable := DisplayServer.screen_get_usable_rect(resolve_screen(screen))
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


## Window-pixel polygon that receives the mouse; everything else passes
## through. Only meaningful in overlay mode.
func set_hit_polygon(polygon: PackedVector2Array) -> void:
	if mode == "overlay":
		DisplayServer.window_set_mouse_passthrough(polygon)


## Top-left position for a window of `size` in a corner of `usable`.
static func corner_position(usable: Rect2i, size: Vector2i, corner: String, margin: int) -> Vector2i:
	var x := usable.position.x + margin
	var y := usable.position.y + margin
	if corner.ends_with("right"):
		x = usable.end.x - size.x - margin
	if corner.begins_with("bottom"):
		y = usable.end.y - size.y - margin
	return Vector2i(x, y)
