extends "res://tests/lib/test_case.gd"
## Effects data and the pure helpers behind the effects player.

const ContentData := preload("res://scripts/systems/content_data.gd")
const EffectsPlayer := preload("res://scripts/components/effects_player.gd")
const BehaviourLoop := preload("res://scripts/systems/behaviour_loop.gd")

var _content := ContentData.new()
var _doc: Dictionary = {}


func _init() -> void:
	_content.load_from("res://data")
	var v: Variant = _content.read_json("res://data/effects/effects.json")
	_doc = v if typeof(v) == TYPE_DICTIONARY else {}


func test_effects_data_validates() -> void:
	var assets: Array = _content.docs["catalog"]["assets"].map(func(a: Dictionary) -> String: return a["id"])
	check_no_errors(EffectsPlayer.validate(_doc, assets), "effects.json")
	check_error(EffectsPlayer.validate({"effects": {"x": {"trigger": "when_bored"}}}), "unknown trigger 'when_bored'")


func test_state_triggers_name_real_behaviour_states() -> void:
	for name in _doc["effects"]:
		var trig: String = _doc["effects"][name]["trigger"]
		if trig.begins_with("state:"):
			check(trig.trim_prefix("state:") in BehaviourLoop.ALL_STATES, "%s listens to a real state (%s)" % [name, trig])


func test_triggers_pick_their_effects() -> void:
	check_eq(EffectsPlayer.effects_for(_doc["effects"], "state:celebration"), ["level_up"], "level-up on celebration")
	check_eq(EffectsPlayer.effects_for(_doc["effects"], "state:evolution"), ["evolution"], "evolution effect")
	check_eq(EffectsPlayer.effects_for(_doc["effects"], "bones_spent"), ["bones_spent"], "spending")
	check_eq(EffectsPlayer.effects_for(_doc["effects"], "state:sleeping"), [], "nothing while sleeping")


func test_text_fills_in_values() -> void:
	check_eq(EffectsPlayer.format_text("Level {level}!", {"level": 12}), "Level 12!", "level")
	check_eq(EffectsPlayer.format_text("+{amount}", {"amount": 13}), "+13", "amount")
	check_eq(EffectsPlayer.format_text("Evolved!", {"level": 3}), "Evolved!", "no placeholders")
