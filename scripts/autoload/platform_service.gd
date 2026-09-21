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


func is_minimized() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED


## Keeps the overlay above other windows, or lets them cover it.
func set_always_on_top(enabled: bool) -> void:
	if mode == "overlay":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, enabled)


## "battery", "ac" or "unknown". Read from /sys on Linux; other systems do
## not expose it to GDScript without a native helper, so they report unknown.
func power_source() -> String:
	if OS.get_name() != "Linux":
		return "unknown"
	return power_source_from_sysfs("/sys/class/power_supply")


static func power_source_from_sysfs(root: String) -> String:
	if not DirAccess.dir_exists_absolute(root):
		return "unknown"
	var has_battery := false
	for supply in DirAccess.get_directories_at(root):
		var dir := root.path_join(supply)
		var kind := _read_trimmed(dir.path_join("type"))
		if kind == "Mains" and _read_trimmed(dir.path_join("online")) == "1":
			return "ac"
		if kind == "Battery":
			has_battery = true
			if _read_trimmed(dir.path_join("status")) == "Discharging":
				return "battery"
	return "ac" if has_battery else "unknown"


static func _read_trimmed(file: String) -> String:
	return FileAccess.get_file_as_string(file).strip_edges() if FileAccess.file_exists(file) else ""


## Whether start-with-OS can work here: an installed (exported) game on a
## system we know how to register with.
func start_with_os_available() -> bool:
	return not OS.has_feature("editor") and autostart_entry(OS.get_name(), OS.get_executable_path(),
			OS.get_environment("HOME"))["kind"] != "unsupported"


## Registers or removes the game from the OS's startup list. Returns "" on
## success or an error message.
func set_start_with_os(enabled: bool) -> String:
	if OS.has_feature("editor"):
		return "only available in the installed game"
	var entry := autostart_entry(OS.get_name(), OS.get_executable_path(), OS.get_environment("HOME"))
	match entry["kind"]:
		"registry":
			var args := ["add", entry["key"], "/v", entry["name"], "/t", "REG_SZ", "/d", entry["value"], "/f"] \
					if enabled else ["delete", entry["key"], "/v", entry["name"], "/f"]
			return "" if OS.execute("reg", args) == 0 or not enabled else "could not update the registry"
		"desktop_file":
			if not enabled:
				if FileAccess.file_exists(entry["path"]):
					DirAccess.remove_absolute(entry["path"])
				return ""
			DirAccess.make_dir_recursive_absolute(entry["path"].get_base_dir())
			var f := FileAccess.open(entry["path"], FileAccess.WRITE)
			if f == null:
				return "could not write %s" % entry["path"]
			f.store_string(entry["content"])
			return ""
	return "not supported on this system"


## How the game registers to start with the OS. Pure, for tests.
static func autostart_entry(os_name: String, exe_path: String, home: String) -> Dictionary:
	var app_name: String = ProjectSettings.get_setting("application/config/name", "My Caramelo")
	match os_name:
		"Windows":
			return {"kind": "registry", "key": "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
					"name": app_name.replace(" ", ""), "value": "\"%s\"" % exe_path}
		"Linux", "FreeBSD":
			if home == "":
				return {"kind": "unsupported"}
			return {"kind": "desktop_file",
					"path": home.path_join(".config/autostart/%s.desktop" % app_name.to_lower().replace(" ", "-")),
					"content": "[Desktop Entry]\nType=Application\nName=%s\nExec=\"%s\"\nX-GNOME-Autostart-enabled=true\n" % [app_name, exe_path]}
	return {"kind": "unsupported"}
