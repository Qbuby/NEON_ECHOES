class_name PlayerStateMachine
extends Node
## Drives the 9 required player animations and exposes a deterministic state
## API for automated testing (spec section 3).
##
## States: idle, walk, run, shoot, reload, melee, dodge, hit, death.
## The machine owns no physics: it reads intent from the Player and plays the
## matching animation, so a headless test can drive it without a scene.

signal state_changed(from_state: String, to_state: String)

const STATES := ["idle", "walk", "run", "shoot", "reload", "melee", "dodge", "hit", "death"]
## States that lock out movement input until they finish.
const LOCKING := {"dodge": true, "hit": true, "death": true, "melee": true}
## States that must play to completion before another can start.
const ONE_SHOT := {"shoot": true, "reload": true, "melee": true, "dodge": true, "hit": true, "death": true}

var state: String = "idle"
var previous_state: String = "idle"
var state_time: float = 0.0
var facing: String = "s"
var transition_count: int = 0

var _locked_left: float = 0.0
var _one_shot_left: float = 0.0


## Force a state. Returns false when the request is rejected (still locked).
func request(next: String) -> bool:
	if not STATES.has(next):
		return false
	if next == state:
		return true
	# death is terminal
	if state == "death":
		return false
	# locking states cannot be interrupted
	if _locked_left > 0.0 and next != "death":
		return false
	# one-shots must finish (except death interrupt and dodge-cancel)
	if _one_shot_left > 0.0 and next != "death":
		return false
	_transition(next)
	return true


## Called every frame with the intent computed by the Player.
func tick(delta: float, moving: bool, running: bool, can_shoot: bool) -> void:
	state_time += delta
	if _locked_left > 0.0:
		_locked_left = maxf(0.0, _locked_left - delta)
	if _one_shot_left > 0.0:
		_one_shot_left = maxf(0.0, _one_shot_left - delta)

	if state == "death":
		return
	if _one_shot_left > 0.0 or _locked_left > 0.0:
		if _one_shot_left <= 0.0 and _locked_left <= 0.0:
			# finished a locking one-shot: fall back to movement
			_transition("walk" if moving else "idle")
		return

	if moving:
		var want := "run" if running else "walk"
		if state != want:
			_transition(want)
	elif state != "idle":
		_transition("idle")


func play_shoot(duration: float = 0.20) -> bool:
	if _locked_left > 0.0 or _one_shot_left > 0.0:
		return false
	_transition("shoot")
	_one_shot_left = duration
	return true


func play_reload(duration: float = 1.10) -> bool:
	if _one_shot_left > 0.0:
		return false
	_transition("reload")
	_one_shot_left = duration
	_locked_left = duration
	return true


func play_melee(duration: float = 0.34) -> bool:
	if _locked_left > 0.0 or _one_shot_left > 0.0:
		return false
	_transition("melee")
	_one_shot_left = duration
	_locked_left = duration * 0.55
	return true


func play_dodge(duration: float = 0.30) -> bool:
	if _locked_left > 0.0 or _one_shot_left > 0.0:
		return false
	_transition("dodge")
	_one_shot_left = duration
	_locked_left = duration
	return true


func play_hit(duration: float = 0.22) -> bool:
	if state == "death":
		return false
	_transition("hit")
	_one_shot_left = duration
	_locked_left = duration * 0.6
	return true


func play_death(duration: float = 2.0) -> void:
	_transition("death")
	_one_shot_left = duration
	_locked_left = duration


func is_locked() -> bool:
	return _locked_left > 0.0 or _one_shot_left > 0.0


func set_facing(dir: String) -> void:
	facing = dir


## Animation name for the current state, resolving against SpriteFrames.
func animation_for(frames: SpriteFrames, dir: String) -> String:
	if frames == null:
		return ""
	var candidates: Array[String] = ["%s_%s" % [state, dir]]
	var fallbacks := {"ne": ["e", "n"], "nw": ["w", "n"], "se": ["e", "s"], "sw": ["w", "s"]}
	for fb in fallbacks.get(dir, []):
		candidates.append("%s_%s" % [state, fb])
	candidates.append("%s_s" % state)
	candidates.append(state)
	for c in candidates:
		if frames.has_animation(c):
			return c
	return ""


func _transition(next: String) -> void:
	if next == state:
		return
	previous_state = state
	state = next
	state_time = 0.0
	transition_count += 1
	state_changed.emit(previous_state, state)
