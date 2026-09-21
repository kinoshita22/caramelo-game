extends "res://tests/lib/test_case.gd"
## Furniture and cosmetics: ownership, equipping, the windows' rows, layer
## swapping, and cosmetic placement on every frame of every form.
##
## No cosmetic or furniture-variant art exists yet, so fixtures below stand
## in with existing catalog images. They live only in this test.

const ContentData := preload("res://scripts/systems/content_data.gd")
const Collection := preload("res://scripts/systems/collection.gd")
const Progression := preload("res://scripts/systems/progression.gd")
const CollectionModal := preload("res://scripts/components/collection_modal.gd")
const CharacterAnimator := preload("res://scripts/components/character_animator.gd")
const IslandStage := preload("res://scripts/components/island_stage.gd")

var _content := ContentData.new()
var _assets: Array = []


func _init() -> void:
	_content.load_from("res://data")
	_assets = _content.docs["catalog"]["assets"].map(func(a: Dictionary) -> String: return a["id"])


func _read(path: String) -> Dictionary:
	var v: Variant = _content.read_json(path)
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _wallet(bones: int) -> RefCounted:
	var p := Progression.new()
	p.configure(_read("res://data/balance/progression.json"), _content.docs["forms"]["forms"])
	p.add_bones(bones)
	return p


## Furniture data plus a stand-in second chair.
func _furniture_with_variant() -> RefCounted:
	var doc := _read("res://data/furniture/furniture.json")
	doc["items"].append({"id": "test_chair", "slot": "chair", "label": "Test chair",
			"asset": "environment.boteco_side_table", "cost": 100, "unlock_level": 5})
	var c := Collection.new()
	c.configure(doc, _assets)
	return c


## Cosmetics data plus a stand-in hat.
func _cosmetics_with_hat() -> RefCounted:
	var doc := _read("res://data/cosmetics/cosmetics.json")
	doc["items"].append({"id": "test_hat", "slot": "head", "label": "Test hat",
			"asset": "ui.currency_xp_star", "cost": 50, "pivot": "bottom_center", "scale": 0.3})
	var c := Collection.new()
	c.configure(doc, _assets)
	return c


func test_shipped_data_validates() -> void:
	check_no_errors(Collection.validate(_read("res://data/furniture/furniture.json"), _assets), "furniture.json")
	check_no_errors(Collection.validate(_read("res://data/cosmetics/cosmetics.json"), _assets), "cosmetics.json")


func test_validation_catches_bad_items() -> void:
	var doc := _read("res://data/furniture/furniture.json")
	doc["items"].append({"id": "yellow_plastic_chair", "slot": "sofa", "asset": "environment.nope", "cost": -1})
	var errors := Collection.validate(doc, _assets)
	check_error(errors, "duplicate item id 'yellow_plastic_chair'")
	check_error(errors, "names unknown slot 'sofa'")
	check_error(errors, "cost must be zero or more")
	check_error(errors, "uses unknown asset 'environment.nope'")
	var no_default := {"slots": {"chair": {}}, "items": [{"id": "a", "slot": "chair", "cost": 5}]}
	check_error(Collection.validate(no_default), "needs a free item")


func test_free_items_start_owned_and_equipped() -> void:
	var c := _furniture_with_variant()
	check_eq(c.equipped["chair"], "yellow_plastic_chair", "plastic chair in place")
	check_eq(c.equipped["table"], "boteco_side_table", "boteco table in place")
	check_eq(c.equipped["kitchen_island"], "", "no kitchen island yet")
	check(not "test_chair" in c.owned, "paid variants start unowned")


func test_buying_locks_funds_and_equips() -> void:
	var c := _furniture_with_variant()
	check_eq(c.buy("test_chair", _wallet(1000), 1)["reason"], "locked", "locked below its level")
	check_eq(c.buy("test_chair", _wallet(10), 5)["reason"], "not_enough_bones", "needs the bones")
	var wallet := _wallet(1000)
	check(c.buy("test_chair", wallet, 5)["ok"], "bought at level 5")
	check_eq(wallet.bones, 900, "paid 100 bones")
	check_eq(c.equipped["chair"], "test_chair", "and it is in place")
	check(c.equip("yellow_plastic_chair"), "can switch back")
	check_eq(c.buy("test_chair", wallet, 5)["reason"], "already_owned", "no buying twice")


func test_only_optional_slots_can_be_emptied() -> void:
	var furniture := _furniture_with_variant()
	check(not furniture.unequip("chair"), "the chair slot always has a chair")
	var cosmetics := _cosmetics_with_hat()
	cosmetics.buy("test_hat", _wallet(100), 1)
	check(cosmetics.unequip("head"), "a hat can be taken off")
	check_eq(cosmetics.equipped["head"], "", "head slot empty again")


func test_restore_ignores_unknown_and_unowned() -> void:
	var c := _furniture_with_variant()
	c.restore({"owned": ["nope"], "equipped": {"chair": "test_chair", "sofa": "x"}})
	check_eq(c.equipped["chair"], "yellow_plastic_chair", "cannot equip what is not owned")
	c.restore({"owned": ["test_chair"], "equipped": {"chair": "test_chair"}})
	check_eq(c.equipped["chair"], "test_chair", "restored when owned")
	check_eq(_furniture_with_variant().snapshot()["equipped"]["table"], "boteco_side_table", "snapshot lists slots")


func test_window_rows_offer_try_before_buying() -> void:
	var c := _furniture_with_variant()
	var sections := CollectionModal.sections_for(c, 5, 200, {"chair": "test_chair"})
	check_eq(sections.size(), 2, "only slots with items get a section")
	var chair_rows: Array = sections[0]["rows"]
	check_eq(chair_rows[0]["state"], "in_use", "plastic chair in use")
	check_eq(chair_rows[1]["state"], "affordable", "test chair affordable")
	check(chair_rows[1]["can_try"], "unowned unlocked items can be tried")
	check(chair_rows[1]["previewing"], "and it shows as being tried")
	var locked := CollectionModal.sections_for(c, 1, 200)
	check(not locked[0]["rows"][1]["can_try"], "locked items cannot be tried")


func test_empty_wardrobe_has_no_sections() -> void:
	var c := Collection.new()
	c.configure(_read("res://data/cosmetics/cosmetics.json"), _assets)
	check_eq(CollectionModal.sections_for(c, 100, 100000), [], "no cosmetics shipped yet")


func test_swapping_a_layer_moves_its_art_and_click_area() -> void:
	var stage: Node2D = IslandStage.new()
	var errors: Array = stage.build(_read("res://data/environment/island_layout.json"), _content,
			_read("res://data/animations/animation_groups.json"))
	check_no_errors(errors, "stage builds")
	var before: Rect2
	for p in stage.placements:
		if p["name"] == "chair":
			before = p["rect"]
	check(stage.set_layer_asset("chair", "environment.boteco_side_table"), "swap accepted")
	var after: Rect2
	for p in stage.placements:
		if p["name"] == "chair":
			after = p["rect"]
			check_eq(p["asset"], "environment.boteco_side_table", "placement records the new art")
	check(after != before, "the chair's rect follows the new art")
	check_eq(after.end.y, before.end.y, "and it still stands on the same ground line")
	check(not stage.set_layer_asset("chair", "environment.nope"), "unknown art is refused")
	stage.free()


func test_hat_sits_on_every_standing_frame_and_hides_when_lying() -> void:
	var cosmetics := _cosmetics_with_hat()
	var hat: Dictionary = cosmetics.item("test_hat")
	var rule: Dictionary = cosmetics.slots["head"]
	var rect := _content.visible_rect(hat["asset"])
	var shown := 0
	var hidden := 0
	for form in _content.form_numbers():
		for slot in range(1, 34):
			var frame := CharacterAnimator.resolve_frame(_content, [], form, slot)
			var p := CharacterAnimator.cosmetic_placement(hat, rule, frame, form, rect, 1.0)
			if "horizontal_sleep" in frame["flags"]:
				check(p.is_empty(), "f%d s%d: hidden while lying down" % [form, slot])
				hidden += 1
				continue
			check(not p.is_empty(), "f%d s%d: shown" % [form, slot])
			if p.is_empty():
				continue
			shown += 1
			var head: Array = frame["attach"]["head_top"]
			check(p["position"].is_equal_approx(Vector2(head[0], head[1]) - frame["anchor"]),
					"f%d s%d: on the head point" % [form, slot])
			check(p["position"].y < 0.0, "f%d s%d: above the ground point" % [form, slot])
		_content.release_textures(range(1, 34).map(func(s: int) -> String: return CharacterAnimator.frame_id(form, s)))
	check_eq(shown + hidden, 363, "every frame considered")
	check_eq(hidden, 33, "three lying frames per form")


func test_per_form_tuning_overrides_scale_and_offset() -> void:
	var hat := {"asset": "ui.currency_xp_star", "scale": 0.3, "offset": [0, 0],
			"per_form": {"11": {"scale": 0.5, "offset": [0, -40]}}}
	var rule := {"attach": "head_top"}
	var rect := _content.visible_rect(hat["asset"])
	var f1 := CharacterAnimator.resolve_frame(_content, [], 1, 3)
	var f11 := CharacterAnimator.resolve_frame(_content, [], 11, 3)
	check(is_equal_approx(CharacterAnimator.cosmetic_placement(hat, rule, f1, 1, rect, 1.0)["scale"], 0.3), "form 1 uses the base scale")
	var p11 := CharacterAnimator.cosmetic_placement(hat, rule, f11, 11, rect, 1.0)
	check(is_equal_approx(p11["scale"], 0.5), "form 11 uses its own scale")
	var head: Array = f11["attach"]["head_top"]
	check(p11["position"].is_equal_approx(Vector2(head[0], head[1] - 40) - f11["anchor"]), "and its own offset")


func test_attachment_overrides_win_over_estimates() -> void:
	_content._overrides = {"1": {"3": {"head_top": [111, 222]}}}
	check_eq(_content.attachment_points(1, 3)["head_top"], [111, 222], "override applied")
	check(_content.attachment_points(1, 4)["head_top"] != [111, 222], "other frames untouched")
	_content._overrides = null
