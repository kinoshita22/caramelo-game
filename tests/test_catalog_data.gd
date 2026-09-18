extends "res://tests/lib/test_case.gd"
## Integration tests against the generated data/ files and runtime assets.

const CatalogValidator := preload("res://scripts/tools/catalog_validator.gd")

var _data := CatalogValidator.load_data(ProjectSettings.globalize_path("res://data"))


func test_generated_catalog_is_valid_including_runtime_files() -> void:
	check_no_errors(CatalogValidator.validate(_data, true), "generated catalog")


func test_eleven_forms_cover_levels_1_to_100() -> void:
	var forms: Array = _data["forms"].get("forms", [])
	check_eq(forms.size(), 11, "form count")
	if forms.size() == 11:
		check_eq([forms[0]["level_min"], forms[10]["level_max"]], [1.0, 100.0], "level span")


func test_all_363_character_frames_catalogued() -> void:
	var frames: Array = _data["catalog"].get("assets", []).filter(
			func(a: Dictionary) -> bool: return a["kind"] == "character")
	check_eq(frames.size(), 363, "character frames")


func test_form_1_and_shared_packs_staged() -> void:
	var staged: Array = _data["catalog"].get("assets", []).filter(
			func(a: Dictionary) -> bool: return a["runtime_path"] != null)
	var character := staged.filter(func(a: Dictionary) -> bool: return a["kind"] == "character")
	check_eq(character.size(), 33, "staged character frames")
	check(character.all(func(a: Dictionary) -> bool: return int(a["form"]) == 1), "only Form 1 frames staged")
	check_eq(staged.size() - character.size(), 52, "staged shared assets")


func test_manifest_form_values_not_propagated() -> void:
	for a in _data["catalog"].get("assets", []):
		if a["kind"] == "character":
			check(int(a["form"]) == int(a["pack"].substr(14, 2)), "%s form matches folder" % a["id"])
			check(not a.has("manifest"), "%s carries no raw manifest columns" % a["id"])


func test_known_issues_record_form_6_values() -> void:
	var ids: Array = _data["issues"].get("issues", []).map(func(i: Dictionary) -> String: return i["id"])
	check("manifest_form_column_wrong" in ids, "form=6 manifest issue recorded")
	check("filename_suffix_differs_from_canonical" in ids, "naming scheme issue recorded")
