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
var _icons: Dictionary = {}


## Loads and validates data_root (a res:// path). Returns true when valid.
func load_from(data_root: String = "res://data") -> bool:
	docs = CatalogValidator.load_data(data_root)
	errors = CatalogValidator.validate(docs, false)
	_assets.clear()
	_textures.clear()
	_icons.clear()
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


## Drops cached textures so the engine can free them (e.g. after evolving
## to a new form).
func release_textures(ids: Array) -> void:
	for id in ids:
		_textures.erase(id)


## Geometry record for one character frame, or {} if unknown.
func frame_geometry(form: int, slot: int) -> Dictionary:
	for f in docs.get("geometry", {}).get("forms", []):
		if int(f["form"]) == form:
			for fr in f["frames"]:
				if int(fr["slot"]) == slot:
					return fr
	return {}


## Form numbers present in the catalog, ascending.
func form_numbers() -> Array[int]:
	var out: Array[int] = []
	for f in docs.get("forms", {}).get("forms", []):
		out.append(int(f["form"]))
	out.sort()
	return out


## Texture cropped to the asset's visible bounds. UI and item art sits on a
## large transparent canvas; cropping keeps it from shrinking in a layout.
func icon_texture(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var base := texture(id)
	var a := asset(id)
	var icon: Texture2D = base
	if base != null and a.has("visible"):
		var atlas := AtlasTexture.new()
		atlas.atlas = base
		atlas.region = visible_rect(id)
		icon = atlas
	_icons[id] = icon
	return icon


## The asset's art cropped to its visible bounds and scaled to `height`
## pixels, as a plain texture. UI art is drawn far larger than it is shown,
## and a style box takes its minimum size from the source pixels, so the
## small version is what the interface needs.
func ui_texture(id: String, height: int) -> Texture2D:
	var key := "%s@%d" % [id, height]
	if _icons.has(key):
		return _icons[key]
	var base := texture(id)
	var made: Texture2D = base
	if base != null:
		var image := base.get_image()
		if image != null:
			image = image.duplicate()
			image.decompress()
			var rect := visible_rect(id)
			if rect.size.x > 0.0:
				image = image.get_region(Rect2i(rect))
			var scale := float(height) / maxf(image.get_height(), 1.0)
			image.resize(maxi(1, roundi(image.get_width() * scale)), height, Image.INTERPOLATE_LANCZOS)
			made = ImageTexture.create_from_image(image)
	_icons[key] = made
	return made


## The asset's visible bounds in source pixels.
func visible_rect(id: String) -> Rect2:
	var v: Dictionary = asset(id).get("visible", {})
	if v.is_empty():
		return Rect2()
	return Rect2(v["x"], v["y"], v["width"], v["height"])


## Largest per-form canvas across every form, in source pixels.
func max_character_canvas() -> Vector2:
	var size := Vector2.ZERO
	for f in docs.get("geometry", {}).get("forms", []):
		size = size.max(Vector2(f["canvas"]["width"], f["canvas"]["height"]))
	return size


## Parses a JSON file under res://data. Returns null if missing or invalid.
func read_json(res_path: String) -> Variant:
	return AssetIO.read_json(res_path)
