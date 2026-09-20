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


func _process(_delta: float) -> void:
	# The readout below changes every frame, so redraw while it is shown.
	if visible:
		queue_redraw()


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
	var behaviour: Node = stage.behaviour
	if behaviour != null:
		var loop: RefCounted = behaviour.loop
		var lines := PackedStringArray([
			"state: %s (%.1fs)" % [loop.state, loop.time_in_state],
			"energy: %.0f   satiety: %.0f" % [loop.energy, loop.satiety],
			"recent: " + " > ".join(loop.history().slice(-4)),
			"level %d (form %d)   xp %.0f/%.0f   bones %d" % [GameState.progression.level,
					GameState.progression.form, GameState.progression.xp,
					GameState.progression.xp_to_next(GameState.progression.level), GameState.progression.bones],
		])
		var at: Vector2 = stage.bounds.position + Vector2(8, 22) * px
		for line in lines:
			draw_string(font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, int(16 * px), BOUNDS_COLOR)
			at.y += 20 * px
	draw_line(Vector2(-20, 0) * px, Vector2(20, 0) * px, Color.WHITE, px)
	draw_line(Vector2(0, -20) * px, Vector2(0, 20) * px, Color.WHITE, px)
