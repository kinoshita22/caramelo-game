extends Node
## Autoload: the authoritative simulation state. For now that is progression
## (level, XP, bones, form); needs, inventory and settings join it later.
##
## Holds no scene references. Scenes observe its signals.

const Progression := preload("res://scripts/systems/progression.gd")
const BALANCE_PATH := "res://data/balance/progression.json"

## Emitted after a level-up or evolution, where Phase 10 will save.
signal save_requested(reason: String)

var progression := Progression.new()
var errors: Array[String] = []


func _enter_tree() -> void:
	var content: RefCounted = ContentCatalog.data
	var balance: Variant = content.read_json(BALANCE_PATH)
	if typeof(balance) != TYPE_DICTIONARY:
		errors = ["progression.json missing or invalid"]
	else:
		errors = progression.configure(balance, content.docs.get("forms", {}).get("forms", []))
	for e in errors:
		push_error("GameState: " + e)
	progression.leveled_up.connect(func(_level: int) -> void: save_requested.emit("level_up"))
	progression.form_changed.connect(func(_from: int, _to: int) -> void: save_requested.emit("evolution"))


func is_valid() -> bool:
	return errors.is_empty()
