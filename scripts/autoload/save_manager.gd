extends Node
## Autoload: loads and saves the game through SaveFile (atomic writes,
## backup, corrupt-file recovery), autosaves, and works out offline progress
## on startup.
##
## Inert until the main scene calls begin(), so tests and tools never touch
## a player's save.
##
## Command line: --save-file <path> to use another file, --no-save to neither
## load nor write (previews and screenshots).

const SaveData := preload("res://scripts/systems/save_data.gd")
const SaveFile := preload("res://scripts/systems/save_file.gd")
const OfflineProgress := preload("res://scripts/systems/offline_progress.gd")
const CONFIG_PATH := "res://data/balance/offline.json"
const BEHAVIOUR_PATH := "res://data/balance/behaviour.json"
const ANIMATIONS_PATH := "res://data/animations/animation_groups.json"
const DEFAULT_PATH := "user://save.json"

signal saved(path: String)

var path := DEFAULT_PATH
var enabled := false
## "fresh", "loaded", "backup" or "fresh_after_corrupt".
var load_status := ""
var errors: Array[String] = []
## Offline summary from the last begin(), or {} when there was none.
var offline_summary := {}
## Saved settings (display mode and friends), editable by the game.
var settings := {}

var _config := {}
var _loop: RefCounted
var _needs := {}
var _autosave: Timer
var _debounce: Timer


## Loads the save (or starts fresh), applies it to GameState and simulates
## the time away. Call once, before the island is built.
func begin(argv: PackedStringArray = OS.get_cmdline_user_args()) -> String:
	var i := argv.find("--save-file")
	if i >= 0 and i + 1 < argv.size():
		path = argv[i + 1]
	enabled = not argv.has("--no-save")
	var config: Variant = ContentCatalog.data.read_json(CONFIG_PATH)
	_config = config if typeof(config) == TYPE_DICTIONARY else {}
	if not enabled:
		load_status = "disabled"
		return load_status

	var loaded: Dictionary = SaveFile.new(path).read()
	load_status = loaded["status"]
	errors.assign(loaded.get("errors", []))
	for e in errors:
		push_warning("SaveManager: " + e)
	if loaded.has("doc"):
		var doc: Dictionary = loaded["doc"]
		SaveData.apply(doc, GameState.progression, GameState.economy, GameState.furniture, GameState.cosmetics)
		settings = doc.get("settings", {})
		_needs = doc.get("needs", {})
		var behaviour: Variant = ContentCatalog.data.read_json(BEHAVIOUR_PATH)
		if typeof(behaviour) == TYPE_DICTIONARY:
			var away: float = Time.get_unix_time_from_system() - float(doc["saved_at_unix"])
			var animations: Variant = ContentCatalog.data.read_json(ANIMATIONS_PATH)
			var lift: float = OfflineProgress.seconds_per_lift(behaviour,
					animations if typeof(animations) == TYPE_DICTIONARY else {})
			offline_summary = OfflineProgress.simulate(away, _config, behaviour,
					GameState.progression, GameState.economy, _needs, lift)
			_needs = {"energy": offline_summary["energy"], "satiety": offline_summary["satiety"]}

	_start_timers()
	GameState.save_requested.connect(func(_reason: String) -> void: _debounce.start())
	save_game()  # records the catch-up at once
	return load_status


## Hands over the live behaviour loop, whose energy and satiety are saved,
## and puts the saved (or caught-up) values into it.
func attach_loop(loop: RefCounted) -> void:
	_loop = loop
	if _loop != null and not _needs.is_empty():
		SaveData.apply_needs({"needs": _needs}, _loop)


## Throws the saved game away and writes the fresh one over it, so a reset
## survives a crash or a kill. GameState.reset() puts the systems back
## first; this clears what is kept here. The player's settings stay: they
## are about the window on their desktop, not the game being started over.
func reset_save() -> bool:
	_needs = {}
	offline_summary = {}
	return save_game()


func save_game() -> bool:
	if not enabled:
		return false
	var doc := SaveData.build(GameState.progression, GameState.economy, GameState.furniture,
			GameState.cosmetics, _loop, settings, Time.get_unix_time_from_system())
	if _loop == null and not _needs.is_empty():
		doc["needs"] = _needs
	var err: String = SaveFile.new(path).write(doc)
	if err != "":
		push_error("SaveManager: " + err)
		return false
	saved.emit(path)
	return true


func _start_timers() -> void:
	_autosave = Timer.new()
	_autosave.wait_time = maxf(float(_config.get("autosave_seconds", 60.0)), 5.0)
	_autosave.timeout.connect(save_game)
	add_child(_autosave)
	_autosave.start()
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = maxf(float(_config.get("save_debounce_seconds", 1.5)), 0.1)
	_debounce.timeout.connect(save_game)
	add_child(_debounce)


func _notification(what: int) -> void:
	# Closing the window lands here; quitting from the menu calls save_game().
	if what == NOTIFICATION_WM_CLOSE_REQUEST and enabled and load_status != "":
		save_game()
