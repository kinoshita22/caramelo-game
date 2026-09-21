extends RefCounted
## Loads the translation tables in data/i18n into Godot's TranslationServer
## and picks the language. English is the source text, so labels and buttons
## translate themselves; formatted text translates its template first (see
## tr_format).

const LANGUAGES := ["en", "pt_BR"]
const LANGUAGE_NAMES := {"en": "English", "pt_BR": "Português"}
const TABLES := ["res://data/i18n/pt_BR.json"]


## Registers every table. Returns errors for tables that fail to load.
static func load_tables(content: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	for path in TABLES:
		var doc: Variant = content.read_json(path)
		if typeof(doc) != TYPE_DICTIONARY or typeof(doc.get("messages")) != TYPE_DICTIONARY:
			errors.append("%s missing or invalid" % path)
			continue
		var translation := Translation.new()
		translation.locale = doc.get("locale", "")
		for source in doc["messages"]:
			translation.add_message(source, doc["messages"][source])
		TranslationServer.add_translation(translation)
	return errors


## The saved language if valid, otherwise Portuguese for a Portuguese system
## and English for everything else.
static func language_for(saved: String, os_locale: String) -> String:
	if saved in LANGUAGES:
		return saved
	return "pt_BR" if os_locale.begins_with("pt") else "en"


static func next_language(current: String) -> String:
	return LANGUAGES[(LANGUAGES.find(current) + 1) % LANGUAGES.size()]


## Translates a template, then fills it: tr_format("Level %d", [5]).
static func tr_format(template: String, values: Array = []) -> String:
	var translated := String(TranslationServer.translate(template))
	return translated % values if not values.is_empty() else translated


## Placeholders a translation must keep, for checking tables.
static func placeholders(text: String) -> Array:
	var found := []
	var re := RegEx.create_from_string("%\\.?\\d*[dsf]|\\{\\w+\\}")
	for m in re.search_all(text):
		found.append(m.get_string())
	found.sort()
	return found
