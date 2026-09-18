extends SceneTree
## Generates the normalized runtime metadata from the source mirror.
##
## Reads assets/source (read-only) and data/catalog/runtime_layout.json.
## Writes:
##   data/catalog/asset_catalog.json
##   data/catalog/known_source_issues.json
##   data/forms/character_forms.json
##   data/animations/animation_slots.json
##   data/animations/frame_geometry.json
##
## Output is deterministic (no timestamps, sorted keys) so reruns only
## change files when the inputs change. Regenerate instead of hand-editing.
##
## Usage:
##   godot --headless --path caramelo-game --script res://tools/build_catalog.gd -- \
##       [--source assets/source] [--layout data/catalog/runtime_layout.json] \
##       [--data data] [--alpha-threshold 32]
##
## Exit code 0 = written, 1 = source problem (nothing written), 2 = bad arguments.

const AssetIO := preload("res://scripts/tools/asset_io.gd")

const DEFAULTS := {
	"source": "assets/source",
	"layout": "data/catalog/runtime_layout.json",
	"data": "data",
	"alpha-threshold": "32",
}
const SCHEMA_VERSION := 1
const GENERATOR := "tools/build_catalog.gd"
const MAX_LEVEL := 100

## Canonical slot table (master plan §6). Slot number is the identity;
## the state name is the canonical label.
const SLOTS := [
	["wardrobe", "wardrobe_base"],
	["wardrobe", "wardrobe_dressed_preview"],
	["idle", "idle_neutral"],
	["idle", "idle_breath"],
	["idle", "idle_blink"],
	["idle", "idle_tail_high"],
	["idle", "idle_tail_low"],
	["idle", "idle_relaxed_reset"],
	["workout", "workout_dumbbells_lowered"],
	["workout", "workout_dumbbells_low_intermediate"],
	["workout", "workout_dumbbells_upper_intermediate"],
	["workout", "workout_dumbbells_raised"],
	["eating", "eating_closed_mouth_chew"],
	["eating", "eating_open_mouth_tail_a"],
	["eating", "eating_open_mouth_tail_b"],
	["eating", "eating_swallow"],
	["eating", "eating_lip_lick"],
	["hunger", "hunger_stomach_rumble"],
	["hunger", "hunger_weak_shiver"],
	["recovery", "recovery_fatigued_sweat"],
	["recovery", "recovery_heavy_pant"],
	["sleep", "sleep_yawn"],
	["sleep", "sleep_lowering"],
	["sleep", "sleep_exhale"],
	["sleep", "sleep_inhale"],
	["wake", "wake_head_lift"],
	["wake", "wake_seated_stretch"],
	["celebration", "celebration_proud_recovery"],
	["celebration", "celebration_victory_jump"],
	["reward", "reward_bone_discovery"],
	["reward", "reward_bone_happy_hold"],
	["pre_evolution", "pre_evolution_confident_charge"],
	["pre_evolution", "pre_evolution_power_surge"],
]

## Form themes (master plan §5).
const THEMES := {
	1: "Base", 2: "Natural progression", 3: "Natural progression",
	4: "Natural progression", 5: "Natural progression", 6: "Natural progression",
	7: "Natural progression", 8: "Peak natural progression", 9: "Golden energy",
	10: "Earth and stone", 11: "Cosmic",
}

## Slots flagged for manual review regardless of measurements.
const SLOT_REVIEW_FLAGS := {
	1: ["wardrobe"], 2: ["wardrobe"],
	23: ["horizontal_sleep"], 24: ["horizontal_sleep"], 25: ["horizontal_sleep"],
	29: ["airborne"],
	32: ["effect_heavy"], 33: ["effect_heavy"],
}
const REVIEW_FLAG_MEANINGS := {
	"wardrobe": "Wardrobe pose; framing may differ from gameplay frames.",
	"horizontal_sleep": "Lying pose; must align to the sleeping mat, not the standing ground line.",
	"airborne": "Character is off the ground; a bottom anchor would pull him down to the floor.",
	"effect_heavy": "Energy effects extend the visible bounds beyond the body.",
	"landscape_bounds": "Visible content is wider than tall.",
	"touches_edge": "Visible content reaches the image edge; art may be cropped.",
	"faint_fringe": "Faint but visible pixels (alpha 8 up to the threshold) extend noticeably beyond the bounds: glow, shadow or haze.",
}
## Faint pixels beyond the thresholded bounds by more than this many pixels
## on any side set the faint_fringe flag.
const FAINT_FRINGE_PX := 8
## Lowest alpha counted as faintly visible. The source images carry
## near-invisible noise at alpha 1-7 far outside the art; bounds are stable
## from alpha 8 to 64, which is why the default threshold is 32.
const FRINGE_ALPHA := 8

var _errors: Array[String] = []


func _init() -> void:
	var args := AssetIO.parse_args(OS.get_cmdline_user_args(), DEFAULTS)
	if args.has("error") or not String(args["alpha-threshold"]).is_valid_int():
		printerr(args.get("error", "--alpha-threshold must be an integer"))
		quit(2)
		return
	var threshold := int(args["alpha-threshold"])
	if threshold < 1 or threshold > 255:
		printerr("--alpha-threshold must be 1-255")
		quit(2)
		return
	var source := AssetIO.absolute(args["source"])
	var data_root := AssetIO.absolute(args["data"])
	var layout: Variant = AssetIO.read_json(AssetIO.absolute(args["layout"]))
	if not DirAccess.dir_exists_absolute(source) or typeof(layout) != TYPE_DICTIONARY:
		printerr("source directory or runtime layout missing")
		quit(2)
		return

	var assets := _scan(source, layout, threshold)
	if not _errors.is_empty():
		for e in _errors:
			printerr("ERROR: ", e)
		printerr("Nothing written.")
		quit(1)
		return

	var char_assets: Array = assets.filter(func(a: Dictionary) -> bool: return a["kind"] == "character")
	var forms := _build_forms(char_assets)
	var outputs := {
		"catalog/asset_catalog.json": _envelope({
			"alpha_threshold": threshold,
			"source_root": args["source"],
			"assets": assets.map(func(a: Dictionary) -> Dictionary: return _public(a)),
		}),
		"forms/character_forms.json": _envelope({"max_level": MAX_LEVEL, "forms": forms}),
		"animations/animation_slots.json": _envelope(_build_slots()),
		"animations/frame_geometry.json": _envelope(_build_geometry(char_assets, threshold)),
		"catalog/known_source_issues.json": _envelope({"issues": _build_issues(assets)}),
	}
	for rel in outputs:
		var err := AssetIO.write_json(data_root.path_join(rel), outputs[rel])
		if err != OK:
			printerr("could not write %s: %s" % [rel, error_string(err)])
			quit(1)
			return
		print("wrote data/", rel)
	var staged := assets.filter(func(a: Dictionary) -> bool: return a["runtime_path"] != null).size()
	print("Assets: %d (character frames: %d, staged at runtime: %d)" % [assets.size(), char_assets.size(), staged])
	quit(0)


func _scan(source: String, layout: Dictionary, threshold: int) -> Array:
	var assets: Array = []
	var form_re := RegEx.create_from_string("^Caramelo_Form_(\\d+)_Levels?_(\\d+)(?:-(\\d+))?$")
	var ids := {}
	for pack in AssetIO.list_dirs(source):
		var entry := AssetIO.layout_for_pack(layout, pack)
		if entry.is_empty():
			_errors.append("%s: no entry in runtime_layout.json" % pack)
			continue
		var rows := {}
		for row in AssetIO.read_csv(source.path_join(pack).path_join("manifest.csv")):
			rows[row.get("filename", "")] = row
		var form_info := {}
		if entry["kind"] == "character":
			var m := form_re.search(pack)
			if m == null:
				_errors.append("%s: character pack name does not match Caramelo_Form_NN_Levels_A-B" % pack)
				continue
			var levels := m.get_string(2) + ("-" + m.get_string(3) if m.get_string(3) != "" else "")
			form_info = {
				"form": int(m.get_string(1)),
				"level_min": int(m.get_string(2)),
				"level_max": int(m.get_string(3)) if m.get_string(3) != "" else int(m.get_string(2)),
				"prefix": "caramelo_f%s_l%s_" % [m.get_string(1), levels.to_lower()],
			}
		var runtime_dir: String = "%s/%s/%s" % [layout["runtime_root"], entry["runtime_category"], pack]
		for file in AssetIO.list_files(source.path_join(pack)):
			if file.get_extension().to_lower() != "png":
				continue
			var a := _describe(source, pack, file, entry, rows.get(file, {}), form_info, threshold)
			if a.is_empty():
				continue
			var runtime_path := runtime_dir.path_join(file)
			a["runtime_path"] = runtime_path if FileAccess.file_exists(runtime_path) else null
			if ids.has(a["id"]):
				_errors.append("duplicate asset id %s (%s and %s)" % [a["id"], ids[a["id"]], a["source_path"]])
			ids[a["id"]] = a["source_path"]
			assets.append(a)
	return assets


func _describe(source: String, pack: String, file: String, entry: Dictionary, row: Dictionary,
		form_info: Dictionary, threshold: int) -> Dictionary:
	var path := source.path_join(pack).path_join(file)
	if row.is_empty():
		_errors.append("%s/%s: not listed in manifest.csv" % [pack, file])
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_errors.append("%s/%s: could not decode image" % [pack, file])
		return {}
	var bounds := AssetIO.visible_bounds(img, threshold)
	var any_alpha := AssetIO.visible_bounds(img, FRINGE_ALPHA)
	var a := {
		"kind": entry["kind"],
		"pack": pack,
		"file": file,
		"source_path": "%s/%s" % [pack, file],
		"sha256": FileAccess.get_sha256(path),
		"bytes": FileAccess.get_file_as_bytes(path).size(),
		"image": {"width": img.get_width(), "height": img.get_height()},
		"visible": AssetIO.rect_dict(bounds),
		"anchor": {"x": bounds.position.x + bounds.size.x / 2.0, "y": bounds.end.y},
		"import_profile": entry["import_profile"],
		# Internal fields (leading underscore) feed the issue and geometry
		# builders and are stripped from the catalog.
		"_any_alpha": any_alpha,
		"_bounds": bounds,
		"_manifest": row,
	}
	if bounds.size == Vector2i.ZERO:
		_errors.append("%s/%s: no pixel reaches alpha %d" % [pack, file, threshold])

	if entry["kind"] != "character":
		a["id"] = "%s.%s" % [entry["kind"], AssetIO.strip_sequence(file)]
		a["sequence"] = int(row.get("sequence", "0"))
		var manifest := {}
		for k in row:
			if not k in ["sequence", "filename"]:
				manifest[k] = row[k]
		a["manifest"] = manifest
		return a

	# Character frame: form from folder + filename prefix, slot from filename.
	var prefix: String = form_info["prefix"]
	if not file.begins_with(prefix):
		_errors.append("%s/%s: filename does not start with folder prefix '%s'" % [pack, file, prefix])
		return {}
	var rest := file.trim_prefix(prefix).get_basename()
	var slot_str := rest.get_slice("_", 0)
	var slot := int(slot_str) if slot_str.is_valid_int() else 0
	if slot < 1 or slot > SLOTS.size():
		_errors.append("%s/%s: slot number '%s' outside 1-%d" % [pack, file, slot_str, SLOTS.size()])
		return {}
	if row.has("sequence") and int(row["sequence"]) != slot:
		_errors.append("%s/%s: manifest sequence %s disagrees with filename slot %d" % [pack, file, row["sequence"], slot])
	a["id"] = "character.f%02d.s%02d" % [form_info["form"], slot]
	a["form"] = form_info["form"]
	a["slot"] = slot
	a["category"] = SLOTS[slot - 1][0]
	a["state"] = SLOTS[slot - 1][1]
	a["description"] = row.get("description", "")
	a["_level_min"] = form_info["level_min"]
	a["_level_max"] = form_info["level_max"]
	a["_filename_suffix"] = rest.trim_prefix(slot_str + "_")
	return a


func _build_forms(char_assets: Array) -> Array:
	var by_form := {}
	for a in char_assets:
		by_form.get_or_add(a["form"], []).append(a)
	var numbers := by_form.keys()
	numbers.sort()
	var forms: Array = []
	for n in numbers:
		var frames: Array = by_form[n]
		var first: Dictionary = frames[0]
		var staged: bool = frames.all(func(a: Dictionary) -> bool: return a["runtime_path"] != null)
		forms.append({
			"form": n,
			"id": "form_%02d" % n,
			"level_min": first["_level_min"],
			"level_max": first["_level_max"],
			"theme": THEMES.get(n, ""),
			"source_pack": first["pack"],
			"frame_count": frames.size(),
			"staged": staged,
			"runtime_dir": String(first["runtime_path"]).get_base_dir() if staged else null,
		})
	return forms


func _build_slots() -> Dictionary:
	var slots: Array = []
	var categories: Array = []
	for i in SLOTS.size():
		slots.append({"slot": i + 1, "category": SLOTS[i][0], "state": SLOTS[i][1]})
		if not SLOTS[i][0] in categories:
			categories.append(SLOTS[i][0])
	return {"slot_count": SLOTS.size(), "categories": categories, "slots": slots}


func _build_geometry(char_assets: Array, threshold: int) -> Dictionary:
	var by_form := {}
	for a in char_assets:
		by_form.get_or_add(a["form"], []).append(a)
	var numbers := by_form.keys()
	numbers.sort()
	var forms: Array = []
	for n in numbers:
		var frames: Array = by_form[n]
		frames.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["slot"] < y["slot"])
		var canvas := Vector2i.ZERO
		var max_image := Vector2i.ZERO
		var out_frames: Array = []
		for a in frames:
			var b: Rect2i = a["_bounds"]
			canvas = canvas.max(b.size)
			max_image = max_image.max(Vector2i(a["image"]["width"], a["image"]["height"]))
			out_frames.append({
				"slot": a["slot"],
				"image": a["image"],
				"visible": a["visible"],
				"anchor": a["anchor"],
				"review_flags": _review_flags(a),
			})
		forms.append({
			"form": n,
			"canvas": {"width": canvas.x, "height": canvas.y},
			"max_image": {"width": max_image.x, "height": max_image.y},
			"frames": out_frames,
		})
	return {
		"alpha_threshold": threshold,
		"threshold_note": "Visible bounds are stable for alpha thresholds 8-64 across the sampled frames; alpha 1-7 is invisible noise and is ignored.",
		"anchor_rule": "bottom_center_of_visible_bounds",
		"coordinates": "Source image pixels; origin top-left; y down. Place a frame so its anchor sits on the character's ground point: Sprite2D with centered=false and offset = -anchor.",
		"canvas_rule": "Per form: the largest visible-bounds width and height across its 33 frames.",
		"review_flag_meanings": REVIEW_FLAG_MEANINGS,
		"forms": forms,
	}


func _review_flags(a: Dictionary) -> Array:
	var flags: Array = SLOT_REVIEW_FLAGS.get(a["slot"], []).duplicate()
	var b: Rect2i = a["_bounds"]
	var any: Rect2i = a["_any_alpha"]
	if b.size.x > b.size.y:
		flags.append("landscape_bounds")
	if b.position.x == 0 or b.position.y == 0 or b.end.x == a["image"]["width"] or b.end.y == a["image"]["height"]:
		flags.append("touches_edge")
	if b.position.x - any.position.x > FAINT_FRINGE_PX or b.position.y - any.position.y > FAINT_FRINGE_PX \
			or any.end.x - b.end.x > FAINT_FRINGE_PX or any.end.y - b.end.y > FAINT_FRINGE_PX:
		flags.append("faint_fringe")
	return flags


func _build_issues(assets: Array) -> Array:
	var chars: Array = assets.filter(func(a: Dictionary) -> bool: return a["kind"] == "character")
	var issues: Array = []

	# 1. Manifest form column disagrees with the folder.
	var wrong_form := {}  # pack -> {value, rows}
	for a in chars:
		var v: String = a["_manifest"].get("form", "")
		if v != "" and int(v) != a["form"]:
			var e: Dictionary = wrong_form.get_or_add(a["pack"], {"pack": a["pack"], "folder_form": a["form"], "manifest_values": [], "rows": 0})
			if not v in e["manifest_values"]:
				e["manifest_values"].append(v)
			e["rows"] += 1
	if not wrong_form.is_empty():
		issues.append({
			"id": "manifest_form_column_wrong",
			"severity": "warning",
			"summary": "Manifest 'form' column disagrees with the folder name.",
			"resolution": "Ignored. Form identity comes from the folder name and filename prefix.",
			"details": _sorted_values(wrong_form),
		})

	# 2. Manifest category/state and 3. filename suffix differ from canonical.
	var manifest_diff := {}
	var suffix_diff := {}
	for a in chars:
		var m: Dictionary = a["_manifest"]
		var manifest_name := "%s/%s" % [m.get("category", ""), m.get("state", "")]
		var canonical_name := "%s/%s" % [a["category"], a["state"].trim_prefix(a["category"] + "_")]
		if manifest_name != canonical_name:
			var key := "%02d|%s" % [a["slot"], manifest_name]
			manifest_diff.get_or_add(key, {"slot": a["slot"], "canonical_state": a["state"],
					"canonical_category": a["category"], "manifest": manifest_name, "forms": []})["forms"].append(a["form"])
		if a["_filename_suffix"] != a["state"]:
			var key := "%02d|%s" % [a["slot"], a["_filename_suffix"]]
			suffix_diff.get_or_add(key, {"slot": a["slot"], "canonical_state": a["state"],
					"filename_suffix": a["_filename_suffix"], "forms": []})["forms"].append(a["form"])
	if not manifest_diff.is_empty():
		issues.append({
			"id": "manifest_names_differ_from_canonical",
			"severity": "info",
			"summary": "Manifest category/state for some slots differs from the canonical slot table.",
			"resolution": "Ignored. Slot number is authoritative; names come from animation_slots.json.",
			"details": _sorted_values(manifest_diff),
		})
	if not suffix_diff.is_empty():
		issues.append({
			"id": "filename_suffix_differs_from_canonical",
			"severity": "info",
			"summary": "Descriptive filename suffixes differ from canonical state names (two naming schemes).",
			"resolution": "Ignored. Suffixes are advisory; slot number is authoritative.",
			"details": _sorted_values(suffix_diff),
		})

	# 4. Byte-identical files.
	var by_hash := {}
	for a in assets:
		by_hash.get_or_add(a["sha256"], []).append(a["source_path"])
	var dupes: Array = []
	for h in by_hash:
		if by_hash[h].size() > 1:
			dupes.append({"sha256": h, "files": by_hash[h]})
	if not dupes.is_empty():
		issues.append({
			"id": "duplicate_content",
			"severity": "info",
			"summary": "Some files are byte-identical.",
			"resolution": "Both copies kept with separate IDs. The button-state/UI-pack pair is expected.",
			"details": dupes,
		})

	# 5. Frame sizes vary inside a form.
	var sizes := {}
	for a in chars:
		var k := "%dx%d" % [a["image"]["width"], a["image"]["height"]]
		var per_form: Dictionary = sizes.get_or_add(a["form"], {})
		per_form[k] = per_form.get(k, 0) + 1
	var size_details: Array = []
	for f in sizes:
		if sizes[f].size() > 1:
			size_details.append({"form": f, "image_sizes": sizes[f]})
	if not size_details.is_empty():
		size_details.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["form"] < y["form"])
		issues.append({
			"id": "variable_frame_dimensions",
			"severity": "info",
			"summary": "Frame image sizes vary within a form.",
			"resolution": "Images unchanged. frame_geometry.json anchors align frames.",
			"details": size_details,
		})

	# 6. Frames needing a human look.
	var flagged := {}
	for a in chars:
		for flag in _review_flags(a):
			flagged.get_or_add(flag, []).append(a["id"])
	if not flagged.is_empty():
		var details: Array = []
		var flags := flagged.keys()
		flags.sort()
		for flag in flags:
			details.append({"flag": flag, "meaning": REVIEW_FLAG_MEANINGS[flag], "count": flagged[flag].size(), "frames": flagged[flag]})
		issues.append({
			"id": "frames_flagged_for_review",
			"severity": "warning",
			"summary": "Frames whose automatic anchor needs manual review.",
			"resolution": "Review before Phase 4 animation work; record manual anchor overrides in data, never edit the images.",
			"details": details,
		})
	return issues


func _sorted_values(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys.map(func(k: Variant) -> Variant: return d[k])


## Drops internal fields (leading underscore).
func _public(a: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		if not String(k).begins_with("_"):
			out[k] = a[k]
	return out


func _envelope(body: Dictionary) -> Dictionary:
	body["schema_version"] = SCHEMA_VERSION
	body["generated_by"] = GENERATOR
	return body
