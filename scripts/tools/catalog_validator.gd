extends RefCounted
## Validates the generated runtime metadata in data/.
##
## Pure checks take parsed JSON and return a list of error strings, so tests
## can feed them synthetic data. check_runtime_files() also touches disk
## (hashes and .import settings); it needs the original PNGs, so it is a
## development-time check, not something an exported build can run.

const AssetIO := preload("res://scripts/tools/asset_io.gd")

const EXPECTED_FORMS := 11
const EXPECTED_SLOTS := 33
const SEVERITIES := ["info", "warning", "error"]
const FILES := {
	"catalog": "catalog/asset_catalog.json",
	"forms": "forms/character_forms.json",
	"slots": "animations/animation_slots.json",
	"geometry": "animations/frame_geometry.json",
	"issues": "catalog/known_source_issues.json",
	"layout": "catalog/runtime_layout.json",
}


## Reads every metadata file under data_root. Result has one key per entry
## in FILES plus "errors" for anything missing or not a JSON object.
static func load_data(data_root: String) -> Dictionary:
	var out := {"errors": []}
	for key in FILES:
		var v: Variant = AssetIO.read_json(data_root.path_join(FILES[key]))
		if typeof(v) != TYPE_DICTIONARY:
			out["errors"].append("%s: missing or not a JSON object" % FILES[key])
			v = {}
		out[key] = v
	return out


static func validate(data: Dictionary, check_files: bool) -> Array[String]:
	var errors: Array[String] = []
	errors.assign(data.get("errors", []))
	if not errors.is_empty():
		return errors
	errors.append_array(check_forms(data["forms"]))
	errors.append_array(check_slots(data["slots"]))
	errors.append_array(check_geometry(data["geometry"], data["forms"]))
	errors.append_array(check_catalog(data["catalog"], data["forms"], data["slots"]))
	errors.append_array(check_issues(data["issues"]))
	if check_files:
		errors.append_array(check_runtime_files(data["catalog"], data["layout"]))
	return errors


## Forms 1..11 each once; level ranges start at 1, end at max_level, and
## have no gaps or overlaps; higher forms cover higher levels.
static func check_forms(doc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var forms: Variant = doc.get("forms")
	if typeof(forms) != TYPE_ARRAY:
		return ["character_forms: 'forms' must be an array"]
	if not _is_num(doc.get("max_level")):
		errors.append("character_forms: 'max_level' must be a number")
		return errors
	var max_level := int(doc["max_level"])
	var seen := {}
	var ranges: Array = []
	for f in forms:
		if typeof(f) != TYPE_DICTIONARY or not _is_num(f.get("form")) \
				or not _is_num(f.get("level_min")) or not _is_num(f.get("level_max")):
			errors.append("character_forms: every form needs numeric form, level_min, level_max")
			continue
		var n := int(f["form"])
		if seen.has(n):
			errors.append("character_forms: form %d listed more than once" % n)
		seen[n] = true
		if int(f["level_min"]) > int(f["level_max"]):
			errors.append("character_forms: form %d has level_min > level_max" % n)
		if _is_num(f.get("frame_count")) and int(f["frame_count"]) != EXPECTED_SLOTS:
			errors.append("character_forms: form %d has %d frames, expected %d" % [n, int(f["frame_count"]), EXPECTED_SLOTS])
		ranges.append([int(f["level_min"]), int(f["level_max"]), n])
	for n in range(1, EXPECTED_FORMS + 1):
		if not seen.has(n):
			errors.append("character_forms: form %d missing" % n)
	if seen.size() != EXPECTED_FORMS:
		errors.append("character_forms: %d forms, expected %d" % [seen.size(), EXPECTED_FORMS])
	if ranges.is_empty():
		return errors
	ranges.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if ranges[0][0] != 1:
		errors.append("character_forms: levels start at %d, expected 1" % ranges[0][0])
	if ranges[-1][1] != max_level:
		errors.append("character_forms: levels end at %d, expected %d" % [ranges[-1][1], max_level])
	for i in range(1, ranges.size()):
		var prev: Array = ranges[i - 1]
		var cur: Array = ranges[i]
		if cur[0] <= prev[1]:
			errors.append("character_forms: forms %d and %d overlap at level %d" % [prev[2], cur[2], cur[0]])
		elif cur[0] > prev[1] + 1:
			errors.append("character_forms: gap between forms %d and %d (levels %d-%d)" % [prev[2], cur[2], prev[1] + 1, cur[0] - 1])
		if cur[2] <= prev[2]:
			errors.append("character_forms: form %d covers higher levels than form %d" % [prev[2], cur[2]])
	return errors


## Slots 1..33 each once, with unique non-empty state names.
static func check_slots(doc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var slots: Variant = doc.get("slots")
	if typeof(slots) != TYPE_ARRAY:
		return ["animation_slots: 'slots' must be an array"]
	var seen := {}
	var states := {}
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY or not _is_num(s.get("slot")) \
				or not _is_str(s.get("state")) or not _is_str(s.get("category")):
			errors.append("animation_slots: every slot needs numeric slot and non-empty state and category")
			continue
		var n := int(s["slot"])
		if seen.has(n):
			errors.append("animation_slots: slot %d listed more than once" % n)
		seen[n] = true
		if states.has(s["state"]):
			errors.append("animation_slots: state '%s' used by slots %d and %d" % [s["state"], states[s["state"]], n])
		states[s["state"]] = n
	errors.append_array(_exact_range(seen, EXPECTED_SLOTS, "animation_slots"))
	return errors


## Every form has geometry for slots 1..33 once, and every rectangle and
## anchor lies inside its image.
static func check_geometry(doc: Dictionary, forms_doc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var forms: Variant = doc.get("forms")
	if typeof(forms) != TYPE_ARRAY:
		return ["frame_geometry: 'forms' must be an array"]
	var by_form := {}
	for g in forms:
		if typeof(g) != TYPE_DICTIONARY or not _is_num(g.get("form")) or typeof(g.get("frames")) != TYPE_ARRAY:
			errors.append("frame_geometry: every form needs numeric form and a frames array")
			continue
		var n := int(g["form"])
		if by_form.has(n):
			errors.append("frame_geometry: form %d listed more than once" % n)
		by_form[n] = g
	for f in forms_doc.get("forms", []):
		if typeof(f) == TYPE_DICTIONARY and _is_num(f.get("form")) and not by_form.has(int(f["form"])):
			errors.append("frame_geometry: no geometry for form %d" % int(f["form"]))
	for n in by_form:
		var g: Dictionary = by_form[n]
		var ctx := "frame_geometry form %d" % n
		var canvas: Variant = g.get("canvas")
		if not _is_size(canvas):
			errors.append("%s: canvas must have positive width and height" % ctx)
			canvas = {"width": INF, "height": INF}
		var seen := {}
		for fr in g["frames"]:
			if typeof(fr) != TYPE_DICTIONARY or not _is_num(fr.get("slot")):
				errors.append("%s: frame without a numeric slot" % ctx)
				continue
			var s := int(fr["slot"])
			if seen.has(s):
				errors.append("%s: slot %d listed more than once" % [ctx, s])
			seen[s] = true
			errors.append_array(_check_frame(fr, canvas, "%s slot %d" % [ctx, s]))
		errors.append_array(_exact_range(seen, EXPECTED_SLOTS, ctx))
	return errors


static func _check_frame(fr: Dictionary, canvas: Dictionary, ctx: String) -> Array[String]:
	var errors: Array[String] = []
	var img: Variant = fr.get("image")
	var vis: Variant = fr.get("visible")
	var anchor: Variant = fr.get("anchor")
	if not _is_size(img):
		return ["%s: image size missing or not positive" % ctx]
	if typeof(vis) != TYPE_DICTIONARY or not _is_num(vis.get("x")) or not _is_num(vis.get("y")) or not _is_size(vis):
		return ["%s: visible rect missing or empty" % ctx]
	if typeof(anchor) != TYPE_DICTIONARY or not _is_num(anchor.get("x")) or not _is_num(anchor.get("y")):
		return ["%s: anchor missing" % ctx]
	if vis["x"] < 0 or vis["y"] < 0 or vis["x"] + vis["width"] > img["width"] or vis["y"] + vis["height"] > img["height"]:
		errors.append("%s: visible rect lies outside the image" % ctx)
	if anchor["x"] < 0 or anchor["y"] < 0 or anchor["x"] > img["width"] or anchor["y"] > img["height"]:
		errors.append("%s: anchor lies outside the image" % ctx)
	if vis["width"] > canvas["width"] or vis["height"] > canvas["height"]:
		errors.append("%s: visible rect larger than the form canvas" % ctx)
	var attach: Variant = fr.get("attach")
	if typeof(attach) != TYPE_DICTIONARY:
		errors.append("%s: attach must be an object" % ctx)
	else:
		for point_name in attach:
			var pt: Variant = attach[point_name]
			if typeof(pt) != TYPE_ARRAY or pt.size() != 2 or not _is_num(pt[0]) or not _is_num(pt[1]) \
					or pt[0] < 0 or pt[1] < 0 or pt[0] > img["width"] or pt[1] > img["height"]:
				errors.append("%s: attach point '%s' missing or outside the image" % [ctx, point_name])
	var stable: Variant = fr.get("stable_anchor")
	if typeof(stable) != TYPE_DICTIONARY or not _is_num(stable.get("x")) or not _is_num(stable.get("y")):
		errors.append("%s: stable_anchor missing" % ctx)
	if typeof(fr.get("review_flags")) != TYPE_ARRAY:
		errors.append("%s: review_flags must be an array" % ctx)
	return errors


## Unique IDs, well-formed hashes, one character frame per form and slot,
## slot states consistent with animation_slots, staged forms fully staged.
static func check_catalog(doc: Dictionary, forms_doc: Dictionary, slots_doc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var assets: Variant = doc.get("assets")
	if typeof(assets) != TYPE_ARRAY:
		return ["asset_catalog: 'assets' must be an array"]
	var slot_states := {}
	for s in slots_doc.get("slots", []):
		if typeof(s) == TYPE_DICTIONARY and _is_num(s.get("slot")):
			slot_states[int(s["slot"])] = s.get("state")
	var ids := {}
	var frames := {}  # form -> {slot: asset}
	for a in assets:
		if typeof(a) != TYPE_DICTIONARY or not _is_str(a.get("id")) or not _is_str(a.get("kind")):
			errors.append("asset_catalog: every asset needs string id and kind")
			continue
		var id: String = a["id"]
		if ids.has(id):
			errors.append("asset_catalog: duplicate id %s" % id)
		ids[id] = true
		var sha: Variant = a.get("sha256")
		if not _is_str(sha) or sha.length() != 64 or not sha.is_valid_hex_number():
			errors.append("asset_catalog: %s has an invalid sha256" % id)
		var rp: Variant = a.get("runtime_path")
		if rp != null and (not _is_str(rp) or not rp.begins_with("res://")):
			errors.append("asset_catalog: %s runtime_path must be null or a res:// path" % id)
		if a["kind"] != "character":
			continue
		if not _is_num(a.get("form")) or not _is_num(a.get("slot")):
			errors.append("asset_catalog: character %s needs numeric form and slot" % id)
			continue
		var f := int(a["form"])
		var s := int(a["slot"])
		var per_form: Dictionary = frames.get_or_add(f, {})
		if per_form.has(s):
			errors.append("asset_catalog: form %d slot %d appears more than once (%s, %s)" % [f, s, per_form[s]["id"], id])
		per_form[s] = a
		if slot_states.has(s) and a.get("state") != slot_states[s]:
			errors.append("asset_catalog: %s state '%s' does not match slot %d state '%s'" % [id, a.get("state"), s, slot_states[s]])
	for f in forms_doc.get("forms", []):
		if typeof(f) != TYPE_DICTIONARY or not _is_num(f.get("form")):
			continue
		var n := int(f["form"])
		var per_form: Dictionary = frames.get(n, {})
		errors.append_array(_exact_range(per_form, EXPECTED_SLOTS, "asset_catalog form %d" % n))
		if f.get("staged") == true:
			for s in per_form:
				if per_form[s].get("runtime_path") == null:
					errors.append("asset_catalog: form %d is marked staged but slot %d has no runtime_path" % [n, s])
	return errors


static func check_issues(doc: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var issues: Variant = doc.get("issues")
	if typeof(issues) != TYPE_ARRAY:
		return ["known_source_issues: 'issues' must be an array"]
	var ids := {}
	for i in issues:
		if typeof(i) != TYPE_DICTIONARY or not _is_str(i.get("id")) or not _is_str(i.get("summary")) \
				or not _is_str(i.get("resolution")) or not i.get("severity") in SEVERITIES:
			errors.append("known_source_issues: every issue needs id, summary, resolution and a severity in %s" % [SEVERITIES])
			continue
		if ids.has(i["id"]):
			errors.append("known_source_issues: duplicate id %s" % i["id"])
		ids[i["id"]] = true
	return errors


## Disk checks: each runtime file exists, matches its catalog hash, and has
## the import settings of its profile; no runtime PNG is missing from the
## catalog.
static func check_runtime_files(catalog: Dictionary, layout: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var profiles: Dictionary = layout.get("import_profiles", {})
	var listed := {}
	for a in catalog.get("assets", []):
		var rp: Variant = a.get("runtime_path")
		if rp == null:
			continue
		listed[rp] = true
		if not FileAccess.file_exists(rp):
			errors.append("runtime: %s missing (%s)" % [rp, a["id"]])
			continue
		if FileAccess.get_sha256(rp) != a.get("sha256"):
			errors.append("runtime: %s hash differs from the source" % rp)
		var profile: Dictionary = profiles.get(a.get("import_profile", ""), {})
		if profile.is_empty():
			errors.append("runtime: %s has unknown import profile '%s'" % [rp, a.get("import_profile")])
			continue
		var cfg := ConfigFile.new()
		if cfg.load(rp + ".import") != OK:
			errors.append("runtime: %s.import missing; run the importer (godot --headless --import)" % rp)
			continue
		var params: Dictionary = profile.get("params", {})
		for key in params:
			if String(key).begins_with("_"):
				continue
			var actual: Variant = cfg.get_value("params", key, null)
			if actual == null or AssetIO.json_int(actual) != AssetIO.json_int(params[key]):
				errors.append("runtime: %s import %s is %s, profile '%s' requires %s" % [
					rp, key, actual, a["import_profile"], AssetIO.json_int(params[key])])
	var root: String = layout.get("runtime_root", "")
	for category in (AssetIO.list_dirs(root) if root != "" else []):
		for pack in AssetIO.list_dirs(root.path_join(category)):
			for f in AssetIO.list_files(root.path_join(category).path_join(pack)):
				var p := "%s/%s/%s/%s" % [root, category, pack, f]
				if f.get_extension().to_lower() == "png" and not listed.has(p):
					errors.append("runtime: %s is not in the catalog; rerun tools/build_catalog.gd" % p)
	return errors


static func _exact_range(seen: Dictionary, count: int, ctx: String) -> Array[String]:
	var errors: Array[String] = []
	for n in range(1, count + 1):
		if not seen.has(n):
			errors.append("%s: slot %d missing" % [ctx, n])
	for n in seen:
		if int(n) < 1 or int(n) > count:
			errors.append("%s: slot %d outside 1-%d" % [ctx, int(n), count])
	return errors


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _is_str(v: Variant) -> bool:
	return typeof(v) == TYPE_STRING and v != ""


static func _is_size(v: Variant) -> bool:
	return typeof(v) == TYPE_DICTIONARY and _is_num(v.get("width")) and _is_num(v.get("height")) \
			and v["width"] > 0 and v["height"] > 0
