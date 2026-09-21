extends RefCounted
## The save file on disk: atomic writes with a backup, and loading with
## fallback. No autoloads, so tests can drive it directly.
##
## Writing: the new save goes to a temp file, is read back and checked, the
## old save becomes the backup, then the temp file takes its place. Loading:
## the main file, then the backup; a file that fails to load is renamed
## aside (never deleted); if both fail the result is a fresh start.

const SaveData := preload("res://scripts/systems/save_data.gd")

var path := "user://save.json"


func _init(file_path: String = "user://save.json") -> void:
	path = file_path


func backup_path() -> String:
	return path.get_basename() + ".bak.json"


## Returns "" on success or an error message.
func write(doc: Dictionary) -> String:
	var tmp := path + ".tmp"
	DirAccess.make_dir_recursive_absolute(_abs(path).get_base_dir())
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "cannot write %s: %s" % [tmp, error_string(FileAccess.get_open_error())]
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	var check := parse(tmp)
	if not check.has("doc"):
		return "written save did not read back: %s" % check.get("error", "")
	var backup := backup_path()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(_abs(backup))
		var moved := DirAccess.rename_absolute(_abs(path), _abs(backup))
		if moved != OK:
			return "cannot keep the previous save as backup: %s" % error_string(moved)
	var placed := DirAccess.rename_absolute(_abs(tmp), _abs(path))
	if placed != OK:
		return "cannot move the new save into place: %s" % error_string(placed)
	return ""


## {"status": "fresh" | "loaded" | "backup" | "fresh_after_corrupt",
##  "doc"?: Dictionary, "errors": Array[String]}
func read() -> Dictionary:
	var errs: Array[String] = []
	var main_exists := FileAccess.file_exists(path)
	var backup_exists := FileAccess.file_exists(backup_path())
	if not main_exists and not backup_exists:
		return {"status": "fresh", "errors": errs}
	if main_exists:
		var main := parse(path)
		if main.has("doc"):
			return {"status": "loaded", "doc": main["doc"], "errors": errs}
		errs.append("save unreadable (%s); kept as %s" % [main["error"], _set_aside(path)])
	if backup_exists:
		var backup := parse(backup_path())
		if backup.has("doc"):
			return {"status": "backup", "doc": backup["doc"], "errors": errs}
		errs.append("backup unreadable (%s); kept as %s" % [backup["error"], _set_aside(backup_path())])
	return {"status": "fresh_after_corrupt", "errors": errs}


## Parses, migrates and validates one file. {"doc"} or {"error"}.
static func parse(file: String) -> Dictionary:
	if not FileAccess.file_exists(file):
		return {"error": "missing"}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(file)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "not valid JSON"}
	var migrated := SaveData.migrate(json.data)
	if migrated.has("error"):
		return migrated
	var problems := SaveData.validate(migrated["doc"])
	if not problems.is_empty():
		return {"error": problems[0]}
	return {"doc": migrated["doc"]}


func _set_aside(file: String) -> String:
	var aside := "%s.corrupt-%d.json" % [file.get_basename(), int(Time.get_unix_time_from_system())]
	DirAccess.rename_absolute(_abs(file), _abs(aside))
	return aside


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)
