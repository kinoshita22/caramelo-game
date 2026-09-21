extends RefCounted
## Bone spending: the four upgrade stats, dumbbell tiers and food tiers.
## Pure simulation, like Progression; it asks a wallet (Progression) to
## spend bones and never touches nodes.
##
## Everything here only ever speeds the loop up. Nothing can be sold, no
## balance can go negative, and a refused purchase changes nothing.

signal stat_upgraded(stat_name: String, new_level: int)
signal equipment_changed(tier_id: String)
signal food_changed(tier_id: String)
signal modifiers_changed()

const STATS := ["strength", "endurance", "speed", "recovery"]

var stat_levels := {}
var owned_equipment: Array[String] = []
var owned_food: Array[String] = []
var equipped_equipment := ""
var active_food := ""

var _upgrades := {}
var _equipment := {}  # id -> tier
var _food := {}
var _equipment_order: Array[String] = []
var _food_order: Array[String] = []


## upgrades/dumbbells/meals are the matching data files. Returns validation
## errors; nothing is applied on error.
func configure(upgrades: Dictionary, dumbbells: Dictionary, meals: Dictionary, known_assets: Array = []) -> Array[String]:
	var errors := validate(upgrades, dumbbells, meals, known_assets)
	if not errors.is_empty():
		return errors
	_upgrades = upgrades
	_equipment.clear()
	_food.clear()
	_equipment_order.clear()
	_food_order.clear()
	for tier in dumbbells["tiers"]:
		_equipment[tier["id"]] = tier
		_equipment_order.append(tier["id"])
	for tier in meals["tiers"]:
		_food[tier["id"]] = tier
		_food_order.append(tier["id"])
	stat_levels = {}
	for stat in STATS:
		stat_levels[stat] = 0
	equipped_equipment = dumbbells["default"]
	active_food = meals["default"]
	owned_equipment = [equipped_equipment]
	owned_food = [active_food]
	return errors


func max_stat_level() -> int:
	return int(_upgrades.get("max_level", 0))


func stat_level(stat_name: String) -> int:
	return int(stat_levels.get(stat_name, 0))


## Bones needed for the next level of a stat; 0 when it is maxed.
## Icon asset for a stat, or "" when the data gives none.
func stat_icon(stat_name: String) -> String:
	var icon: Variant = _upgrades.get("stats", {}).get(stat_name, {}).get("icon")
	return icon if typeof(icon) == TYPE_STRING else ""


func stat_cost(stat_name: String) -> int:
	var next_level := stat_level(stat_name) + 1
	if not stat_name in STATS or next_level > max_stat_level():
		return 0
	var cost: Dictionary = _upgrades["cost"]
	return int(roundf(float(cost["base"]) * pow(float(cost["growth"]), float(next_level - 1))))


## Buys one level of a stat. Returns {"ok", "reason", "cost", "level"}.
func upgrade_stat(stat_name: String, wallet: RefCounted) -> Dictionary:
	if not stat_name in STATS:
		return _refused("unknown_stat")
	if stat_level(stat_name) >= max_stat_level():
		return _refused("maxed")
	var cost := stat_cost(stat_name)
	if not wallet.spend_bones(cost):
		return _refused("not_enough_bones", cost)
	stat_levels[stat_name] = stat_level(stat_name) + 1
	stat_upgraded.emit(stat_name, stat_levels[stat_name])
	modifiers_changed.emit()
	return {"ok": true, "reason": "", "cost": cost, "level": stat_levels[stat_name]}


## Buys a dumbbell tier and equips it. Returns {"ok", "reason", "cost"}.
func buy_equipment(tier_id: String, wallet: RefCounted, level: int) -> Dictionary:
	return _buy(tier_id, wallet, level, _equipment, owned_equipment, "equipment")


## Buys a food tier and makes it active.
func buy_food(tier_id: String, wallet: RefCounted, level: int) -> Dictionary:
	return _buy(tier_id, wallet, level, _food, owned_food, "food")


func equip(tier_id: String) -> bool:
	if not tier_id in owned_equipment or equipped_equipment == tier_id:
		return false
	equipped_equipment = tier_id
	equipment_changed.emit(tier_id)
	modifiers_changed.emit()
	return true


func set_active_food(tier_id: String) -> bool:
	if not tier_id in owned_food or active_food == tier_id:
		return false
	active_food = tier_id
	food_changed.emit(tier_id)
	modifiers_changed.emit()
	return true


func equipment_tier(tier_id: String = "") -> Dictionary:
	return _equipment.get(tier_id if tier_id != "" else equipped_equipment, {})


func food_tier(tier_id: String = "") -> Dictionary:
	return _food.get(tier_id if tier_id != "" else active_food, {})


func equipment_ids() -> Array[String]:
	return _equipment_order.duplicate()


func food_ids() -> Array[String]:
	return _food_order.duplicate()


## Tiers the player could buy now: unlocked by level and not yet owned.
func available_equipment(level: int) -> Array[String]:
	return _available(level, _equipment_order, _equipment, owned_equipment)


func available_food(level: int) -> Array[String]:
	return _available(level, _food_order, _food, owned_food)


## Everything the rest of the game needs from the economy, in one place.
func modifiers() -> Dictionary:
	var per_level: Dictionary = _upgrades.get("stats", {})
	var strength := _effect(per_level, "strength")
	var endurance := _effect(per_level, "endurance")
	var speed := _effect(per_level, "speed")
	var recovery := _effect(per_level, "recovery")
	var rest_scale := 1.0 / (1.0 + recovery)
	var food: Dictionary = food_tier()
	var eating_speed := float(food.get("eating_speed", 1.0))
	return {
		"xp_multiplier": (1.0 + strength) * float(equipment_tier().get("xp_multiplier", 1.0)),
		"workout_duration_scale": (1.0 + endurance) / (1.0 + speed),
		"animation_speed": 1.0 + speed,
		"rest_duration_scale": rest_scale,
		"rest_rate_scale": 1.0 + recovery,
		"eating_duration_scale": rest_scale / eating_speed,
		"satiety_rate_scale": float(food.get("satiety_multiplier", 1.0)) * eating_speed,
	}


## Restores saved state (Phase 10). Unknown ids are ignored.
func restore(saved: Dictionary) -> void:
	for stat in STATS:
		stat_levels[stat] = clampi(int(saved.get("stats", {}).get(stat, 0)), 0, max_stat_level())
	for key in [["equipment", _equipment, owned_equipment], ["food", _food, owned_food]]:
		for id in saved.get("owned_" + key[0], []):
			if key[1].has(id) and not id in key[2]:
				key[2].append(id)
	if _equipment.has(saved.get("equipped_equipment", "")):
		equipped_equipment = saved["equipped_equipment"]
	if _food.has(saved.get("active_food", "")):
		active_food = saved["active_food"]
	if not equipped_equipment in owned_equipment:
		owned_equipment.append(equipped_equipment)
	if not active_food in owned_food:
		owned_food.append(active_food)
	modifiers_changed.emit()


## State for the save file.
func snapshot() -> Dictionary:
	return {
		"stats": stat_levels.duplicate(),
		"owned_equipment": owned_equipment.duplicate(),
		"owned_food": owned_food.duplicate(),
		"equipped_equipment": equipped_equipment,
		"active_food": active_food,
	}


func _effect(per_level: Dictionary, stat_name: String) -> float:
	return float(per_level.get(stat_name, {}).get("effect_per_level", 0.0)) * stat_level(stat_name)


func _available(level: int, order: Array[String], tiers: Dictionary, owned: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id in order:
		if not id in owned and level >= int(tiers[id]["unlock_level"]):
			out.append(id)
	return out


func _buy(tier_id: String, wallet: RefCounted, level: int, tiers: Dictionary,
		owned: Array[String], kind: String) -> Dictionary:
	if not tiers.has(tier_id):
		return _refused("unknown_tier")
	var tier: Dictionary = tiers[tier_id]
	if tier_id in owned:
		return _refused("already_owned")
	if level < int(tier["unlock_level"]):
		return _refused("locked")
	var cost := int(tier["cost"])
	if not wallet.spend_bones(cost):
		return _refused("not_enough_bones", cost)
	owned.append(tier_id)
	if kind == "equipment":
		equipped_equipment = tier_id
		equipment_changed.emit(tier_id)
	else:
		active_food = tier_id
		food_changed.emit(tier_id)
	modifiers_changed.emit()
	return {"ok": true, "reason": "", "cost": cost}


func _refused(reason: String, cost: int = 0) -> Dictionary:
	return {"ok": false, "reason": reason, "cost": cost}


static func validate(upgrades: Dictionary, dumbbells: Dictionary, meals: Dictionary, known_assets: Array = []) -> Array[String]:
	var errors: Array[String] = []
	var cost: Variant = upgrades.get("cost")
	if typeof(cost) != TYPE_DICTIONARY or not _positive(cost.get("base")) or not _positive(cost.get("growth")):
		errors.append("upgrades: cost.base and cost.growth must be positive numbers")
	if not _positive(upgrades.get("max_level")):
		errors.append("upgrades: max_level must be a positive number")
	var stats: Variant = upgrades.get("stats")
	if typeof(stats) != TYPE_DICTIONARY:
		errors.append("upgrades: 'stats' must be an object")
	else:
		for stat in STATS:
			var s: Variant = stats.get(stat)
			if typeof(s) != TYPE_DICTIONARY or not _positive(s.get("effect_per_level")):
				errors.append("upgrades: stats.%s needs a positive effect_per_level" % stat)
		for stat in stats:
			if not stat in STATS and not String(stat).begins_with("_"):
				errors.append("upgrades: unknown stat '%s'" % stat)
	errors.append_array(_validate_tiers(dumbbells, "dumbbells", ["xp_multiplier"], known_assets))
	errors.append_array(_validate_tiers(meals, "meals", ["satiety_multiplier", "eating_speed"], known_assets))
	return errors


static func _validate_tiers(doc: Dictionary, label: String, numbers: Array, known_assets: Array) -> Array[String]:
	var errors: Array[String] = []
	var tiers: Variant = doc.get("tiers")
	if typeof(tiers) != TYPE_ARRAY or tiers.is_empty():
		return ["%s: 'tiers' must be a non-empty array" % label]
	var ids := {}
	for tier in tiers:
		if typeof(tier) != TYPE_DICTIONARY or typeof(tier.get("id")) != TYPE_STRING:
			errors.append("%s: every tier needs a string id" % label)
			continue
		var id: String = tier["id"]
		if ids.has(id):
			errors.append("%s: duplicate tier id '%s'" % [label, id])
		ids[id] = true
		if not _non_negative(tier.get("cost")):
			errors.append("%s: tier '%s' cost must be zero or more" % [label, id])
		if not _positive(tier.get("unlock_level")):
			errors.append("%s: tier '%s' unlock_level must be a positive number" % [label, id])
		for key in numbers:
			if not _positive(tier.get(key)):
				errors.append("%s: tier '%s' %s must be a positive number" % [label, id, key])
		if not known_assets.is_empty() and not tier.get("asset", "") in known_assets:
			errors.append("%s: tier '%s' uses unknown asset '%s'" % [label, id, tier.get("asset")])
	if not ids.has(doc.get("default", "")):
		errors.append("%s: 'default' must name one of the tiers" % label)
	elif int(doc["tiers"][0].get("cost", -1)) != 0:
		errors.append("%s: the first tier must cost nothing" % label)
	return errors


static func _positive(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) > 0.0


static func _non_negative(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and float(v) >= 0.0
