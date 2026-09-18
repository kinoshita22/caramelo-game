extends Node2D
## Main scene: builds the island stage, puts the window into overlay or
## windowed mode, keeps the stage fitted to the window and keeps the
## click-through region in sync.
##
## Keys: F3 toggles the debug overlay.
## Command-line overrides (after --): --display-mode overlay|windowed,
## --overlay-scale N, --corner top_left|top_right|bottom_left|bottom_right,
## --window-size WxH, --debug-overlay, --screenshot path.png [--screenshot-frames N].

const DebugOverlay := preload("res://scripts/components/stage_debug_overlay.gd")
const PlatformServiceScript := preload("res://scripts/autoload/platform_service.gd")
const DisplayLayout := preload("res://scripts/components/display_layout.gd")
const LAYOUT_PATH := "res://data/environment/island_layout.json"
const SETTINGS_PATH := "res://data/settings/display_defaults.json"

@onready var stage: Node2D = $Stage

var settings: Dictionary = {}
var window_polygon := PackedVector2Array()
var _debug: Node2D
var _screenshot_path := ""
var _screenshot_frames := 0


func _ready() -> void:
	var content: RefCounted = ContentCatalog.data
	settings = DisplayLayout.load_settings(content.read_json(SETTINGS_PATH), OS.get_cmdline_user_args())
	var layout: Variant = content.read_json(LAYOUT_PATH)
	var errors: Array[String] = ["island_layout.json missing or invalid"] if typeof(layout) != TYPE_DICTIONARY \
			else stage.build(layout, content)
	if not content.is_valid():
		errors.append_array(content.errors)
	if not errors.is_empty():
		for e in errors:
			push_error(e)
		settings["mode"] = "windowed"

	_debug = DebugOverlay.new()
	_debug.stage = stage
	_debug.visible = settings["debug_overlay"]
	stage.add_child(_debug)

	_apply_mode()
	get_viewport().size_changed.connect(_refit)
	_refit()
	_screenshot_path = settings.get("screenshot", "")
	_screenshot_frames = int(settings.get("screenshot_frames", 10))


func _apply_mode() -> void:
	var o: Dictionary = settings["overlay"]
	var screen := PlatformService.resolve_screen(int(o["screen"]))
	if settings["mode"] == "overlay" and PlatformService.transparency_available():
		var usable := DisplayServer.screen_get_usable_rect(screen)
		var size := DisplayLayout.overlay_size(stage.bounds.size, float(o["scale"]), usable.size, int(o["margin_px"]))
		var pos := PlatformServiceScript.corner_position(usable, size, o["corner"], int(o["margin_px"]))
		PlatformService.enter_overlay(Rect2i(pos, size), bool(o["always_on_top"]))
		return
	if settings["mode"] == "overlay":
		push_warning("Window transparency unavailable; falling back to windowed mode.")
	var w: Dictionary = settings["windowed"]
	PlatformService.enter_windowed(Vector2i(int(w["size"][0]), int(w["size"][1])), Color(w["background"]), screen)


func _refit() -> void:
	var margin := 0.0 if PlatformService.mode == "overlay" else float(settings["fit_margin"])
	var t := DisplayLayout.fit(stage.bounds, get_viewport().get_visible_rect(), margin)
	stage.scale = Vector2.ONE * t["scale"]
	stage.position = t["position"]
	_debug.queue_redraw()
	var to_window := get_viewport().get_final_transform() * stage.get_global_transform_with_canvas()
	window_polygon = to_window * stage.hit_polygon
	PlatformService.set_hit_polygon(window_polygon)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_debug.visible = not _debug.visible
		_debug.queue_redraw()


func _process(_delta: float) -> void:
	if _screenshot_path == "":
		return
	_screenshot_frames -= 1
	if _screenshot_frames > 0:
		return
	var path := _screenshot_path
	_screenshot_path = ""
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	var meta := {
		"mode": PlatformService.mode,
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"window_position": [DisplayServer.window_get_position().x, DisplayServer.window_get_position().y],
		"hit_polygon_window_px": Array(window_polygon).map(func(p: Vector2) -> Array: return [p.x, p.y]),
		"stage_scale": stage.scale.x,
	}
	var f := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	get_tree().quit()
