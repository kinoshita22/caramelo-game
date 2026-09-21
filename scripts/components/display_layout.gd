extends RefCounted
## Pure display maths and settings parsing for the main scene. No autoload
## or scene-tree access, so tests can call it directly.

const PlatformServiceScript := preload("res://scripts/autoload/platform_service.gd")
const MODES := ["overlay", "windowed"]
const DEFAULT_OVERLAY_SCALE := 0.7


## Scale and position that fit `bounds` inside `into`, centred, leaving
## `margin` (fraction of the size) free on every side.
static func fit(bounds: Rect2, into: Rect2, margin: float) -> Dictionary:
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return {"scale": 1.0, "position": into.position}
	var avail := into.size * (1.0 - 2.0 * margin)
	var s := minf(avail.x / bounds.size.x, avail.y / bounds.size.y)
	return {"scale": s, "position": into.get_center() - bounds.get_center() * s}


## Overlay window size: stage bounds at `scale`, shrunk (keeping the aspect
## ratio) so it fits inside the usable screen area minus `margin` per side.
static func overlay_size(bounds_size: Vector2, scale: float, usable: Vector2i, margin: int) -> Vector2i:
	var size := bounds_size * scale
	var room := Vector2(usable - Vector2i(2 * margin, 2 * margin))
	if size.x > room.x or size.y > room.y:
		size *= minf(room.x / size.x, room.y / size.y)
	return Vector2i(size.floor())


## Order the menu cycles through, smallest first.
const SIZE_ORDER := ["small", "medium", "large"]


## The preset name closest to `scale`.
static func size_name_for(scale: float, presets: Dictionary) -> String:
	var best := "medium"
	var best_gap := INF
	for name in SIZE_ORDER:
		if presets.has(name) and absf(float(presets[name]) - scale) < best_gap:
			best_gap = absf(float(presets[name]) - scale)
			best = name
	return best


## The size after `current` in the menu's cycle, wrapping round.
static func next_size(current: String, presets: Dictionary) -> String:
	var names: Array = SIZE_ORDER.filter(func(n: String) -> bool: return presets.has(n))
	if names.is_empty():
		return current
	return names[(names.find(current) + 1) % names.size()]


## Pointer travel (screen pixels) that turns a press into a drag.
const DRAG_THRESHOLD := 8.0


static func is_drag(start_mouse: Vector2i, now_mouse: Vector2i) -> bool:
	return Vector2(now_mouse - start_mouse).length() >= DRAG_THRESHOLD


## Window position while dragging: follows the pointer, kept fully inside
## the usable screen area so the overlay cannot be lost off-screen.
static func dragged_position(start_window: Vector2i, start_mouse: Vector2i, now_mouse: Vector2i,
		window_size: Vector2i, usable: Rect2i) -> Vector2i:
	var target := start_window + (now_mouse - start_mouse)
	return clamp_to(target, window_size, usable)


static func clamp_to(position: Vector2i, window_size: Vector2i, usable: Rect2i) -> Vector2i:
	var max_pos := usable.end - window_size
	return Vector2i(clampi(position.x, usable.position.x, maxi(usable.position.x, max_pos.x)),
			clampi(position.y, usable.position.y, maxi(usable.position.y, max_pos.y)))


## Display defaults from data, then command-line overrides. Invalid values
## fall back to built-in defaults with a warning.
static func load_settings(defaults: Variant, argv: PackedStringArray) -> Dictionary:
	var s := {
		"mode": "overlay",
		"overlay": {"corner": "bottom_right", "margin_px": 24, "scale": DEFAULT_OVERLAY_SCALE, "screen": -1, "always_on_top": false},
		"windowed": {"size": [1280, 720], "background": "#8ec5e8"},
		"fit_margin": 0.04,
		"debug_overlay": false,
	}
	if typeof(defaults) == TYPE_DICTIONARY:
		for k in ["mode", "fit_margin"]:
			if defaults.has(k):
				s[k] = defaults[k]
		for k in ["overlay", "windowed"]:
			if typeof(defaults.get(k)) == TYPE_DICTIONARY:
				s[k].merge(defaults[k], true)
	var i := 0
	while i < argv.size():
		var a := argv[i]
		var v := argv[i + 1] if i + 1 < argv.size() else ""
		match a:
			"--display-mode": s["mode"] = v; i += 1
			"--overlay-scale": s["overlay"]["scale"] = float(v); i += 1
			"--corner": s["overlay"]["corner"] = v; i += 1
			"--window-size":
				var parts := v.split("x")
				if parts.size() == 2:
					s["windowed"]["size"] = [int(parts[0]), int(parts[1])]
				i += 1
			"--debug-overlay": s["debug_overlay"] = true
			"--screenshot": s["screenshot"] = v; i += 1
			"--screenshot-frames": s["screenshot_frames"] = int(v); i += 1
			"--animation": s["animation"] = v; i += 1
			"--form": s["form"] = int(v); i += 1
			"--animation-frame": s["animation_frame"] = int(v); i += 1
			"--time-scale": s["time_scale"] = float(v); i += 1
			"--start-level": s["start_level"] = int(v); i += 1
			"--bones": s["bones"] = int(v); i += 1
			"--equip": s["equip"] = v; i += 1
			"--meal": s["meal"] = v; i += 1
			"--open-shop": s["open_shop"] = v; i += 1
			"--preview-cosmetic": s["preview_cosmetic"] = v; i += 1
			"--play-effect": s["play_effect"] = v; i += 1
		i += 1
	if not s["mode"] in MODES:
		push_warning("Unknown display mode '%s'; using overlay." % s["mode"])
		s["mode"] = "overlay"
	if not s["overlay"]["corner"] in PlatformServiceScript.CORNERS:
		push_warning("Unknown corner '%s'; using bottom_right." % s["overlay"]["corner"])
		s["overlay"]["corner"] = "bottom_right"
	if not float(s["overlay"]["scale"]) > 0.0:
		s["overlay"]["scale"] = DEFAULT_OVERLAY_SCALE
	var size: Variant = s["windowed"]["size"]
	if typeof(size) != TYPE_ARRAY or size.size() != 2 or int(size[0]) < 320 or int(size[1]) < 240:
		s["windowed"]["size"] = [1280, 720]
	return s
