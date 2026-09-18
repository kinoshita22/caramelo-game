extends "res://tests/lib/test_case.gd"
## Unit tests for CatalogValidator using small synthetic documents.

const CatalogValidator := preload("res://scripts/tools/catalog_validator.gd")

const LEVELS := [[1, 9], [10, 19], [20, 29], [30, 39], [40, 49], [50, 59],
		[60, 69], [70, 79], [80, 89], [90, 99], [100, 100]]
const SHA := "0000000000000000000000000000000000000000000000000000000000000000"


func _forms(levels: Array = LEVELS) -> Dictionary:
	var forms: Array = []
	for i in levels.size():
		forms.append({"form": i + 1, "id": "form_%02d" % (i + 1), "level_min": levels[i][0],
				"level_max": levels[i][1], "frame_count": 33, "staged": false})
	return {"max_level": 100, "forms": forms}


func _slots() -> Dictionary:
	var slots: Array = []
	for s in range(1, 34):
		slots.append({"slot": s, "category": "c", "state": "state_%02d" % s})
	return {"slot_count": 33, "slots": slots}


func _frame(slot: int) -> Dictionary:
	return {"slot": slot, "image": {"width": 100, "height": 200},
			"visible": {"x": 10, "y": 20, "width": 80, "height": 170},
			"anchor": {"x": 50.0, "y": 190}, "review_flags": []}


func _geometry(form_count: int = 11) -> Dictionary:
	var forms: Array = []
	for f in range(1, form_count + 1):
		var frames: Array = []
		for s in range(1, 34):
			frames.append(_frame(s))
		forms.append({"form": f, "canvas": {"width": 80, "height": 170}, "frames": frames})
	return {"forms": forms}


func _catalog() -> Dictionary:
	var assets: Array = []
	for f in range(1, 12):
		for s in range(1, 34):
			assets.append({"id": "character.f%02d.s%02d" % [f, s], "kind": "character", "form": f,
					"slot": s, "state": "state_%02d" % s, "sha256": SHA, "runtime_path": null})
	assets.append({"id": "ui.icon", "kind": "ui", "sha256": SHA, "runtime_path": null})
	return {"assets": assets}


func test_valid_forms_pass() -> void:
	check_no_errors(CatalogValidator.check_forms(_forms()), "valid forms")


func test_level_gap_detected() -> void:
	var levels := LEVELS.duplicate(true)
	levels[3] = [31, 39]
	check_error(CatalogValidator.check_forms(_forms(levels)), "gap between forms 3 and 4")


func test_level_overlap_detected() -> void:
	var levels := LEVELS.duplicate(true)
	levels[4] = [39, 49]
	check_error(CatalogValidator.check_forms(_forms(levels)), "overlap")


func test_levels_must_start_at_one_and_end_at_max() -> void:
	var levels := LEVELS.duplicate(true)
	levels[0] = [2, 9]
	levels[10] = [100, 99]
	var errors := CatalogValidator.check_forms(_forms(levels))
	check_error(errors, "levels start at 2")
	check_error(errors, "level_min > level_max")


func test_missing_and_duplicate_form_detected() -> void:
	var doc := _forms()
	doc["forms"][10]["form"] = 10
	var errors := CatalogValidator.check_forms(doc)
	check_error(errors, "form 10 listed more than once")
	check_error(errors, "form 11 missing")


func test_wrong_types_rejected() -> void:
	check_error(CatalogValidator.check_forms({"max_level": 100, "forms": "nope"}), "must be an array")
	var doc := _forms()
	doc["forms"][0]["level_min"] = "1"
	check_error(CatalogValidator.check_forms(doc), "numeric form, level_min, level_max")


func test_valid_slots_pass() -> void:
	check_no_errors(CatalogValidator.check_slots(_slots()), "valid slots")


func test_duplicate_and_missing_slot_detected() -> void:
	var doc := _slots()
	doc["slots"][32]["slot"] = 32
	var errors := CatalogValidator.check_slots(doc)
	check_error(errors, "slot 32 listed more than once")
	check_error(errors, "slot 33 missing")


func test_duplicate_state_name_detected() -> void:
	var doc := _slots()
	doc["slots"][1]["state"] = "state_01"
	check_error(CatalogValidator.check_slots(doc), "state 'state_01' used by slots 1 and 2")


func test_valid_geometry_passes() -> void:
	check_no_errors(CatalogValidator.check_geometry(_geometry(), _forms()), "valid geometry")


func test_geometry_missing_form_and_slot_detected() -> void:
	var doc := _geometry(10)
	doc["forms"][0]["frames"].remove_at(5)
	var errors := CatalogValidator.check_geometry(doc, _forms())
	check_error(errors, "no geometry for form 11")
	check_error(errors, "form 1: slot 6 missing")


func test_geometry_out_of_bounds_detected() -> void:
	var doc := _geometry()
	doc["forms"][0]["frames"][0]["anchor"] = {"x": 150.0, "y": 190}
	doc["forms"][0]["frames"][1]["visible"]["width"] = 95
	var errors := CatalogValidator.check_geometry(doc, _forms())
	check_error(errors, "slot 1: anchor lies outside the image")
	check_error(errors, "slot 2: visible rect lies outside the image")


func test_valid_catalog_passes() -> void:
	check_no_errors(CatalogValidator.check_catalog(_catalog(), _forms(), _slots()), "valid catalog")


func test_catalog_duplicate_frame_and_bad_hash_detected() -> void:
	var doc := _catalog()
	doc["assets"][1]["slot"] = 1
	doc["assets"][2]["sha256"] = "xyz"
	var errors := CatalogValidator.check_catalog(doc, _forms(), _slots())
	check_error(errors, "form 1 slot 1 appears more than once")
	check_error(errors, "invalid sha256")
	check_error(errors, "asset_catalog form 1: slot 2 missing")


func test_catalog_state_mismatch_detected() -> void:
	var doc := _catalog()
	doc["assets"][0]["state"] = "wrong"
	check_error(CatalogValidator.check_catalog(doc, _forms(), _slots()), "does not match slot 1")


func test_staged_form_requires_runtime_paths() -> void:
	var forms := _forms()
	forms["forms"][0]["staged"] = true
	check_error(CatalogValidator.check_catalog(_catalog(), forms, _slots()), "form 1 is marked staged")


func test_issue_severity_validated() -> void:
	var errors := CatalogValidator.check_issues({"issues": [
		{"id": "a", "severity": "bad", "summary": "s", "resolution": "r"}]})
	check_error(errors, "severity")
