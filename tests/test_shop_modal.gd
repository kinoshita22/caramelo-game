extends "res://tests/lib/test_case.gd"
## Purchase-window rows and the clickable island props that open them.

const ContentData := preload("res://scripts/systems/content_data.gd")
const Economy := preload("res://scripts/systems/economy.gd")
const Progression := preload("res://scripts/systems/progression.gd")
const ShopModal := preload("res://scripts/components/shop_modal.gd")
const IslandStage := preload("res://scripts/components/island_stage.gd")

var _content := ContentData.new()
var _layout: Dictionary = {}


func _init() -> void:
	_content.load_from("res://data")
	var l: Variant = _content.read_json("res://data/environment/island_layout.json")
	_layout = l if typeof(l) == TYPE_DICTIONARY else {}


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


func _read(path: String) -> Dictionary:
	var v: Variant = _content.read_json(path)
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _row(rows: Array, id: String) -> Dictionary:
	for r in rows:
		if r["id"] == id:
			return r
	return {}


func test_equipment_rows_show_use_price_and_locks() -> void:
	var rows := ShopModal.rows_for(ShopModal.EQUIPMENT, _economy(), 10, 200)
	check_eq(rows.size(), 6, "one row per dumbbell tier")
	check_eq(_row(rows, "starter_light")["state"], "in_use", "the starting pair is in use")
	check(not _row(rows, "starter_light")["actionable"], "no action on the pair already in use")
	check_eq(_row(rows, "standard_iron")["state"], "affordable", "iron is affordable at 200 bones")
	check_eq(_row(rows, "standard_iron")["action_label"], "Buy", "and offers to buy")
	check_eq(_row(rows, "heavy_pro")["state"], "locked", "pro is locked at level 10")
	check_eq(_row(rows, "heavy_pro")["action_label"], "Level 40", "showing the level it needs")


func test_rows_mark_items_that_cost_too_much() -> void:
	var rows := ShopModal.rows_for(ShopModal.EQUIPMENT, _economy(), 10, 20)
	check_eq(_row(rows, "standard_iron")["state"], "too_expensive", "not enough bones")
	check(not _row(rows, "standard_iron")["actionable"], "so it cannot be bought")


func test_bought_items_become_owned_then_in_use() -> void:
	var e := _economy()
	var wallet := _wallet(5000)
	e.buy_equipment("standard_iron", wallet, 10)
	e.equip("starter_light")
	var rows := ShopModal.rows_for(ShopModal.EQUIPMENT, e, 10, wallet.bones)
	check_eq(_row(rows, "standard_iron")["state"], "owned", "bought tiers read as owned")
	check(_row(rows, "standard_iron")["owned"], "and carry the owned flag the view colours")
	check_eq(_row(rows, "standard_iron")["action_label"], "Use", "offering to switch to it")
	check_eq(_row(rows, "starter_light")["state"], "in_use", "the equipped pair is marked in use")


func test_food_rows_describe_the_meal() -> void:
	var rows := ShopModal.rows_for(ShopModal.FOOD, _economy(), 20, 500)
	check_eq(rows.size(), 5, "one row per meal")
	check_eq(_row(rows, "basic_kibble")["state"], "in_use", "kibble starts active")
	check_eq(_row(rows, "balanced_chicken")["detail"], "Fills x1.25, eats x1.10", "meals show what they do")
	check(_row(rows, "premium_beef_pumpkin")["state"] == "locked", "the premium meal is locked at level 20")


func test_rows_carry_the_item_art() -> void:
	for row in ShopModal.rows_for(ShopModal.FOOD, _economy(), 100, 0):
		check(_content.has_asset(row["asset"]), "%s has art: %s" % [row["id"], row["asset"]])


func test_clicking_the_rack_and_the_station_opens_their_windows() -> void:
	var placements := IslandStage.compute_placements(_layout, _content)
	var by_name := {}
	for p in placements:
		by_name[p["name"]] = p
	check_eq(IslandStage.click_action_at(placements, by_name["dumbbell_rack"]["rect"].get_center()),
			"shop_equipment", "the rack opens the dumbbell window")
	check_eq(IslandStage.click_action_at(placements, by_name["food_station"]["rect"].get_center()),
			"shop_food", "the station opens the food window")


func test_clicking_elsewhere_opens_nothing() -> void:
	var placements := IslandStage.compute_placements(_layout, _content)
	check_eq(IslandStage.click_action_at(placements, Vector2(-10000, -10000)), "", "empty sky does nothing")
	for p in placements:
		if p["name"] in ["tree", "swing", "sleeping_mat"]:
			check_eq(IslandStage.click_action_at([p], p["rect"].get_center()), "",
					"%s is not clickable" % p["name"])
		if p["name"] in ["chair", "side_table"]:
			check_eq(IslandStage.click_action_at([p], p["rect"].get_center()), "furniture",
					"%s opens the furniture window" % p["name"])
