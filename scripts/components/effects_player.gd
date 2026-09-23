extends Node2D
## Plays short effects (a star, a bone burst, "+3") from
## data/effects/effects.json when their trigger happens. Lives on the UI
## layer, so effects draw above the island; positions come from the stage
## (Caramelo's head) or the HUD (the bone counter).

const UIKit := preload("res://scripts/components/ui_kit.gd")
const FLASH_SECONDS := 0.6

var content: RefCounted
var effects := {}
var stage: Node2D
var hud: Control


func setup(content_data: RefCounted, doc: Dictionary, stage_node: Node2D, hud_node: Control) -> void:
	content = content_data
	effects = doc.get("effects", {})
	stage = stage_node
	hud = hud_node


## Plays every effect whose trigger matches. values fill {level} and friends.
func trigger(trigger_name: String, values: Dictionary = {}) -> void:
	for name in effects_for(effects, trigger_name):
		play(effects[name], values)


func play(effect: Dictionary, values: Dictionary) -> void:
	var origin := _origin(effect.get("at", "character_head"))
	var holder := Node2D.new()
	holder.position = origin
	holder.scale = Vector2.ONE * 0.4
	add_child(holder)

	var size := float(effect.get("size", 80))
	var texture: Texture2D = content.icon_texture(effect.get("asset", "")) if effect.has("asset") else null
	if texture != null:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.scale = Vector2.ONE * size / maxf(texture.get_width(), texture.get_height())
		holder.add_child(sprite)
	var text := format_text(tr(effect.get("text", "")), values)
	if text != "":
		var label := UIKit.label(text, int(clampf(size * 0.45, 30, 56)), Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		label.add_theme_constant_override("outline_size", 10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(420, 70)
		label.position = Vector2(-210, size * 0.45)
		holder.add_child(label)

	var duration := maxf(float(effect.get("duration", 1.2)), 0.2)
	var tween := create_tween().set_parallel()
	tween.tween_property(holder, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(holder, "position:y", origin.y - float(effect.get("rise", 60)), duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(holder, "modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tween.chain().tween_callback(holder.queue_free)

	if effect.get("flash", false):
		_flash()


## A brief white flash over the whole window (evolution).
func _flash() -> void:
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 0.75)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = get_viewport().get_visible_rect().size
	add_child(rect)
	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, FLASH_SECONDS)
	tween.tween_callback(rect.queue_free)


## Where an effect starts, in UI-layer coordinates.
func _origin(at: String) -> Vector2:
	if at == "bone_counter" and hud != null and hud.has_method("bone_counter_centre"):
		return hud.bone_counter_centre()
	if stage == null or stage.character == null:
		return get_viewport().get_visible_rect().get_center()
	var point: Vector2 = stage.character.position
	if at == "character_head" and stage.animator != null:
		point += stage.animator.point_offset("head_top")
	# The stage and this layer share the canvas coordinate space.
	return stage.get_global_transform_with_canvas() * point


## Effect names for a trigger. Pure.
static func effects_for(all_effects: Dictionary, trigger_name: String) -> Array[String]:
	var names: Array[String] = []
	for name in all_effects:
		if typeof(all_effects[name]) == TYPE_DICTIONARY and all_effects[name].get("trigger", "") == trigger_name:
			names.append(name)
	return names


## "Level {level}!" with {"level": 12} -> "Level 12!". Pure.
static func format_text(template: String, values: Dictionary) -> String:
	var out := template
	for key in values:
		out = out.replace("{%s}" % key, str(values[key]))
	return out


static func validate(doc: Dictionary, known_assets: Array = []) -> Array[String]:
	var errors: Array[String] = []
	var all: Variant = doc.get("effects")
	if typeof(all) != TYPE_DICTIONARY:
		return ["effects: 'effects' must be an object"]
	for name in all:
		var e: Variant = all[name]
		if typeof(e) != TYPE_DICTIONARY:
			errors.append("effects: '%s' must be an object" % name)
			continue
		var trig: String = str(e.get("trigger", ""))
		if not (trig.begins_with("state:") or trig in ["bones_gained", "bones_spent", "xp_gained"]):
			errors.append("effects: '%s' has unknown trigger '%s'" % [name, trig])
		if not e.get("at", "character_head") in ["character_head", "character", "bone_counter"]:
			errors.append("effects: '%s' has unknown 'at' '%s'" % [name, e.get("at")])
		if e.has("asset") and not known_assets.is_empty() and not e["asset"] in known_assets:
			errors.append("effects: '%s' uses unknown asset '%s'" % [name, e["asset"]])
		for key in ["size", "duration"]:
			var v: Variant = e.get(key, 1)
			if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) or float(v) <= 0.0:
				errors.append("effects: '%s' %s must be a positive number" % [name, key])
	return errors
