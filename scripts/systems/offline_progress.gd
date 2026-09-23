extends RefCounted
## Works out what Caramelo did while the game was closed, by running the
## real behaviour loop over the time away. Pure: no nodes, no files.
##
## Rules (master plan Phase 10): time away is capped; very short absences
## count for nothing; a clock that went backwards grants nothing. The
## simulation pays exactly as the live game does: every lift of the
## dumbbells earns its XP, and a finished session its bones.

const BehaviourLoop := preload("res://scripts/systems/behaviour_loop.gd")


## How long one lift of the dumbbells takes at speed 1, from the group the
## workout state plays and the rate it runs at. 0 when the data does not
## say. Pure.
static func seconds_per_lift(behaviour_balance: Dictionary, animations: Dictionary) -> float:
	var group_name: String = str(behaviour_balance.get("states", {}).get(BehaviourLoop.WORKOUT, ""))
	var group: Variant = animations.get("groups", {}).get(group_name)
	if typeof(group) != TYPE_DICTIONARY:
		return 0.0
	var slots: Variant = group.get("slots")
	var fps: float = float(group.get("fps", 0.0))
	if typeof(slots) != TYPE_ARRAY or slots.is_empty() or fps <= 0.0:
		return 0.0
	return slots.size() / fps


## seconds_away: now minus the save's timestamp (may be negative).
## lift_seconds: how long one dumbbell lift takes (see seconds_per_lift);
## 0 pays for finished sessions only.
## Returns a summary; the progression is updated in place.
static func simulate(seconds_away: float, config: Dictionary, behaviour_balance: Dictionary,
		progression: RefCounted, economy: RefCounted, needs: Dictionary,
		lift_seconds: float = 0.0) -> Dictionary:
	var cap := float(config.get("cap_hours", 8.0)) * 3600.0
	var step := maxf(float(config.get("step_seconds", 1.0)), 0.1)
	var summary := {
		"seconds_away": seconds_away, "counted_seconds": 0.0, "capped": false, "clock_rollback": false,
		"workouts": 0, "xp_gained": 0.0, "bones_gained": 0, "levels_gained": 0,
		"from_level": progression.level, "to_level": progression.level,
		"from_form": progression.form, "to_form": progression.form,
		"energy": float(needs.get("energy", 100.0)), "satiety": float(needs.get("satiety", 100.0)),
	}
	if seconds_away < 0.0:
		summary["clock_rollback"] = true
		return summary
	var counted := minf(seconds_away, cap)
	summary["capped"] = seconds_away > cap
	if counted < float(config.get("min_seconds", 60.0)):
		return summary

	var loop := BehaviourLoop.new()
	if not loop.configure(behaviour_balance).is_empty():
		return summary
	loop.energy = clampf(summary["energy"], 0.0, 100.0)
	loop.satiety = clampf(summary["satiety"], 0.0, 100.0)
	var modifiers: Dictionary = economy.modifiers()
	loop.apply_modifiers(modifiers)
	var bones_before: int = progression.bones
	loop.action_completed.connect(func(state_name: String) -> void:
		if state_name == BehaviourLoop.WORKOUT:
			var result: Dictionary = progression.complete_workout(modifiers["xp_multiplier"])
			summary["workouts"] += 1
			summary["xp_gained"] += result["xp_awarded"])

	# A reduced offline rate plays less of the time away through the loop.
	var rate := clampf(float(config.get("offline_rate", 1.0)), 0.0, 1.0)
	var steps := int(counted * rate / step)
	var lifting := 0.0
	for i in steps:
		loop.tick(step)
		if loop.state == BehaviourLoop.WORKOUT:
			lifting += step
	# The lifts he got through, paid the same way they are paid live. They
	# are settled in one go here: what matters afterwards is the level he
	# comes back to, not the order the XP arrived in.
	if lift_seconds > 0.0:
		for lift in int(lifting / lift_seconds):
			summary["xp_gained"] += float(progression.complete_rep(modifiers["xp_multiplier"])["xp_awarded"])
	summary["counted_seconds"] = counted
	summary["offline_rate"] = rate
	summary["bones_gained"] = progression.bones - bones_before
	summary["to_level"] = progression.level
	summary["levels_gained"] = progression.level - summary["from_level"]
	summary["to_form"] = progression.form
	summary["energy"] = loop.energy
	summary["satiety"] = loop.satiety
	return summary


## "3 h 20 min", "12 min", "45 s".
static func describe_duration(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d h %d min" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d min" % (s / 60)
	return "%d s" % s
