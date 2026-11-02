class_name Progression
extends RefCounted
## Attributes, skills and cyberware. Pure logic so it can be unit-tested
## headless (spec section 7.4).

const ATTRS := ["strength", "reflex", "tech", "intel", "will"]

var level: int = 1
var xp: int = 0
var skill_points: int = 0
var attribute_points: int = 0
var attributes: Dictionary = {}
var unlocked: Dictionary = {}          # skill_id -> true
var equipped: Dictionary = {}          # slot -> cyberware_id
var _skill_defs: Dictionary = {}       # skill_id -> node data
var _cyber_defs: Dictionary = {}       # cyberware_id -> data


func _init(skills_data: Dictionary, cyber_data: Dictionary) -> void:
	for a in ATTRS:
		attributes[a] = 3
	for tree in skills_data.get("trees", []):
		for node in tree.get("nodes", []):
			node["tree"] = tree["id"]
			_skill_defs[node["id"]] = node
	for c in cyber_data.get("cyberware", []):
		_cyber_defs[c["id"]] = c


# --- experience / levels --------------------------------------------------

func xp_for_next() -> int:
	return 100 + (level - 1) * 75


func add_xp(amount: int) -> int:
	xp += amount
	var gained := 0
	while xp >= xp_for_next():
		xp -= xp_for_next()
		level += 1
		skill_points += 1
		attribute_points += 1
		gained += 1
	return gained


# --- attributes -----------------------------------------------------------

func raise_attribute(name: String) -> bool:
	if not attributes.has(name) or attribute_points <= 0:
		return false
	if int(attributes[name]) >= 10:
		return false
	attributes[name] += 1
	attribute_points -= 1
	return true


## Attributes must each influence at least two real parameters (spec 7.1).
func derived_stats() -> Dictionary:
	var s := float(attributes["strength"])
	var r := float(attributes["reflex"])
	var t := float(attributes["tech"])
	var i := float(attributes["intel"])
	var w := float(attributes["will"])
	var stats := {
		"max_hp": 80.0 + s * 8.0 + w * 4.0,
		"melee_damage_mul": 1.0 + s * 0.06,
		"carry_capacity": 40.0 + s * 6.0,
		"move_speed_mul": 1.0 + r * 0.03,
		"attack_rate_mul": 1.0 + r * 0.04,
		"armor": 0.0 + t * 0.015,
		"hack_range": 200.0 + i * 15.0,
		"ram_max": 4.0 + i * 1.0,
		"crit_chance": 0.02 + w * 0.012,
		"regen": 0.0 + w * 0.1,
		"damage_mul": 1.0,
		"accuracy": 0.0,
		"recoil_mul": 1.0,
		"reload_speed": 0.0,
		"mag_bonus": 0.0,
		"hack_speed": 0.0,
		"hack_cost_mul": 1.0,
		"detect_range_mul": 1.0,
		"noise_mul": 1.0,
	}
	# skills
	for id in unlocked.keys():
		_apply_effects(_skill_defs.get(id, {}).get("effect", {}), stats, false)
	# cyberware
	for slot in equipped.keys():
		var c = _cyber_defs.get(equipped[slot], {})
		_apply_effects(c.get("effect", {}), stats, true)
	return stats


func _apply_effects(eff: Dictionary, stats: Dictionary, from_cyber: bool) -> void:
	for key in eff.keys():
		var v = eff[key]
		match key:
			"damage_mul", "melee_damage_mul", "accuracy", "speed_mul", "move_speed_mul", "recoil_mul":
				if stats.has(key):
					stats[key] = float(stats[key]) + float(v)
			"max_hp", "hp_bonus":
				stats["max_hp"] = float(stats.get("max_hp", 80.0)) + float(v)
			"armor":
				stats["armor"] = float(stats.get("armor", 0.0)) + float(v)
			"crit_chance":
				stats["crit_chance"] = float(stats.get("crit_chance", 0.0)) + float(v)
			"ram_bonus":
				stats["ram_max"] = float(stats.get("ram_max", 4.0)) + float(v)
			"hack_range":
				stats["hack_range"] = float(stats.get("hack_range", 200.0)) * (1.0 + float(v))
			"regen":
				stats["regen"] = float(stats.get("regen", 0.0)) + float(v)
			_:
				stats[key] = v


# --- skills ---------------------------------------------------------------

func can_unlock(skill_id: String) -> bool:
	if unlocked.has(skill_id):
		return false
	var node = _skill_defs.get(skill_id, null)
	if node == null:
		return false
	if skill_points < int(node.get("cost", 1)):
		return false
	for req in node.get("requires", []):
		if not unlocked.has(req):
			return false
	return true


func unlock(skill_id: String) -> bool:
	if not can_unlock(skill_id):
		return false
	skill_points -= int(_skill_defs[skill_id].get("cost", 1))
	unlocked[skill_id] = true
	return true


func skill_count() -> int:
	return _skill_defs.size()


func skill_tree_count(tree_id: String) -> int:
	var n := 0
	for id in _skill_defs.keys():
		if _skill_defs[id].get("tree", "") == tree_id:
			n += 1
	return n


# --- cyberware ------------------------------------------------------------

func equip_cyberware(id: String) -> bool:
	var c = _cyber_defs.get(id, null)
	if c == null:
		return false
	var slot: String = c.get("slot", "")
	if slot == "":
		return false
	equipped[slot] = id
	return true


func unequip_slot(slot: String) -> bool:
	if not equipped.has(slot):
		return false
	equipped.erase(slot)
	return true


func has_active_ability() -> int:
	var n := 0
	for slot in equipped.keys():
		if _cyber_defs.get(equipped[slot], {}).get("active", false):
			n += 1
	return n


func cyberware_count() -> int:
	return _cyber_defs.size()


# --- save -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"level": level, "xp": xp, "skill_points": skill_points,
		"attribute_points": attribute_points,
		"attributes": attributes.duplicate(),
		"unlocked": unlocked.duplicate(),
		"equipped": equipped.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	skill_points = int(d.get("skill_points", 0))
	attribute_points = int(d.get("attribute_points", 0))
	attributes = (d.get("attributes", {}) as Dictionary).duplicate()
	unlocked = (d.get("unlocked", {}) as Dictionary).duplicate()
	equipped = (d.get("equipped", {}) as Dictionary).duplicate()
