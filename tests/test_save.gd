extends "res://tests/lib/test_case.gd"
## Save format, file safety (atomic writes, backup, corrupt recovery),
## offline progress rules and the "while you were away" text.

const ContentData := preload("res://scripts/systems/content_data.gd")
const Progression := preload("res://scripts/systems/progression.gd")
const Economy := preload("res://scripts/systems/economy.gd")
const Collection := preload("res://scripts/systems/collection.gd")
const BehaviourLoop := preload("res://scripts/systems/behaviour_loop.gd")
const SaveData := preload("res://scripts/systems/save_data.gd")
const OfflineProgress := preload("res://scripts/systems/offline_progress.gd")
const SaveFile := preload("res://scripts/systems/save_file.gd")
const AwayModal := preload("res://scripts/components/away_modal.gd")
const TEST_DIR := "user://test_saves"

var _content := ContentData.new()


func _init() -> void:
	_content.load_from("res://data")


func _read(path: String) -> Dictionary:
	var v: Variant = _content.read_json(path)
	return v if typeof(v) == TYPE_DICTIONARY else {}


## A full set of freshly configured systems.
func _systems() -> Dictionary:
	var p := Progression.new()
	p.configure(_read("res://data/balance/progression.json"), _content.docs["forms"]["forms"])
	var e := Economy.new()
	e.configure(_read("res://data/balance/upgrades.json"), _read("res://data/equipment/dumbbells.json"),
			_read("res://data/food/meals.json"))
	var f := Collection.new()
	f.configure(_read("res://data/furniture/furniture.json"))
	var c := Collection.new()
	c.configure(_read("res://data/cosmetics/cosmetics.json"))
	var l := BehaviourLoop.new()
	l.configure(_read("res://data/balance/behaviour.json"))
	return {"progression": p, "economy": e, "furniture": f, "cosmetics": c, "loop": l}


func _build(s: Dictionary, now: float = 1000.0) -> Dictionary:
	return SaveData.build(s["progression"], s["economy"], s["furniture"], s["cosmetics"], s["loop"],
			{"display_mode": "windowed"}, now)


## Through JSON and back, as the file would be.
func _round_trip(doc: Dictionary) -> Dictionary:
	var json := JSON.new()
	json.parse(JSON.stringify(doc))
	return SaveData.migrate(json.data)["doc"]


func test_everything_survives_a_round_trip() -> void:
	var a := _systems()
	a["progression"].restore(37, 12.5, 4321, 99)
	a["economy"].upgrade_stat("speed", a["progression"])
	a["economy"].buy_equipment("standard_iron", a["progression"], 37)
	a["loop"].energy = 41.0
	a["loop"].satiety = 63.0
	var doc := _round_trip(_build(a))
	check_no_errors(SaveData.validate(doc), "saved document")
	var b := _systems()
	SaveData.apply(doc, b["progression"], b["economy"], b["furniture"], b["cosmetics"])
	SaveData.apply_needs(doc, b["loop"])
	check_eq(b["progression"].level, 37, "level")
	check_eq(b["progression"].xp, 12.5, "xp")
	check_eq(b["progression"].bones, a["progression"].bones, "bones")
	check_eq(b["progression"].form, 4, "form follows the level")
	check_eq(b["economy"].snapshot(), a["economy"].snapshot(), "upgrades and gear")
	check_eq(b["furniture"].snapshot(), a["furniture"].snapshot(), "furniture")
	check_eq([b["loop"].energy, b["loop"].satiety], [41.0, 63.0], "energy and satiety")
	check_eq(doc["settings"], {"display_mode": "windowed"}, "settings")


func test_untrusted_values_are_clamped_on_apply() -> void:
	var doc := _round_trip(_build(_systems()))
	doc["progression"] = {"level": 500, "xp": -30, "bones": -99}
	doc["needs"] = {"energy": 900, "satiety": -5}
	var s := _systems()
	SaveData.apply(doc, s["progression"], s["economy"], s["furniture"], s["cosmetics"])
	SaveData.apply_needs(doc, s["loop"])
	check_eq(s["progression"].level, 100, "level clamped to 100")
	check_eq(s["progression"].bones, 0, "bones clamped to 0")
	check_eq([s["loop"].energy, s["loop"].satiety], [100.0, 0.0], "needs clamped to 0-100")


func test_validation_rejects_wrong_shapes() -> void:
	var doc := _round_trip(_build(_systems()))
	doc["progression"]["level"] = "ten"
	doc["economy"] = []
	var errors := SaveData.validate(doc)
	check_error(errors, "progression.level must be a number")
	check_error(errors, "'economy' must be an object")


func test_migrations_run_in_order_and_newer_saves_are_refused() -> void:
	check_error([SaveData.migrate({"schema_version": 99}).get("error", "")], "newer version")
	check_error([SaveData.migrate({}).get("error", "")], "no schema_version")
	check_error([SaveData.migrate({"schema_version": 0}).get("error", "")], "no migration from schema 0")
	SaveData.migrations[0] = func(old: Dictionary) -> Dictionary:
		old["progression"] = {"level": old["lvl"], "xp": 0, "bones": 0}
		return old
	var result := SaveData.migrate({"schema_version": 0, "lvl": 7, "saved_at_unix": 1})
	SaveData.migrations.clear()
	check(result.has("doc"), "old save migrated")
	check_eq(result["doc"]["schema_version"], SaveData.SCHEMA_VERSION, "now at the current schema")
	check_eq(result["doc"]["progression"]["level"], 7, "data carried over")


func _manager(name: String) -> RefCounted:
	return SaveFile.new(TEST_DIR.path_join(name))


func _clear_test_dir() -> void:
	var dir := ProjectSettings.globalize_path(TEST_DIR)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))


func test_writes_keep_the_previous_save_as_backup() -> void:
	_clear_test_dir()
	var m := _manager("a.json")
	var s := _systems()
	s["progression"].restore(5, 0, 10)
	check_eq(m.write(_build(s)), "", "first write")
	s["progression"].restore(6, 0, 20)
	check_eq(m.write(_build(s)), "", "second write")
	var loaded: Dictionary = m.read()
	check_eq(loaded["status"], "loaded", "main save loads")
	check_eq(int(loaded["doc"]["progression"]["level"]), 6, "with the latest level")
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(m.backup_path()))
	check_eq(int(backup["progression"]["level"]), 5, "backup holds the previous save")
	check(not FileAccess.file_exists(m.path + ".tmp"), "no temp file left behind")


func test_a_corrupt_save_falls_back_to_the_backup_and_is_kept() -> void:
	_clear_test_dir()
	var m := _manager("b.json")
	var s := _systems()
	s["progression"].restore(8, 0, 0)
	m.write(_build(s))
	s["progression"].restore(9, 0, 0)
	m.write(_build(s))
	var f := FileAccess.open(m.path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var loaded: Dictionary = m.read()
	check_eq(loaded["status"], "backup", "falls back to the backup")
	check_eq(int(loaded["doc"]["progression"]["level"]), 8, "which has the previous level")
	var kept := Array(DirAccess.get_files_at(ProjectSettings.globalize_path(TEST_DIR))).filter(
			func(n: String) -> bool: return n.begins_with("b.corrupt-"))
	check_eq(kept.size(), 1, "the broken save is kept aside, not deleted")


func test_both_files_corrupt_starts_fresh_without_deleting() -> void:
	_clear_test_dir()
	var m := _manager("c.json")
	for p in [m.path, m.backup_path()]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string("garbage")
		f.close()
	var loaded: Dictionary = m.read()
	check_eq(loaded["status"], "fresh_after_corrupt", "starts fresh")
	check_eq(loaded["errors"].size(), 2, "and reports both files")
	var kept := DirAccess.get_files_at(ProjectSettings.globalize_path(TEST_DIR)).size()
	check_eq(kept, 2, "both broken files are kept aside")
	check_eq(_manager("none.json").read()["status"], "fresh", "no save at all is a fresh start")
	_clear_test_dir()


func _offline(seconds: float, config_overrides: Dictionary = {}) -> Dictionary:
	var config := _read("res://data/balance/offline.json")
	config.merge(config_overrides, true)
	var s := _systems()
	var summary := OfflineProgress.simulate(seconds, config, _read("res://data/balance/behaviour.json"),
			s["progression"], s["economy"], {"energy": 80.0, "satiety": 70.0})
	summary["progression"] = s["progression"]
	return summary


func test_an_hour_away_pays_like_an_hour_watched() -> void:
	var r := _offline(3600.0)
	check(r["workouts"] > 50, "about one workout every 45-odd seconds: %d" % r["workouts"])
	check_eq(r["bones_gained"], r["progression"].bones, "bones reported match bones earned")
	check(r["levels_gained"] > 0, "levels were gained")
	check_eq(r["counted_seconds"], 3600.0, "the whole hour counted")
	check(r["energy"] >= 0.0 and r["energy"] <= 100.0 and r["satiety"] >= 0.0 and r["satiety"] <= 100.0,
			"needs stay in range")


func test_offline_rate_scales_what_time_away_earns() -> void:
	var full := _offline(3600.0)
	var half := _offline(3600.0, {"offline_rate": 0.5})
	check_eq(half["counted_seconds"], 3600.0, "the whole hour still counts as time away")
	check(half["workouts"] < full["workouts"] * 0.6 and half["workouts"] > full["workouts"] * 0.4,
			"about half the workouts: %d of %d" % [half["workouts"], full["workouts"]])
	check_eq(_offline(3600.0, {"offline_rate": 0.0})["workouts"], 0, "a rate of 0 earns nothing")


func test_time_away_is_capped() -> void:
	var r := _offline(48 * 3600.0, {"cap_hours": 1.0})
	check(r["capped"], "reported as capped")
	check_eq(r["counted_seconds"], 3600.0, "only the cap counts")


func test_a_clock_moved_backwards_grants_nothing() -> void:
	var r := _offline(-5000.0)
	check(r["clock_rollback"], "rollback noticed")
	check_eq(r["workouts"], 0, "no workouts")
	check_eq(r["progression"].level, 1, "no levels")


func test_short_absences_count_for_nothing() -> void:
	var r := _offline(30.0)
	check_eq(r["counted_seconds"], 0.0, "under the minimum")
	check_eq(r["workouts"], 0, "nothing paid")


func test_offline_progress_is_deterministic() -> void:
	var a := _offline(1800.0)
	var b := _offline(1800.0)
	check_eq([a["workouts"], a["bones_gained"], a["to_level"]], [b["workouts"], b["bones_gained"], b["to_level"]],
			"same time away, same result")


func test_upgrades_make_time_away_more_productive() -> void:
	var config := _read("res://data/balance/offline.json")
	var behaviour := _read("res://data/balance/behaviour.json")
	var plain := _systems()
	var trained := _systems()
	trained["progression"].add_bones(1000000)
	for i in 10:
		trained["economy"].upgrade_stat("speed", trained["progression"])
		trained["economy"].upgrade_stat("strength", trained["progression"])
	var needs := {"energy": 80.0, "satiety": 70.0}
	var a := OfflineProgress.simulate(3600.0, config, behaviour, plain["progression"], plain["economy"], needs)
	var b := OfflineProgress.simulate(3600.0, config, behaviour, trained["progression"], trained["economy"], needs)
	check(b["workouts"] > a["workouts"], "speed fits in more workouts: %d vs %d" % [b["workouts"], a["workouts"]])
	check(b["xp_gained"] > a["xp_gained"], "strength earns more XP")


func test_away_summary_text() -> void:
	var r := _offline(3600.0)
	var lines := AwayModal.lines_for(r)
	check_eq(lines[0], "Caramelo trained for 1 h 0 min.", "time trained")
	check(lines[1].begins_with("%d workouts, +%d bones" % [r["workouts"], r["bones_gained"]]), "workouts and bones")
	check(AwayModal.worth_showing(r), "worth showing")
	check(not AwayModal.worth_showing(_offline(10.0)), "nothing to show for a short break")
	check_eq(AwayModal.lines_for(_offline(-10.0)), ["The clock went backwards, so no time was counted."], "rollback message")
	check_eq(OfflineProgress.describe_duration(125.0), "2 min", "minutes")
	check_eq(OfflineProgress.describe_duration(3 * 3600.0 + 20 * 60.0), "3 h 20 min", "hours")
