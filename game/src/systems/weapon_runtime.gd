class_name WeaponRuntime
extends RefCounted
## Per-weapon state: ammo, cooldown, reload timer. Data-driven from
## data/weapons.json so all 10 share one code path but behave differently.

var def: Dictionary
var ammo: int = 0
var cooldown: float = 0.0
var reloading: float = 0.0
var shots_fired: int = 0
var shots_hit: int = 0


func _init(weapon_def: Dictionary) -> void:
	def = weapon_def
	ammo = int(def.get("mag", 0))


func is_melee() -> bool:
	return String(def.get("class", "")) == "melee"


func max_ammo() -> int:
	return int(def.get("mag", 0))


func can_fire() -> bool:
	if reloading > 0.0:
		return false
	if cooldown > 0.0:
		return false
	if not is_melee() and ammo <= 0:
		return false
	return true


## Consume one shot. Returns true when the shot actually went out.
func fire() -> bool:
	if not can_fire():
		return false
	if not is_melee():
		ammo -= 1
	cooldown = float(def.get("rate", 0.2))
	shots_fired += 1
	return true


func start_reload() -> bool:
	if is_melee() or reloading > 0.0 or ammo >= max_ammo():
		return false
	reloading = float(def.get("reload", 1.0))
	return true


func tick(delta: float) -> bool:
	## Returns true on the frame the reload completes.
	var done := false
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)
	if reloading > 0.0:
		reloading = maxf(0.0, reloading - delta)
		if reloading == 0.0:
			ammo = max_ammo()
			done = true
	return done


func reserve_needed() -> int:
	return max_ammo() - ammo


func accuracy() -> float:
	return 100.0 * float(shots_hit) / float(maxi(1, shots_fired))


func to_dict() -> Dictionary:
	return {"id": def.get("id", ""), "ammo": ammo}


func from_dict(d: Dictionary) -> void:
	ammo = int(d.get("ammo", max_ammo()))
