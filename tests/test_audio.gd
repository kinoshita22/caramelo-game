extends "res://tests/lib/test_case.gd"
## Audio data, event mapping and volume maths. No sounds exist yet, so
## every event must be silent without errors.

const ContentData := preload("res://scripts/systems/content_data.gd")
const AudioManagerScript := preload("res://scripts/autoload/audio_manager.gd")

var _doc: Dictionary = {}


func _init() -> void:
	var v: Variant = ContentData.new().read_json("res://data/audio/audio.json")
	_doc = v if typeof(v) == TYPE_DICTIONARY else {}


func test_audio_data_validates() -> void:
	check_no_errors(AudioManagerScript.validate(_doc), "audio.json")
	var bad := _doc.duplicate(true)
	bad["sounds"]["boom"] = {"file": "res://elsewhere/boom.ogg", "bus": "Effects"}
	bad["default_volumes"]["Music"] = 3
	check_error(AudioManagerScript.validate(bad), "needs a file under res://assets/runtime/audio/")
	check_error(AudioManagerScript.validate(bad), "default volume for 'Music' must be 0-1")


func test_events_are_silent_until_sounds_arrive() -> void:
	check_eq(AudioManagerScript.sound_for(_doc, "state:celebration"), "", "mapped but not delivered")
	var with_sound := _doc.duplicate(true)
	with_sound["sounds"]["level_up"] = {"file": "res://assets/runtime/audio/level_up.ogg", "bus": "Effects"}
	check_eq(AudioManagerScript.sound_for(with_sound, "state:celebration"), "level_up", "plays once delivered")
	check_eq(AudioManagerScript.sound_for(with_sound, "state:idle"), "", "unmapped events are silent")


func test_volume_maths() -> void:
	check_eq(AudioManagerScript.volume_db(0.0), -80.0, "zero is silence")
	check(is_equal_approx(AudioManagerScript.volume_db(1.0), 0.0), "full volume is 0 dB")
	check(AudioManagerScript.volume_db(0.5) < 0.0, "half volume is quieter")


func test_buses_are_created_once() -> void:
	AudioManagerScript.ensure_bus("TestBus")
	AudioManagerScript.ensure_bus("TestBus")
	var count := 0
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == "TestBus":
			count += 1
	check_eq(count, 1, "one bus, however often it is asked for")
