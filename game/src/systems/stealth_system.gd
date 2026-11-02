class_name StealthSystem
extends RefCounted
## Vision cones, line of sight, noise, alert escalation and takedowns
## (spec section 5). Pure logic so every rule is testable headless.

enum Alert { UNAWARE, SUSPICIOUS, SEARCHING, COMBAT }

const VIEW_DISTANCE := 260.0
const VIEW_ANGLE_DEG := 100.0
const SEARCH_TIME := 5.0
const ALERT_DECAY := 3.0
const HEAR_DISTANCE := 150.0

var alert: int = Alert.UNAWARE
var alert_value: float = 0.0
var search_timer: float = 0.0
var last_seen: Vector2 = Vector2.ZERO
var has_last_seen: bool = false
var noise_events: Array = []


## Can the guard see the target? Checks distance, cone and wall occlusion.
func can_see(guard_pos: Vector2, guard_dir: Vector2, target_pos: Vector2,
		walls: Array, view_scale: float = 1.0) -> bool:
	var to_target := target_pos - guard_pos
	var dist := to_target.length()
	if dist > VIEW_DISTANCE * view_scale:
		return false
	if dist < 0.001:
		return true
	var angle := rad_to_deg(guard_dir.angle_to(to_target))
	if absf(angle) > VIEW_ANGLE_DEG * 0.5:
		return false
	for w in walls:
		if w is Rect2 and CombatSystem.segment_hits_rect(guard_pos, target_pos, w):
			return false
	return true


## Emit a sound the guards can hear.
func make_noise(pos: Vector2, loudness: float = 1.0) -> void:
	noise_events.append({"pos": pos, "loudness": loudness})


func hears(guard_pos: Vector2, guard_hearing: float = 1.0) -> bool:
	for n in noise_events:
		if guard_pos.distance_to(n["pos"]) <= HEAR_DISTANCE * float(n["loudness"]) * guard_hearing:
			return true
	return false


func clear_noise() -> void:
	noise_events.clear()


## Per-frame update. Returns the new alert state.
func tick(delta: float, sees: bool, hears: bool, target_pos: Vector2) -> int:
	if sees:
		alert_value = minf(1.0, alert_value + delta * 2.5)
		last_seen = target_pos
		has_last_seen = true
		search_timer = 0.0
	elif hears:
		alert_value = minf(1.0, alert_value + delta * 1.2)
	else:
		alert_value = maxf(0.0, alert_value - delta / ALERT_DECAY)

	if alert_value >= 1.0:
		alert = Alert.COMBAT
	elif alert == Alert.COMBAT:
		# lost them: drop into a search instead of instantly forgetting
		alert = Alert.SEARCHING
		search_timer = SEARCH_TIME
	elif alert == Alert.SEARCHING:
		search_timer = maxf(0.0, search_timer - delta)
		if search_timer == 0.0:
			alert = Alert.UNAWARE if alert_value <= 0.0 else Alert.SUSPICIOUS
	elif alert_value >= 0.5:
		alert = Alert.SUSPICIOUS
	elif alert_value <= 0.0:
		alert = Alert.UNAWARE
	return alert


func is_combat() -> bool:
	return alert == Alert.COMBAT


func is_searching() -> bool:
	return alert == Alert.SEARCHING


## Takedown allowed only from behind, close, and out of combat.
func can_takedown(guard_pos: Vector2, guard_dir: Vector2, attacker_pos: Vector2,
		stealth_skill: bool = false) -> bool:
	if alert == Alert.COMBAT:
		return false
	if attacker_pos.distance_to(guard_pos) > (64.0 if stealth_skill else 48.0):
		return false
	var to_attacker := (attacker_pos - guard_pos).normalized()
	# behind = more than 100 degrees away from facing
	return rad_to_deg(guard_dir.angle_to(to_attacker)) > 100.0


func reset() -> void:
	alert = Alert.UNAWARE
	alert_value = 0.0
	search_timer = 0.0
	has_last_seen = false
	clear_noise()
