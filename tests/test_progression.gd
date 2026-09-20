extends "res://tests/lib/test_case.gd"
## XP curve, levelling, bones, form changes and the level-100 ending.

const ContentData := preload("res://scripts/systems/content_data.gd")
const Progression := preload("res://scripts/systems/progression.gd")

var _content := ContentData.new()
var _balance: Dictionary = {}
var _forms: Array = []


func _init() -> void:
	_content.load_from("res://data")
	var b: Variant = _content.read_json("res://data/balance/progression.json")
	_balance = b if typeof(b) == TYPE_DICTIONARY else {}
	_forms = _content.docs.get("forms", {}).get("forms", [])


func _progression() -> RefCounted:
	var p := Progression.new()
	p.configure(_balance, _forms)
	return p


func test_balance_data_validates() -> void:
	check_no_errors(Progression.validate_balance(_balance, _forms), "progression.json")


func test_validation_catches_bad_balance() -> void:
	var bad := _balance.duplicate(true)
	bad["xp_curve"]["base"] = 0
	bad["rewards"]["workout_xp"] = -5
	check_error(Progression.validate_balance(bad, _forms), "xp_curve.base must be a positive number")
	check_error(Progression.validate_balance(bad, _forms), "rewards.workout_xp must be a positive number")
	var short_forms := _forms.duplicate(true)
	short_forms.pop_back()
	check_error(Progression.validate_balance(_balance, short_forms), "xp_curve.max_level is 100")


func test_curve_rises_and_has_no_gaps() -> void:
	var p := _progression()
	var previous := 0.0
	for level in range(1, 100):
		var needed: float = p.xp_to_next(level)
		check(needed >= previous, "level %d needs at least as much as the one before" % level)
		check(needed > 0.0, "level %d needs XP" % level)
		previous = needed
	check_eq(p.xp_to_next(100), 0.0, "nothing left to earn at the cap")


func test_levels_up_and_carries_the_remainder() -> void:
	var p := _progression()
	var needed: float = p.xp_to_next(1)
	var result: Dictionary = p.add_xp(needed + 1.0)
	check_eq(result["levels_gained"], 1, "one level gained")
	check_eq(p.level, 2, "now level 2")
	check_eq(p.xp, 1.0, "the extra XP carried over")


func test_one_award_can_cross_several_levels() -> void:
	var p := _progression()
	var result: Dictionary = p.add_xp(p.total_xp_for_level(6))
	check_eq(p.level, 6, "jumped to level 6")
	check_eq(result["levels_gained"], 5, "reported five levels")
	check_eq(result["from_level"], 1, "reported the starting level")


func test_level_never_drops_and_negative_xp_is_ignored() -> void:
	var p := _progression()
	p.add_xp(p.total_xp_for_level(12))
	var before: int = p.level
	p.add_xp(-500.0)
	check_eq(p.level, before, "negative XP changes nothing")
	check_eq(p.xp, 0.0, "and does not eat into the current level")


func test_forms_follow_the_level_ranges() -> void:
	var p := _progression()
	for pair in [[1, 1], [9, 1], [10, 2], [29, 3], [30, 4], [99, 10], [100, 11]]:
		check_eq(p.form_for_level(pair[0]), pair[1], "level %d is form %d" % pair)


func test_crossing_a_form_boundary_is_reported() -> void:
	var p := _progression()
	var changes: Array = []
	p.form_changed.connect(func(from: int, to: int) -> void: changes.append([from, to]))
	var result: Dictionary = p.add_xp(p.total_xp_for_level(10))
	check_eq(p.level, 10, "reached level 10")
	check(result["form_changed"], "form change reported")
	check_eq(result["to_form"], 2, "now form 2")
	check_eq(changes, [[1, 2]], "signal fired once")


func test_reaching_level_100_ends_the_curve() -> void:
	var p := _progression()
	var result: Dictionary = p.add_xp(p.total_xp_for_level(100) + 10000.0)
	check_eq(p.level, 100, "capped at 100")
	check_eq(p.form, 11, "wearing the final form")
	check(result["at_max_level"], "reported as maxed")
	check_eq(p.xp, 0.0, "no leftover XP at the cap")
	var after: Dictionary = p.add_xp(500.0)
	check_eq(after["levels_gained"], 0, "no further levels")
	check_eq(after["xp_awarded"], 0.0, "XP stops counting")


func test_workouts_pay_xp_and_bones_with_a_bonus() -> void:
	var p := _progression()
	var every := int(_balance["rewards"]["bonus_bones_every"])
	var plain: Dictionary = {}
	for i in range(1, every):
		plain = p.complete_workout()
	check(not plain["bonus"], "no bonus before the Nth workout")
	check_eq(p.bones, int(_balance["rewards"]["workout_bones"]) * (every - 1), "bones so far")
	var bonus: Dictionary = p.complete_workout()
	check(bonus["bonus"], "the Nth workout pays a bonus")
	check_eq(bonus["bones_awarded"], int(_balance["rewards"]["workout_bones"]) + int(_balance["rewards"]["bonus_bones"]), "bonus added")
	check(p.xp > 0.0 or p.level > 1, "workouts also pay XP")


func test_bones_only_ever_increase() -> void:
	var p := _progression()
	p.add_bones(50)
	p.add_bones(-100)
	check_eq(p.bones, 50, "negative awards are ignored")


func test_restore_puts_back_a_saved_state() -> void:
	var p := _progression()
	p.restore(42, 17.0, 250, 33)
	check_eq(p.level, 42, "level restored")
	check_eq(p.xp, 17.0, "xp restored")
	check_eq(p.bones, 250, "bones restored")
	check_eq(p.form, 5, "form follows the level")
	p.restore(0, -5.0, -1)
	check_eq(p.level, 1, "level clamped to 1")
	check_eq(p.bones, 0, "bones clamped to 0")


func test_whole_run_from_level_1_to_100_is_consistent() -> void:
	var p := _progression()
	var levels_seen: Array = []
	p.leveled_up.connect(func(l: int) -> void: levels_seen.append(l))
	var workouts := 0
	while not p.at_max_level() and workouts < 100000:
		p.complete_workout()
		workouts += 1
	check_eq(p.level, 100, "reached level 100 in %d workouts" % workouts)
	check_eq(levels_seen.size(), 99, "every level announced once")
	check_eq(p.form, 11, "ends in the final form")
	check(workouts > 1000 and workouts < 10000, "workouts needed stays in a sane range: %d" % workouts)
