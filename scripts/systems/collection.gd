extends RefCounted
## Slot-based items the player owns and equips: furniture on the island,
## cosmetics on Caramelo. Pure simulation; a wallet (Progression) pays.
##
## One instance per data file (data/furniture/furniture.json,
## data/cosmetics/cosmetics.json). Adding an item is a data change only.
## In every slot the free items are owned from the start and the first of
## them is equipped. Nothing can be sold and balances never go negative.

signal changed(slot_name: String)

var slots := {}
var owned: Array[String] = []
## Slot name -> equipped item id ("" when the slot is empty).
var equipped := {}

var _items := {}  # id -> item
var _order: Array[String] = []


## Returns validation errors; nothing is applied on error.
func configure(doc: Dictionary, known_assets: Array = []) -> Array[String]:
	var errors := validate(doc, known_assets)
	if not errors.is_empty():
		return errors
	slots = doc["slots"]
	_items.clear()
	_order.clear()
	owned.clear()
	equipped.clear()
	for slot_name in slots:
		if not String(slot_name).begins_with("_"):
			equipped[slot_name] = ""
	for item in doc["items"]:
		_items[item["id"]] = item
		_order.append(item["id"])
		if int(item["cost"]) == 0:
			owned.append(item["id"])
			if equipped[item["slot"]] == "":
				equipped[item["slot"]] = item["id"]
	return errors


func slot_names() -> Array[String]:
	var out: Array[String] = []
	for slot_name in equipped:
		out.append(slot_name)
	return out


func item(id: String) -> Dictionary:
	return _items.get(id, {})


func items_for(slot_name: String) -> Array[String]:
	var out: Array[String] = []
	for id in _order:
		if _items[id]["slot"] == slot_name:
			out.append(id)
	return out


## The asset shown in a slot, or "" when it is empty.
func equipped_asset(slot_name: String) -> String:
	return item(equipped.get(slot_name, "")).get("asset", "")


## Buys an item and equips it. Returns {"ok", "reason", "cost"}.
func buy(id: String, wallet: RefCounted, level: int) -> Dictionary:
	var it := item(id)
	if it.is_empty():
		return _refused("unknown_item")
	if id in owned:
		return _refused("already_owned")
	if level < int(it.get("unlock_level", 1)):
		return _refused("locked")
	var cost := int(it["cost"])
	if not wallet.spend_bones(cost):
		return _refused("not_enough_bones", cost)
	owned.append(id)
	_put_in_slot(it["slot"], id)
	return {"ok": true, "reason": "", "cost": cost}


func equip(id: String) -> bool:
	if not id in owned or equipped.get(item(id).get("slot", ""), "") == id:
		return false
	_put_in_slot(item(id)["slot"], id)
	return true


## Empties a slot, if its data allows an empty slot.
func unequip(slot_name: String) -> bool:
	if not bool(slots.get(slot_name, {}).get("allow_empty", false)) or equipped.get(slot_name, "") == "":
		return false
	_put_in_slot(slot_name, "")
	return true


func snapshot() -> Dictionary:
	return {"owned": owned.duplicate(), "equipped": equipped.duplicate()}


## Restores saved state. Unknown ids and slots are ignored; an equipped item
## must also be owned.
func restore(saved: Dictionary) -> void:
	for id in saved.get("owned", []):
		if _items.has(id) and not id in owned:
			owned.append(id)
	var saved_equipped: Variant = saved.get("equipped", {})
	if typeof(saved_equipped) == TYPE_DICTIONARY:
		for slot_name in saved_equipped:
			var id: String = str(saved_equipped[slot_name])
			if not equipped.has(slot_name):
				continue
			if id == "" and bool(slots[slot_name].get("allow_empty", false)):
				equipped[slot_name] = ""
			elif id in owned and item(id)["slot"] == slot_name:
				equipped[slot_name] = id
	for slot_name in equipped:
		changed.emit(slot_name)


func _put_in_slot(slot_name: String, id: String) -> void:
	equipped[slot_name] = id
	changed.emit(slot_name)


func _refused(reason: String, cost: int = 0) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": cost}


static func validate(doc: Dictionary, known_assets: Array = []) -> Array[String]:
	var errors: Array[String] = []
	var slot_doc: Variant = doc.get("slots")
	var items: Variant = doc.get("items")
	if typeof(slot_doc) != TYPE_DICTIONARY or slot_doc.is_empty():
		return ["collection: 'slots' must be a non-empty object"]
	if typeof(items) != TYPE_ARRAY:
		return ["collection: 'items' must be an array"]
	var ids := {}
	var has_default := {}
	for it in items:
		if typeof(it) != TYPE_DICTIONARY or typeof(it.get("id")) != TYPE_STRING:
			errors.append("collection: every item needs a string id")
			continue
		var id: String = it["id"]
		if ids.has(id):
			errors.append("collection: duplicate item id '%s'" % id)
		ids[id] = true
		var slot_name: Variant = it.get("slot")
		if typeof(slot_name) != TYPE_STRING or not slot_doc.has(slot_name):
			errors.append("collection: item '%s' names unknown slot '%s'" % [id, slot_name])
		if not _non_negative(it.get("cost")):
			errors.append("collection: item '%s' cost must be zero or more" % id)
		elif int(it["cost"]) == 0 and typeof(slot_name) == TYPE_STRING:
			has_default[slot_name] = true
		if it.has("unlock_level") and not _non_negative(it["unlock_level"]):
			errors.append("collection: item '%s' unlock_level must be a number" % id)
		if not known_assets.is_empty() and not it.get("asset", "") in known_assets:
			errors.append("collection: item '%s' uses unknown asset '%s'" % [id, it.get("asset")])
	for slot_name in slot_doc:
		if String(slot_name).begins_with("_"):
			continue
		var spec: Variant = slot_doc[slot_name]
		if typeof(spec) != TYPE_DICTIONARY:
			errors.append("collection: slot '%s' must be an object" % slot_name)
			continue
		var has_items: bool = items.any(func(i: Variant) -> bool:
			return typeof(i) == TYPE_DICTIONARY and i.get("slot") == slot_name)
		if has_items and not has_default.has(slot_name) and not bool(spec.get("allow_empty", false)):
			errors.append("collection: slot '%s' cannot be empty, so it needs a free item" % slot_name)
	return errors


static func _non_negative(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) >= 0.0
