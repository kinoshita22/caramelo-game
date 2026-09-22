extends Node2D
## Plays Caramelo's animation groups for one form.
##
## Frames come from the catalog; each frame is drawn so its stable anchor
## (frame_geometry.json) sits on this node's origin, so the character stays
## planted while poses change. Groups, timing and per-frame fixes come from
## data/animations/animation_groups.json. The node never travels by itself:
## whoever owns it places it on the group's anchor (see group_started).
##
## What it does move is the small stuff that keeps him from looking stiff,
## all of it laid over the drawn frames and all of it tuned in that file's
## "motion" block (see Motion):
##   * a dissolve from the outgoing frame into the new one when the group
##     changes, and between the frames of groups slow enough to see them
##     change (the sleep holds each drawing for two seconds);
##   * a slide that swallows a small frame-to-frame shift of his body, so
##     poses ease into place instead of popping (bigger moves still snap:
##     a jump should look like a jump);
##   * breathing and sway, so a held pose never freezes dead.

signal group_started(group_name: String, anchor_name: String)
signal group_finished(group_name: String)
signal frame_changed(slot: int)

const Motion := preload("res://scripts/systems/motion.gd")

const EXPECTED_SLOTS := 33

var content: RefCounted
var groups: Dictionary = {}
var overrides: Array = []
var base_scale := 1.0
## Multiplies every group's fps (e.g. the Speed stat for workouts).
var speed_scale := 1.0
## Whether a finished one-shot group starts its "next" group by itself. The
## behaviour driver turns this off: the loop decides what follows, and a
## group handing over early made him idle between states (hungry -> idle ->
## eating). Previews keep it on.
var follow_next := true
var form := 0
var group := ""
var frame_index := 0
## Displacement and squash the owner adds, in stage units: the hop of a move
## between anchors (see IslandStage). Breathing is added on top.
var travel_offset := Vector2.ZERO
var travel_squash := Vector2.ONE

var _frames: Dictionary = {}  # slot -> {texture, anchor, scale, visible, attach, flags}
## Cosmetic slot -> {"rule": slot spec from cosmetics.json, "item": item or {},
## "sprite": Sprite2D}.
var _cosmetics: Dictionary = {}
var _elapsed := 0.0
var _holding := false  # one-shot group finished with no next group
var _sprite: Sprite2D
## The outgoing frame, fading out over the new one.
var _ghost: Sprite2D
var _fade_left := 0.0
var _fade_time := 0.0
var _motion: Dictionary = {}
var _blend: Dictionary = Motion.blend({})
var _secondary: Dictionary = Motion.secondary_for({}, "")
var _breath_time := 0.0
## How far the current frame is still displaced while a pop eases out.
var _slide := Vector2.ZERO
var _last_frame: Dictionary = {}


func _init() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Frame"
	_sprite.centered = false
	add_child(_sprite)
	# Added second, so the outgoing frame dissolves on top of the new one.
	_ghost = Sprite2D.new()
	_ghost.name = "Outgoing"
	_ghost.centered = false
	_ghost.visible = false
	add_child(_ghost)


## doc is animation_groups.json. Call before set_form/play.
func setup(content_data: RefCounted, doc: Dictionary, scale_factor: float) -> void:
	content = content_data
	groups = doc.get("groups", {})
	overrides = doc.get("frame_overrides", [])
	base_scale = scale_factor
	_motion = doc.get("motion", {})
	_blend = Motion.blend(_motion)
	_secondary = Motion.secondary_for(_motion, group)


## Loads the 33 frames of a form and releases the previous form's textures.
func set_form(new_form: int) -> void:
	if new_form == form and not _frames.is_empty():
		return
	var old_ids: Array = []
	for slot in _frames:
		old_ids.append(frame_id(form, slot))
	_frames.clear()
	# A different body: its frames are not a continuation of this one's.
	_last_frame = {}
	_slide = Vector2.ZERO
	form = new_form
	for slot in range(1, EXPECTED_SLOTS + 1):
		_frames[slot] = resolve_frame(content, overrides, form, slot)
	content.release_textures(old_ids)
	if group != "":
		# A form swap is a whole new body: dissolve into it.
		_show(float(_blend["crossfade"]))


func play(group_name: String, restart: bool = false) -> void:
	if not groups.has(group_name):
		push_error("CharacterAnimator: unknown group '%s'" % group_name)
		return
	if group_name == group and not restart:
		return
	var same_group := group_name == group
	group = group_name
	frame_index = 0
	_elapsed = 0.0
	_holding = false
	if not same_group:
		# Start the breath with the pose, so a group drawn breathing (the
		# sleep is an exhale and an inhale) lifts on the same beat instead
		# of beating against it. Carry the lift he is at into the slide, so
		# restarting the clock eases out rather than dropping him.
		_slide += Motion.breath_offset(_secondary, _breath_time)
		_breath_time = 0.0
	_secondary = Motion.secondary_for(_motion, group)
	# Restarting the group he is already in is not a change to dissolve.
	_show(0.0 if same_group else float(_blend["crossfade"]))
	group_started.emit(group, groups[group].get("anchor", ""))


## Advances time. Called from _process; tests call it directly.
func tick(delta: float) -> void:
	_advance_motion(delta)
	if group == "" or _holding:
		return
	var g: Dictionary = groups[group]
	var frame_time := 1.0 / (float(g["fps"]) * maxf(speed_scale, 0.01))
	# A group slow enough to see the frames change (the sleep holds each
	# drawing for two seconds) dissolves between them, over no more than
	# half of the frame's own time. Brisk groups cut.
	var frame_blend := 0.0
	if float(g["fps"]) <= float(_blend["slow_fps"]):
		frame_blend = minf(float(_blend["frame_crossfade"]), frame_time * 0.5)
	_elapsed += delta
	while _elapsed >= frame_time and group != "":
		_elapsed -= frame_time
		var step := advance(frame_index, g["slots"].size(), bool(g["loop"]))
		if step["finished"]:
			var finished := group
			group_finished.emit(finished)
			if follow_next and g.has("next") and group == finished:
				play(g["next"], true)
				return
			frame_index = step["index"]
			_holding = true
			return
		frame_index = step["index"]
		_show(frame_blend)


## The dissolve, the easing of a frame's pop and the breathing, none of
## which depend on the frame timing.
func _advance_motion(delta: float) -> void:
	_breath_time += delta
	if _fade_left > 0.0:
		_fade_left = maxf(_fade_left - delta, 0.0)
		_ghost.modulate.a = Motion.fade(_fade_left, _fade_time)
		_ghost.visible = _fade_left > 0.0
		if not _ghost.visible:
			_ghost.texture = null
	_slide = _slide.lerp(Vector2.ZERO, Motion.approach_factor(delta, float(_blend["jitter_ease"])))
	if _slide.length() < 0.05:
		_slide = Vector2.ZERO
	_apply_motion()


## Whether a pose change is still dissolving, so the frame rate should stay
## smooth until it finishes. The per-frame slide is deliberately left out:
## it is over in a frame or two and happens all day, so counting it would
## hold the rate up for good.
func is_settling() -> bool:
	return _fade_left > 0.0


func _process(delta: float) -> void:
	tick(delta)


## Shows one frame of the current group and stops advancing (debugging).
func freeze_at(index: int) -> void:
	if group == "":
		return
	frame_index = clampi(index, 0, groups[group]["slots"].size() - 1)
	_holding = true
	_show()


func current_slot() -> int:
	if group == "":
		return 0
	return int(groups[group]["slots"][frame_index])


## Draws the current frame. blend_seconds > 0 leaves the outgoing frame
## behind to dissolve.
func _show(blend_seconds: float = 0.0) -> void:
	var slot := current_slot()
	var f: Dictionary = _frames.get(slot, {})
	if f.is_empty():
		return
	if blend_seconds > 0.0 and _sprite.texture != null:
		_ghost.texture = _sprite.texture
		_ghost.offset = _sprite.offset
		_ghost.scale = _sprite.scale
		_ghost.modulate.a = 1.0
		_ghost.visible = true
		_fade_time = blend_seconds
		_fade_left = blend_seconds
	_slide = (_slide + body_shift(_last_frame, f, base_scale, float(_blend["jitter_px"]))).limit_length(
			float(_blend["jitter_px"]))
	_last_frame = f
	_sprite.texture = f["texture"]
	_sprite.offset = -f["anchor"]
	_sprite.scale = Vector2.ONE * base_scale * f["scale"]
	_apply_motion()
	for cosmetic_slot in _cosmetics:
		_place_cosmetic(cosmetic_slot, f)
	frame_changed.emit(slot)


## Moves the whole character (frame, dissolve and cosmetics together) by the
## breathing, the easing pop and whatever the owner added for a move. The
## shadow is a sibling, so it stays on the ground.
func _apply_motion() -> void:
	position = travel_offset + _slide + Motion.breath_offset(_secondary, _breath_time)
	scale = travel_squash * Motion.breath_scale(_secondary, _breath_time)


## How far to hold a new frame back so its body carries on from where the
## previous one left it, in stage units. Small shifts are pops in the art
## and ease away; anything above `limit` is real movement and is left to
## land on its own. Pure.
static func body_shift(from_frame: Dictionary, to_frame: Dictionary, character_scale: float,
		limit: float) -> Vector2:
	if from_frame.is_empty() or to_frame.is_empty():
		return Vector2.ZERO
	var shift := _body_point(to_frame, character_scale) - _body_point(from_frame, character_scale)
	return Vector2.ZERO if shift.length() > limit else -shift


## Where the drawn body sits relative to this node's origin: the middle of
## its feet, in stage units.
static func _body_point(f: Dictionary, character_scale: float) -> Vector2:
	var vis: Rect2 = f.get("visible", Rect2())
	if vis.size == Vector2.ZERO:
		return Vector2.ZERO
	return (Vector2(vis.get_center().x, vis.end.y) - f["anchor"]) * character_scale * float(f["scale"])


## Declares the cosmetic slots (cosmetics.json "slots"). Call once.
func setup_cosmetics(slot_rules: Dictionary) -> void:
	for slot_name in slot_rules:
		if String(slot_name).begins_with("_"):
			continue
		var sprite := Sprite2D.new()
		sprite.name = "Cosmetic_" + slot_name
		sprite.centered = false
		sprite.visible = false
		add_child(sprite)
		_cosmetics[slot_name] = {"rule": slot_rules[slot_name], "item": {}, "sprite": sprite}


## Shows `item` (a cosmetics.json entry) in a slot, or clears it with {}.
func set_cosmetic(slot_name: String, item: Dictionary) -> void:
	if not _cosmetics.has(slot_name):
		return
	_cosmetics[slot_name]["item"] = item
	var sprite: Sprite2D = _cosmetics[slot_name]["sprite"]
	sprite.texture = content.texture(item["asset"]) if not item.is_empty() else null
	var f: Dictionary = _frames.get(current_slot(), {})
	if not f.is_empty():
		_place_cosmetic(slot_name, f)


## Offset from this node's origin to an attachment point ("head_top"...) on
## the current frame, in this node's parent units. Falls back to straight up.
func point_offset(point_name: String) -> Vector2:
	var f: Dictionary = _frames.get(current_slot(), {})
	var point: Variant = f.get("attach", {}).get(point_name)
	if f.is_empty() or typeof(point) != TYPE_ARRAY:
		return position + Vector2(0.0, -300.0 * base_scale) * scale
	# Through this node's own transform, so an effect follows the breathing
	# and any move in progress.
	var local: Vector2 = (Vector2(point[0], point[1]) - f["anchor"]) * base_scale * float(f["scale"])
	return position + local * scale


## Where a cosmetic sprite goes on the current frame, or {} when hidden.
## Pure maths, so tests can check every form and frame.
static func cosmetic_placement(item: Dictionary, rule: Dictionary, frame: Dictionary, form_number: int,
		item_visible: Rect2, character_scale: float) -> Dictionary:
	if item.is_empty():
		return {}
	for flag in rule.get("hide_on_flags", []):
		if flag in frame.get("flags", []):
			return {}
	var point: Variant = frame.get("attach", {}).get(rule.get("attach", ""))
	if typeof(point) != TYPE_ARRAY or point.size() != 2:
		return {}
	var tuning: Dictionary = item.get("per_form", {}).get(str(form_number), {})
	var offset: Array = tuning.get("offset", item.get("offset", [0, 0]))
	var item_scale := float(tuning.get("scale", item.get("scale", 1.0)))
	var frame_scale := character_scale * float(frame["scale"])
	var target := Vector2(point[0], point[1]) + Vector2(offset[0], offset[1])
	return {
		"position": (target - frame["anchor"]) * frame_scale,
		"pivot": _pivot(item_visible, item.get("pivot", "bottom_center")),
		"scale": frame_scale * item_scale,
	}


func _place_cosmetic(slot_name: String, f: Dictionary) -> void:
	var entry: Dictionary = _cosmetics[slot_name]
	var sprite: Sprite2D = entry["sprite"]
	var item: Dictionary = entry["item"]
	var rect := Rect2()
	if not item.is_empty():
		rect = content.visible_rect(item["asset"])
	var p := cosmetic_placement(item, entry["rule"], f, form, rect, base_scale)
	sprite.visible = not p.is_empty()
	if p.is_empty():
		return
	sprite.position = p["position"]
	sprite.offset = -p["pivot"]
	sprite.scale = Vector2.ONE * p["scale"]


static func _pivot(visible: Rect2, spec: String) -> Vector2:
	match spec:
		"center":
			return visible.get_center()
		"top_center":
			return Vector2(visible.get_center().x, visible.position.y)
	return Vector2(visible.get_center().x, visible.end.y)


## Next frame index. One-shot groups report finished after the last frame
## and stay on it.
static func advance(index: int, count: int, loop: bool) -> Dictionary:
	if index + 1 < count:
		return {"index": index + 1, "finished": false}
	if loop:
		return {"index": 0, "finished": false}
	return {"index": count - 1, "finished": true}


static func frame_id(f: int, slot: int) -> String:
	return "character.f%02d.s%02d" % [f, slot]


## Texture, drawing anchor (source px, lift applied) and scale factor for
## one frame.
static func resolve_frame(content_data: RefCounted, frame_overrides: Array, f: int, slot: int) -> Dictionary:
	var geo: Dictionary = content_data.frame_geometry(f, slot)
	var anchor := Vector2.ZERO
	var visible_rect := Rect2()
	if not geo.is_empty():
		var a: Dictionary = geo.get("stable_anchor", geo["anchor"])
		anchor = Vector2(a["x"], a["y"])
		var v: Dictionary = geo["visible"]
		visible_rect = Rect2(v["x"], v["y"], v["width"], v["height"])
	var scale := 1.0
	for o in frame_overrides:
		if int(o.get("slot", -1)) != slot:
			continue
		if o.has("forms") and not float(f) in o["forms"] and not f in o["forms"]:
			continue
		if o.has("lift") and not geo.is_empty():
			anchor.y += float(o["lift"]) * float(geo["visible"]["height"])
		if o.has("scale"):
			scale *= float(o["scale"])
	return {
		"texture": content_data.texture(frame_id(f, slot)), "anchor": anchor, "scale": scale,
		"visible": visible_rect, "attach": content_data.attachment_points(f, slot),
		"flags": geo.get("review_flags", []),
	}


## Checks animation_groups.json against the slot table and layout anchors.
static func validate_groups(doc: Dictionary, anchor_names: Array) -> Array[String]:
	var errors: Array[String] = []
	var gs: Variant = doc.get("groups")
	if typeof(gs) != TYPE_DICTIONARY or gs.is_empty():
		return ["animation_groups: 'groups' must be a non-empty object"]
	if not gs.has(doc.get("default_group", "")):
		errors.append("animation_groups: default_group must name a group")
	for n in gs:
		var g: Variant = gs[n]
		var ctx := "animation_groups: group '%s'" % n
		if typeof(g) != TYPE_DICTIONARY:
			errors.append(ctx + " must be an object")
			continue
		var slots: Variant = g.get("slots")
		if typeof(slots) != TYPE_ARRAY or slots.is_empty():
			errors.append(ctx + " needs a non-empty slots array")
		else:
			for s in slots:
				if not _is_num(s) or int(s) < 1 or int(s) > EXPECTED_SLOTS or float(int(s)) != float(s):
					errors.append(ctx + " has invalid slot %s" % [s])
		if not _is_num(g.get("fps")) or float(g["fps"]) <= 0:
			errors.append(ctx + " fps must be a positive number")
		if typeof(g.get("loop")) != TYPE_BOOL:
			errors.append(ctx + " loop must be true or false")
		if g.has("next") and not gs.has(g["next"]):
			errors.append(ctx + " next names unknown group '%s'" % g["next"])
		if not g.get("anchor", "") in anchor_names:
			errors.append(ctx + " anchor '%s' is not an island_layout anchor" % g.get("anchor", ""))
	var ov: Variant = doc.get("frame_overrides", [])
	if typeof(ov) != TYPE_ARRAY:
		errors.append("animation_groups: frame_overrides must be an array")
	else:
		for o in ov:
			if typeof(o) != TYPE_DICTIONARY or not _is_num(o.get("slot")) or int(o["slot"]) < 1 or int(o["slot"]) > EXPECTED_SLOTS:
				errors.append("animation_groups: every frame override needs a slot 1-%d" % EXPECTED_SLOTS)
				continue
			if o.has("scale") and (not _is_num(o["scale"]) or float(o["scale"]) <= 0):
				errors.append("animation_groups: override for slot %d has a non-positive scale" % int(o["slot"]))
			if o.has("lift") and not _is_num(o["lift"]):
				errors.append("animation_groups: override for slot %d has a non-numeric lift" % int(o["slot"]))
			if o.has("forms") and typeof(o["forms"]) != TYPE_ARRAY:
				errors.append("animation_groups: override for slot %d forms must be an array" % int(o["slot"]))
	var motion: Variant = doc.get("motion", {})
	if typeof(motion) != TYPE_DICTIONARY:
		errors.append("animation_groups: 'motion' must be an object")
	else:
		errors.append_array(Motion.validate(motion, gs.keys()))
	return errors


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
