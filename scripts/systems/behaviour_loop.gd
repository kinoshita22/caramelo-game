extends RefCounted
## Decides what Caramelo does next. Pure simulation: no nodes, no textures,
## no rendering, so it runs deterministically in tests at a fixed timestep.
##
## The player never drives this. Energy and satiety are hidden 0-100 values
## that steer the cycle:
##   workout -> recovery -> (hunger cue -> eating) -> (sleep -> wake) -> ...
## with idle filling short gaps. Events (level-up celebration, bone reward,
## evolution, wardrobe preview) interrupt by priority; nothing interrupts an
## evolution, and no state ever ends in failure or lost progress.

signal state_changed(from_state: String, to_state: String)
## Emitted when a state ran to its natural end (not when interrupted).
signal action_completed(state_name: String)

const IDLE := "idle"
const WORKOUT := "workout"
const RECOVERY := "recovery"
const HUNGER_CUE := "hunger_cue"
const EATING := "eating"
const SLEEP_ENTER := "sleep_enter"
const SLEEPING := "sleeping"
const WAKE := "wake"
const CELEBRATION := "celebration"
const REWARD := "reward"
const PRE_EVOLUTION := "pre_evolution"
const EVOLUTION := "evolution"
const WARDROBE := "wardrobe"

const CYCLE_STATES := [IDLE, WORKOUT, RECOVERY, HUNGER_CUE, EATING, SLEEP_ENTER, SLEEPING, WAKE]
const EVENT_STATES := [CELEBRATION, REWARD, PRE_EVOLUTION, EVOLUTION, WARDROBE]
const ALL_STATES := CYCLE_STATES + EVENT_STATES

## Master plan Phase 5 priority. Higher wins; a request is accepted only if
## it outranks the current state.
const PRIORITY := {
	IDLE: 0, WORKOUT: 1, RECOVERY: 2, HUNGER_CUE: 3, EATING: 3,
	SLEEP_ENTER: 3, SLEEPING: 3, WAKE: 3,
	WARDROBE: 5, CELEBRATION: 7, REWARD: 7, PRE_EVOLUTION: 9, EVOLUTION: 10,
}

## Transitions the loop may make on its own. Event states are entered by
## request() instead, and always return through their listed exits.
const TRANSITIONS := {
	IDLE: [WORKOUT, HUNGER_CUE, SLEEP_ENTER],
	WORKOUT: [RECOVERY],
	RECOVERY: [IDLE, WORKOUT, HUNGER_CUE, SLEEP_ENTER],
	HUNGER_CUE: [EATING],
	EATING: [IDLE, WORKOUT, SLEEP_ENTER],
	SLEEP_ENTER: [SLEEPING],
	SLEEPING: [WAKE],
	WAKE: [IDLE, WORKOUT, HUNGER_CUE],
	CELEBRATION: [IDLE],
	REWARD: [IDLE],
	PRE_EVOLUTION: [EVOLUTION],
	EVOLUTION: [IDLE],
	WARDROBE: [IDLE],
}

var state := IDLE
var time_in_state := 0.0
var energy := 100.0
var satiety := 100.0
## Set while a wardrobe preview is open; the cycle waits.
var paused := false

var _rates := {}
var _thresholds := {}
var _durations := {}
var _groups := {}
var _history: Array[String] = []


## Applies data/balance/behaviour.json. Returns validation errors; on error
## nothing is applied.
func configure(balance: Dictionary, group_names: Array = []) -> Array[String]:
	var errors := validate_balance(balance, group_names)
	if not errors.is_empty():
		return errors
	_rates = balance["rates"]
	_thresholds = balance["thresholds"]
	_durations = balance["durations"]
	_groups = balance["states"]
	energy = float(balance["drivers"]["energy"]["start"])
	satiety = float(balance["drivers"]["satiety"]["start"])
	state = IDLE
	time_in_state = 0.0
	_history = [IDLE]
	return errors


## Animation group for the current state.
func group_for(state_name: String) -> String:
	return _groups.get(state_name, "")


## States entered so far, oldest first (debugging and tests).
func history() -> Array[String]:
	return _history.duplicate()


func tick(delta: float) -> void:
	if _rates.is_empty() or delta <= 0.0:
		return
	_update_drivers(delta)
	time_in_state += delta
	if paused:
		return
	var next := _next_state()
	if next != "":
		_enter(next, true)


## Asks for an event state (celebration, reward, evolution, wardrobe).
## Returns false when the current state outranks it.
func request(state_name: String) -> bool:
	if not state_name in EVENT_STATES or not _groups.has(state_name):
		return false
	if int(PRIORITY[state_name]) <= int(PRIORITY[state]):
		return false
	paused = state_name == WARDROBE
	_enter(state_name, false)
	return true


## Closes a wardrobe preview and lets the cycle continue.
func close_wardrobe() -> void:
	if state == WARDROBE:
		paused = false
		_enter(IDLE, false)


func _update_drivers(delta: float) -> void:
	match state:
		WORKOUT:
			energy -= float(_rates["energy_drain_workout"]) * delta
			satiety -= float(_rates["satiety_drain_workout"]) * delta
		RECOVERY:
			energy += float(_rates["energy_restore_recovery"]) * delta
			satiety -= float(_rates["satiety_drain_default"]) * delta
		SLEEPING, SLEEP_ENTER:
			energy += float(_rates["energy_restore_sleeping"]) * delta
			satiety -= float(_rates["satiety_drain_sleeping"]) * delta
		EATING:
			satiety += float(_rates["satiety_restore_eating"]) * delta
		_:
			energy -= float(_rates["energy_drain_default"]) * delta
			satiety -= float(_rates["satiety_drain_default"]) * delta
	energy = clampf(energy, 0.0, 100.0)
	satiety = clampf(satiety, 0.0, 100.0)


## The state to move to now, or "" to stay.
func _next_state() -> String:
	var elapsed := time_in_state
	match state:
		WORKOUT:
			if elapsed >= float(_durations["workout_session"]) or energy <= float(_thresholds["tired"]):
				return RECOVERY
		RECOVERY:
			if elapsed >= float(_durations["recovery"]):
				return _decide()
		HUNGER_CUE:
			if elapsed >= float(_durations["hunger_cue"]):
				return EATING
		EATING:
			if satiety >= float(_thresholds["full"]) or elapsed >= float(_durations["eating_max"]):
				return SLEEP_ENTER if energy <= float(_thresholds["tired"]) else WORKOUT
		SLEEP_ENTER:
			if elapsed >= float(_durations["sleep_enter"]):
				return SLEEPING
		SLEEPING:
			if energy >= float(_thresholds["rested"]) or elapsed >= float(_durations["sleeping_max"]):
				return WAKE
		WAKE:
			if elapsed >= float(_durations["wake"]):
				return HUNGER_CUE if satiety <= float(_thresholds["hungry"]) else WORKOUT
		IDLE:
			if elapsed >= float(_durations["idle_gap"]):
				return _decide()
		CELEBRATION, REWARD, EVOLUTION, PRE_EVOLUTION:
			if elapsed >= float(_durations[state]):
				return TRANSITIONS[state][0]
	return ""


## What to do when the cycle is free to choose.
func _decide() -> String:
	if satiety <= float(_thresholds["hungry"]):
		return HUNGER_CUE
	if energy <= float(_thresholds["sleepy"]):
		return SLEEP_ENTER
	return WORKOUT


func _enter(next: String, natural: bool) -> void:
	if natural and not next in TRANSITIONS.get(state, []):
		push_error("BehaviourLoop: %s -> %s is not an allowed transition" % [state, next])
		return
	var previous := state
	if natural:
		action_completed.emit(previous)
	state = next
	time_in_state = 0.0
	_history.append(next)
	if _history.size() > 200:
		_history = _history.slice(_history.size() - 200)
	state_changed.emit(previous, next)


## Checks behaviour.json: every state maps to a known animation group, and
## every rate, threshold and duration is present and sane.
static func validate_balance(balance: Dictionary, group_names: Array = []) -> Array[String]:
	var errors: Array[String] = []
	for section in ["drivers", "rates", "thresholds", "durations", "states"]:
		if typeof(balance.get(section)) != TYPE_DICTIONARY:
			errors.append("behaviour: '%s' must be an object" % section)
	if not errors.is_empty():
		return errors
	for driver in ["energy", "satiety"]:
		var d: Variant = balance["drivers"].get(driver)
		if typeof(d) != TYPE_DICTIONARY or not _in_range(d.get("start"), 0.0, 100.0):
			errors.append("behaviour: drivers.%s.start must be a number 0-100" % driver)
	for key in ["energy_drain_workout", "energy_drain_default", "energy_restore_recovery",
			"energy_restore_sleeping", "satiety_drain_default", "satiety_drain_workout",
			"satiety_drain_sleeping", "satiety_restore_eating"]:
		if not _positive(balance["rates"].get(key)):
			errors.append("behaviour: rates.%s must be a positive number" % key)
	for key in ["hungry", "full", "tired", "sleepy", "rested"]:
		if not _in_range(balance["thresholds"].get(key), 0.0, 100.0):
			errors.append("behaviour: thresholds.%s must be a number 0-100" % key)
	for pair in [["hungry", "full"], ["tired", "sleepy"], ["sleepy", "rested"]]:
		var low: Variant = balance["thresholds"].get(pair[0])
		var high: Variant = balance["thresholds"].get(pair[1])
		if _in_range(low, 0.0, 100.0) and _in_range(high, 0.0, 100.0) and float(low) >= float(high):
			errors.append("behaviour: thresholds.%s must be below thresholds.%s" % [pair[0], pair[1]])
	for key in ["workout_session", "recovery", "hunger_cue", "eating_max", "sleep_enter",
			"sleeping_max", "wake", "celebration", "reward", "pre_evolution", "evolution", "idle_gap"]:
		if not _positive(balance["durations"].get(key)):
			errors.append("behaviour: durations.%s must be a positive number" % key)
	for state_name in ALL_STATES:
		var group: Variant = balance["states"].get(state_name)
		if typeof(group) != TYPE_STRING or group == "":
			errors.append("behaviour: states.%s must name an animation group" % state_name)
		elif not group_names.is_empty() and not group in group_names:
			errors.append("behaviour: states.%s names unknown animation group '%s'" % [state_name, group])
	return errors


static func _positive(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) > 0.0


static func _in_range(v: Variant, low: float, high: float) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) >= low and float(v) <= high
