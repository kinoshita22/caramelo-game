extends "res://tests/lib/test_case.gd"
## Bone spending: upgrade costs and caps, purchase rules, ownership and the
## modifiers the rest of the game reads.

const ContentData := preload("res://scripts/systems/content_data.gd")
const Economy := preload("res://scripts/systems/economy.gd")
const Progression := preload("res://scripts/systems/progression.gd")
const BehaviourLoop := preload("res://scripts/systems/behaviour_loop.gd")

var _content := ContentData.new()
var _upgrades: Dictionary = {}
var _dumbbells: Dictionary = {}
var _meals: Dictionary = {}
var _assets: Array = []


func _init() -> void:
	_content.load_from("res://data")
	_upgrades = _read("res://data/balance/upgrades.json")
	_dumbbells = _read("res://data/equipment/dumbbells.json")
	_meals = _read("res://data/food/meals.json")
	_assets = _content.docs.get("catalog", {}).get("assets", []).map(func(a: Dictionary) -> String: return a["id"])


func _read(path: String) -> Dictionary:
	var v: Variant = _content.read_json(path)
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _economy() -> RefCounted:
	var e := Economy.new()
	e.configure(_upgrades, _dumbbells, _meals, _assets)
	return e


func _wallet(bones: int) -> RefCounted:
	var p := Progression.new()
	p.configure(_read("res://data/balance/progression.json"), _content.docs["forms"]["forms"])
	p.add_bones(bones)
	return p


func test_data_validates() -> void:
	check_no_errors(Economy.validate(_upgrades, _dumbbells, _meals, _assets), "upgrade, dumbbell and meal data")


func test_validation_catches_bad_data() -> void:
	var bad_up := _upgrades.duplicate(true)
	bad_up["stats"]["strength"]["effect_per_level"] = 0
	bad_up["stats"]["cleanliness"] = {"effect_per_level": 1}
	check_error(Economy.validate(bad_up, _dumbbells, _meals, _assets), "stats.strength needs a positive effect_per_level")
	check_error(Economy.validate(bad_up, _dumbbells, _meals, _assets), "unknown stat 'cleanliness'")
	var bad_tiers := _dumbbells.duplicate(true)
	bad_tiers["tiers"][1]["cost"] = -5
	bad_tiers["tiers"][2]["asset"] = "equipment_food.nope"
	bad_tiers["default"] = "missing"
	var errors := Economy.validate(_upgrades, bad_tiers, _meals, _assets)
	check_error(errors, "cost must be zero or more")
	check_error(errors, "uses unknown asset 'equipment_food.nope'")
	check_error(errors, "'default' must name one of the tiers")


func test_starts_with_the_free_tiers_only() -> void:
	var e := _economy()
	check_eq(e.equipped_equipment, "starter_light", "starter dumbbells equipped")
	check_eq(e.active_food, "basic_kibble", "kibble active")
	check_eq(e.owned_equipment.size(), 1, "owns one dumbbell tier")
	for stat in Economy.STATS:
		check_eq(e.stat_level(stat), 0, "%s starts at 0" % stat)


func test_upgrade_costs_rise_and_stop_at_the_cap() -> void:
	var e := _economy()
	var wallet := _wallet(1000000)
	var previous := 0
	for i in e.max_stat_level():
		var cost: int = e.stat_cost("strength")
		check(cost > previous, "level %d costs more than the one before" % (i + 1))
		previous = cost
		check(e.upgrade_stat("strength", wallet)["ok"], "bought level %d" % (i + 1))
	check_eq(e.stat_level("strength"), e.max_stat_level(), "reached the cap")
	check_eq(e.stat_cost("strength"), 0, "nothing more to buy")
	check_eq(e.upgrade_stat("strength", wallet)["reason"], "maxed", "refused at the cap")


func test_upgrade_refused_without_bones_and_spends_nothing() -> void:
	var e := _economy()
	var wallet := _wallet(5)
	var result: Dictionary = e.upgrade_stat("strength", wallet)
	check_eq(result["reason"], "not_enough_bones", "refused")
	check_eq(wallet.bones, 5, "bones untouched")
	check_eq(e.stat_level("strength"), 0, "no level gained")


func test_bones_never_go_negative() -> void:
	var wallet := _wallet(10)
	check(not wallet.spend_bones(11), "cannot overspend")
	check(not wallet.spend_bones(-5), "cannot spend a negative amount")
	check_eq(wallet.bones, 10, "balance unchanged")
	check(wallet.spend_bones(10), "can spend everything")
	check_eq(wallet.bones, 0, "down to zero, not below")


func test_equipment_locked_until_the_level_is_reached() -> void:
	var e := _economy()
	var wallet := _wallet(100000)
	check_eq(e.buy_equipment("heavy_pro", wallet, 5)["reason"], "locked", "level 5 cannot buy the pro tier")
	check_eq(wallet.bones, 100000, "locked purchase spends nothing")
	check(e.buy_equipment("standard_iron", wallet, 10)["ok"], "level 10 can buy iron")
	check_eq(e.equipped_equipment, "standard_iron", "and it is equipped")
	check_eq(e.buy_equipment("standard_iron", wallet, 10)["reason"], "already_owned", "no buying twice")


func test_equipping_requires_ownership() -> void:
	var e := _economy()
	check(not e.equip("cosmic_final"), "cannot equip what is not owned")
	check_eq(e.equipped_equipment, "starter_light", "still on the starter pair")
	e.buy_equipment("standard_iron", _wallet(1000), 10)
	check(e.equip("starter_light"), "can switch back to an owned tier")
	check_eq(e.equipped_equipment, "starter_light", "switched")


func test_food_purchase_and_selection() -> void:
	var e := _economy()
	var wallet := _wallet(5000)
	check(e.buy_food("balanced_chicken", wallet, 20)["ok"], "bought the chicken bowl")
	check_eq(e.active_food, "balanced_chicken", "it becomes the active meal")
	check(e.set_active_food("basic_kibble"), "can go back to kibble")
	check(not e.set_active_food("premium_beef_pumpkin"), "cannot pick an unowned meal")


func test_available_lists_follow_level_and_ownership() -> void:
	var e := _economy()
	check_eq(e.available_equipment(1), [], "nothing new at level 1")
	check_eq(e.available_equipment(10), ["standard_iron"], "iron unlocks at 10")
	e.buy_equipment("standard_iron", _wallet(1000), 10)
	check_eq(e.available_equipment(10), [], "owned tiers drop off the list")
	check_eq(e.available_food(50), ["snack_banana_oats", "balanced_chicken", "fish_sweet_potato"], "meals up to level 50")


func test_modifiers_reflect_upgrades_and_gear() -> void:
	var e := _economy()
	var base: Dictionary = e.modifiers()
	check_eq(base["xp_multiplier"], 1.0, "no bonus at the start")
	var wallet := _wallet(1000000)
	for i in 5:
		e.upgrade_stat("strength", wallet)
		e.upgrade_stat("speed", wallet)
		e.upgrade_stat("recovery", wallet)
	e.buy_equipment("standard_iron", wallet, 10)
	var m: Dictionary = e.modifiers()
	check(is_equal_approx(m["xp_multiplier"], 1.2 * 1.15), "strength and gear multiply XP: %s" % m["xp_multiplier"])
	check(m["animation_speed"] > base["animation_speed"], "speed quickens the animation")
	check(m["rest_duration_scale"] < base["rest_duration_scale"], "recovery shortens rests")
	check(m["workout_duration_scale"] < base["workout_duration_scale"], "speed shortens the session")


func test_modifiers_change_how_long_states_last() -> void:
	var balance: Dictionary = _read("res://data/balance/behaviour.json")
	var groups: Array = _read("res://data/animations/animation_groups.json")["groups"].keys()
	var plain := BehaviourLoop.new()
	plain.configure(balance, groups)
	var quick := BehaviourLoop.new()
	quick.configure(balance, groups)
	quick.duration_scale = {"recovery": 0.5}
	quick.rate_scale = {"energy_restore_recovery": 2.0}
	for loop in [plain, quick]:
		while loop.state != "recovery":
			loop.tick(0.1)
	var plain_time := 0.0
	while plain.state == "recovery":
		plain.tick(0.1)
		plain_time += 0.1
	var quick_time := 0.0
	while quick.state == "recovery":
		quick.tick(0.1)
		quick_time += 0.1
	check(quick_time < plain_time * 0.6, "halved recovery is shorter: %.1fs vs %.1fs" % [quick_time, plain_time])


func test_snapshot_and_restore_round_trip() -> void:
	var e := _economy()
	var wallet := _wallet(100000)
	e.upgrade_stat("endurance", wallet)
	e.buy_equipment("standard_iron", wallet, 10)
	e.buy_food("balanced_chicken", wallet, 20)
	var saved: Dictionary = e.snapshot()
	var restored := _economy()
	restored.restore(saved)
	check_eq(restored.stat_level("endurance"), 1, "stat restored")
	check_eq(restored.equipped_equipment, "standard_iron", "gear restored")
	check_eq(restored.active_food, "balanced_chicken", "meal restored")
	check_eq(restored.modifiers(), e.modifiers(), "same modifiers after restoring")


func test_restore_ignores_unknown_entries() -> void:
	var e := _economy()
	e.restore({"stats": {"strength": 999, "nonsense": 5}, "owned_equipment": ["nope"],
			"equipped_equipment": "nope", "active_food": "nope"})
	check_eq(e.stat_level("strength"), e.max_stat_level(), "clamped to the cap")
	check_eq(e.equipped_equipment, "starter_light", "unknown gear ignored")
	check_eq(e.owned_equipment, ["starter_light"], "unknown ownership ignored")
