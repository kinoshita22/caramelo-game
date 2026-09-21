extends "res://tests/lib/test_case.gd"
## One copy of the game at a time. Ports here are private to the tests.

const SingleInstance := preload("res://scripts/autoload/single_instance.gd")


func _args(port: int, extra: Array = []) -> PackedStringArray:
	return PackedStringArray(["--instance-port", str(port)] + extra)


func test_first_copy_claims_the_port() -> void:
	var first: Node = SingleInstance.new()
	check(first.claim(_args(47950)), "nobody else running: go ahead")
	check(not SingleInstance.ask_existing_to_show(47951), "an unused port has nobody to ask")
	first.release()
	first.free()


func test_allow_multiple_skips_the_check() -> void:
	var first: Node = SingleInstance.new()
	first.claim(_args(47952))
	var second: Node = SingleInstance.new()
	check(second.claim(_args(47952, ["--allow-multiple"])), "--allow-multiple always runs")
	first.release()
	first.free()
	second.free()


func test_a_port_owned_by_another_program_does_not_stop_the_game() -> void:
	var stranger := TCPServer.new()
	check_eq(stranger.listen(47953, "127.0.0.1"), OK, "some other program holds the port")
	var copy: Node = SingleInstance.new()
	check(copy.claim(_args(47953)), "it does not answer like the game, so the game runs anyway")
	stranger.stop()
	copy.free()


var _running: Node
var _keep_polling := true


func _poll_running_copy() -> void:
	while _keep_polling:
		_running.poll()
		OS.delay_msec(5)


func test_second_copy_is_turned_away_and_the_first_is_asked_to_show() -> void:
	_running = SingleInstance.new()
	check(_running.claim(_args(47954)), "first copy runs")
	var asked := [false]
	_running.show_requested.connect(func() -> void: asked[0] = true)
	var thread := Thread.new()
	thread.start(_poll_running_copy)  # the running copy keeps answering
	var second: Node = SingleInstance.new()
	var may_run: bool = second.claim(_args(47954))
	_keep_polling = false
	thread.wait_to_finish()
	check(not may_run, "a second copy must not run")
	check(asked[0], "the running copy was asked to come to the front")
	_running.release()
	_running.free()
	second.free()
