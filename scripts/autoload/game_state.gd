extends Node
## Autoload: the authoritative simulation state. For now that is progression
## (level, XP, bones, form); needs, inventory and settings join it later.
##
## Holds no scene references. Scenes observe its signals.

const Progression := preload("res://scripts/systems/progression.gd")
const Economy := preload("res://scripts/systems/economy.gd")
const BALANCE_PATH := "res://data/balance/progression.json"
const UPGRADES_PATH := "res://data/balance/upgrades.json"
const DUMBBELLS_PATH := "res://data/equipment/dumbbells.json"
const MEALS_PATH := "res://data/food/meals.json"

## Emitted after a level-up or evolution, where Phase 10 will save.
signal save_requested(reason: String)

var progression := Progression.new()
var economy := Economy.new()
var errors: Array[String] = []


func _enter_tree() -> void:
	var content: RefCounted = ContentCatalog.data
	var balance: Variant = content.read_json(BALANCE_PATH)
	if typeof(balance) != TYPE_DICTIONARY:
		errors = ["progression.json missing or invalid"]
	else:
		errors = progression.configure(balance, content.docs.get("forms", {}).get("forms", []))
	var upgrades: Variant = content.read_json(UPGRADES_PATH)
	var dumbbells: Variant = content.read_json(DUMBBELLS_PATH)
	var meals: Variant = content.read_json(MEALS_PATH)
	if typeof(upgrades) != TYPE_DICTIONARY or typeof(dumbbells) != TYPE_DICTIONARY or typeof(meals) != TYPE_DICTIONARY:
		errors.append("upgrades.json, dumbbells.json or meals.json missing or invalid")
	else:
		var asset_ids: Array = content.docs.get("catalog", {}).get("assets", []).map(
				func(a: Dictionary) -> String: return a["id"])
		errors.append_array(economy.configure(upgrades, dumbbells, meals, asset_ids))
	for e in errors:
		push_error("GameState: " + e)
	progression.leveled_up.connect(func(_level: int) -> void: save_requested.emit("level_up"))
	progression.form_changed.connect(func(_from: int, _to: int) -> void: save_requested.emit("evolution"))
	economy.stat_upgraded.connect(func(_stat: String, _level: int) -> void: save_requested.emit("upgrade"))
	economy.equipment_changed.connect(func(_id: String) -> void: save_requested.emit("purchase"))
	economy.food_changed.connect(func(_id: String) -> void: save_requested.emit("purchase"))


func is_valid() -> bool:
	return errors.is_empty()
