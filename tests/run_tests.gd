extends SceneTree
## Runs every tests/test_*.gd. Each public method named test_* is one test.
##
## Usage:
##   godot --headless --path caramelo-game --script res://tests/run_tests.gd [-- --filter name]
##
## Exit code 0 = all passed, 1 = failures.

const TEST_DIR := "res://tests"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var filter := args[args.find("--filter") + 1] if args.has("--filter") and args.find("--filter") + 1 < args.size() else ""
	var passed := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR)).filter(
			func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	for file in files:
		var script: GDScript = load(TEST_DIR.path_join(file))
		if script == null:
			printerr("FAIL  %s: could not load" % file)
			failed += 1
			continue
		var names: Array = script.get_script_method_list().map(
				func(m: Dictionary) -> String: return m["name"]).filter(
				func(n: String) -> bool: return n.begins_with("test_") and (filter == "" or filter in n))
		names.sort()
		for name in names:
			var t: Object = script.new()
			t.call(name)
			if t.failures.is_empty():
				passed += 1
				print("ok    %s::%s" % [file.get_basename(), name])
			else:
				failed += 1
				printerr("FAIL  %s::%s" % [file.get_basename(), name])
				for f in t.failures:
					printerr("        ", f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
