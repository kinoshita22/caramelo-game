extends Node2D
## Main scene: builds the island stage, puts the window into overlay or
## windowed mode, keeps the stage fitted to the window and keeps the
## click-through region in sync.
##
## Clicking Caramelo opens the training window; the dumbbell rack and the
## food station open their purchase windows. Escape opens the menu.
##
## Keys: F3 toggles the debug overlay; [ and ] cycle animation groups;
## - and = cycle forms; X grants a level's worth of XP, B grants bones,
## 1-4 upgrade the four stats, E and F buy the next dumbbell or meal.
## Preview options: --bones N, --equip <tier id>, --meal <tier id>,
## --open-shop equipment|food|upgrades|menu.
## Command-line overrides (after --): --display-mode overlay|windowed,
## --overlay-scale N, --corner top_left|top_right|bottom_left|bottom_right,
## --window-size WxH, --debug-overlay, --animation group [--animation-frame i], --form N,
## --time-scale N (speeds up the autonomous loop for testing), --start-level N,
## --screenshot path.png [--screenshot-frames N].

const DebugOverlay := preload("res://scripts/components/stage_debug_overlay.gd")
const IslandStage := preload("res://scripts/components/island_stage.gd")
const ShopModal := preload("res://scripts/components/shop_modal.gd")
const UpgradesModal := preload("res://scripts/components/upgrades_modal.gd")
const MenuModal := preload("res://scripts/components/menu_modal.gd")
const Hud := preload("res://scripts/components/hud.gd")
## Clicking Caramelo opens the training window.
const CHARACTER_ACTION := "upgrades"
const PlatformServiceScript := preload("res://scripts/autoload/platform_service.gd")
const DisplayLayout := preload("res://scripts/components/display_layout.gd")
const LAYOUT_PATH := "res://data/environment/island_layout.json"
const SETTINGS_PATH := "res://data/settings/display_defaults.json"
const ANIMATIONS_PATH := "res://data/animations/animation_groups.json"
const BEHAVIOUR_PATH := "res://data/balance/behaviour.json"

@onready var stage: Node2D = $Stage

var settings: Dictionary = {}
var window_polygon := PackedVector2Array()
var _debug: Node2D
var _shop: Control
var _upgrades: Control
var _menu: Control
var _hud: Control
var _screenshot_path := ""
var _screenshot_frames := 0


func _ready() -> void:
	var content: RefCounted = ContentCatalog.data
	settings = DisplayLayout.load_settings(content.read_json(SETTINGS_PATH), OS.get_cmdline_user_args())
	var layout: Variant = content.read_json(LAYOUT_PATH)
	var animations: Variant = content.read_json(ANIMATIONS_PATH)
	var errors: Array[String] = []
	if typeof(layout) != TYPE_DICTIONARY or typeof(animations) != TYPE_DICTIONARY:
		errors.append("island_layout.json or animation_groups.json missing or invalid")
	else:
		errors = stage.build(layout, content, animations)
		if errors.is_empty():
			if settings.has("bones"):
				GameState.progression.add_bones(int(settings["bones"]))
			# Preview options: hand over a tier without paying for it.
			for pair in [["equip", "equipment"], ["meal", "food"]]:
				if settings.has(pair[0]):
					GameState.economy.restore({"owned_%s" % pair[1]: [settings[pair[0]]],
							("equipped_equipment" if pair[1] == "equipment" else "active_food"): settings[pair[0]]})
			if settings.has("start_level"):
				GameState.progression.restore(int(settings["start_level"]), 0.0, GameState.progression.bones)
				stage.animator.set_form(GameState.progression.form)
			if settings.has("form"):
				stage.animator.set_form(int(settings["form"]))
			if settings.has("animation"):
				# Previewing one group: leave the autonomous loop switched off.
				stage.animator.play(settings["animation"], true)
				if settings.has("animation_frame"):
					stage.animator.freeze_at(int(settings["animation_frame"]))
			else:
				var balance: Variant = content.read_json(BEHAVIOUR_PATH)
				if typeof(balance) != TYPE_DICTIONARY:
					errors.append("behaviour.json missing or invalid")
				else:
					errors.append_array(GameState.errors)
					errors.append_array(stage.start_behaviour(balance, GameState.progression, GameState.economy))
			if settings.has("time_scale"):
				Engine.time_scale = maxf(0.01, float(settings["time_scale"]))
	if not content.is_valid():
		errors.append_array(content.errors)
	if not errors.is_empty():
		for e in errors:
			push_error(e)
		settings["mode"] = "windowed"

	_debug = DebugOverlay.new()
	_debug.stage = stage
	_debug.visible = settings["debug_overlay"]
	stage.add_child(_debug)

	_build_ui()
	_apply_mode()
	get_viewport().size_changed.connect(_refit)
	_refit()
	match settings.get("open_shop", ""):
		"": pass
		"upgrades": _open_upgrades()
		"menu": _open_menu()
		var shop: _open_shop("shop_%s" % shop)
	_screenshot_path = settings.get("screenshot", "")
	_screenshot_frames = int(settings.get("screenshot_frames", 10))


## Click-through windows live on their own layer, above the island.
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	_hud = Hud.new()
	_hud.name = "Hud"
	layer.add_child(_hud)
	_hud.setup(ContentCatalog.data, GameState.progression)
	_hud.upgrades_requested.connect(_open_upgrades)
	_hud.wardrobe_requested.connect(func() -> void: print("Wardrobe: waiting on cosmetic art"))
	_hud.menu_requested.connect(_open_menu)

	_shop = ShopModal.new()
	_shop.name = "Shop"
	_shop.visible = false
	_shop.closed.connect(_on_modal_closed)
	layer.add_child(_shop)

	_upgrades = UpgradesModal.new()
	_upgrades.name = "Upgrades"
	_upgrades.visible = false
	_upgrades.closed.connect(_on_modal_closed)
	layer.add_child(_upgrades)

	_menu = MenuModal.new()
	_menu.name = "Menu"
	_menu.visible = false
	_menu.closed.connect(_on_modal_closed)
	_menu.mode_toggle_requested.connect(_toggle_display_mode)
	_menu.quit_requested.connect(func() -> void: get_tree().quit())
	layer.add_child(_menu)


func _open_shop(action: String) -> void:
	_shop.open(ContentCatalog.data, GameState.economy, GameState.progression, action)
	_take_all_clicks()


func _open_upgrades() -> void:
	_upgrades.open(ContentCatalog.data, GameState.economy, GameState.progression)
	_take_all_clicks()


func _open_menu() -> void:
	_menu.open(ContentCatalog.data, PlatformService.mode)
	_take_all_clicks()


## While a window is open the whole window takes clicks, not just the island.
func _take_all_clicks() -> void:
	PlatformService.set_hit_polygon(_window_rect_polygon())


func _on_modal_closed() -> void:
	PlatformService.set_hit_polygon(window_polygon)


func _toggle_display_mode() -> void:
	settings["mode"] = "windowed" if PlatformService.mode == "overlay" else "overlay"
	_apply_mode()
	_refit()
	_menu.close()


func _window_rect_polygon() -> PackedVector2Array:
	var size := Vector2(DisplayServer.window_get_size())
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])


func _apply_mode() -> void:
	var o: Dictionary = settings["overlay"]
	var screen := PlatformService.resolve_screen(int(o["screen"]))
	if settings["mode"] == "overlay" and PlatformService.transparency_available():
		var usable := DisplayServer.screen_get_usable_rect(screen)
		var size := DisplayLayout.overlay_size(stage.bounds.size, float(o["scale"]), usable.size, int(o["margin_px"]))
		var pos := PlatformServiceScript.corner_position(usable, size, o["corner"], int(o["margin_px"]))
		PlatformService.enter_overlay(Rect2i(pos, size), bool(o["always_on_top"]))
		return
	if settings["mode"] == "overlay":
		push_warning("Window transparency unavailable; falling back to windowed mode.")
	var w: Dictionary = settings["windowed"]
	PlatformService.enter_windowed(Vector2i(int(w["size"][0]), int(w["size"][1])), Color(w["background"]), screen)


func _refit() -> void:
	var margin := 0.0 if PlatformService.mode == "overlay" else float(settings["fit_margin"])
	var t := DisplayLayout.fit(stage.bounds, get_viewport().get_visible_rect(), margin)
	stage.scale = Vector2.ONE * t["scale"]
	stage.position = t["position"]
	_debug.queue_redraw()
	var to_window := get_viewport().get_final_transform() * stage.get_global_transform_with_canvas()
	window_polygon = to_window * stage.hit_polygon
	PlatformService.set_hit_polygon(window_polygon)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point := stage.to_local(get_global_mouse_position())
		var action := IslandStage.click_action_at(stage.placements, point)
		if action == "" and stage.character != null and _character_rect().has_point(point):
			action = CHARACTER_ACTION
		match action:
			"": pass
			CHARACTER_ACTION: _open_upgrades()
			_: _open_shop(action)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			if _menu.visible:
				_menu.close()
			else:
				_open_menu()
		KEY_F3:
			_debug.visible = not _debug.visible
			_debug.queue_redraw()
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			_cycle_group(1 if event.keycode == KEY_BRACKETRIGHT else -1)
		KEY_MINUS, KEY_EQUAL:
			_cycle_form(1 if event.keycode == KEY_EQUAL else -1)
		KEY_X:
			var p: RefCounted = GameState.progression
			p.add_xp(maxf(p.xp_to_next(p.level) - p.xp, 1.0))
		KEY_B:
			GameState.progression.add_bones(500)
		KEY_1, KEY_2, KEY_3, KEY_4:
			var stat: String = GameState.economy.STATS[event.keycode - KEY_1]
			print("upgrade %s: %s" % [stat, GameState.economy.upgrade_stat(stat, GameState.progression)])
		KEY_E, KEY_F:
			_buy_next(event.keycode == KEY_E)


## Where Caramelo stands now, as a clickable box.
func _character_rect() -> Rect2:
	var size: Vector2 = ContentCatalog.data.max_character_canvas() * float(stage.character_scale)
	var at: Vector2 = stage.character.position
	return Rect2(at.x - size.x / 2.0, at.y - size.y, size.x, size.y)


func _cycle_group(step: int) -> void:
	if stage.animator == null:
		return
	var names: Array = stage.animator.groups.keys()
	var i := names.find(stage.animator.group)
	stage.animator.play(names[posmod(i + step, names.size())], true)


## Buys the next affordable dumbbell tier (equipment) or meal (food).
func _buy_next(equipment: bool) -> void:
	var e: RefCounted = GameState.economy
	var level: int = GameState.progression.level
	var ids: Array = e.available_equipment(level) if equipment else e.available_food(level)
	if ids.is_empty():
		print("nothing to buy yet")
		return
	var result: Dictionary = e.buy_equipment(ids[0], GameState.progression, level) if equipment \
			else e.buy_food(ids[0], GameState.progression, level)
	print("buy %s: %s" % [ids[0], result])


func _cycle_form(step: int) -> void:
	if stage.animator == null:
		return
	var forms: Array[int] = ContentCatalog.data.form_numbers()
	var i := forms.find(stage.animator.form)
	stage.animator.set_form(forms[posmod(i + step, forms.size())])


func _process(_delta: float) -> void:
	if _screenshot_path == "":
		return
	_screenshot_frames -= 1
	if _screenshot_frames > 0:
		return
	var path := _screenshot_path
	_screenshot_path = ""
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	var meta := {
		"mode": PlatformService.mode,
		"window_size": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"window_position": [DisplayServer.window_get_position().x, DisplayServer.window_get_position().y],
		"hit_polygon_window_px": Array(window_polygon).map(func(p: Vector2) -> Array: return [p.x, p.y]),
		"stage_scale": stage.scale.x,
		"animation": {"group": stage.animator.group, "slot": stage.animator.current_slot()} if stage.animator != null else {},
		"behaviour": {"state": stage.behaviour.loop.state, "energy": stage.behaviour.loop.energy,
				"satiety": stage.behaviour.loop.satiety,
				"recent_states": stage.behaviour.loop.history().slice(-14)} if stage.behaviour != null else {},
		"progression": {"level": GameState.progression.level, "form": GameState.progression.form,
				"bones": GameState.progression.bones, "xp": GameState.progression.xp},
		"economy": {"stats": GameState.economy.stat_levels, "equipped": GameState.economy.equipped_equipment,
				"food": GameState.economy.active_food, "modifiers": GameState.economy.modifiers()},
	}
	var f := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	get_tree().quit()
