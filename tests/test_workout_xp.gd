extends "res://tests/lib/test_case.gd"
## XP earned lift by lift: the animator reporting each lap of a looping
## group, the driver paying for the ones that are dumbbell lifts, and the
## bar that walks up to what was earned.

const ContentData := preload("res://scripts/systems/content_data.gd")
const CharacterAnimator := preload("res://scripts/components/character_animator.gd")
const BehaviourDriver := preload("res://scripts/components/behaviour_driver.gd")
const BehaviourLoop := preload("res://scripts/systems/behaviour_loop.gd")
const Progression := preload("res://scripts/systems/progression.gd")
const Hud := preload("res://scripts/components/hud.gd")

var _content := ContentData.new()
var _animations: Dictionary = {}
var _balance: Dictionary = {}
var _progression_balance: Dictionary = {}
var _forms: Array = []


func _init() -> void:
	_content.load_from("res://data")
	_animations = _read("res://data/animations/animation_groups.json")
	_balance = _read("res://data/balance/behaviour.json")
	_progression_balance = _read("res://data/balance/progression.json")
	_forms = _content.docs.get("forms", {}).get("forms", [])


func _read(path: String) -> Dictionary:
	var v: Variant = _content.read_json(path)
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _animator() -> Node2D:
	var a: Node2D = CharacterAnimator.new()
	a.setup(_content, _animations, 1.0)
	a.set_form(1)
	return a


## Seconds one lap of a group takes at speed 1.
func _lap_seconds(group_name: String) -> float:
	var g: Dictionary = _animations["groups"][group_name]
	return g["slots"].size() / float(g["fps"])


func test_a_looping_group_reports_each_lap() -> void:
	var a := _animator()
	var laps := [0]
	a.loop_completed.connect(func(_g: String) -> void: laps[0] += 1)
	a.play("workout")
	var lap := _lap_seconds("workout")
	a.tick(lap * 0.5)
	check_eq(laps[0], 0, "nothing reported halfway through a lift")
	a.tick(lap * 0.5 + 0.001)
	check_eq(laps[0], 1, "one lift, one report")
	for step in 12:
		a.tick(lap / 4.0)
	check_eq(laps[0], 4, "and one for every lift after it")
	a.free()


func test_a_one_shot_group_reports_no_lap() -> void:
	var a := _animator()
	var laps := [0]
	a.follow_next = false
	a.loop_completed.connect(func(_g: String) -> void: laps[0] += 1)
	a.play("celebration")
	a.tick(_lap_seconds("celebration") * 3.0)
	check_eq(laps[0], 0, "a celebration plays once and holds; it never comes round")
	a.free()


func _driver(p: RefCounted) -> Node:
	var driver: Node = BehaviourDriver.new()
	driver.progression = p
	driver.setup(_animator(), _balance)
	return driver


## Only the workout pays: the idle group loops all day too.
func test_lifts_pay_only_during_a_workout() -> void:
	var p := Progression.new()
	p.configure(_progression_balance, _forms)
	var driver := _driver(p)
	var paid := [0]
	driver.rep_paid.connect(func(xp: int) -> void: paid[0] += xp)

	check_eq(driver.loop.state, BehaviourLoop.IDLE, "he starts idle")
	for step in 20:
		driver.animator.tick(_lap_seconds("idle"))
	check_eq(paid[0], 0, "idling pays nothing")

	while driver.loop.state != BehaviourLoop.WORKOUT:
		driver.loop.tick(0.1)
	var lift: float = _lap_seconds("workout")
	for step in 5:
		driver.animator.tick(lift)
	check_eq(paid[0], 5 * int(_progression_balance["rewards"]["rep_xp"]), "five lifts, five payments")
	check_eq(p.xp, float(paid[0]), "and the XP is his")
	driver.animator.free()
	driver.free()


func test_the_bar_walks_up_to_new_xp() -> void:
	var shown := Hud.advance_fill(0.0, 0.5, 0.1, Hud.FILL_SECONDS)
	check(shown > 0.0 and shown < 0.5, "it sets off towards the new total")
	# A whole bar takes FILL_SECONDS, so half of it takes half that.
	var steps := 0
	while shown < 0.5 and steps < 1000:
		shown = Hud.advance_fill(shown, 0.5, 1.0 / 60.0, Hud.FILL_SECONDS)
		steps += 1
	check_eq(shown, 0.5, "and arrives")
	check(absf(steps / 60.0 - Hud.FILL_SECONDS * 0.5) < 0.1, "taking about half a bar's time")
	check_eq(Hud.advance_fill(0.5, 0.5, 0.1, Hud.FILL_SECONDS), 0.5, "then stays put")


func test_the_bar_finishes_and_starts_again_on_a_level_up() -> void:
	# A level-up leaves the target below what is on screen.
	var shown := 0.9
	var went_backwards := false
	var wrapped := false
	for step in 200:
		var next := Hud.advance_fill(shown, 0.1, 1.0 / 60.0, Hud.FILL_SECONDS)
		if next < shown and not wrapped:
			wrapped = next == 0.0
			went_backwards = not wrapped
		shown = next
		if wrapped and shown >= 0.1:
			break
	check(not went_backwards, "the bar never slides back")
	check(wrapped, "it fills to the end and comes round at nothing")
	check_eq(shown, 0.1, "then walks up to the new level's share")
