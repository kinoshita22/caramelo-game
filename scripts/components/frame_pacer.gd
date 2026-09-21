extends Node
## Keeps the overlay cheap to leave running: sets Engine.max_fps from what
## is happening (see FramePacing) and checks the power source now and then.
## Nothing here touches the simulation; ticks just arrive less often.

const FramePacing := preload("res://scripts/systems/frame_pacing.gd")

var config := {}
## Set by the main scene while a window (shop, menu...) is open.
var window_open := false
## The player's 30 FPS cap.
var cap_30 := false
var target := 60

var _idle_for := 0.0
var _power_check_in := 0.0
var _on_battery := false


func setup(performance: Dictionary) -> void:
	config = performance


func _input(event: InputEvent) -> void:
	# Only events inside the clickable region reach the game in overlay
	# mode, so any pointer or key event means someone is using it.
	if event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey:
		_idle_for = 0.0


func _process(delta: float) -> void:
	# Real seconds, not scaled game time.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	_idle_for += real_delta
	_power_check_in -= real_delta
	if _power_check_in <= 0.0:
		_power_check_in = float(config.get("check_power_seconds", 30.0))
		_on_battery = PlatformService.power_source() == "battery"
	var interacting := window_open or _idle_for < float(config.get("idle_after_seconds", 5.0))
	target = FramePacing.target_fps({
		"minimized": PlatformService.is_minimized(),
		"interacting": interacting,
		"on_battery": _on_battery,
		"cap_30": cap_30,
	}, config)
	if Engine.max_fps != target:
		Engine.max_fps = target
