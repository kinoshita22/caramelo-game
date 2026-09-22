extends "res://tests/lib/test_case.gd"
## Starting the game over: the menu's confirmation step, and that a reset
## leaves every system exactly as a first run does.

const ContentData := preload("res://scripts/systems/content_data.gd")
const Progression := preload("res://scripts/systems/progression.gd")
const Economy := preload("res://scripts/systems/economy.gd")
const Collection := preload("res://scripts/systems/collection.gd")
const MenuModal := preload("res://scripts/components/menu_modal.gd")

var _content := ContentData.new()


func _init() -> void:
	_content.load_from("res://data")


func _read(path: String) -> Dictionary:
	var v: Variant = _content.read_json(path)
	return v if typeof(v) == TYPE_DICTIONARY else {}


## The one call GameState.reset() makes: the systems are configured from the
## data files again, in place.
func _configure(progression: RefCounted, economy: RefCounted, cosmetics: RefCounted) -> void:
	var forms: Array = _content.docs.get("forms", {}).get("forms", [])
	progression.configure(_read("res://data/balance/progression.json"), forms)
	economy.configure(_read("res://data/balance/upgrades.json"), _read("res://data/equipment/dumbbells.json"),
			_read("res://data/food/meals.json"))
	cosmetics.configure(_read("res://data/cosmetics/cosmetics.json"))


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _menu() -> Control:
	var menu: Control = MenuModal.new()
	menu.open(_content, "overlay", {})
	return menu


func test_the_reset_button_only_asks() -> void:
	var menu := _menu()
	var resets := [0]
	menu.reset_requested.connect(func() -> void: resets[0] += 1)
	var button := _find_button(menu, TranslationServer.translate(MenuModal.RESET_LABEL))
	check(button != null, "the menu has a reset button")
	button.pressed.emit()
	check_eq(resets[0], 0, "pressing it resets nothing by itself")
	check(menu.confirming_reset(), "it asks first")
	menu.free()


func test_keeping_the_game_calls_the_whole_thing_off() -> void:
	var menu := _menu()
	var resets := [0]
	menu.reset_requested.connect(func() -> void: resets[0] += 1)
	_find_button(menu, TranslationServer.translate(MenuModal.RESET_LABEL)).pressed.emit()
	_find_button(menu, TranslationServer.translate(MenuModal.CONFIRM_NO)).pressed.emit()
	check_eq(resets[0], 0, "no means no")
	check(not menu.confirming_reset(), "and the question is gone")
	menu.free()


func test_only_the_confirmation_resets() -> void:
	var menu := _menu()
	var resets := [0]
	menu.reset_requested.connect(func() -> void: resets[0] += 1)
	_find_button(menu, TranslationServer.translate(MenuModal.RESET_LABEL)).pressed.emit()
	_find_button(menu, TranslationServer.translate(MenuModal.CONFIRM_YES)).pressed.emit()
	check_eq(resets[0], 1, "yes resets, once")
	check(not menu.confirming_reset(), "and the question is gone")
	menu.free()


func test_closing_the_menu_drops_the_question() -> void:
	var menu := _menu()
	_find_button(menu, TranslationServer.translate(MenuModal.RESET_LABEL)).pressed.emit()
	menu.close()
	check(not menu.confirming_reset(), "closing the menu forgets it was asked")
	menu.open(_content, "overlay", {})
	check(not menu.confirming_reset(), "and it does not come back on the next visit")
	menu.free()


func test_a_reset_gives_back_a_first_run() -> void:
	var progression := Progression.new()
	var economy := Economy.new()
	var cosmetics := Collection.new()
	_configure(progression, economy, cosmetics)
	var fresh_level := progression.level
	var fresh_stats := economy.snapshot()
	var fresh_cosmetics := cosmetics.snapshot()

	# Play a while: levels, bones, an upgrade and a better dumbbell.
	progression.restore(24, 10.0, 5000, 40)
	economy.upgrade_stat("strength", progression)
	economy.buy_equipment(economy.equipment_ids()[1], progression, progression.level)
	check(progression.bones < 5000, "the shopping was paid for")
	# There is nothing to buy in the wardrobe yet (the art arrives later),
	# so a worn item stands in for one.
	cosmetics.owned.append("a_hat_from_later")

	_configure(progression, economy, cosmetics)
	check_eq(progression.level, fresh_level, "back to the starting level")
	check_eq(progression.xp, 0.0, "no experience")
	check_eq(progression.bones, 0, "no bones")
	check_eq(progression.workouts_completed, 0, "no workouts")
	check_eq(progression.form, 1, "the first form again")
	check_eq(economy.snapshot(), fresh_stats, "no upgrades, nothing bought, starting gear")
	check_eq(cosmetics.snapshot(), fresh_cosmetics, "the wardrobe is empty again")
