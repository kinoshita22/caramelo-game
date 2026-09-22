extends "res://tests/lib/test_case.gd"
## Animation groups data, frame resolution and playback timing.

const ContentData := preload("res://scripts/systems/content_data.gd")
const CharacterAnimator := preload("res://scripts/components/character_animator.gd")
const AssetIO := preload("res://scripts/tools/asset_io.gd")

var _content := ContentData.new()
var _doc: Dictionary = {}
var _anchors: Array = []


func _init() -> void:
	_content.load_from("res://data")
	var d: Variant = _content.read_json("res://data/animations/animation_groups.json")
	_doc = d if typeof(d) == TYPE_DICTIONARY else {}
	var layout: Variant = _content.read_json("res://data/environment/island_layout.json")
	_anchors = layout["anchors"].keys() if typeof(layout) == TYPE_DICTIONARY else []


func _animator(doc: Dictionary = _doc) -> Node2D:
	var a: Node2D = CharacterAnimator.new()
	a.setup(_content, doc, 1.0)
	a.set_form(1)
	return a


func test_animation_groups_validate() -> void:
	check_no_errors(CharacterAnimator.validate_groups(_doc, _anchors), "animation_groups.json")


func test_validation_catches_bad_groups() -> void:
	var bad := _doc.duplicate(true)
	bad["groups"]["idle"]["slots"] = [3, 34]
	bad["groups"]["workout"]["fps"] = 0
	bad["groups"]["tail_wag"]["next"] = "nope"
	bad["groups"]["eating"]["anchor"] = "kitchen"
	var errors := CharacterAnimator.validate_groups(bad, _anchors)
	check_error(errors, "has invalid slot 34")
	check_error(errors, "'workout' fps must be a positive number")
	check_error(errors, "next names unknown group 'nope'")
	check_error(errors, "anchor 'kitchen' is not an island_layout anchor")


func test_every_frame_of_every_form_loads() -> void:
	var missing: Array = []
	for f in _content.form_numbers():
		for slot in range(1, 34):
			var r := CharacterAnimator.resolve_frame(_content, _doc["frame_overrides"], f, slot)
			if r["texture"] == null:
				missing.append(CharacterAnimator.frame_id(f, slot))
		_content.release_textures(range(1, 34).map(func(s: int) -> String: return CharacterAnimator.frame_id(f, s)))
	check_eq(missing, [], "frames without a texture")


func test_every_frame_has_a_stable_anchor() -> void:
	for f in _content.form_numbers():
		for slot in range(1, 34):
			check(_content.frame_geometry(f, slot).has("stable_anchor"), "f%d s%d stable_anchor" % [f, slot])


func test_overrides_apply_lift_and_per_form_scale() -> void:
	var ov: Array = _doc["frame_overrides"]
	var geo := _content.frame_geometry(1, 29)
	var jump := CharacterAnimator.resolve_frame(_content, ov, 1, 29)
	check(jump["anchor"].y > float(geo["stable_anchor"]["y"]), "jump frame lifted")
	check_eq(CharacterAnimator.resolve_frame(_content, ov, 6, 18)["scale"], 0.832, "form 6 hunger rumble scaled")
	check_eq(CharacterAnimator.resolve_frame(_content, ov, 1, 18)["scale"], 1.0, "form 1 hunger rumble unscaled")


func test_advance_loops_and_finishes() -> void:
	check_eq(CharacterAnimator.advance(0, 3, true), {"index": 1, "finished": false}, "step")
	check_eq(CharacterAnimator.advance(2, 3, true), {"index": 0, "finished": false}, "loop wraps")
	check_eq(CharacterAnimator.advance(2, 3, false), {"index": 2, "finished": true}, "one-shot finishes on last frame")


func test_one_shot_group_hands_over_to_next() -> void:
	var a := _animator()
	var events: Array = []
	a.group_started.connect(func(g: String, anchor: String) -> void: events.append("start %s@%s" % [g, anchor]))
	a.group_finished.connect(func(g: String) -> void: events.append("end " + g))
	a.play("tail_wag")
	check_eq(a.current_slot(), 6, "first tail_wag frame")
	var wag: Dictionary = _doc["groups"]["tail_wag"]
	a.tick(wag["slots"].size() / float(wag["fps"]) + 0.01)  # every frame of the wag
	check_eq(a.group, "idle", "tail_wag hands over to idle")
	check_eq(events, ["start tail_wag@idle", "end tail_wag", "start idle@idle"], "signals")
	a.free()


func test_one_shot_without_next_holds_last_frame() -> void:
	var doc := _doc.duplicate(true)
	doc["groups"]["reward"].erase("next")
	var a := _animator(doc)
	var ends := [0]
	a.group_finished.connect(func(_g: String) -> void: ends[0] += 1)
	a.play("reward")
	a.tick(10.0)
	a.tick(10.0)
	check_eq(a.current_slot(), 31, "holds last reward frame")
	check_eq(ends[0], 1, "finished emitted once")
	a.free()


func test_loop_and_speed_scale() -> void:
	var a := _animator()
	a.play("workout")
	a.speed_scale = 2.0
	var g: Dictionary = _doc["groups"]["workout"]
	var frame_time: float = 1.0 / (float(g["fps"]) * 2.0)
	a.tick(3 * frame_time + frame_time * 0.01)
	check_eq(a.frame_index, 3, "speed scale doubles frame rate")
	a.tick((g["slots"].size() - 3) * frame_time)
	check_eq(a.frame_index, 0, "workout loops")
	check_eq(a.group, "workout", "still working out")
	a.free()


func test_set_form_releases_previous_textures() -> void:
	var a := _animator()
	check(_content._textures.has("character.f01.s03"), "form 1 cached")
	a.set_form(2)
	check(not _content._textures.has("character.f01.s03"), "form 1 released")
	check(_content._textures.has("character.f02.s03"), "form 2 cached")
	a.free()


func test_silhouette_registration_recovers_shift() -> void:
	var base := Image.create_empty(200, 200, false, Image.FORMAT_RGBA8)
	base.fill(Color(0, 0, 0, 0))
	base.fill_rect(Rect2i(60, 40, 60, 140), Color.WHITE)  # body
	base.fill_rect(Rect2i(120, 60, 50, 20), Color.WHITE)  # arm
	var moved := Image.create_empty(200, 200, false, Image.FORMAT_RGBA8)
	moved.fill(Color(0, 0, 0, 0))
	moved.blit_rect(base, Rect2i(0, 0, 200, 200), Vector2i(16, 0))
	var a := AssetIO.silhouette_runs(base, Vector2(100, 180), 4, 32)
	var b := AssetIO.silhouette_runs(moved, Vector2(100, 180), 4, 32)
	var r := AssetIO.best_shift(a, b, 10)
	check_eq(r["shift"], -4, "16 px right at 1/4 scale needs -4")
	check(r["iou"] > 0.99, "perfect overlap after shifting: %s" % r["iou"])
