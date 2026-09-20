extends RefCounted
## Static file, JSON, CSV and image helpers shared by the headless tools and
## the catalog validator. Load with preload(); no class_name so tools run
## without a global class cache.

const PNG_SIGNATURE_HEX := "89504e470d0a1a0a"


## Merges "--key value" pairs into a copy of defaults. Unknown keys and
## missing values return {"error": message}.
static func parse_args(argv: PackedStringArray, defaults: Dictionary) -> Dictionary:
	var out := defaults.duplicate()
	var i := 0
	while i < argv.size():
		var key := argv[i].trim_prefix("--")
		if not argv[i].begins_with("--") or not defaults.has(key):
			return {"error": "unknown argument '%s'" % argv[i]}
		if i + 1 >= argv.size():
			return {"error": "missing value for %s" % argv[i]}
		out[key] = argv[i + 1]
		i += 2
	return out


## Resolves res://, absolute, or project-relative paths to an absolute path.
static func absolute(p: String) -> String:
	if p.begins_with("res://"):
		return ProjectSettings.globalize_path(p).simplify_path()
	if p.is_absolute_path():
		return p.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


static func is_within(path: String, root: String) -> bool:
	var p := path.simplify_path().trim_suffix("/") + "/"
	var r := root.simplify_path().trim_suffix("/") + "/"
	return p.begins_with(r)


static func list_dirs(dir: String) -> Array:
	var names := Array(DirAccess.get_directories_at(dir))
	names.sort()
	return names


static func list_files(dir: String) -> Array:
	var names := Array(DirAccess.get_files_at(dir))
	names.sort()
	return names


## Rows as dictionaries keyed by trimmed header names. Blank lines skipped.
static func read_csv(path: String) -> Array:
	var rows: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
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


## Returns the parsed value, or null if the file is missing or invalid.
static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("%s: JSON parse error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Stable output: tab indent, sorted keys, trailing newline.
static func write_json(path: String, data: Variant) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t", true) + "\n")
	return OK


static func is_png(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	return f != null and f.get_buffer(8).hex_encode() == PNG_SIGNATURE_HEX


## "01_floating_island_base.png" -> "floating_island_base"
static func strip_sequence(filename: String) -> String:
	var base := filename.get_basename()
	var parts := base.split("_", false, 1)
	if parts.size() == 2 and parts[0].is_valid_int():
		return parts[1]
	return base


## Smallest rectangle containing every pixel with alpha >= threshold (0-255).
## Returns an empty Rect2i when no pixel qualifies.
##
## Starts from Image.get_used_rect() (alpha > 0, done natively) and only
## scans inward from its edges, so cost stays near the size of the faint
## fringe rather than the whole image.
static func visible_bounds(img: Image, threshold: int) -> Rect2i:
	var used := img.get_used_rect()
	if used.size == Vector2i.ZERO or threshold <= 1:
		return used
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var w := img.get_width()
	var top := used.position.y
	var bottom := used.end.y - 1
	var left := used.position.x
	var right := used.end.x - 1
	while top <= bottom and not _row_has(data, w, top, left, right, threshold):
		top += 1
	if top > bottom:
		return Rect2i()
	while not _row_has(data, w, bottom, left, right, threshold):
		bottom -= 1
	while not _col_has(data, w, left, top, bottom, threshold):
		left += 1
	while not _col_has(data, w, right, top, bottom, threshold):
		right -= 1
	return Rect2i(left, top, right - left + 1, bottom - top + 1)


static func _row_has(data: PackedByteArray, w: int, y: int, x0: int, x1: int, t: int) -> bool:
	var i := (y * w + x0) * 4 + 3
	for x in range(x0, x1 + 1):
		if data[i] >= t:
			return true
		i += 4
	return false


static func _col_has(data: PackedByteArray, w: int, x: int, y0: int, y1: int, t: int) -> bool:
	var i := (y0 * w + x) * 4 + 3
	var stride := w * 4
	for y in range(y0, y1 + 1):
		if data[i] >= t:
			return true
		i += stride
	return false


## JSON parses every number as float; turn whole floats back into ints.
static func json_int(v: Variant) -> Variant:
	if typeof(v) == TYPE_FLOAT and is_equal_approx(v, floorf(v)):
		return int(v)
	return v


static func rect_dict(r: Rect2i) -> Dictionary:
	return {"x": r.position.x, "y": r.position.y, "width": r.size.x, "height": r.size.y}


## Pack entry from runtime_layout.json whose match_prefix fits pack_name.
static func layout_for_pack(layout: Dictionary, pack_name: String) -> Dictionary:
	for entry in layout.get("packs", []):
		var prefix: String = entry.get("match_prefix", "")
		if prefix != "" and pack_name.begins_with(prefix):
			return entry
	return {}


## Contents for a .import sidecar that pins the given importer params.
## Godot fills in uid, paths and remaining defaults on first import and
## keeps these params on every reimport.
static func import_sidecar(params: Dictionary) -> String:
	var lines := PackedStringArray(["[remap]", "", "importer=\"texture\"", "type=\"CompressedTexture2D\"", "", "[params]", ""])
	var keys := params.keys()
	keys.sort()
	for k in keys:
		if not String(k).begins_with("_"):
			lines.append("%s=%s" % [k, var_to_str(json_int(params[k]))])
	return "\n".join(lines) + "\n"


## Silhouette of an image as horizontal runs per row, measured from `anchor`
## after downscaling by `factor`. Used to register animation frames against
## each other. Returns {"rows": {row: PackedInt32Array [x0, x1, ...]}, "area": int}.
static func silhouette_runs(img: Image, anchor: Vector2, factor: int, threshold: int) -> Dictionary:
	var small := img.duplicate() as Image
	if small.get_format() != Image.FORMAT_RGBA8:
		small.convert(Image.FORMAT_RGBA8)
	small.resize(maxi(1, img.get_width() / factor), maxi(1, img.get_height() / factor), Image.INTERPOLATE_BILINEAR)
	var w := small.get_width()
	var data := small.get_data()
	var ax := roundi(anchor.x / factor)
	var ay := roundi(anchor.y / factor)
	var rows := {}
	var area := 0
	for y in small.get_height():
		var runs := PackedInt32Array()
		var start := -1
		var i := y * w * 4 + 3
		for x in w:
			var on := data[i] >= threshold
			if on and start < 0:
				start = x
			elif not on and start >= 0:
				runs.append_array([start - ax, x - ax])
				area += x - start
				start = -1
			i += 4
		if start >= 0:
			runs.append_array([start - ax, w - ax])
			area += w - start
		if not runs.is_empty():
			rows[y - ay] = runs
	return {"rows": rows, "area": area}


## Horizontal shift (in downscaled pixels) that best overlaps silhouette `b`
## onto `a`, searching -max_shift..max_shift. Returns {"shift", "iou"}.
static func best_shift(a: Dictionary, b: Dictionary, max_shift: int) -> Dictionary:
	var best := {"shift": 0, "iou": -1.0}
	var tried := {}
	# Coarse pass in steps of 2, then refine around the best.
	for s in range(-max_shift, max_shift + 1, 2):
		best = _better(best, s, _iou(a, b, s))
		tried[s] = true
	var centre: int = best["shift"]
	for s in [centre - 1, centre + 1]:
		if absi(s) <= max_shift and not tried.has(s):
			best = _better(best, s, _iou(a, b, s))
	return best


static func _better(best: Dictionary, s: int, iou: float) -> Dictionary:
	# Ties prefer the smaller shift so identical frames stay put.
	if iou > best["iou"] + 1e-9 or (is_equal_approx(iou, best["iou"]) and absi(s) < absi(best["shift"])):
		return {"shift": s, "iou": iou}
	return best


static func _iou(a: Dictionary, b: Dictionary, s: int) -> float:
	var inter := 0
	var ra_rows: Dictionary = a["rows"]
	var rb_rows: Dictionary = b["rows"]
	for row in ra_rows:
		if not rb_rows.has(row):
			continue
		var ra: PackedInt32Array = ra_rows[row]
		var rb: PackedInt32Array = rb_rows[row]
		for i in range(0, ra.size(), 2):
			for j in range(0, rb.size(), 2):
				var lo := maxi(ra[i], rb[j] + s)
				var hi := mini(ra[i + 1], rb[j + 1] + s)
				if hi > lo:
					inter += hi - lo
	var union: int = a["area"] + b["area"] - inter
	return float(inter) / union if union > 0 else 0.0
