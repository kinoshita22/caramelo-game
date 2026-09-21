extends RefCounted
## The save file's format: building it from the game systems, checking and
## migrating a loaded one, and applying it back. Pure: no files, no nodes.
## SaveManager does the reading and writing.
##
## A save holds IDs and values only, never scene references. Everything read
## back is treated as untrusted: wrong types are rejected and values are
## clamped by the systems' own restore functions.

const SCHEMA_VERSION := 1

## Upgrades from older schemas: version -> Callable(doc) -> doc, each taking
## a save of that version to the next. Empty until the format changes.
static var migrations := {}


static func build(progression: RefCounted, economy: RefCounted, furniture: RefCounted,
		cosmetics: RefCounted, loop: RefCounted, settings: Dictionary, now_unix: float) -> Dictionary:
	var doc := {
		"schema_version": SCHEMA_VERSION,
		"saved_at_unix": now_unix,
		"progression": {
			"level": progression.level,
			"xp": progression.xp,
			"bones": progression.bones,
			"workouts_completed": progression.workouts_completed,
		},
		"economy": economy.snapshot(),
		"furniture": furniture.snapshot(),
		"cosmetics": cosmetics.snapshot(),
		"settings": settings.duplicate(true),
	}
	if loop != null:
		doc["needs"] = {"energy": loop.energy, "satiety": loop.satiety}
	return doc


## Brings an older save up to SCHEMA_VERSION. Returns {"doc"} or {"error"}.
static func migrate(doc: Dictionary) -> Dictionary:
	var version: Variant = doc.get("schema_version")
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return {"error": "save has no schema_version"}
	var v := int(version)
	if v > SCHEMA_VERSION:
		return {"error": "save is from a newer version (%d > %d)" % [v, SCHEMA_VERSION]}
	var current := doc.duplicate(true)
	while v < SCHEMA_VERSION:
		if not migrations.has(v):
			return {"error": "no migration from schema %d" % v}
		current = migrations[v].call(current)
		v += 1
		current["schema_version"] = v
	return {"doc": current}


## Structural check of a migrated save. Values are clamped later, on apply.
static func validate(doc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _is_num(doc.get("saved_at_unix")):
		errors.append("save: saved_at_unix must be a number")
	var p: Variant = doc.get("progression")
	if typeof(p) != TYPE_DICTIONARY:
		errors.append("save: 'progression' must be an object")
	else:
		for key in ["level", "xp", "bones"]:
			if not _is_num(p.get(key)):
				errors.append("save: progression.%s must be a number" % key)
	for section in ["economy", "furniture", "cosmetics", "settings"]:
		if doc.has(section) and typeof(doc[section]) != TYPE_DICTIONARY:
			errors.append("save: '%s' must be an object" % section)
	var needs: Variant = doc.get("needs", {})
	if typeof(needs) != TYPE_DICTIONARY:
		errors.append("save: 'needs' must be an object")
	return errors


## Puts a validated save back into the systems. The loop is optional
## (it does not exist yet at startup; see apply_needs).
static func apply(doc: Dictionary, progression: RefCounted, economy: RefCounted,
		furniture: RefCounted, cosmetics: RefCounted) -> void:
	var p: Dictionary = doc["progression"]
	# The economy first: restoring progression may announce a form change.
	economy.restore(doc.get("economy", {}))
	progression.restore(int(p["level"]), float(p["xp"]), int(p["bones"]), int(p.get("workouts_completed", 0)))
	furniture.restore(doc.get("furniture", {}))
	cosmetics.restore(doc.get("cosmetics", {}))


static func apply_needs(doc: Dictionary, loop: RefCounted) -> void:
	var needs: Dictionary = doc.get("needs", {})
	if _is_num(needs.get("energy")):
		loop.energy = clampf(float(needs["energy"]), 0.0, 100.0)
	if _is_num(needs.get("satiety")):
		loop.satiety = clampf(float(needs["satiety"]), 0.0, 100.0)


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
