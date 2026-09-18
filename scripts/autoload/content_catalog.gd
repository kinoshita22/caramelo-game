extends Node
## Autoload: the game's single loaded, validated copy of data/.

const ContentData := preload("res://scripts/systems/content_data.gd")

var data := ContentData.new()


func _enter_tree() -> void:
	if not data.load_from("res://data"):
		for e in data.errors:
			push_error("ContentCatalog: " + e)
