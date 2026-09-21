extends "res://tests/lib/test_case.gd"
## Window fitting, corner placement and display settings parsing.

const DisplayLayout := preload("res://scripts/components/display_layout.gd")
const PlatformServiceScript := preload("res://scripts/autoload/platform_service.gd")


func test_fit_centres_and_scales() -> void:
	var t := DisplayLayout.fit(Rect2(-100, -50, 200, 100), Rect2(0, 0, 1000, 1000), 0.0)
	check_eq(t["scale"], 5.0, "limited by width")
	check_eq(t["position"], Vector2(500, 500), "bounds centre lands on window centre")


func test_fit_respects_margin() -> void:
	var t := DisplayLayout.fit(Rect2(0, 0, 100, 100), Rect2(0, 0, 200, 400), 0.1)
	check(is_equal_approx(t["scale"], 1.6), "10%% margin each side leaves 160 px: got %s" % t["scale"])


func test_fit_handles_1280x720_and_1920x1080_the_same_way() -> void:
	var b := Rect2(-760, -560, 1520, 800)
	var small := DisplayLayout.fit(b, Rect2(0, 0, 1280, 720), 0.04)
	var large := DisplayLayout.fit(b, Rect2(0, 0, 1920, 1080), 0.04)
	check(is_equal_approx(large["scale"] / small["scale"], 1.5), "scale grows with the window")
	for t in [small, large]:
		var r := Rect2(t["position"] + b.position * t["scale"], b.size * t["scale"])
		var window := Rect2(0, 0, 1280, 720) if t == small else Rect2(0, 0, 1920, 1080)
		check(window.encloses(r), "stage %s fits inside %s" % [r, window])


func test_overlay_size_scales_and_fits_screen() -> void:
	var b := Vector2(1630, 1068)
	check_eq(DisplayLayout.overlay_size(b, 0.7, Vector2i(1920, 1014), 24), Vector2i(1141, 747), "fits at full scale")
	var small := DisplayLayout.overlay_size(b, 0.7, Vector2i(1366, 728), 24)
	check(small.y <= 728 - 48 and small.x <= 1366 - 48, "shrunk to fit a 1366x768 screen: %s" % small)
	check(absf(float(small.x) / small.y - b.x / b.y) < 0.01, "aspect ratio kept")


func test_short_press_is_a_click_longer_travel_is_a_drag() -> void:
	check(not DisplayLayout.is_drag(Vector2i(100, 100), Vector2i(104, 103)), "a wobble is still a click")
	check(DisplayLayout.is_drag(Vector2i(100, 100), Vector2i(112, 100)), "a real move starts a drag")


func test_dragging_follows_the_pointer_but_stays_on_screen() -> void:
	var usable := Rect2i(0, 0, 1920, 1014)
	var size := Vector2i(800, 500)
	check_eq(DisplayLayout.dragged_position(Vector2i(500, 300), Vector2i(900, 600), Vector2i(700, 500), size, usable),
			Vector2i(300, 200), "moves with the pointer")
	check_eq(DisplayLayout.dragged_position(Vector2i(500, 300), Vector2i(900, 600), Vector2i(-2000, 5000), size, usable),
			Vector2i(0, 514), "cannot leave the screen")
	check_eq(DisplayLayout.clamp_to(Vector2i(5000, -40), size, usable), Vector2i(1120, 0), "saved spots are pulled back on screen")


func test_corner_positions() -> void:
	var usable := Rect2i(0, 30, 1920, 1000)
	var size := Vector2i(800, 500)
	check_eq(PlatformServiceScript.corner_position(usable, size, "top_left", 24), Vector2i(24, 54), "top_left")
	check_eq(PlatformServiceScript.corner_position(usable, size, "top_right", 24), Vector2i(1096, 54), "top_right")
	check_eq(PlatformServiceScript.corner_position(usable, size, "bottom_left", 24), Vector2i(24, 506), "bottom_left")
	check_eq(PlatformServiceScript.corner_position(usable, size, "bottom_right", 24), Vector2i(1096, 506), "bottom_right")


func test_settings_defaults_and_overrides() -> void:
	var defaults := {"mode": "overlay", "overlay": {"scale": 0.75, "corner": "top_left"}}
	var s := DisplayLayout.load_settings(defaults, PackedStringArray())
	check_eq(s["overlay"]["scale"], 0.75, "data default applied")
	check_eq(s["overlay"]["margin_px"], 24, "built-in default kept")
	s = DisplayLayout.load_settings(defaults, PackedStringArray(["--display-mode", "windowed", "--window-size", "1366x768", "--debug-overlay"]))
	check_eq(s["mode"], "windowed", "mode override")
	check_eq(s["windowed"]["size"], [1366, 768], "window size override")
	check_eq(s["debug_overlay"], true, "debug flag")


func test_invalid_settings_fall_back() -> void:
	var s := DisplayLayout.load_settings({"mode": "fullscreen"}, PackedStringArray(["--corner", "middle", "--window-size", "10x10", "--overlay-scale", "-1"]))
	check_eq(s["mode"], "overlay", "unknown mode")
	check_eq(s["overlay"]["corner"], "bottom_right", "unknown corner")
	check_eq(s["windowed"]["size"], [1280, 720], "too-small window")
	check_eq(s["overlay"]["scale"], DisplayLayout.DEFAULT_OVERLAY_SCALE, "non-positive scale")
