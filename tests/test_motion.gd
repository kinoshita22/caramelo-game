extends "res://tests/lib/test_case.gd"
## The movement-feel curves, their tuning in animation_groups.json, and the
## easing the animator lays over the frames.

const ContentData := preload("res://scripts/systems/content_data.gd")
const Motion := preload("res://scripts/systems/motion.gd")
const CharacterAnimator := preload("res://scripts/components/character_animator.gd")
const FramePacing := preload("res://scripts/systems/frame_pacing.gd")

var _content := ContentData.new()
var _doc: Dictionary = {}
var _motion: Dictionary = {}


func _init() -> void:
	_content.load_from("res://data")
	var d: Variant = _content.read_json("res://data/animations/animation_groups.json")
	_doc = d if typeof(d) == TYPE_DICTIONARY else {}
	_motion = _doc.get("motion", {})


func _animator() -> Node2D:
	var a: Node2D = CharacterAnimator.new()
	a.setup(_content, _doc, 1.0)
	a.set_form(1)
	return a


func test_motion_tuning_validates() -> void:
	check(not _motion.is_empty(), "animation_groups.json has a motion block")
	check_no_errors(Motion.validate(_motion, _doc["groups"].keys()), "motion tuning")


func test_validation_catches_bad_tuning() -> void:
	var bad := _motion.duplicate(true)
	bad["travel"]["speed"] = 0
	bad["travel"]["squash"] = 0.9
	bad["blend"]["crossfade"] = -1
	bad["secondary"]["groups"]["zoomies"] = {"bob": 2.0}
	bad["secondary"]["groups"]["idle"]["period"] = 0
	var errors := Motion.validate(bad, _doc["groups"].keys())
	check_error(errors, "travel.speed must be a positive number")
	check_error(errors, "must stay subtle")
	check_error(errors, "blend.crossfade must not be negative")
	check_error(errors, "unknown group 'zoomies'")
	check_error(errors, "idle period must be a positive number")


func test_tuning_defaults_fill_in_and_merge() -> void:
	check_eq(Motion.travel({})["speed"], Motion.TRAVEL["speed"], "travel defaults")
	check_eq(Motion.blend({"blend": {"crossfade": 0.5}})["crossfade"], 0.5, "override wins")
	check_eq(Motion.blend({"blend": {"crossfade": 0.5}})["jitter_px"], Motion.BLEND["jitter_px"],
			"the rest keeps its default")
	var idle := Motion.secondary_for(_motion, "idle")
	var unknown := Motion.secondary_for(_motion, "zoomies")
	check(idle["bob"] > 0.0, "idle breathes")
	check_eq(unknown["bob"], _motion["secondary"]["default"]["bob"], "an unlisted group takes the default")


func test_easing_starts_and_ends_at_rest() -> void:
	check_eq(Motion.ease_in_out(0.0), 0.0, "starts at the start")
	check_eq(Motion.ease_in_out(1.0), 1.0, "ends at the end")
	check_eq(Motion.ease_in_out(0.5), 0.5, "symmetric")
	check_eq(Motion.ease_in_out(-3.0), 0.0, "clamped below")
	check_eq(Motion.ease_in_out(3.0), 1.0, "clamped above")
	# Slow at both ends, fastest in the middle: that is the ease.
	var first := Motion.ease_in_out(0.1) - Motion.ease_in_out(0.0)
	var middle := Motion.ease_in_out(0.55) - Motion.ease_in_out(0.45)
	var last := Motion.ease_in_out(1.0) - Motion.ease_in_out(0.9)
	check(middle > first and middle > last, "moves fastest halfway through")
	check(absf(first - last) < 0.0001, "leaves and arrives just as gently")


func test_a_longer_move_takes_longer_but_not_forever() -> void:
	var cfg := Motion.travel(_motion)
	check_eq(Motion.travel_seconds(0.5, cfg), 0.0, "a step too small to animate is instant")
	var short_hop := Motion.travel_seconds(100.0, cfg)
	var long_hop := Motion.travel_seconds(320.0, cfg)
	check(long_hop > short_hop, "the far anchor takes longer")
	check(short_hop >= float(cfg["min_seconds"]), "never a flicker")
	check(Motion.travel_seconds(100000.0, cfg) == float(cfg["max_seconds"]), "never a crawl")


func test_he_leaves_one_anchor_and_lands_on_the_next() -> void:
	var from := Vector2(-40, 25)
	var to := Vector2(280, 30)
	check_eq(Motion.ground_point(from, to, 0.0), from, "starts where he was")
	check_eq(Motion.ground_point(from, to, 1.0), to, "ends on the anchor")
	var previous := from.x
	for step in range(1, 11):
		var x := Motion.ground_point(from, to, step / 10.0).x
		check(x > previous, "keeps going forward at %d/10" % step)
		previous = x


func test_he_hops_rather_than_slides() -> void:
	var cfg := Motion.travel(_motion)
	var distance := 320.0
	check(is_zero_approx(Motion.hop_offset(distance, 0.0, cfg)), "on the ground at the start")
	check(is_zero_approx(Motion.hop_offset(distance, 1.0, cfg)), "back on the ground at the end")
	var peak := Motion.hop_offset(distance, 0.5, cfg)
	check(peak < 0.0, "up in the air halfway")
	check(peak >= -float(cfg["hop_max"]), "a hop, not a leap")
	check(Motion.hop_offset(40.0, 0.5, cfg) > peak, "a short move hops lower than a long one")


func test_the_hop_stretches_and_squashes_without_a_pop() -> void:
	var cfg := Motion.travel(_motion)
	check_eq(Motion.hop_squash(0.0, cfg), Vector2.ONE, "no squash at the start")
	check_eq(Motion.hop_squash(1.0, cfg), Vector2.ONE, "none at the end either")
	var rising := Motion.hop_squash(0.25, cfg)
	var falling := Motion.hop_squash(0.75, cfg)
	check(rising.y > 1.0 and rising.x < 1.0, "stretched on the way up")
	check(falling.y < 1.0 and falling.x > 1.0, "squashed on the way down")


func test_the_shadow_tightens_while_he_is_airborne() -> void:
	var cfg := Motion.travel(_motion)
	check_eq(Motion.shadow_scale(0.0, cfg), 1.0, "full size on the ground")
	check_eq(Motion.shadow_scale(1.0, cfg), 1.0, "full size again on landing")
	var mid := Motion.shadow_scale(0.5, cfg)
	check(mid < 1.0 and mid > 0.0, "smaller, but still there, at the top of the hop")


func test_a_dissolve_runs_out() -> void:
	check_eq(Motion.fade(0.16, 0.16), 1.0, "the outgoing frame is whole when it starts")
	check_eq(Motion.fade(0.0, 0.16), 0.0, "and gone when it ends")
	check_eq(Motion.fade(0.5, 0.0), 0.0, "no dissolve means nothing left over")
	check(Motion.fade(0.08, 0.16) < 1.0, "fading in between")


func test_easing_towards_a_target_does_not_depend_on_the_frame_rate() -> void:
	var one_step := Motion.approach_factor(0.1, 0.08)
	var left := (1.0 - Motion.approach_factor(0.05, 0.08)) * (1.0 - Motion.approach_factor(0.05, 0.08))
	check(absf((1.0 - one_step) - left) < 0.0001, "two half steps close as much as one whole one")
	check(one_step > 0.0 and one_step < 1.0, "closes part of the gap")
	check_eq(Motion.approach_factor(0.1, 0.0), 1.0, "no easing time means arrive now")


func test_breathing_lifts_him_and_sets_him_down() -> void:
	var cfg := Motion.secondary_for(_motion, "sleeping")
	var period: float = float(cfg["period"])
	check_eq(Motion.breath_offset(cfg, 0.0).y, 0.0, "starts on the pose")
	check(absf(Motion.breath_offset(cfg, period).y) < 0.0001, "and is back a period later")
	check(Motion.breath_offset(cfg, period * 0.5).y < 0.0, "lifted in between")
	var lowest := 0.0
	for step in 40:
		lowest = maxf(lowest, Motion.breath_offset(cfg, step * period / 40.0).y)
	check_eq(lowest, 0.0, "never sinks below the pose")
	var scale := Motion.breath_scale(cfg, period * 0.25)
	check(scale.y > 1.0 and scale.x < 1.0, "the chest widens with the breath")
	check(absf(scale.y - 1.0) < 0.05, "and stays subtle")


func test_a_small_frame_shift_slides_and_a_big_one_snaps() -> void:
	var still := {"anchor": Vector2(100, 400), "scale": 1.0, "visible": Rect2(60, 100, 80, 300)}
	var nudged := {"anchor": Vector2(100, 400), "scale": 1.0, "visible": Rect2(66, 100, 80, 304)}
	var jumped := {"anchor": Vector2(100, 400), "scale": 1.0, "visible": Rect2(60, 20, 80, 220)}
	var slide := CharacterAnimator.body_shift(still, nudged, 1.0, 18.0)
	check(slide != Vector2.ZERO, "a few pixels of drift are held back")
	check(slide.x < 0.0 and slide.y < 0.0, "held back the way the body moved")
	check_eq(CharacterAnimator.body_shift(still, jumped, 1.0, 18.0), Vector2.ZERO,
			"a real move lands on its own")
	check_eq(CharacterAnimator.body_shift({}, nudged, 1.0, 18.0), Vector2.ZERO, "nothing to follow on from")
	check_eq(CharacterAnimator.body_shift(still, nudged, 0.0, 18.0), Vector2.ZERO, "scaled to nothing")


func test_the_animator_dissolves_between_groups_and_settles() -> void:
	var a := _animator()
	a.play("idle")
	a.tick(0.1)
	check(not a.is_settling(), "nothing to settle before the first change")
	a.play("workout")
	check(a.is_settling(), "the outgoing pose is still there")
	for step in 30:
		a.tick(0.02)
	check(not a.is_settling(), "and it is gone half a second later")
	a.play("workout", true)
	check(not a.is_settling(), "restarting the same group is not a change to dissolve")
	a.free()


## The frames of one group are the same pose moving, so dissolving between
## them showed both drawings at once, most of all through the 1 fps sleep.
func test_frames_inside_a_group_never_leave_a_ghost() -> void:
	var a := _animator()
	a.play("sleeping")
	# Past the dissolve into sleeping, and on through several frame changes.
	for step in 8:
		a.tick(0.05)
	var ghosted := false
	for step in 100:
		a.tick(0.05)
		ghosted = ghosted or a.is_settling()
	check(not ghosted, "five seconds of sleep with no frame laid over another")
	a.free()


## Slots 24 and 25 are an exhale and an inhale, so the group's own frame
## rate is the breathing rate and the lift has to share it.
func test_the_sleeping_breath_is_slow_and_matches_the_drawings() -> void:
	var sleeping: Dictionary = _doc["groups"]["sleeping"]
	var drawn_cycle: float = sleeping["slots"].size() / float(sleeping["fps"])
	check(drawn_cycle >= 3.0, "a sleeping breath takes %.1f s, not a pant" % drawn_cycle)
	check_eq(float(Motion.secondary_for(_motion, "sleeping")["period"]), drawn_cycle,
			"the lift breathes with the drawings")


func test_the_breath_starts_with_the_pose() -> void:
	var a := _animator()
	a.play("idle")
	a.tick(1.7)
	a.play("sleeping")
	# Straight after the change he is where the last breath left him, and
	# it eases away rather than dropping.
	var period: float = float(Motion.secondary_for(_motion, "sleeping")["period"])
	for step in 20:
		a.tick(0.02)
	check(absf(a.position.y) < 0.5, "settled on the pose at the start of the breath")
	a.tick(period * 0.5 - 0.4)
	var lifted := a.position.y
	a.tick(period * 0.5)
	check(lifted < -1.0, "lifted halfway through, where the inhale is drawn")
	check(absf(a.position.y) < 0.2, "and back down a full breath later")
	a.free()


func test_the_animator_breathes_while_a_pose_holds() -> void:
	var a := _animator()
	a.play("sleeping")
	var seen := {}
	var furthest := 0.0
	for step in 60:
		a.tick(0.05)
		seen[snappedf(a.position.y, 0.01)] = true
		furthest = maxf(furthest, a.position.length())
	check(seen.size() > 10, "he keeps moving through a 1 fps sleep")
	var budget: float = float(Motion.secondary_for(_motion, "sleeping")["bob"]) \
			+ float(Motion.blend(_motion)["jitter_px"])
	check(furthest <= budget, "and stays put: %.1f px of the %.1f he may use" % [furthest, budget])
	a.free()


func test_moving_earns_smooth_frames() -> void:
	var v: Variant = ContentData.new().read_json("res://data/settings/performance.json")
	var config: Dictionary = v if typeof(v) == TYPE_DICTIONARY else {}
	check_no_errors(FramePacing.validate(config), "performance.json")
	check_eq(FramePacing.target_fps({"moving": true}, config), 60, "a hop gets real frames")
	check_eq(FramePacing.target_fps({}, config), 20, "standing still stays cheap")
	check_eq(FramePacing.target_fps({"moving": true, "on_battery": true}, config), 30,
			"on battery a hop is capped")
	check_eq(FramePacing.target_fps({"moving": true, "cap_30": true}, config), 30, "the player's cap wins")
	check_eq(FramePacing.target_fps({"moving": true, "minimized": true}, config), 5,
			"nothing to see when minimized")
