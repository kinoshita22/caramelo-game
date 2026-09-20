extends Node2D
## Plays Caramelo's animation groups for one form.
##
## Frames come from the catalog; each frame is drawn so its stable anchor
## (frame_geometry.json) sits on this node's origin, so the character stays
## planted while poses change. Groups, timing and per-frame fixes come from
## data/animations/animation_groups.json. The node never moves itself:
## whoever owns it places it on the group's anchor (see group_started).

signal group_started(group_name: String, anchor_name: String)
signal group_finished(group_name: String)
signal frame_changed(slot: int)

const EXPECTED_SLOTS := 33

var content: RefCounted
var groups: Dictionary = {}
var overrides: Array = []
var base_scale := 1.0
## Multiplies every group's fps (e.g. the Speed stat for workouts).
var speed_scale := 1.0
var form := 0
var group := ""
var frame_index := 0

var _frames: Dictionary = {}  # slot -> {texture, anchor, scale}
var _elapsed := 0.0
var _holding := false  # one-shot group finished with no next group
var _sprite: Sprite2D


func _init() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Frame"
	_sprite.centered = false
	add_child(_sprite)


## doc is animation_groups.json. Call before set_form/play.
func setup(content_data: RefCounted, doc: Dictionary, scale_factor: float) -> void:
	content = content_data
	groups = doc.get("groups", {})
	overrides = doc.get("frame_overrides", [])
	base_scale = scale_factor


## Loads the 33 frames of a form and releases the previous form's textures.
func set_form(new_form: int) -> void:
	if new_form == form and not _frames.is_empty():
		return
	var old_ids: Array = []
	for slot in _frames:
		old_ids.append(frame_id(form, slot))
	_frames.clear()
	form = new_form
	for slot in range(1, EXPECTED_SLOTS + 1):
		_frames[slot] = resolve_frame(content, overrides, form, slot)
	content.release_textures(old_ids)
	if group != "":
		_show()


func play(group_name: String, restart: bool = false) -> void:
	if not groups.has(group_name):
		push_error("CharacterAnimator: unknown group '%s'" % group_name)
		return
	if group_name == group and not restart:
		return
	group = group_name
	frame_index = 0
	_elapsed = 0.0
	_holding = false
	_show()
	group_started.emit(group, groups[group].get("anchor", ""))


## Advances time. Called from _process; tests call it directly.
func tick(delta: float) -> void:
	if group == "" or _holding:
		return
	var g: Dictionary = groups[group]
	var frame_time := 1.0 / (float(g["fps"]) * maxf(speed_scale, 0.01))
	_elapsed += delta
	while _elapsed >= frame_time and group != "":
		_elapsed -= frame_time
		var step := advance(frame_index, g["slots"].size(), bool(g["loop"]))
		if step["finished"]:
			var finished := group
			group_finished.emit(finished)
			if g.has("next") and group == finished:
				play(g["next"], true)
				return
			frame_index = step["index"]
			_holding = true
			return
		frame_index = step["index"]
		_show()


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


func _show() -> void:
	var slot := current_slot()
	var f: Dictionary = _frames.get(slot, {})
	if f.is_empty():
		return
	_sprite.texture = f["texture"]
	_sprite.offset = -f["anchor"]
	_sprite.scale = Vector2.ONE * base_scale * f["scale"]
	frame_changed.emit(slot)


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
	if not geo.is_empty():
		var a: Dictionary = geo.get("stable_anchor", geo["anchor"])
		anchor = Vector2(a["x"], a["y"])
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
	return {"texture": content_data.texture(frame_id(f, slot)), "anchor": anchor, "scale": scale}


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
	return errors


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
