extends SceneTree
## Validates data/ metadata and, unless --files no, the runtime assets on disk.
##
## Usage:
##   godot --headless --path caramelo-game --script res://tools/validate_catalog.gd -- \
##       [--data data] [--files yes|no]
##
## Exit code 0 = valid, 1 = errors found, 2 = bad arguments.

const AssetIO := preload("res://scripts/tools/asset_io.gd")
const CatalogValidator := preload("res://scripts/tools/catalog_validator.gd")

const DEFAULTS := {"data": "data", "files": "yes"}


func _init() -> void:
	var args := AssetIO.parse_args(OS.get_cmdline_user_args(), DEFAULTS)
	if args.has("error") or not args["files"] in ["yes", "no"]:
		printerr(args.get("error", "--files must be yes or no"))
		quit(2)
		return
	var data := CatalogValidator.load_data(AssetIO.absolute(args["data"]))
	var errors := CatalogValidator.validate(data, args["files"] == "yes")
	for e in errors:
		printerr("ERROR: ", e)
	if errors.is_empty():
		var assets: Array = data["catalog"]["assets"]
		var staged := assets.filter(func(a: Dictionary) -> bool: return a.get("runtime_path") != null).size()
		print("Catalog valid: %d forms, %d slots, %d assets (%d staged at runtime)%s" % [
			data["forms"]["forms"].size(), data["slots"]["slots"].size(), assets.size(), staged,
			"; runtime files verified" if args["files"] == "yes" else ""])
	quit(0 if errors.is_empty() else 1)
