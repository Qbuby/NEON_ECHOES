class_name CombatSystem
extends RefCounted
## Damage, ammo, reload and crit maths, extracted from the node layer so the
## suite can test it headless (spec 4.2).

## Returns {damage, crit, killed}.
func resolve_hit(base_damage: float, attacker_stats: Dictionary, target_armor: float,
		is_crit: bool = false) -> Dictionary:
	var dmg: float = base_damage * float(attacker_stats.get("damage_mul", 1.0))
	if is_crit:
		dmg *= 2.0
	dmg *= (1.0 - clampf(target_armor, 0.0, 0.9))
	dmg = maxf(1.0, dmg)
	return {"damage": dmg, "crit": is_crit}


func roll_crit(crit_chance: float, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < clampf(crit_chance, 0.0, 1.0)


## Spread a shot inside a cone; returns the unit direction actually fired.
func apply_spread(direction: Vector2, spread_deg: float, rng: RandomNumberGenerator) -> Vector2:
	if spread_deg <= 0.0:
		return direction.normalized()
	var half := deg_to_rad(spread_deg) * 0.5
	return direction.rotated(rng.randf_range(-half, half)).normalized()


## Shotgun pellets: one call per pellet, damage split evenly.
func pellet_damage(weapon: Dictionary) -> float:
	var pellets := int(weapon.get("pellets", 1))
	return float(weapon.get("damage", 1)) / float(maxi(1, pellets))



## Segment vs axis-aligned box (slab test). Rect2 has no intersects_segment.
static func segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var p: float = a.x if axis == 0 else a.y
		var dd: float = d.x if axis == 0 else d.y
		var lo: float = r.position.x if axis == 0 else r.position.y
		var hi: float = lo + (r.size.x if axis == 0 else r.size.y)
		if absf(dd) < 0.000001:
			if p < lo or p > hi:
				return false
		else:
			var ta := (lo - p) / dd
			var tb := (hi - p) / dd
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return false
	return true

## True when the shot is blocked by a wall segment between two points.
func blocked(a: Vector2, b: Vector2, walls: Array) -> bool:
	for w in walls:
		if w is Rect2 and segment_hits_rect(a, b, w):
			return true
	return false
