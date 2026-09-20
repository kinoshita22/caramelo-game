extends Node
## Bridges the simulation to the presentation: ticks a BehaviourLoop and
## plays the animation group each state maps to. The loop knows nothing
## about nodes; the animator knows nothing about the loop.

const BehaviourLoop := preload("res://scripts/systems/behaviour_loop.gd")

var loop := BehaviourLoop.new()
var animator: Node2D
var enabled := true


## Returns validation errors for data/balance/behaviour.json.
func setup(character_animator: Node2D, balance: Dictionary) -> Array[String]:
	animator = character_animator
	var errors := loop.configure(balance, animator.groups.keys())
	if not errors.is_empty():
		return errors
	loop.state_changed.connect(_on_state_changed)
	_play_current()
	return errors


func _process(delta: float) -> void:
	if enabled:
		loop.tick(delta)


func _on_state_changed(_from: String, _to: String) -> void:
	_play_current()


func _play_current() -> void:
	if animator == null:
		return
	var group := loop.group_for(loop.state)
	if group != "":
		animator.play(group, true)
