extends "res://tests/lib/test_case.gd"
## Translation tables, language choice, and that every phrase the game shows
## from data has a Portuguese version.

const ContentData := preload("res://scripts/systems/content_data.gd")
const Localization := preload("res://scripts/systems/localization.gd")
const MenuModal := preload("res://scripts/components/menu_modal.gd")
const UpgradesModal := preload("res://scripts/components/upgrades_modal.gd")
const AwayModal := preload("res://scripts/components/away_modal.gd")

var _content := ContentData.new()
var _pt: Dictionary = {}


func _init() -> void:
	var v: Variant = _content.read_json("res://data/i18n/pt_BR.json")
	_pt = v.get("messages", {}) if typeof(v) == TYPE_DICTIONARY else {}
	Localization.load_tables(_content)


func _read(path: String) -> Dictionary:
	var v: Variant = _content.read_json(path)
	return v if typeof(v) == TYPE_DICTIONARY else {}


func test_language_choice() -> void:
	check_eq(Localization.language_for("pt_BR", "en_US"), "pt_BR", "a saved choice wins")
	check_eq(Localization.language_for("", "pt_BR"), "pt_BR", "Portuguese systems start in Portuguese")
	check_eq(Localization.language_for("", "pt_PT"), "pt_BR", "any Portuguese locale")
	check_eq(Localization.language_for("klingon", "de_DE"), "en", "everything else starts in English")
	check_eq(Localization.next_language("en"), "pt_BR", "English -> Portuguese")
	check_eq(Localization.next_language("pt_BR"), "en", "and back")


func test_translations_keep_their_placeholders() -> void:
	for source in _pt:
		check_eq(Localization.placeholders(_pt[source]), Localization.placeholders(source),
				"'%s' keeps its placeholders" % source)


func test_every_name_shown_from_data_has_portuguese() -> void:
	var phrases: Array = []
	for tier in _read("res://data/equipment/dumbbells.json")["tiers"] + _read("res://data/food/meals.json")["tiers"]:
		phrases.append(tier["label"])
	for path in ["res://data/furniture/furniture.json", "res://data/cosmetics/cosmetics.json"]:
		var doc := _read(path)
		for slot in doc["slots"]:
			if not String(slot).begins_with("_"):
				phrases.append(doc["slots"][slot]["label"])
		for item in doc["items"]:
			phrases.append(item["label"])
	for stat in UpgradesModal.EFFECT_TEXT:
		phrases.append(stat.capitalize())
		phrases.append(UpgradesModal.EFFECT_TEXT[stat])
	phrases.append_array(MenuModal.OPTIONS.values())
	phrases.append_array(MenuModal.PHRASES)
	for e in _read("res://data/effects/effects.json")["effects"].values():
		if e.has("text") and not String(e["text"]).begins_with("+") and not String(e["text"]).begins_with("-"):
			phrases.append(e["text"])
	for p in phrases:
		check(_pt.has(p), "Portuguese for '%s'" % p)


func test_formatted_text_switches_language() -> void:
	TranslationServer.set_locale("pt_BR")
	var pt_label := MenuModal.option_label("always_on_top", true)
	var pt_level := Localization.tr_format("Level %d", [40])
	var pt_away := AwayModal.lines_for({"counted_seconds": 3600.0, "workouts": 5, "bones_gained": 20,
			"levels_gained": 0, "from_level": 3, "to_level": 3, "from_form": 1, "to_form": 1})
	TranslationServer.set_locale("en")
	check_eq(pt_label, "Sempre no topo: Ligado", "menu option in Portuguese")
	check_eq(pt_level, "Nível 40", "formatted template in Portuguese")
	check_eq(pt_away[1], "5 treinos, +20 ossos.", "away summary in Portuguese")
	check_eq(MenuModal.option_label("always_on_top", true), "Always on top: On", "and back to English")
