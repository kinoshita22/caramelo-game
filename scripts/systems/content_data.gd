extends RefCounted
## Read-only view of the generated metadata in data/: asset lookup, texture
## loading and the character geometry. Validates everything on load and
## refuses to serve data that fails validation.
##
## The ContentCatalog autoload holds one instance; tests create their own.

const AssetIO := preload("res://scripts/tools/asset_io.gd")
const CatalogValidator := preload("res://scripts/tools/catalog_validator.gd")

var docs: Dictionary = {}
var errors: Array[String] = []
var _assets: Dictionary = {}
var _textures: Dictionary = {}


## Loads and validates data_root (a res:// path). Returns true when valid.
func load_from(data_root: String = "res://data") -> bool:
	docs = CatalogValidator.load_data(data_root)
	errors = CatalogValidator.validate(docs, false)
	_assets.clear()
	_textures.clear()
	if not errors.is_empty():
		return false
	for a in docs["catalog"]["assets"]:
		_assets[a["id"]] = a
	return true


func is_valid() -> bool:
	return errors.is_empty() and not _assets.is_empty()


func has_asset(id: String) -> bool:
	return _assets.has(id)


## Catalog entry, or an empty dictionary for an unknown id.
func asset(id: String) -> Dictionary:
	return _assets.get(id, {})


## Runtime texture for an asset, cached. Null if the asset is not staged.
func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var path: Variant = asset(id).get("runtime_path")
	var tex: Texture2D = load(path) if path != null else null
	_textures[id] = tex
	return tex


## Largest per-form canvas across every form, in source pixels.
func max_character_canvas() -> Vector2:
	var size := Vector2.ZERO
	for f in docs.get("geometry", {}).get("forms", []):
		size = size.max(Vector2(f["canvas"]["width"], f["canvas"]["height"]))
	return size


## Parses a JSON file under res://data. Returns null if missing or invalid.
func read_json(res_path: String) -> Variant:
	return AssetIO.read_json(res_path)
