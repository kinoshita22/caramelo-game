extends "res://tests/lib/test_case.gd"
## Training window rows: levels, costs, affordability and the cap.

const ContentData := preload("res://scripts/systems/content_data.gd")
const Economy := preload("res://scripts/systems/economy.gd")
const Progression := preload("res://scripts/systems/progression.gd")
const UpgradesModal := preload("res://scripts/components/upgrades_modal.gd")

var _content := ContentData.new()


func _init() -> void:
	_content.load_from("res://data")


func _read(path: String) -> Dictionary:
	var v: Variant = _content.read_json(path)
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _economy() -> RefCounted:
	var e := Economy.new()
	e.configure(_read("res://data/balance/upgrades.json"), _read("res://data/equipment/dumbbells.json"),
			_read("res://data/food/meals.json"))
	return e


func _wallet(bones: int) -> RefCounted:
	var p := Progression.new()
	p.configure(_read("res://data/balance/progression.json"), _content.docs["forms"]["forms"])
	p.add_bones(bones)
	return p


func test_one_row_per_stat_with_an_explanation() -> void:
	var rows := UpgradesModal.rows_for(_economy(), 100)
	check_eq(rows.size(), 4, "four stats")
	for row in rows:
		check(row["id"] in Economy.STATS, "%s is a known stat" % row["id"])
		check(row["detail"] != "", "%s explains what it does" % row["id"])
		check_eq(row["level"], 0, "%s starts at 0" % row["id"])
		check_eq(row["max_level"], 20, "%s caps at 20" % row["id"])


func test_every_stat_row_has_an_icon() -> void:
	for row in UpgradesModal.rows_for(_economy(), 0):
		check(_content.has_asset(row["icon"]), "%s has an icon: %s" % [row["id"], row["icon"]])


func test_rows_follow_the_bone_balance() -> void:
	var affordable := UpgradesModal.rows_for(_economy(), 25)
	check(affordable[0]["actionable"], "25 bones buys the first level")
	check_eq(affordable[0]["action_label"], "Train", "and the button offers to train")
	var broke := UpgradesModal.rows_for(_economy(), 5)
	check(not broke[0]["actionable"], "5 bones is not enough")


func test_cost_rises_as_levels_are_bought() -> void:
	var e := _economy()
	var wallet := _wallet(100000)
	var first: int = UpgradesModal.rows_for(e, wallet.bones)[0]["cost"]
	e.upgrade_stat("strength", wallet)
	var rows := UpgradesModal.rows_for(e, wallet.bones)
	check_eq(rows[0]["level"], 1, "level went up")
	check(rows[0]["cost"] > first, "the next level costs more: %d then %d" % [first, rows[0]["cost"]])


func test_a_maxed_stat_stops_asking_for_bones() -> void:
	var e := _economy()
	var wallet := _wallet(1000000)
	for i in e.max_stat_level():
		e.upgrade_stat("recovery", wallet)
	var row: Dictionary = {}
	for r in UpgradesModal.rows_for(e, wallet.bones):
		if r["id"] == "recovery":
			row = r
	check_eq(row["action_label"], "Maxed", "the button says so")
	check(not row["actionable"], "and does nothing")
	check_eq(row["cost"], 0, "with no price shown")
