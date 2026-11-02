class_name EnemyAI
extends RefCounted
## The six enemy behaviour archetypes from data/enemies.json, as pure logic so
## each can be tested headless (spec 4.3).

var def: Dictionary
var hp: float = 0.0
var alert: int = 0            # StealthSystem.Alert
var pos: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var cooldown: float = 0.0
var behavior: String = ""
var state: String = "idle"    # idle|patrol|chase|strafe|hold|attack|dead
var damage_taken: float = 0.0


func _init(enemy_def: Dictionary) -> void:
	def = enemy_def
	hp = float(def.get("hp", 20))
	behavior = String(def.get("behavior", "ranged_cover"))


func is_dead() -> bool:
	return hp <= 0.0


## One AI step. Returns the action to perform this frame.
func tick(delta: float, player_pos: Vector2, can_see: bool) -> Dictionary:
	if is_dead():
		state = "dead"
		return {"action": "none", "state": state}
	cooldown = maxf(0.0, cooldown - delta)
	var to_player := player_pos - pos
	var dist := to_player.length()
	if dist > 0.001:
		facing = to_player.normalized()
	var result := _decide(delta, player_pos, dist, can_see)
	# move according to the decision so the next tick sees the new distance
	var speed := float(def.get("speed", 40))
	match String(result.get("action", "")):
		"approach", "charge", "advance":
			pos += facing * speed * delta
		"retreat":
			pos -= facing * speed * delta
		"strafe":
			var d: Vector2 = result.get("dir", facing.orthogonal())
			pos += d.normalized() * speed * 0.7 * delta
	state = String(result.get("state", state))
	return result


func _decide(_delta: float, _player_pos: Vector2, dist: float, can_see: bool) -> Dictionary:
	if cooldown > 0.0:
		return {"action": "wait", "state": state}

	match behavior:
		"ranged_cover":
			# hold a preferred distance, fire on cooldown
			var pref := float(def.get("preferred_range", 200))
			if dist > pref * 1.15:
				return {"action": "approach", "state": "chase", "dir": facing}
			if dist < pref * 0.7:
				return {"action": "retreat", "state": "strafe", "dir": -facing}
			if can_see:
				cooldown = float(def.get("cooldown", 1.1))
				return {"action": "shoot", "state": "attack", "damage": float(def.get("damage", 5))}
			return {"action": "strafe", "state": "strafe", "dir": facing.orthogonal()}
		"melee_charge":
			var reach := float(def.get("attack_range", 36))
			if dist > reach:
				return {"action": "charge", "state": "chase", "dir": facing}
			cooldown = float(def.get("cooldown", 0.8))
			return {"action": "melee", "state": "attack", "damage": float(def.get("damage", 10))}
		"sniper_hold":
			# never approaches; fires a telegraphed high-damage shot
			if can_see:
				cooldown = float(def.get("cooldown", 2.4))
				return {"action": "shoot", "state": "attack", "damage": float(def.get("damage", 25)),
					"telegraph": 0.6}
			return {"action": "hold", "state": "hold"}
		"heavy_advance":
			var heavy_reach := float(def.get("attack_range", 46))
			if dist > heavy_reach:
				return {"action": "advance", "state": "chase", "dir": facing}
			cooldown = float(def.get("cooldown", 1.6))
			return {"action": "melee", "state": "attack", "damage": float(def.get("damage", 18))}
		"hacker_disrupt":
			# stays mid-range and disables player systems instead of shooting
			if dist > float(def.get("preferred_range", 280)) * 1.2:
				return {"action": "approach", "state": "chase", "dir": facing}
			cooldown = float(def.get("cooldown", 2.8))
			return {"action": "hack", "state": "ability", "effect": "disable_cyberware",
				"duration": 4.0}
		"drone_strafe":
			# circles the player and fires
			if dist > float(def.get("preferred_range", 180)) * 1.3:
				return {"action": "approach", "state": "chase", "dir": facing}
			cooldown = float(def.get("cooldown", 1.3))
			return {"action": "shoot", "state": "attack", "damage": float(def.get("damage", 9)),
				"dir": facing.orthogonal(), "strafe": true}
	return {"action": "idle", "state": "idle"}


## Armor applies here so all enemies share one damage path.
func take_damage(amount: float) -> Dictionary:
	var armor := float(def.get("armor", 0.0))
	var applied := maxf(1.0, amount * (1.0 - clampf(armor, 0.0, 0.9)))
	hp -= applied
	damage_taken += applied
	return {"applied": applied, "dead": is_dead(), "hp_left": maxf(0.0, hp)}


func xp_value() -> int:
	return int(def.get("xp", 0))


func loot() -> Array:
	return def.get("loot", [])


## Bosses: 2 phases driven by an HP threshold. Returns the active phase index.
func boss_phase() -> int:
	var phases: Array = def.get("phases", [])
	if phases.is_empty():
		return 0
	var frac := hp / maxf(1.0, float(def.get("hp", 1)))
	for i in range(phases.size() - 1, -1, -1):
		if frac <= float(phases[i].get("at", 0.0)) + 0.0001:
			return i
	return 0


func boss_attacks() -> Array:
	var phases: Array = def.get("phases", [])
	if phases.is_empty():
		return []
	var idx := clampi(boss_phase(), 0, phases.size() - 1)
	return phases[idx].get("attacks", [])
