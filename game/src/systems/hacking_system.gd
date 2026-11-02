class_name HackingSystem
extends RefCounted
## Six hacking operations with target, range, RAM cost, cooldown and a real
## state change (spec section 6).

const OPS := {
	"camera_slice": {"name": "Camera Slice", "ram": 2, "cooldown": 6.0, "range": 320.0, "effect": "camera_off"},
	"device_toggle": {"name": "Device Toggle", "ram": 1, "cooldown": 2.0, "range": 120.0, "effect": "device_toggle"},
	"optics_glitch": {"name": "Optics Glitch", "ram": 3, "cooldown": 9.0, "range": 280.0, "effect": "blind"},
	"weapon_lock": {"name": "Weapon Lock", "ram": 4, "cooldown": 12.0, "range": 240.0, "effect": "disable_weapon"},
	"turret_hijack": {"name": "Turret Hijack", "ram": 5, "cooldown": 15.0, "range": 200.0, "effect": "turret_control"},
	"trap_trigger": {"name": "Trap Trigger", "ram": 2, "cooldown": 8.0, "range": 400.0, "effect": "trigger_trap"},
}

var ram: float = 0.0
var ram_max: float = 8.0
var cooldowns: Dictionary = {}
var last_error: String = ""
var ops_used: Dictionary = {}


func _init(ram_capacity: float = 8.0) -> void:
	ram_max = ram_capacity
	ram = ram_max


func cost_for(op: String) -> int:
	return int(OPS.get(op, {}).get("ram", 999))


func range_for(op: String) -> float:
	return float(OPS.get(op, {}).get("range", 0.0))


func cooldown_left(op: String) -> float:
	return float(cooldowns.get(op, 0.0))


## Attempt an operation. Returns {ok, reason, effect}.
func execute(op: String, player_pos: Vector2, target_pos: Vector2,
		target_valid: bool = true, modifiers: Dictionary = {}) -> Dictionary:
	last_error = ""
	if not OPS.has(op):
		return _fail("unknown_op")
	if not target_valid:
		return _fail("invalid_target")
	var cost := int(float(cost_for(op)) * float(modifiers.get("cost_mul", 1.0)))
	cost = maxi(1, cost)
	if cooldown_left(op) > 0.0:
		return _fail("cooldown")
	if ram < cost:
		return _fail("insufficient_ram")
	var rng := range_for(op) * float(modifiers.get("range_mul", 1.0))
	if player_pos.distance_to(target_pos) > rng:
		return _fail("out_of_range")
	ram -= cost
	cooldowns[op] = float(OPS[op]["cooldown"]) * float(modifiers.get("cooldown_mul", 1.0))
	ops_used[op] = int(ops_used.get(op, 0)) + 1
	return {"ok": true, "reason": "", "effect": String(OPS[op]["effect"]), "ram_left": ram}


func _fail(reason: String) -> Dictionary:
	last_error = reason
	return {"ok": false, "reason": reason, "effect": "", "ram_left": ram}


func tick(delta: float, regen: float = 0.5) -> void:
	for op in cooldowns.keys():
		cooldowns[op] = maxf(0.0, float(cooldowns[op]) - delta)
	ram = minf(ram_max, ram + regen * delta)


func op_count() -> int:
	return OPS.size()


func to_dict() -> Dictionary:
	return {"ram": ram, "cooldowns": cooldowns.duplicate(), "ops_used": ops_used.duplicate()}


func from_dict(d: Dictionary) -> void:
	ram = float(d.get("ram", ram_max))
	cooldowns = (d.get("cooldowns", {}) as Dictionary).duplicate()
	ops_used = (d.get("ops_used", {}) as Dictionary).duplicate()
