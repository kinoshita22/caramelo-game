extends Node
## Autoload: sound effects, music and ambience on their own buses, each with
## a volume the player can change. Everything comes from data/audio/audio.json;
## a sound with no file is simply silent, so the game runs fine before the
## audio is delivered.

const AssetIO := preload("res://scripts/tools/asset_io.gd")
const CONFIG_PATH := "res://data/audio/audio.json"
const POOL_SIZE := 6

var config := {}
## Bus name -> linear volume 0-1.
var volumes := {}

var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _streams := {}


func _ready() -> void:
	var doc: Variant = AssetIO.read_json(CONFIG_PATH)
	config = doc if typeof(doc) == TYPE_DICTIONARY else {}
	for bus in config.get("buses", []):
		ensure_bus(bus)
	volumes = config.get("default_volumes", {}).duplicate()
	for bus in volumes:
		set_volume(bus, float(volumes[bus]))
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "Effects"
		add_child(player)
		_pool.append(player)
	_music = _looping_player("Music")
	_ambience = _looping_player("Ambience")


## Sets a bus volume (0-1) and remembers it.
func set_volume(bus: String, linear: float) -> void:
	volumes[bus] = clampf(linear, 0.0, 1.0)
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, volume_db(volumes[bus]))
		AudioServer.set_bus_mute(index, volumes[bus] <= 0.0)


## Plays whatever sound data/audio maps to an event; silent if none.
func play_event(event_name: String) -> void:
	var sound_id: String = sound_for(config, event_name)
	if sound_id != "":
		play(sound_id)


func play(sound_id: String) -> void:
	var stream := _stream(sound_id)
	if stream == null:
		return
	var player: AudioStreamPlayer = _pool[0]
	for p in _pool:
		if not p.playing:
			player = p
			break
	player.bus = config.get("sounds", {}).get(sound_id, {}).get("bus", "Effects")
	player.stream = stream
	player.play()


## Starts the music and ambience named in the data, if they exist.
func start_background() -> void:
	for pair in [[_music, config.get("music", "")], [_ambience, config.get("ambience", "")]]:
		var stream := _stream(pair[1])
		if stream != null:
			pair[0].stream = stream
			pair[0].play()


func _stream(sound_id: String) -> AudioStream:
	if sound_id == "":
		return null
	if _streams.has(sound_id):
		return _streams[sound_id]
	var file: String = config.get("sounds", {}).get(sound_id, {}).get("file", "")
	var stream: AudioStream = load(file) if file != "" and ResourceLoader.exists(file) else null
	_streams[sound_id] = stream
	return stream


func _looping_player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.finished.connect(player.play)  # loop whatever is given
	add_child(player)
	return player


static func ensure_bus(bus: String) -> void:
	if AudioServer.get_bus_index(bus) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, "Master")


## The sound id for an event, or "" when none is mapped or delivered.
static func sound_for(doc: Dictionary, event_name: String) -> String:
	var id: String = str(doc.get("events", {}).get(event_name, ""))
	return id if doc.get("sounds", {}).has(id) else ""


## Linear 0-1 to decibels, with 0 as silence.
static func volume_db(linear: float) -> float:
	return -80.0 if linear <= 0.0 else linear_to_db(clampf(linear, 0.0, 1.0))


static func validate(doc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var buses: Variant = doc.get("buses")
	if typeof(buses) != TYPE_ARRAY or buses.is_empty():
		return ["audio: 'buses' must be a non-empty array"]
	for bus in doc.get("default_volumes", {}):
		var v: Variant = doc["default_volumes"][bus]
		if not bus in buses:
			errors.append("audio: default volume for unknown bus '%s'" % bus)
		elif not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) or float(v) < 0.0 or float(v) > 1.0:
			errors.append("audio: default volume for '%s' must be 0-1" % bus)
	var sounds: Variant = doc.get("sounds", {})
	for id in sounds:
		var s: Variant = sounds[id]
		if typeof(s) != TYPE_DICTIONARY or not str(s.get("file", "")).begins_with("res://assets/runtime/audio/"):
			errors.append("audio: sound '%s' needs a file under res://assets/runtime/audio/" % id)
		elif not s.get("bus", "Effects") in buses:
			errors.append("audio: sound '%s' uses unknown bus '%s'" % [id, s.get("bus")])
	return errors
