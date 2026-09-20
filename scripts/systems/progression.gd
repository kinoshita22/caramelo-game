extends RefCounted
## Levels, XP, bones and which form Caramelo wears. Pure simulation: no
## nodes, no textures, so tests run it directly.
##
## Rules (master plan Phase 6): levels never go down, XP left over after a
## level-up carries into the next level, and level 100 is the end of the
## curve (bones keep coming, XP stops counting).

signal leveled_up(new_level: int)
signal form_changed(from_form: int, to_form: int)
signal bones_changed(total: int)
signal xp_changed(xp_into_level: float, needed: float)

var level := 1
## XP earned towards the next level.
var xp := 0.0
var bones := 0
var form := 1
var workouts_completed := 0

var _curve := {}
var _rewards := {}
var _forms: Array = []


## balance is data/balance/progression.json; forms is the "forms" array of
## character_forms.json. Returns validation errors; nothing is applied on error.
func configure(balance: Dictionary, forms: Array) -> Array[String]:
	var errors := validate_balance(balance, forms)
	if not errors.is_empty():
		return errors
	_curve = balance["xp_curve"]
	_rewards = balance["rewards"]
	_forms = forms
	level = 1
	xp = 0.0
	bones = 0
	workouts_completed = 0
	form = form_for_level(level)
	return errors


func max_level() -> int:
	return int(_curve.get("max_level", 100))


func at_max_level() -> bool:
	return level >= max_level()


## XP needed to leave `for_level`. 0 at the maximum level.
func xp_to_next(for_level: int) -> float:
	if for_level >= max_level():
		return 0.0
	return roundf(float(_curve["base"]) * pow(float(for_level), float(_curve["exponent"])))


## Total XP needed to get from level 1 to `target_level`.
func total_xp_for_level(target_level: int) -> float:
	var total := 0.0
	for l in range(1, mini(target_level, max_level())):
		total += xp_to_next(l)
	return total


## The form covering a level, from character_forms.json. Falls back to the
## highest form for levels past the last range.
func form_for_level(for_level: int) -> int:
	var best := 1
	for f in _forms:
		if for_level >= int(f["level_min"]) and for_level <= int(f["level_max"]):
			return int(f["form"])
		if int(f["level_min"]) <= for_level:
			best = maxi(best, int(f["form"]))
	return best


## Adds XP and reports what happened. Never lowers the level.
func add_xp(amount: float) -> Dictionary:
	var result := {
		"xp_awarded": 0.0, "levels_gained": 0, "from_level": level, "to_level": level,
		"form_changed": false, "from_form": form, "to_form": form, "at_max_level": at_max_level(),
	}
	if amount <= 0.0 or at_max_level():
		return result
	result["xp_awarded"] = amount
	xp += amount
	while not at_max_level() and xp >= xp_to_next(level):
		xp -= xp_to_next(level)  # overflow carries into the next level
		level += 1
		result["levels_gained"] += 1
		leveled_up.emit(level)
	if at_max_level():
		xp = 0.0
	result["to_level"] = level
	result["at_max_level"] = at_max_level()
	var new_form := form_for_level(level)
	if new_form != form:
		var previous := form
		form = new_form
		result["form_changed"] = true
		result["to_form"] = form
		form_changed.emit(previous, form)
	xp_changed.emit(xp, xp_to_next(level))
	return result


## Spends bones if there are enough. Balances never go negative.
func spend_bones(amount: int) -> bool:
	if amount < 0 or amount > bones:
		return false
	bones -= amount
	bones_changed.emit(bones)
	return true


func add_bones(amount: int) -> void:
	if amount <= 0:
		return
	bones += amount
	bones_changed.emit(bones)


## Pays out one finished workout session. Every Nth session pays a bonus,
## which is the cue for the bone-reward animation.
func complete_workout(xp_multiplier: float = 1.0) -> Dictionary:
	workouts_completed += 1
	var result := add_xp(float(_rewards["workout_xp"]) * maxf(xp_multiplier, 0.0))
	var earned := int(_rewards["workout_bones"])
	var every := int(_rewards.get("bonus_bones_every", 0))
	var bonus := every > 0 and workouts_completed % every == 0
	if bonus:
		earned += int(_rewards.get("bonus_bones", 0))
	add_bones(earned)
	result["bones_awarded"] = earned
	result["bonus"] = bonus
	return result


## Restores a saved state (used by Phase 10 loading and by tests).
func restore(saved_level: int, saved_xp: float, saved_bones: int, saved_workouts: int = 0) -> void:
	level = clampi(saved_level, 1, max_level())
	xp = maxf(saved_xp, 0.0)
	if not at_max_level():
		xp = minf(xp, xp_to_next(level))
	else:
		xp = 0.0
	bones = maxi(saved_bones, 0)
	workouts_completed = maxi(saved_workouts, 0)
	var previous := form
	form = form_for_level(level)
	if form != previous:
		form_changed.emit(previous, form)


static func validate_balance(balance: Dictionary, forms: Array) -> Array[String]:
	var errors: Array[String] = []
	var curve: Variant = balance.get("xp_curve")
	var rewards: Variant = balance.get("rewards")
	if typeof(curve) != TYPE_DICTIONARY:
		errors.append("progression: 'xp_curve' must be an object")
	else:
		if not _positive(curve.get("base")):
			errors.append("progression: xp_curve.base must be a positive number")
		if not _positive(curve.get("exponent")):
			errors.append("progression: xp_curve.exponent must be a positive number")
		if not _positive(curve.get("max_level")) or int(curve.get("max_level", 0)) < 2:
			errors.append("progression: xp_curve.max_level must be at least 2")
	if typeof(rewards) != TYPE_DICTIONARY:
		errors.append("progression: 'rewards' must be an object")
	else:
		if not _positive(rewards.get("workout_xp")):
			errors.append("progression: rewards.workout_xp must be a positive number")
		if not _positive(rewards.get("workout_bones")):
			errors.append("progression: rewards.workout_bones must be a positive number")
		for key in ["bonus_bones_every", "bonus_bones"]:
			if rewards.has(key) and not _non_negative(rewards[key]):
				errors.append("progression: rewards.%s must be zero or more" % key)
	if typeof(forms) != TYPE_ARRAY or forms.is_empty():
		errors.append("progression: character forms are missing")
	elif typeof(curve) == TYPE_DICTIONARY and _positive(curve.get("max_level")):
		var top := 0
		for f in forms:
			top = maxi(top, int(f["level_max"]))
		if top != int(curve["max_level"]):
			errors.append("progression: forms end at level %d but xp_curve.max_level is %d" % [top, int(curve["max_level"])])
	return errors


static func _positive(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) > 0.0


static func _non_negative(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) >= 0.0
