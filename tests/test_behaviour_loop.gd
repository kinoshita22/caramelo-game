extends "res://tests/lib/test_case.gd"
## Autonomous behaviour loop: cycle order, hidden drivers, interruptions.
## Everything runs at a fixed timestep with no nodes or rendering.

const ContentData := preload("res://scripts/systems/content_data.gd")
const BehaviourLoop := preload("res://scripts/systems/behaviour_loop.gd")
const STEP := 0.1

var _content := ContentData.new()
var _balance: Dictionary = {}
var _groups: Array = []


func _init() -> void:
	_content.load_from("res://data")
	var b: Variant = _content.read_json("res://data/balance/behaviour.json")
	_balance = b if typeof(b) == TYPE_DICTIONARY else {}
	var a: Variant = _content.read_json("res://data/animations/animation_groups.json")
	_groups = a["groups"].keys() if typeof(a) == TYPE_DICTIONARY else []


func _loop(overrides: Dictionary = {}) -> RefCounted:
	var balance := _balance.duplicate(true)
	for section in overrides:
		balance[section].merge(overrides[section], true)
	var loop := BehaviourLoop.new()
	loop.configure(balance, _groups)
	return loop


## Runs until the state changes to `until`, or seconds run out.
func _run_until(loop: RefCounted, until: String, max_seconds: float = 600.0) -> float:
	var t := 0.0
	while t < max_seconds:
		loop.tick(STEP)
		t += STEP
		if loop.state == until:
			return t
	return -1.0


func test_balance_data_validates() -> void:
	check_no_errors(BehaviourLoop.validate_balance(_balance, _groups), "behaviour.json")


func test_validation_catches_bad_balance() -> void:
	var bad := _balance.duplicate(true)
	bad["rates"]["energy_drain_workout"] = -1
	bad["thresholds"]["hungry"] = 99
	bad["durations"]["recovery"] = 0
	bad["states"]["eating"] = "munching"
	var errors := BehaviourLoop.validate_balance(bad, _groups)
	check_error(errors, "rates.energy_drain_workout must be a positive number")
	check_error(errors, "thresholds.hungry must be below thresholds.full")
	check_error(errors, "durations.recovery must be a positive number")
	check_error(errors, "states.eating names unknown animation group 'munching'")


func test_every_state_maps_to_a_real_animation_group() -> void:
	var loop := _loop()
	for state in BehaviourLoop.ALL_STATES:
		check(loop.group_for(state) in _groups, "%s -> %s" % [state, loop.group_for(state)])


func test_starts_working_out_and_recovers() -> void:
	var loop := _loop()
	check_eq(loop.state, "idle", "starts idle")
	check(_run_until(loop, "workout") > 0.0, "reaches workout")
	var to_recovery := _run_until(loop, "recovery")
	check(to_recovery > 0.0, "workout ends in recovery")
	check(loop.energy < 100.0, "workout drains energy")
	check(_run_until(loop, "workout") > 0.0, "returns to workout after recovery")


func test_default_run_reaches_every_part_of_the_cycle() -> void:
	# Regression: recovery used to lift energy back over the threshold, so
	# he trained and ate forever and never went to bed.
	var loop := _loop()
	for i in 6000:  # ten minutes
		loop.tick(STEP)
	var visited: Array = loop.history()
	for state in ["workout", "recovery", "hunger_cue", "eating", "sleep_enter", "sleeping", "wake"]:
		check(state in visited, "ten minutes include %s" % state)


func test_only_declared_transitions_are_used() -> void:
	var loop := _loop()
	var seen: Array = []
	loop.state_changed.connect(func(from: String, to: String) -> void: seen.append([from, to]))
	for i in 12000:  # 20 minutes at 0.1 s
		loop.tick(STEP)
	check(seen.size() > 10, "the loop kept moving: %d transitions" % seen.size())
	for pair in seen:
		check(pair[1] in BehaviourLoop.TRANSITIONS[pair[0]], "%s -> %s is declared" % pair)


func test_hunger_detour_when_satiety_runs_low() -> void:
	var loop := _loop({"drivers": {"satiety": {"start": 36.0}}})
	check(_run_until(loop, "hunger_cue") > 0.0, "shows the hunger cue")
	check(_run_until(loop, "eating") > 0.0, "then eats")
	check(_run_until(loop, "workout") > 0.0, "and goes back to training")
	check(loop.satiety >= float(_balance["thresholds"]["full"]) - 1.0, "eating filled him up: %.1f" % loop.satiety)


func test_sleep_detour_when_energy_runs_low() -> void:
	var loop := _loop({"drivers": {"energy": {"start": 26.0}}})
	check(_run_until(loop, "sleep_enter") > 0.0, "starts going to sleep")
	check(_run_until(loop, "sleeping") > 0.0, "sleeps")
	check(_run_until(loop, "wake") > 0.0, "wakes up")
	check(loop.energy >= float(_balance["thresholds"]["rested"]) - 1.0, "sleeping restored energy: %.1f" % loop.energy)


func test_drivers_stay_within_range_over_a_long_run() -> void:
	var loop := _loop()
	for i in 36000:  # one hour
		loop.tick(STEP)
		if loop.energy < 0.0 or loop.energy > 100.0 or loop.satiety < 0.0 or loop.satiety > 100.0:
			check(false, "drivers left 0-100: energy %.1f satiety %.1f" % [loop.energy, loop.satiety])
			return
	check(true, "drivers stayed in range")


func test_reward_interrupts_a_workout_and_returns() -> void:
	var loop := _loop()
	_run_until(loop, "workout")
	check(loop.request("reward"), "reward accepted during a workout")
	check_eq(loop.state, "reward", "playing the reward")
	check(_run_until(loop, "idle") > 0.0, "returns through idle")


func test_evolution_cannot_be_interrupted() -> void:
	var loop := _loop()
	check(loop.request("evolution"), "evolution accepted")
	check(not loop.request("reward"), "reward refused during evolution")
	check(not loop.request("wardrobe"), "wardrobe refused during evolution")
	check_eq(loop.state, "evolution", "still evolving")


func test_pre_evolution_leads_into_evolution() -> void:
	var loop := _loop()
	check(loop.request("pre_evolution"), "pre-evolution accepted")
	check(_run_until(loop, "evolution") > 0.0, "pre-evolution hands over to evolution")
	check(_run_until(loop, "idle") > 0.0, "evolution ends in idle")


func test_wardrobe_pauses_the_cycle_until_closed() -> void:
	var loop := _loop()
	check(loop.request("wardrobe"), "wardrobe opens")
	for i in 600:  # a minute
		loop.tick(STEP)
	check_eq(loop.state, "wardrobe", "cycle waits while the wardrobe is open")
	loop.close_wardrobe()
	check_eq(loop.state, "idle", "closing returns to idle")
	check(_run_until(loop, "workout") > 0.0, "cycle resumes")


func test_action_completed_only_on_natural_endings() -> void:
	var loop := _loop()
	var completed: Array = []
	loop.action_completed.connect(func(s: String) -> void: completed.append(s))
	_run_until(loop, "workout")
	check_eq(completed, ["idle"], "idle gap completed")
	loop.request("celebration")
	check_eq(completed, ["idle"], "interrupted workout did not complete")
