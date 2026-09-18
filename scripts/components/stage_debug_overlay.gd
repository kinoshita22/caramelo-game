extends Node2D
## Draws the island stage's layer bounds, character boxes, anchors, stage
## bounds and hit polygon in stage units. Add as a child of the stage.

const LAYER_COLOR := Color(1, 0.3, 0.3, 0.9)
const BOX_COLOR := Color(1, 0.9, 0.2, 0.6)
const BOUNDS_COLOR := Color(0.2, 1, 1, 0.9)
const HIT_COLOR := Color(0.3, 1, 0.3, 0.9)
const ANCHOR_COLOR := Color(1, 0.2, 1, 1)

var stage: Node2D


func _ready() -> void:
	z_index = 100
	z_as_relative = false


func _draw() -> void:
	if stage == null:
		return
	var px := 1.0 / maxf(stage.global_scale.x, 0.001)  # one screen pixel in stage units
	var font := ThemeDB.fallback_font
	var font_size := int(14 * px)
	for p in stage.placements:
		draw_rect(p["rect"], LAYER_COLOR, false, 2 * px)
		draw_string(font, p["rect"].position + Vector2(4, 14) * px, p["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LAYER_COLOR)
	for r in stage.character_boxes:
		draw_rect(r, BOX_COLOR, false, px)
	draw_rect(stage.bounds, BOUNDS_COLOR, false, 2 * px)
	if stage.hit_polygon.size() > 2:
		var closed: PackedVector2Array = stage.hit_polygon.duplicate()
		closed.append(closed[0])
		draw_polyline(closed, HIT_COLOR, 3 * px)
	for n in stage.anchors:
		var at: Vector2 = stage.anchors[n]
		draw_circle(at, 6 * px, ANCHOR_COLOR)
		draw_string(font, at + Vector2(8, -8) * px, n, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ANCHOR_COLOR)
	draw_line(Vector2(-20, 0) * px, Vector2(20, 0) * px, Color.WHITE, px)
	draw_line(Vector2(0, -20) * px, Vector2(0, 20) * px, Color.WHITE, px)
