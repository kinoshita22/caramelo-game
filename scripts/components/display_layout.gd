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
