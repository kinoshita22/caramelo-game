extends Node
## Bridges the simulation to the presentation: ticks a BehaviourLoop and
## plays the animation group each state maps to. The loop knows nothing
## about nodes; the animator knows nothing about the loop.

const BehaviourLoop := preload("res://scripts/systems/behaviour_loop.gd")

## One lift paid `xp`, for the number that floats over his head.
signal rep_paid(xp: int)

var loop := BehaviourLoop.new()
var animator: Node2D
var enabled := true
## Progression system; when set, finished workouts pay XP and bones and can
## trigger a celebration, a bone reward or an evolution.
var progression: RefCounted
## Economy system; when set, its upgrades scale the loop and the payouts.
var economy: RefCounted

var _balance := {}
## The level and form he started this workout at, so a level-up earned
## halfway through still gets its celebration when the session ends.
var _level_at_session := 1
var _form_at_session := 1


## Returns validation errors for data/balance/behaviour.json.
func setup(character_animator: Node2D, balance: Dictionary) -> Array[String]:
	animator = character_animator
	_balance = balance
	# The loop decides what comes after each state, not the animation data.
	animator.follow_next = false
	var errors := loop.configure(balance, animator.groups.keys())
	if not errors.is_empty():
		return errors
	loop.state_changed.connect(_on_state_changed)
	loop.action_completed.connect(_on_action_completed)
	animator.loop_completed.connect(_on_loop_completed)
	if progression != null:
		animator.set_form(progression.form)
	if economy != null:
		economy.modifiers_changed.connect(apply_modifiers)
		apply_modifiers()
	_play_current()
	return errors


## Back to the start of a day: idle, rested and fed, with no history. Used
## by a reset; the systems it reads are put back by whoever asks.
func restart() -> void:
	loop.configure(_balance, animator.groups.keys())
	apply_modifiers()
	if progression != null:
		animator.set_form(progression.form)
	_play_current()


func _process(delta: float) -> void:
	if enabled:
		loop.tick(delta)


## Every lift of the dumbbells pays, so the XP arrives while he works
## rather than all at once at the end. Nothing else in the loop pays by the
## frame.
func _on_loop_completed(group_name: String) -> void:
	if progression == null or loop.state != BehaviourLoop.WORKOUT or group_name != loop.group_for(BehaviourLoop.WORKOUT):
		return
	var xp_multiplier: float = economy.modifiers()["xp_multiplier"] if economy != null else 1.0
	var result: Dictionary = progression.complete_rep(xp_multiplier)
	if result["xp_awarded"] > 0.0:
		rep_paid.emit(int(result["xp_awarded"]))


func _on_state_changed(_from: String, to: String) -> void:
	# The form swap happens inside the evolution state, where the character
	# is mid power-surge and no other action can interrupt.
	if to == BehaviourLoop.EVOLUTION and progression != null and animator != null:
		animator.set_form(progression.form)
	if to == BehaviourLoop.WORKOUT and progression != null:
		_level_at_session = progression.level
		_form_at_session = progression.form
	_play_current()


## A finished workout is what pays the bones; interrupted ones pay none.
## The XP was paid lift by lift along the way, so what is settled here is
## the finishing bonus and what the session as a whole earned him: a level
## reached halfway through still gets its celebration, and nothing
## interrupts him mid-set to hand it over.
func _on_action_completed(state_name: String) -> void:
	if state_name != BehaviourLoop.WORKOUT or progression == null:
		return
	var xp_multiplier: float = economy.modifiers()["xp_multiplier"] if economy != null else 1.0
	var result: Dictionary = progression.complete_workout(xp_multiplier)
	if progression.form != _form_at_session:
		loop.request(BehaviourLoop.PRE_EVOLUTION)
	elif progression.level > _level_at_session:
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
