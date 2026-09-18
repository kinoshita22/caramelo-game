extends SceneTree
## Read-only inventory of the original Caramelo asset packs.
##
## Never writes into the source directory. Opens files for reading only.
##
## Usage:
##   godot --headless --path caramelo-game --script res://tools/asset_inventory.gd -- \
##       --source ../00 --out docs
##
## Outputs <out>/asset_inventory.json and <out>/asset_inventory.md.
## Exit code 0 = no blocking issues, 1 = issues found, 2 = bad arguments.

const EXPECTED_FRAMES_PER_FORM := 33
var PNG_SIGNATURE := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
const COLOR_TYPES := {
	0: "grayscale", 2: "rgb", 3: "indexed", 4: "grayscale_alpha", 6: "rgba",
}
## Asset categories the game design calls for, mapped to pack-name patterns.
const REQUIRED_CATEGORIES := {
	"character": "Caramelo_Form_",
	"environment": "Environment",
	"equipment": "Equipment",
	"food": "Food",
	"ui": "UI",
	"currency": "Currency",
	"button_state": "Button_State",
}

## Byte-identical files that are known and accepted. Each group is sorted.
const ALLOWED_DUPLICATE_GROUPS := [
	["Caramelo_Button_State_Pack/01_button_normal.png",
			"Caramelo_UI_and_Currency_Pack/16_button_primary_blank.png"],
]

var _issues: Array[String] = []
## Known, confirmed deviations. Reported, but they do not fail the run.
var _acknowledged: Array[String] = []


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if not args.has("source") or not args.has("out"):
		printerr("usage: --source <asset dir> --out <report dir>")
		quit(2)
		return
	var source := ProjectSettings.globalize_path(args["source"]) if args["source"].begins_with("res://") \
			else _absolute(args["source"])
	var out := ProjectSettings.globalize_path(args["out"]) if args["out"].begins_with("res://") \
			else _absolute(args["out"])
	if not DirAccess.dir_exists_absolute(source):
		printerr("source directory not found: ", source)
		quit(2)
		return

	var report := _build_report(source)
	DirAccess.make_dir_recursive_absolute(out)
	_write_text(out.path_join("asset_inventory.json"), JSON.stringify(report, "\t", false))
	_write_text(out.path_join("asset_inventory.md"), _to_markdown(report))
	print("Packs: %d  PNGs: %d  Issues: %d" % [
		report["packs"].size(), report["totals"]["png_count"], _issues.size()])
	for issue in _issues:
		print("  ISSUE: ", issue)
	for note in _acknowledged:
		print("  ACKNOWLEDGED: ", note)
	quit(0 if _issues.is_empty() else 1)


func _build_report(source: String) -> Dictionary:
	var packs: Array = []
	var hash_index := {}  # sha256 -> Array of "pack/file"
	var totals := {"file_count": 0, "png_count": 0, "bytes": 0}

	var loose := _list(source, false)
	for f in loose:
		_issue("Loose file outside any pack: %s" % f)

	for pack_name in _list(source, true):
		var pack := _inspect_pack(source.path_join(pack_name), pack_name, hash_index)
		packs.append(pack)
		totals["file_count"] += pack["file_count"]
		totals["png_count"] += pack["png_count"]
		totals["bytes"] += pack["bytes"]

	var duplicates: Array = []
	for h in hash_index:
		if hash_index[h].size() > 1:
			var group: Array = hash_index[h].duplicate()
			group.sort()
			var allowed := group in ALLOWED_DUPLICATE_GROUPS
			duplicates.append({"sha256": h, "files": group, "allowlisted": allowed})
			var msg := "Duplicate content (sha256 %s…): %s" % [h.substr(0, 12), ", ".join(group)]
			if allowed:
				_acknowledged.append(msg + " [allowlisted]")
			else:
				_issue("Unexpected " + msg)

	var coverage := {}
	for category in REQUIRED_CATEGORIES:
		var matched: Array = []
		for pack in packs:
			if REQUIRED_CATEGORIES[category] in pack["name"]:
				matched.append(pack["name"])
		coverage[category] = matched
		if matched.is_empty():
			_issue("No asset pack found for required category '%s'" % category)

	var forms := _check_forms(packs)

	return {
		"source": source,
		"generated_with": "Godot %s" % Engine.get_version_info()["string"],
		"totals": totals,
		"category_coverage": coverage,
		"packs": packs,
		"forms": forms,
		"duplicate_hashes": duplicates,
		"issues": _issues,
		"acknowledged": _acknowledged,
	}


func _inspect_pack(dir: String, pack_name: String, hash_index: Dictionary) -> Dictionary:
	var files := _list(dir, false)
	var pngs: Array = files.filter(func(f: String) -> bool: return f.get_extension().to_lower() == "png")
	var other: Array = files.filter(func(f: String) -> bool: return f.get_extension().to_lower() != "png")
	var manifest_path := dir.path_join("manifest.csv")
	var has_manifest := FileAccess.file_exists(manifest_path)
	var manifest_rows: Array = _read_csv(manifest_path) if has_manifest else []
	if not has_manifest:
		_issue("%s: manifest.csv missing" % pack_name)

	var images: Array = []
	var dims := {}
	var bytes := 0
	for f in pngs:
		var info := _inspect_png(dir.path_join(f))
		info["file"] = f
		images.append(info)
		bytes += info["bytes"]
		var key := "%dx%d" % [info["width"], info["height"]]
		dims[key] = dims.get(key, 0) + 1
		hash_index.get_or_add(info["sha256"], []).append("%s/%s" % [pack_name, f])
		if not info["valid_png"]:
			_issue("%s/%s: not a valid PNG" % [pack_name, f])
		elif not info["has_alpha_channel"]:
			_issue("%s/%s: no alpha channel (color type %s)" % [pack_name, f, info["color_type"]])
	for f in other:
		bytes += FileAccess.get_file_as_bytes(dir.path_join(f)).size()

	var listed: Array = manifest_rows.map(func(r: Dictionary) -> String: return r.get("filename", ""))
	var missing_files: Array = listed.filter(func(f: String) -> bool: return not f in pngs)
	var unlisted_files: Array = pngs.filter(func(f: String) -> bool: return not f in listed)
	for f in missing_files:
		_issue("%s: manifest lists '%s' but the file is missing" % [pack_name, f])
	for f in unlisted_files:
		_issue("%s: '%s' is not listed in manifest" % [pack_name, f])
	if has_manifest and manifest_rows.size() != listed.duplicate().reduce(
			func(acc: Array, f: String) -> Array: return acc if f in acc else acc + [f], []).size():
		_issue("%s: manifest lists a filename more than once" % pack_name)

	return {
		"name": pack_name,
		"file_count": files.size(),
		"png_count": pngs.size(),
		"other_files": other,
		"bytes": bytes,
		"manifest_present": has_manifest,
		"manifest_row_count": manifest_rows.size(),
		"manifest_columns": manifest_rows[0].keys() if not manifest_rows.is_empty() else [],
		"dimensions": dims,
		"all_have_alpha_channel": images.all(func(i: Dictionary) -> bool: return i["has_alpha_channel"]),
		"missing_files": missing_files,
		"unlisted_files": unlisted_files,
		"manifest_rows": manifest_rows,
		"images": images,
	}


## Reads the PNG header directly so the report reflects the file on disk,
## not Godot's decoded/converted copy.
func _inspect_png(path: String) -> Dictionary:
	var data := FileAccess.get_file_as_bytes(path)
	var info := {
		"bytes": data.size(),
		"sha256": FileAccess.get_sha256(path),
		"valid_png": false,
		"width": 0, "height": 0, "bit_depth": 0,
		"color_type": "unknown",
		"has_alpha_channel": false,
		"uses_transparency": "unknown",
	}
	if data.size() < 33 or data.slice(0, 8) != PNG_SIGNATURE or data.slice(12, 16).get_string_from_ascii() != "IHDR":
		return info
	info["valid_png"] = true
	info["width"] = _be32(data, 16)
	info["height"] = _be32(data, 20)
	info["bit_depth"] = data[24]
	var ct: int = data[25]
	info["color_type"] = COLOR_TYPES.get(ct, "unknown(%d)" % ct)
	info["has_alpha_channel"] = ct == 4 or ct == 6 or (ct == 3 and _has_chunk(data, "tRNS"))

	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		info["valid_png"] = false
		return info
	match img.detect_alpha():
		Image.ALPHA_NONE: info["uses_transparency"] = "none"
		Image.ALPHA_BIT: info["uses_transparency"] = "bit"
		Image.ALPHA_BLEND: info["uses_transparency"] = "blend"
	return info


func _check_forms(packs: Array) -> Array:
	var re := RegEx.create_from_string("^Caramelo_Form_(\\d+)_Levels?_([\\d-]+)$")
	var reference_slots: Array = []  # category per sequence, from the first form
	var results: Array = []
	for pack in packs:
		var m := re.search(pack["name"])
		if m == null:
			continue
		var form_no := int(m.get_string(1))
		var levels := m.get_string(2)
		var problems: Array[String] = []
		if pack["png_count"] != EXPECTED_FRAMES_PER_FORM:
			problems.append("has %d PNGs, expected %d" % [pack["png_count"], EXPECTED_FRAMES_PER_FORM])
		if pack["manifest_row_count"] != EXPECTED_FRAMES_PER_FORM:
			problems.append("manifest has %d rows, expected %d" % [pack["manifest_row_count"], EXPECTED_FRAMES_PER_FORM])

		var sequences: Array = []
		var slots: Array = []
		var bad_form_values := {}  # manifest value -> row count
		var bad_level_values := {}
		for row in pack["manifest_rows"]:
			sequences.append(int(row.get("sequence", "0")))
			slots.append(row.get("category", ""))
			if int(row.get("form", "-1")) != form_no:
				bad_form_values[row.get("form")] = bad_form_values.get(row.get("form"), 0) + 1
			if _normalise_levels(row.get("levels", "")) != _normalise_levels(levels):
				bad_level_values[row.get("levels")] = bad_level_values.get(row.get("levels"), 0) + 1
			var expected_prefix := "caramelo_f%02d_l%s_%02d_" % [form_no, levels.to_lower(), int(row.get("sequence", "0"))]
			if not String(row.get("filename", "")).begins_with(expected_prefix):
				problems.append("row %s: filename '%s' does not start with '%s'" % [row.get("sequence"), row.get("filename"), expected_prefix])
		# Folder name is authoritative for form identity, so a wrong manifest
		# 'form' column is a known defect rather than a failure.
		for v in bad_form_values:
			_acknowledged.append("%s: manifest 'form' column is '%s' in %d rows; folder says %d (folder is authoritative)" % [
				pack["name"], v, bad_form_values[v], form_no])
			problems.append("manifest 'form' column is '%s' in %d rows; folder says %d" % [v, bad_form_values[v], form_no])
		for v in bad_level_values:
			problems.append("manifest 'levels' column is '%s' in %d rows; folder says '%s'" % [v, bad_level_values[v], levels])
		var expected_seq: Array = range(1, EXPECTED_FRAMES_PER_FORM + 1)
		var sorted_seq := sequences.duplicate()
		sorted_seq.sort()
		if sorted_seq != expected_seq:
			problems.append("sequence numbers are not exactly 1..%d" % EXPECTED_FRAMES_PER_FORM)
		if reference_slots.is_empty():
			reference_slots = slots
		elif slots != reference_slots:
			problems.append("category-per-slot layout differs from %s" % packs[0]["name"])

		var state_names: Array = pack["manifest_rows"].map(
				func(r: Dictionary) -> String: return "%s/%s" % [r.get("category"), r.get("state")])
		for p in problems:
			if not p.begins_with("manifest 'form' column"):
				_issue("%s: %s" % [pack["name"], p])
		results.append({
			"pack": pack["name"],
			"form": form_no,
			"levels": levels,
			"frame_count": pack["png_count"],
			"exactly_33": pack["png_count"] == EXPECTED_FRAMES_PER_FORM \
					and pack["manifest_row_count"] == EXPECTED_FRAMES_PER_FORM \
					and sorted_seq == expected_seq and pack["missing_files"].is_empty(),
			"states": state_names,
			"problems": problems,
		})
	return results


func _to_markdown(r: Dictionary) -> String:
	var md := PackedStringArray()
	md.append("# Caramelo asset inventory\n")
	md.append("Generated by `tools/asset_inventory.gd` (%s). Source is read-only; regenerate rather than edit.\n" % r["generated_with"])
	md.append("- Source: `%s`" % r["source"])
	md.append("- Packs: %d, files: %d, PNGs: %d, total size: %.1f MiB" % [
		r["packs"].size(), r["totals"]["file_count"], r["totals"]["png_count"], r["totals"]["bytes"] / 1048576.0])
	md.append("- Issues: %d, acknowledged: %d\n" % [r["issues"].size(), r["acknowledged"].size()])

	md.append("## Packs\n")
	md.append("| Asset pack | Files | PNGs | Manifest | Dimensions | Alpha channel | Missing files | Unlisted files |")
	md.append("|---|---:|---:|---|---|---|---|---|")
	for p in r["packs"]:
		var dims := PackedStringArray()
		for d in p["dimensions"]:
			dims.append("%s ×%d" % [d, p["dimensions"][d]])
		md.append("| %s | %d | %d | %s | %s | %s | %s | %s |" % [
			p["name"], p["file_count"], p["png_count"],
			"yes (%d rows)" % p["manifest_row_count"] if p["manifest_present"] else "**no**",
			", ".join(dims), "all" if p["all_have_alpha_channel"] else "**not all**",
			", ".join(p["missing_files"]) if not p["missing_files"].is_empty() else "none",
			", ".join(p["unlisted_files"]) if not p["unlisted_files"].is_empty() else "none"])

	md.append("\n## Category coverage\n")
	md.append("| Category | Pack(s) |")
	md.append("|---|---|")
	for c in r["category_coverage"]:
		var packs: Array = r["category_coverage"][c]
		md.append("| %s | %s |" % [c, ", ".join(packs) if not packs.is_empty() else "**none found**"])

	md.append("\n## Character forms\n")
	md.append("| Form | Levels | Frames | Exactly 33 | Problems |")
	md.append("|---:|---|---:|---|---|")
	for f in r["forms"]:
		md.append("| %d | %s | %d | %s | %s |" % [f["form"], f["levels"], f["frame_count"],
			"yes" if f["exactly_33"] else "**no**",
			"<br>".join(f["problems"]) if not f["problems"].is_empty() else "none"])

	md.append("\n## Duplicate hashes\n")
	if r["duplicate_hashes"].is_empty():
		md.append("None: every file's SHA-256 is unique.")
	for d in r["duplicate_hashes"]:
		md.append("- `%s`%s: %s" % [d["sha256"], " (allowlisted)" if d["allowlisted"] else " **unexpected**", ", ".join(d["files"])])

	md.append("\n## Transparency usage per image\n")
	md.append("| Pack | File | Size | Color type | Transparency used |")
	md.append("|---|---|---|---|---|")
	for p in r["packs"]:
		for i in p["images"]:
			md.append("| %s | %s | %dx%d | %s %d-bit | %s |" % [
				p["name"], i["file"], i["width"], i["height"], i["color_type"], i["bit_depth"], i["uses_transparency"]])

	md.append("\n## All issues\n")
	if r["issues"].is_empty():
		md.append("None.")
	for i in r["issues"]:
		md.append("- %s" % i)

	md.append("\n## Acknowledged (known, not failures)\n")
	if r["acknowledged"].is_empty():
		md.append("None.")
	for i in r["acknowledged"]:
		md.append("- %s" % i)
	return "\n".join(md) + "\n"


func _read_csv(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	var rows: Array = []
	if f == null:
		return rows
	var header := f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() == 1 and line[0].strip_edges() == "":
			continue
		var row := {}
		for i in header.size():
			row[header[i].strip_edges()] = line[i].strip_edges() if i < line.size() else ""
		rows.append(row)
	return rows


func _list(dir: String, dirs: bool) -> Array:
	var names: Array = Array(DirAccess.get_directories_at(dir) if dirs else DirAccess.get_files_at(dir))
	names.sort()
	return names


func _has_chunk(data: PackedByteArray, chunk: String) -> bool:
	var pos := 8
	while pos + 8 <= data.size():
		var length := _be32(data, pos)
		var type := data.slice(pos + 4, pos + 8).get_string_from_ascii()
		if type == chunk:
			return true
		if type == "IDAT" or type == "IEND":
			return false
		pos += 12 + length
	return false


func _be32(data: PackedByteArray, at: int) -> int:
	return (data[at] << 24) | (data[at + 1] << 16) | (data[at + 2] << 8) | data[at + 3]


func _normalise_levels(s: String) -> String:
	var parts := s.split("-")
	return "-".join(Array(parts).map(func(p: String) -> String: return str(int(p))))


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size():
		if argv[i].begins_with("--") and i + 1 < argv.size():
			out[argv[i].substr(2)] = argv[i + 1]
			i += 2
		else:
			i += 1
	return out


func _absolute(p: String) -> String:
	if p.is_absolute_path():
		return p.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)


func _issue(msg: String) -> void:
	_issues.append(msg)
