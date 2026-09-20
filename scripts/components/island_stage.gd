extends Node2D
## Builds the floating-island composition from data/environment/island_layout.json.
##
## Stage units are design pixels; the origin is the centre of the walkable
## surface. The static functions hold all placement maths so tests can run
## them without a scene tree or textures.

const CharacterAnimator := preload("res://scripts/components/character_animator.gd")
const BehaviourDriver := preload("res://scripts/components/behaviour_driver.gd")
const REQUIRED_ANCHORS := ["idle", "workout", "eating", "sleep", "wardrobe", "celebration"]
const PIVOTS := ["bottom_center", "top_center", "center"]

## Visible bounds of everything that can be drawn, in stage units.
var bounds := Rect2()
## Anchor name -> stage position.
var anchors: Dictionary = {}
## Stage-space polygon that should receive mouse input.
var hit_polygon := PackedVector2Array()
## Per-layer placement records (see compute_placements).
var placements: Array = []
## Reserved character boxes at every anchor, stage units.
var character_boxes: Array[Rect2] = []
## Moves between anchors; holds the shadow and the animator.
var character: Node2D
var animator: Node2D
## Decides what Caramelo does; null until start_behaviour() succeeds.
var behaviour: Node
## Slot name -> Sprite2D for runtime-swapped props (dumbbells, meal).
var prop_sprites := {}
var _prop_slots := {}
var _content: RefCounted


## Validates the layout and animation groups, then creates one Sprite2D per
## layer plus the animated character and its shadow. Returns validation
## errors; builds nothing when there are any.
func build(layout: Dictionary, content: RefCounted, animation_doc: Dictionary) -> Array[String]:
	var errors := validate_layout(layout, content)
	if errors.is_empty():
		errors = CharacterAnimator.validate_groups(animation_doc, layout["anchors"].keys())
	if not errors.is_empty():
		return errors
	for child in get_children():
		child.queue_free()
	_content = content
	_prop_slots = layout.get("prop_slots", {})
	prop_sprites.clear()
	placements = compute_placements(layout, content)
	anchors = compute_anchors(layout)
	character_boxes = compute_character_boxes(layout, content, anchors)
	var rects: Array[Rect2] = []
	for p in placements:
		rects.append(p["rect"])
	rects.append_array(character_boxes)
	bounds = union_rect(rects).grow(float(layout.get("stage_padding", 0)))
	hit_polygon = outline(rects, float(layout.get("passthrough", {}).get("padding", 0)))

	for p in placements:
		add_child(_sprite(p["name"], content.texture(p["asset"]), p))
	var ch: Dictionary = layout["character"]
	character = Node2D.new()
	character.name = "Character"
	character.z_index = int(ch["z"])
	add_child(character)
	var shadow: Dictionary = ch["shadow"]
	var shadow_sprite := _sprite("Shadow", content.texture(shadow["asset"]),
			place(content.asset(shadow["asset"]), shadow, Vector2.ZERO))
	shadow_sprite.z_index = int(shadow.get("z", 0)) - int(ch["z"])
	character.add_child(shadow_sprite)
	animator = CharacterAnimator.new()
	animator.name = "Animator"
	animator.setup(content, animation_doc, float(ch["scale"]))
	animator.group_started.connect(func(_g: String, anchor_name: String) -> void: move_character_to(anchor_name))
	character.add_child(animator)
	animator.set_form(int(ch["form"]))
	animator.play(animation_doc["default_group"])
	return errors


## Starts the autonomous loop. Returns validation errors for the balance
## data; without it the character just keeps playing its current group.
func start_behaviour(balance: Dictionary, progression: RefCounted = null, economy: RefCounted = null) -> Array[String]:
	var driver: Node = BehaviourDriver.new()
	driver.name = "Behaviour"
	driver.progression = progression
	driver.economy = economy
	var errors: Array[String] = driver.setup(animator, balance)
	if not errors.is_empty():
		driver.free()
		return errors
	add_child(driver)
	behaviour = driver
	return errors


## Shows an asset in a prop slot (or hides the slot with an empty id).
func set_prop(slot_name: String, asset_id: String) -> void:
	var spec: Variant = _prop_slots.get(slot_name)
	if typeof(spec) != TYPE_DICTIONARY or _content == null:
		return
	var asset: Dictionary = _content.asset(asset_id)
	if asset.is_empty() or asset.get("runtime_path") == null:
		if prop_sprites.has(slot_name):
			prop_sprites[slot_name].visible = false
		return
	var placement := place(asset, spec, _vec(spec["position"]))
	if not prop_sprites.has(slot_name):
		var sprite := _sprite("Prop_" + slot_name, null, placement)
		add_child(sprite)
		prop_sprites[slot_name] = sprite
	var s: Sprite2D = prop_sprites[slot_name]
	s.visible = true
	s.texture = _content.texture(asset_id)
	s.offset = -placement["pivot"]
	s.position = placement["position"]
	s.scale = Vector2.ONE * placement["scale"]
	s.z_index = placement["z"]


## Places the character on a named anchor; unknown names are ignored.
func move_character_to(anchor_name: String) -> void:
	if character != null and anchors.has(anchor_name):
		character.position = anchors[anchor_name]


func _sprite(node_name: String, tex: Texture2D, p: Dictionary) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = tex
	s.centered = false
	s.offset = -p["pivot"]
	s.position = p["position"]
	s.scale = Vector2.ONE * p["scale"]
	s.z_index = p["z"]
	return s


static func validate_layout(layout: Dictionary, content: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	var layers: Variant = layout.get("layers")
	if typeof(layers) != TYPE_ARRAY or layers.is_empty():
		return ["island_layout: 'layers' must be a non-empty array"]
	var names := {}
	for l in layers:
		if typeof(l) != TYPE_DICTIONARY:
			errors.append("island_layout: every layer must be an object")
			continue
		var n: String = str(l.get("name", ""))
		if n == "" or names.has(n):
			errors.append("island_layout: layer name '%s' missing or repeated" % n)
		names[n] = true
		errors.append_array(_check_placed(l, content, "layer " + n))
	var ch: Variant = layout.get("character")
	if typeof(ch) != TYPE_DICTIONARY:
		errors.append("island_layout: 'character' must be an object")
	else:
		if not _positive(ch.get("scale")):
			errors.append("island_layout: character.scale must be a positive number")
		if not _is_num(ch.get("z")):
			errors.append("island_layout: character.z must be a number")
		var form_ok: bool = _is_num(ch.get("form")) and int(ch["form"]) in content.form_numbers()
		if not form_ok:
			errors.append("island_layout: character.form must be a known form number")
		elif content.asset(CharacterAnimator.frame_id(int(ch["form"]), 1)).get("runtime_path") == null:
			errors.append("island_layout: character.form %d is not staged" % int(ch["form"]))
		if typeof(ch.get("shadow")) != TYPE_DICTIONARY:
			errors.append("island_layout: character.shadow must be an object")
		else:
			var sh: Dictionary = ch["shadow"].duplicate()
			sh["position"] = [0, 0]
			errors.append_array(_check_placed(sh, content, "character shadow"))
	var anchors: Variant = layout.get("anchors")
	if typeof(anchors) != TYPE_DICTIONARY:
		errors.append("island_layout: 'anchors' must be an object")
	else:
		for a in REQUIRED_ANCHORS:
			if not anchors.has(a) or not _is_vec(anchors[a].get("position") if typeof(anchors[a]) == TYPE_DICTIONARY else null):
				errors.append("island_layout: anchor '%s' missing or has no [x, y] position" % a)
	return errors


static func _check_placed(l: Dictionary, content: RefCounted, ctx: String) -> Array[String]:
	var errors: Array[String] = []
	var a: Dictionary = content.asset(str(l.get("asset", "")))
	if a.is_empty():
		errors.append("island_layout: %s uses unknown asset '%s'" % [ctx, l.get("asset")])
	elif a.get("runtime_path") == null:
		errors.append("island_layout: %s asset '%s' is not staged" % [ctx, l.get("asset")])
	var pivot: Variant = l.get("pivot", "bottom_center")
	if not (pivot in PIVOTS or _is_vec(pivot)):
		errors.append("island_layout: %s pivot must be one of %s or [x, y]" % [ctx, PIVOTS])
	if not _is_vec(l.get("position")):
		errors.append("island_layout: %s position must be [x, y]" % ctx)
	if not _positive(l.get("scale")):
		errors.append("island_layout: %s scale must be a positive number" % ctx)
	if l.has("z") and not _is_num(l["z"]):
		errors.append("island_layout: %s z must be a number" % ctx)
	return errors


## One record per layer: name, asset, pivot (source px), position, scale,
## z, and rect (visible bounds in stage units).
static func compute_placements(layout: Dictionary, content: RefCounted) -> Array:
	var out: Array = []
	for l in layout["layers"]:
		var p := place(content.asset(l["asset"]), l, _vec(l["position"]))
		p["name"] = l["name"]
		p["asset"] = l["asset"]
		out.append(p)
	return out


## Placement of one asset whose pivot lands at `at`.
static func place(asset: Dictionary, spec: Dictionary, at: Vector2) -> Dictionary:
	var v: Dictionary = asset["visible"]
	var vis := Rect2(v["x"], v["y"], v["width"], v["height"])
	var pivot := pivot_point(vis, spec.get("pivot", "bottom_center"))
	var s := float(spec["scale"])
	return {
		"pivot": pivot,
		"position": at,
		"scale": s,
		"z": int(spec.get("z", 0)),
		"rect": Rect2(at + (vis.position - pivot) * s, vis.size * s),
	}


static func pivot_point(vis: Rect2, spec: Variant) -> Vector2:
	match spec:
		"bottom_center":
			return Vector2(vis.get_center().x, vis.end.y)
		"top_center":
			return Vector2(vis.get_center().x, vis.position.y)
		"center":
			return vis.get_center()
	return _vec(spec)


static func compute_anchors(layout: Dictionary) -> Dictionary:
	var out := {}
	for n in layout["anchors"]:
		out[n] = _vec(layout["anchors"][n]["position"])
	return out


## Space any form's largest frame could need at each anchor: the biggest
## per-form canvas at character scale, standing on the anchor.
static func compute_character_boxes(layout: Dictionary, content: RefCounted, anchor_points: Dictionary) -> Array[Rect2]:
	var size: Vector2 = content.max_character_canvas() * float(layout["character"]["scale"])
	var boxes: Array[Rect2] = []
	for n in anchor_points:
		var at: Vector2 = anchor_points[n]
		boxes.append(Rect2(at.x - size.x / 2.0, at.y - size.y, size.x, size.y))
	return boxes


static func union_rect(rects: Array[Rect2]) -> Rect2:
	if rects.is_empty():
		return Rect2()
	var r := rects[0]
	for i in range(1, rects.size()):
		r = r.merge(rects[i])
	return r


## Outer outline of the union of every rect grown by padding. Holes are
## dropped. Falls back to the convex hull when the rects do not join into a
## single shape, because the OS accepts only one click-through polygon.
static func outline(rects: Array[Rect2], padding: float) -> PackedVector2Array:
	var polys: Array[PackedVector2Array] = []
	for r in rects:
		var g := r.grow(padding)
		polys.append(PackedVector2Array([g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]))
	var merged_any := true
	while merged_any and polys.size() > 1:
		merged_any = false
		for i in polys.size():
			for j in range(i + 1, polys.size()):
				if Geometry2D.intersect_polygons(polys[i], polys[j]).is_empty():
					continue
				polys[i] = _largest(Geometry2D.merge_polygons(polys[i], polys[j]))
				polys.remove_at(j)
				merged_any = true
				break
			if merged_any:
				break
	return polys[0] if polys.size() == 1 else hull(rects, padding)


static func _largest(polys: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for p in polys:
		var area := 0.0
		for k in p.size():
			area += p[k].cross(p[(k + 1) % p.size()])
		if absf(area) > best_area:
			best_area = absf(area)
			best = p
	return best


## Convex hull of every rect grown by padding, as an open polygon.
static func hull(rects: Array[Rect2], padding: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for r in rects:
		var g := r.grow(padding)
		pts.append_array([g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)])
	var h := Geometry2D.convex_hull(pts)
	if h.size() > 1 and h[0] == h[h.size() - 1]:
		h.remove_at(h.size() - 1)
	return h


static func _vec(v: Variant) -> Vector2:
	return Vector2(float(v[0]), float(v[1]))


static func _is_vec(v: Variant) -> bool:
	return typeof(v) == TYPE_ARRAY and v.size() == 2 and _is_num(v[0]) and _is_num(v[1])


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _positive(v: Variant) -> bool:
	return _is_num(v) and v > 0
