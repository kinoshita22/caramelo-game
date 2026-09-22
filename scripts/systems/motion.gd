extends RefCounted
## How Caramelo moves between poses and places: the eased hop over to an
## anchor, the dissolve from one animation group into the next, the slide
## that swallows a frame's positional pop, and the breathing that keeps him
## alive while a pose holds.
##
## Pure maths: no nodes, no textures and no clock of its own, so every curve
## is checked in tests. The tuning lives in animation_groups.json under
## "motion"; CharacterAnimator and IslandStage read it from there.

## Stage units are design pixels; seconds are game seconds.
const TRAVEL := {
	"speed": 460.0,
	"min_seconds": 0.3,
	"max_seconds": 1.1,
	"hop": 0.14,
	"hop_max": 40.0,
	"squash": 0.07,
	"shadow_shrink": 0.18,
}
const BLEND := {
	"crossfade": 0.16,
	"slow_fps": 3.0,
	"frame_crossfade": 0.14,
	"jitter_px": 18.0,
	"jitter_ease": 0.08,
}
const SECONDARY := {"bob": 2.0, "period": 3.0, "sway": 0.0, "breathe": 0.004}


## Travel tuning, defaults filled in.
static func travel(motion: Dictionary) -> Dictionary:
	return _merged(TRAVEL, motion.get("travel", {}))


## Blending tuning, defaults filled in.
static func blend(motion: Dictionary) -> Dictionary:
	return _merged(BLEND, motion.get("blend", {}))


## Secondary-motion tuning for one animation group: the "secondary.default"
## block with that group's overrides on top.
static func secondary_for(motion: Dictionary, group_name: String) -> Dictionary:
	var s: Dictionary = motion.get("secondary", {})
	var base := _merged(SECONDARY, s.get("default", {}))
	return _merged(base, s.get("groups", {}).get(group_name, {}))


## Smoothstep: leaves and arrives at rest.
static func ease_in_out(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## How long a move of `distance` takes, or 0 for a step too small to bother
## animating.
static func travel_seconds(distance: float, cfg: Dictionary) -> float:
	if distance <= 1.0:
		return 0.0
	return clampf(distance / maxf(float(cfg["speed"]), 1.0),
			float(cfg["min_seconds"]), float(cfg["max_seconds"]))


## Where his feet are at t (0-1) along a move.
static func ground_point(from: Vector2, to: Vector2, t: float) -> Vector2:
	return from.lerp(to, ease_in_out(t))


## How far off the ground he is at t; negative is up. Longer moves hop
## higher, up to hop_max.
static func hop_offset(distance: float, t: float, cfg: Dictionary) -> float:
	var height := minf(distance * float(cfg["hop"]), float(cfg["hop_max"]))
	return -height * sin(PI * clampf(t, 0.0, 1.0))


## Stretch on the way up, squash on the way down, neutral at both ends so
## the hop starts and finishes without a pop. Multiplies the character's
## scale.
static func hop_squash(t: float, cfg: Dictionary) -> Vector2:
	var k := float(cfg["squash"]) * sin(TAU * clampf(t, 0.0, 1.0))
	return Vector2(1.0 - k, 1.0 + k)


## The shadow tightens while he is in the air. Multiplies its scale.
static func shadow_scale(t: float, cfg: Dictionary) -> float:
	return 1.0 - float(cfg["shadow_shrink"]) * sin(PI * clampf(t, 0.0, 1.0))


## Alpha of the outgoing frame, from `remaining` seconds of a dissolve that
## lasts `duration`: 1 when it starts, 0 when it ends.
static func fade(remaining: float, duration: float) -> float:
	if duration <= 0.0:
		return 0.0
	return ease_in_out(clampf(remaining / duration, 0.0, 1.0))


## Share of the remaining distance to close this frame when easing towards a
## target with time constant `seconds`. Frame-rate independent: two half
## steps close as much as one whole one.
static func approach_factor(delta: float, seconds: float) -> float:
	if seconds <= 0.0 or delta <= 0.0:
		return 1.0
	return 1.0 - exp(-delta / seconds)


## Breathing and sway laid over the frames, in stage units. y is never
## positive, so he lifts off the pose and settles back rather than sinking
## through the ground.
static func breath_offset(cfg: Dictionary, time: float) -> Vector2:
	var phase := TAU * time / maxf(float(cfg["period"]), 0.05)
	return Vector2(float(cfg["sway"]) * sin(phase * 0.5),
			-float(cfg["bob"]) * 0.5 * (1.0 - cos(phase)))


## The chest widening with the same breath. Multiplies the character's scale.
static func breath_scale(cfg: Dictionary, time: float) -> Vector2:
	var k := float(cfg["breathe"]) * sin(TAU * time / maxf(float(cfg["period"]), 0.05))
	return Vector2(1.0 - k, 1.0 + k)


## Checks the "motion" block of animation_groups.json.
static func validate(motion: Dictionary, group_names: Array = []) -> Array[String]:
	var errors: Array[String] = []
	if motion.is_empty():
		return errors
	for section in ["travel", "blend", "secondary"]:
		if motion.has(section) and typeof(motion[section]) != TYPE_DICTIONARY:
			errors.append("motion: '%s' must be an object" % section)
	if not errors.is_empty():
		return errors
	var t := travel(motion)
	for key in ["speed", "min_seconds", "max_seconds"]:
		if float(t[key]) <= 0.0:
			errors.append("motion: travel.%s must be a positive number" % key)
	if float(t["min_seconds"]) > float(t["max_seconds"]):
		errors.append("motion: travel.min_seconds must not exceed travel.max_seconds")
	for key in ["hop", "hop_max", "squash", "shadow_shrink"]:
		if float(t[key]) < 0.0:
			errors.append("motion: travel.%s must not be negative" % key)
	if float(t["squash"]) > 0.5 or float(t["shadow_shrink"]) > 1.0:
		errors.append("motion: travel.squash and travel.shadow_shrink must stay subtle")
	var b := blend(motion)
	for key in ["crossfade", "slow_fps", "frame_crossfade", "jitter_px", "jitter_ease"]:
		if float(b[key]) < 0.0:
			errors.append("motion: blend.%s must not be negative" % key)
	var secondary: Dictionary = motion.get("secondary", {})
	var groups: Variant = secondary.get("groups", {})
	if typeof(groups) != TYPE_DICTIONARY:
		errors.append("motion: secondary.groups must be an object")
		return errors
	for name in groups:
		if String(name).begins_with("_"):
			continue
		if not group_names.is_empty() and not name in group_names:
			errors.append("motion: secondary.groups names unknown group '%s'" % name)
		var cfg := secondary_for(motion, name)
		if float(cfg["period"]) <= 0.0:
			errors.append("motion: secondary.groups.%s period must be a positive number" % name)
		for key in ["bob", "sway", "breathe"]:
			if float(cfg[key]) < 0.0:
				errors.append("motion: secondary.groups.%s %s must not be negative" % [name, key])
	return errors


## Base with every numeric key of `over` laid on top; comments and other
## types are ignored.
static func _merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate()
	if typeof(over) != TYPE_DICTIONARY:
		return out
	for key in over:
		var v: Variant = over[key]
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			out[key] = float(v)
	return out
