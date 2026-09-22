extends RefCounted
## Chooses the frame rate for the overlay from what is going on. Pure, so
## tests can check every case.
##
## Order of precedence: minimized (nothing to see), then someone using the
## window (smooth), then Caramelo mid-movement (a hop or a dissolve, which
## the idle rate would make steppy), then idle, then battery lowers idle
## further. The player's 30 FPS cap limits everything, and on battery it also
## limits the moving rate.


## state: {"minimized": bool, "interacting": bool, "moving": bool,
##         "on_battery": bool, "cap_30": bool}.
## config: data/settings/performance.json.
static func target_fps(state: Dictionary, config: Dictionary) -> int:
	var fps: int
	if state.get("minimized", false):
		fps = int(config.get("minimized_fps", 5))
	elif state.get("interacting", false):
		fps = int(config.get("interactive_fps", 60))
	elif state.get("moving", false):
		fps = int(config.get("moving_fps", 60))
		if state.get("on_battery", false):
			fps = mini(fps, int(config.get("capped_fps", 30)))
	elif state.get("on_battery", false):
		fps = mini(int(config.get("battery_fps", 15)), int(config.get("idle_fps", 20)))
	else:
		fps = int(config.get("idle_fps", 20))
	if state.get("cap_30", false):
		fps = mini(fps, int(config.get("capped_fps", 30)))
	return maxi(fps, 1)


static func validate(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["interactive_fps", "capped_fps", "moving_fps", "idle_fps", "battery_fps", "minimized_fps"]:
		var v: Variant = config.get(key)
		if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) or int(v) < 1 or int(v) > 240:
			errors.append("performance: %s must be 1-240" % key)
	for key in ["idle_after_seconds", "check_power_seconds"]:
		var v: Variant = config.get(key)
		if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) or float(v) <= 0.0:
			errors.append("performance: %s must be a positive number" % key)
	return errors
