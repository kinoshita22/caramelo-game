extends Node
## Bridges the simulation to the presentation: ticks a BehaviourLoop and
## plays the animation group each state maps to. The loop knows nothing
## about nodes; the animator knows nothing about the loop.

const BehaviourLoop := preload("res://scripts/systems/behaviour_loop.gd")

var loop := BehaviourLoop.new()
var animator: Node2D
var enabled := true
## Progression system; when set, finished workouts pay XP and bones and can
## trigger a celebration, a bone reward or an evolution.
var progression: RefCounted
## Economy system; when set, its upgrades scale the loop and the payouts.
var economy: RefCounted


## Returns validation errors for data/balance/behaviour.json.
func setup(character_animator: Node2D, balance: Dictionary) -> Array[String]:
	animator = character_animator
	var errors := loop.configure(balance, animator.groups.keys())
	if not errors.is_empty():
		return errors
	loop.state_changed.connect(_on_state_changed)
	loop.action_completed.connect(_on_action_completed)
	if progression != null:
		animator.set_form(progression.form)
	if economy != null:
		economy.modifiers_changed.connect(apply_modifiers)
		apply_modifiers()
	_play_current()
	return errors


func _process(delta: float) -> void:
	if enabled:
		loop.tick(delta)


func _on_state_changed(_from: String, to: String) -> void:
	# The form swap happens inside the evolution state, where the character
	# is mid power-surge and no other action can interrupt.
	if to == BehaviourLoop.EVOLUTION and progression != null and animator != null:
		animator.set_form(progression.form)
	_play_current()


## A finished workout is what pays out; interrupted ones pay nothing.
func _on_action_completed(state_name: String) -> void:
	if state_name != BehaviourLoop.WORKOUT or progression == null:
		return
	var xp_multiplier: float = economy.modifiers()["xp_multiplier"] if economy != null else 1.0
	var result: Dictionary = progression.complete_workout(xp_multiplier)
	if result["form_changed"]:
		loop.request(BehaviourLoop.PRE_EVOLUTION)
	elif result["levels_gained"] > 0:
		loop.request(BehaviourLoop.CELEBRATION)
	elif result["bonus"]:
		loop.request(BehaviourLoop.REWARD)


## Pushes the economy's multipliers into the loop and the animator.
func apply_modifiers() -> void:
	if economy == null:
		return
	var m: Dictionary = economy.modifiers()
	loop.apply_modifiers(m)
	if animator != null:
		animator.speed_scale = m["animation_speed"]


func _play_current() -> void:
	if animator == null:
		return
	var group := loop.group_for(loop.state)
	if group != "":
		animator.play(group, true)
