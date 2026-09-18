extends "res://tests/lib/test_case.gd"
## Island layout data and the stage placement maths.

const ContentData := preload("res://scripts/systems/content_data.gd")
const IslandStage := preload("res://scripts/components/island_stage.gd")
const LAYOUT_PATH := "res://data/environment/island_layout.json"

var _content := ContentData.new()
var _layout: Dictionary = {}


func _init() -> void:
	_content.load_from("res://data")
	var l: Variant = _content.read_json(LAYOUT_PATH)
	_layout = l if typeof(l) == TYPE_DICTIONARY else {}


func _rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for p in IslandStage.compute_placements(_layout, _content):
		rects.append(p["rect"])
	return rects


func test_content_loads() -> void:
	check_no_errors(_content.errors, "content data")
	check(_content.is_valid(), "content data valid")


func test_layout_validates() -> void:
	check_no_errors(IslandStage.validate_layout(_layout, _content), "island_layout.json")


func test_every_required_anchor_is_on_the_island() -> void:
	var island: Rect2 = IslandStage.compute_placements(_layout, _content)[0]["rect"]
	var anchors := IslandStage.compute_anchors(_layout)
	for n in IslandStage.REQUIRED_ANCHORS:
		check(anchors.has(n), "anchor %s present" % n)
		if anchors.has(n):
			check(island.has_point(anchors[n]), "anchor %s at %s lies on the island %s" % [n, anchors[n], island])


func test_hit_polygon_covers_every_layer_and_anchor() -> void:
	var rects := _rects()
	var anchors := IslandStage.compute_anchors(_layout)
	rects.append_array(IslandStage.compute_character_boxes(_layout, _content, anchors))
	var poly := IslandStage.outline(rects, 12.0)
	check(poly.size() >= 4, "outline has a shape")
	for r in rects:
		check(Geometry2D.is_point_in_polygon(r.get_center(), poly), "outline contains centre of %s" % r)
	for n in anchors:
		check(Geometry2D.is_point_in_polygon(anchors[n], poly), "outline contains anchor %s" % n)


func test_placement_puts_pivot_at_position() -> void:
	var asset := {"visible": {"x": 100, "y": 50, "width": 200, "height": 400}}
	var p := IslandStage.place(asset, {"pivot": "bottom_center", "scale": 0.5}, Vector2(10, 20))
	check_eq(p["pivot"], Vector2(200, 450), "bottom-centre pivot in source pixels")
	check_eq(p["rect"], Rect2(-40, -180, 100, 200), "visible rect ends at the position")
	var top := IslandStage.place(asset, {"pivot": "top_center", "scale": 1.0}, Vector2.ZERO)
	check_eq(top["rect"].position, Vector2(-100, 0), "top-centre pivot hangs below the position")


func test_validation_catches_bad_layouts() -> void:
	var bad := _layout.duplicate(true)
	bad["layers"][1]["asset"] = "environment.does_not_exist"
	bad["layers"][2]["pivot"] = "middle"
	bad["anchors"].erase("sleep")
	bad["character"]["preview_asset"] = "ui.currency_bone_single"
	var errors := IslandStage.validate_layout(bad, _content)
	check_error(errors, "unknown asset 'environment.does_not_exist'")
	check_error(errors, "pivot must be one of")
	check_error(errors, "anchor 'sleep' missing")
	check_error(errors, "preview_asset must be a character frame")


func test_outline_joins_overlapping_rects() -> void:
	var rects: Array[Rect2] = [Rect2(0, 0, 100, 100), Rect2(50, 50, 100, 100)]
	var poly := IslandStage.outline(rects, 0.0)
	check_eq(poly.size(), 8, "L-shaped outline has 8 corners")
	check(not Geometry2D.is_point_in_polygon(Vector2(140, 10), poly), "notch outside both rects is excluded")


func test_outline_falls_back_to_hull_for_separate_shapes() -> void:
	var rects: Array[Rect2] = [Rect2(0, 0, 10, 10), Rect2(100, 0, 10, 10)]
	var poly := IslandStage.outline(rects, 0.0)
	check(Geometry2D.is_point_in_polygon(Vector2(55, 5), poly), "hull spans the gap")
