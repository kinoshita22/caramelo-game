extends "res://tests/lib/test_case.gd"
## Frame pacing decisions, power-source detection, start-with-OS entries and
## the menu's option labels.

const ContentData := preload("res://scripts/systems/content_data.gd")
const FramePacing := preload("res://scripts/systems/frame_pacing.gd")
const PlatformServiceScript := preload("res://scripts/autoload/platform_service.gd")
const MenuModal := preload("res://scripts/components/menu_modal.gd")
const POWER_DIR := "user://test_power"

var _config: Dictionary = {}


func _init() -> void:
	var c := ContentData.new()
	var v: Variant = c.read_json("res://data/settings/performance.json")
	_config = v if typeof(v) == TYPE_DICTIONARY else {}


func _fps(state: Dictionary) -> int:
	return FramePacing.target_fps(state, _config)


func test_performance_data_validates() -> void:
	check_no_errors(FramePacing.validate(_config), "performance.json")
	check_error(FramePacing.validate({"idle_fps": 0}), "idle_fps must be 1-240")


func test_frame_rate_follows_what_is_happening() -> void:
	check_eq(_fps({"interacting": true}), 60, "smooth while someone uses it")
	check_eq(_fps({}), 20, "idle")
	check_eq(_fps({"on_battery": true}), 15, "lower still on battery")
	check_eq(_fps({"minimized": true, "interacting": true}), 5, "minimized wins over everything")


func test_idle_rate_still_covers_every_animation() -> void:
	var content := ContentData.new()
	var groups: Dictionary = content.read_json("res://data/animations/animation_groups.json")["groups"]
	var fastest := 0.0
	for g in groups.values():
		fastest = maxf(fastest, float(g["fps"]))
	# A fully bought Speed stat plays the reps faster still.
	var upgrades: Dictionary = content.read_json("res://data/balance/upgrades.json")
	var speed: Dictionary = upgrades["stats"]["speed"]
	fastest *= 1.0 + float(speed["effect_per_level"]) * float(upgrades["max_level"])
	check(_fps({}) >= fastest, "idle %d fps keeps up with the fastest animation (%.1f fps at full Speed)"
			% [_fps({}), fastest])


func test_30_fps_cap_limits_every_state() -> void:
	check_eq(_fps({"interacting": true, "cap_30": true}), 30, "capped while interacting")
	check_eq(_fps({"cap_30": true}), 20, "idle is already below the cap")


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _clear_power() -> void:
	var root := ProjectSettings.globalize_path(POWER_DIR)
	if not DirAccess.dir_exists_absolute(root):
		return
	for supply in DirAccess.get_directories_at(root):
		for f in DirAccess.get_files_at(root.path_join(supply)):
			DirAccess.remove_absolute(root.path_join(supply).path_join(f))
		DirAccess.remove_absolute(root.path_join(supply))


func test_power_source_from_sysfs() -> void:
	_clear_power()
	var root := ProjectSettings.globalize_path(POWER_DIR)
	check_eq(PlatformServiceScript.power_source_from_sysfs(root.path_join("missing")), "unknown", "no sysfs")
	_write(POWER_DIR + "/BAT0/type", "Battery\n")
	_write(POWER_DIR + "/BAT0/status", "Discharging\n")
	_write(POWER_DIR + "/AC/type", "Mains\n")
	_write(POWER_DIR + "/AC/online", "0\n")
	check_eq(PlatformServiceScript.power_source_from_sysfs(root), "battery", "unplugged laptop")
	_write(POWER_DIR + "/AC/online", "1\n")
	check_eq(PlatformServiceScript.power_source_from_sysfs(root), "ac", "plugged in")
	_clear_power()


func test_start_with_os_entries() -> void:
	var win := PlatformServiceScript.autostart_entry("Windows", "C:/Games/Caramelo/Caramelo.exe", "")
	check_eq(win["kind"], "registry", "Windows uses the Run key")
	check_eq(win["key"], "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run", "current user only")
	check_eq(win["value"], "\"C:/Games/Caramelo/Caramelo.exe\"", "quoted executable path")
	var linux := PlatformServiceScript.autostart_entry("Linux", "/opt/caramelo/caramelo", "/home/u")
	check_eq(linux["kind"], "desktop_file", "Linux uses an autostart file")
	check(linux["path"].begins_with("/home/u/.config/autostart/"), "in the user's autostart folder")
	check("Exec=\"/opt/caramelo/caramelo\"" in linux["content"], "that runs the game")
	check_eq(PlatformServiceScript.autostart_entry("macOS", "/x", "/home/u")["kind"], "unsupported", "not yet on macOS")


func test_start_with_os_refuses_to_register_the_editor() -> void:
	var service: Node = PlatformServiceScript.new()
	check_eq(service.set_start_with_os(true), "only available in the installed game", "editor builds refuse")
	check(not service.start_with_os_available(), "and say it is unavailable")
	service.free()


func test_menu_size_label() -> void:
	check_eq(MenuModal.size_label("large"), "Size: Large", "size label")


func test_menu_option_labels() -> void:
	check_eq(MenuModal.option_label("always_on_top", true), "Always on top: On", "on")
	check_eq(MenuModal.option_label("fps_cap_30", false), "30 FPS cap: Off", "off")
	check_eq(MenuModal.option_label("start_with_os", false, "installed game only"),
			"Start with the computer: installed game only", "unavailable reason")
