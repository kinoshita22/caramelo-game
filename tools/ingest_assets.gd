extends SceneTree
## Byte-for-byte mirror of the original asset packs into the project.
##
## Safe to rerun:
## - Files already present with a matching SHA-256 are skipped.
## - A destination file with a different hash is a conflict: it is never
##   overwritten, and the run fails.
## - Nothing is ever deleted, in the source or the destination.
## - Copies go to "<name>.ingest-tmp", are verified, then renamed into place.
##   A temp file that fails verification is left behind and reported.
##
## Usage (paths are relative to the project root):
##   godot --headless --path caramelo-game --script res://tools/ingest_assets.gd -- \
##       [--source ../00] [--destination assets/source] [--runtime-form 01] \
##       [--report docs/ingestion_report.json]
##
## Exit code 0 = all files mirrored and verified, 1 = any failure or conflict,
## 2 = bad arguments.

const DEFAULTS := {
	"source": "../00",
	"destination": "assets/source",
	"runtime-form": "01",
	"report": "docs/ingestion_report.json",
}
const TEMP_SUFFIX := ".ingest-tmp"
## Files this tool owns inside the destination; never treated as extras.
const DESTINATION_OWN_FILES := [".gdignore"]


func _init() -> void:
	var args := DEFAULTS.duplicate()
	var parsed := _parse_args(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail_args(parsed["error"])
		return
	args.merge(parsed, true)

	var source := _absolute(args["source"])
	var destination := _absolute(args["destination"])
	var report_path := _absolute(args["report"])
	if not DirAccess.dir_exists_absolute(source):
		_fail_args("source directory not found: %s" % source)
		return
	if _is_within(destination, source) or _is_within(source, destination):
		_fail_args("source and destination must not contain each other")
		return
	if _is_within(report_path, source):
		_fail_args("report must not be written inside the source")
		return

	var runtime_form := _resolve_runtime_form(source, args["runtime-form"])
	if runtime_form.has("error"):
		_fail_args(runtime_form["error"])
		return

	# .gdignore goes in first so an editor scan can never import the mirror.
	DirAccess.make_dir_recursive_absolute(destination)
	var gdignore_created := false
	if not FileAccess.file_exists(destination.path_join(".gdignore")):
		_write_text(destination.path_join(".gdignore"), "")
		gdignore_created = true

	var started := Time.get_datetime_string_from_system(true)
	var entries: Array = []
	var counts := {"copied": 0, "skipped_identical": 0, "conflict": 0, "failed": 0}
	var source_files := _walk(source, "")
	for rel in source_files:
		var entry := _ingest_file(source.path_join(rel), destination.path_join(rel), rel)
		counts[entry["status"]] += 1
		entries.append(entry)

	# Re-hash the source afterwards to prove it was not touched mid-run.
	var source_changed: Array = []
	for entry in entries:
		if FileAccess.get_sha256(source.path_join(entry["path"])) != entry["source_sha256"]:
			source_changed.append(entry["path"])

	var extras: Array = []
	var leftover_temps: Array = []
	for rel in _walk(destination, ""):
		if rel in DESTINATION_OWN_FILES:
			continue
		if rel.ends_with(TEMP_SUFFIX):
			leftover_temps.append(rel)
		elif not rel in source_files:
			extras.append(rel)

	var ok: bool = counts["conflict"] == 0 and counts["failed"] == 0 and source_changed.is_empty()
	var report := {
		"tool": "tools/ingest_assets.gd",
		"godot": Engine.get_version_info()["string"],
		"started_utc": started,
		"finished_utc": Time.get_datetime_string_from_system(true),
		"source": source,
		"destination": destination,
		"runtime_form": runtime_form,
		"gdignore_created": gdignore_created,
		"ok": ok,
		"totals": {
			"source_files": source_files.size(),
			"copied": counts["copied"],
			"skipped_identical": counts["skipped_identical"],
			"conflict": counts["conflict"],
			"failed": counts["failed"],
		},
		"source_changed_during_run": source_changed,
		"destination_extra_files": extras,
		"destination_leftover_temp_files": leftover_temps,
		"files": entries,
	}
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	_write_text(report_path, JSON.stringify(report, "\t", false))

	print("Source files: %d  copied: %d  skipped (identical): %d  conflicts: %d  failed: %d" % [
		source_files.size(), counts["copied"], counts["skipped_identical"], counts["conflict"], counts["failed"]])
	print("Runtime form: %s (%s)" % [runtime_form["form"], runtime_form["pack"]])
	for e in entries:
		if e["status"] in ["conflict", "failed"]:
			printerr("  %s: %s — %s" % [e["status"].to_upper(), e["path"], e["detail"]])
	for p in source_changed:
		printerr("  SOURCE CHANGED DURING RUN: ", p)
	for p in extras:
		print("  NOTE: destination file not in source (left untouched): ", p)
	for p in leftover_temps:
		print("  NOTE: leftover temp file (left untouched): ", p)
	print("Report: ", report_path)
	print("RESULT: ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)


func _ingest_file(src: String, dst: String, rel: String) -> Dictionary:
	var entry := {
		"path": rel,
		"bytes": FileAccess.get_file_as_bytes(src).size(),
		"source_sha256": FileAccess.get_sha256(src),
		"destination_sha256": "",
		"status": "",
		"detail": "",
	}
	if entry["source_sha256"] == "":
		return _mark(entry, "failed", "could not read source file")

	if FileAccess.file_exists(dst):
		entry["destination_sha256"] = FileAccess.get_sha256(dst)
		if entry["destination_sha256"] == entry["source_sha256"]:
			return _mark(entry, "skipped_identical", "")
		return _mark(entry, "conflict", "destination exists with a different hash; not overwritten")

	var tmp := dst + TEMP_SUFFIX
	if FileAccess.file_exists(tmp):
		return _mark(entry, "failed", "temp file %s already exists; remove it manually after inspection" % tmp.get_file())
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var err := DirAccess.copy_absolute(src, tmp)
	if err != OK:
		return _mark(entry, "failed", "copy error %s" % error_string(err))
	var tmp_hash := FileAccess.get_sha256(tmp)
	if tmp_hash != entry["source_sha256"]:
		entry["destination_sha256"] = tmp_hash
		return _mark(entry, "failed", "hash mismatch after copy; temp file left at %s" % tmp.get_file())
	# Re-check the final path right before the rename to avoid clobbering a
	# file that appeared while we were copying.
	if FileAccess.file_exists(dst):
		return _mark(entry, "conflict", "destination appeared during copy; temp file left at %s" % tmp.get_file())
	err = DirAccess.rename_absolute(tmp, dst)
	if err != OK:
		return _mark(entry, "failed", "rename error %s; temp file left at %s" % [error_string(err), tmp.get_file()])
	entry["destination_sha256"] = FileAccess.get_sha256(dst)
	if entry["destination_sha256"] != entry["source_sha256"]:
		return _mark(entry, "failed", "hash mismatch after rename")
	return _mark(entry, "copied", "")


## Accepts "1", "01" or "11"; must match exactly one Caramelo_Form_NN_* pack.
func _resolve_runtime_form(source: String, value: String) -> Dictionary:
	if not value.is_valid_int() or int(value) < 1:
		return {"error": "--runtime-form must be a positive form number, got '%s'" % value}
	var prefix := "Caramelo_Form_%02d_" % int(value)
	var matches: Array = Array(DirAccess.get_directories_at(source)).filter(
			func(d: String) -> bool: return d.begins_with(prefix))
	if matches.size() != 1:
		return {"error": "--runtime-form %s matches %d packs in source (expected 1)" % [value, matches.size()]}
	return {"form": "%02d" % int(value), "pack": matches[0]}


## Recursive, sorted list of files relative to root. Includes dotfiles.
func _walk(root: String, rel: String) -> Array:
	var here := root.path_join(rel) if rel != "" else root
	var out: Array = []
	var dir := DirAccess.open(here)
	if dir == null:
		return out
	dir.include_hidden = true
	for f in dir.get_files():
		out.append(rel.path_join(f) if rel != "" else f)
	for d in dir.get_directories():
		out.append_array(_walk(root, rel.path_join(d) if rel != "" else d))
	out.sort()
	return out


func _mark(entry: Dictionary, status: String, detail: String) -> Dictionary:
	entry["status"] = status
	entry["detail"] = detail
	return entry


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size():
		var key := argv[i].trim_prefix("--")
		if not argv[i].begins_with("--") or not DEFAULTS.has(key):
			return {"error": "unknown argument '%s'" % argv[i]}
		if i + 1 >= argv.size():
			return {"error": "missing value for %s" % argv[i]}
		out[key] = argv[i + 1]
		i += 2
	return out


func _fail_args(msg: String) -> void:
	printerr(msg)
	printerr("usage: --source <dir> --destination <dir> --runtime-form <NN> --report <file.json>")
	quit(2)


func _is_within(path: String, root: String) -> bool:
	var p := path.simplify_path().trim_suffix("/") + "/"
	var r := root.simplify_path().trim_suffix("/") + "/"
	return p.begins_with(r)


func _absolute(p: String) -> String:
	if p.begins_with("res://"):
		return ProjectSettings.globalize_path(p).simplify_path()
	if p.is_absolute_path():
		return p.simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(p).simplify_path()


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
