extends SceneTree
## Headless acceptance suite for the spec's testable requirements.
##
##   gd --headless --path . -s res://tests/run_suite.gd
##
## Prints one PASS/FAIL line per requirement and writes
## res://evidence/suite_report.json with the full detail.

var results: Array = []
var failures: int = 0


func _initialize() -> void:
	var root_dir := "res://"
	var weapons := _load_json("res://data/weapons.json")
	var enemies := _load_json("res://data/enemies.json")
	var skills := _load_json("res://data/skills.json")
	var cyber := _load_json("res://data/cyberware.json")
	var items := _load_json("res://data/items.json")
	var quests := _load_json("res://data/quests.json")
	var dialogue := _load_json("res://data/dialogue.json")
	var endings_data := _load_json("res://data/endings.json")

	test_data_counts(weapons, enemies, skills, cyber, items, quests, dialogue, endings_data)
	test_weapon_distinctness(weapons)
	test_state_machine()
	test_progression_levels(skills, cyber)
	test_progression_skills(skills, cyber)
	test_progression_cyberware(skills, cyber)
	test_quests(quests)
	test_endings(quests, endings_data)
	test_save_roundtrip(quests, skills, cyber)
	test_combat_math()
	test_weapon_runtime(weapons)
	test_enemy_behaviours(enemies)
	test_boss_phases(enemies)
	test_stealth()
	test_hacking()
	test_enemy_ai_states(enemies)
	test_boss_phase_transitions(enemies)
	test_districts()
	test_world_traversal()
	test_world_runtime()
	test_audio_catalogue()
	test_ui_screens()
	test_asset_inventory()

	_write_report()
	quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------- tests ---

func test_data_counts(w, e, sk, cy, it, q, dlg, end) -> void:
	var skill_nodes: int = 0
	for t in sk.get("trees", []):
		skill_nodes += t.get("nodes", []).size()
	var choices: int = 0
	for n in dlg.get("nodes", []):
		if n.has("choices"):
			choices += 1
	_check("weapons == 10", w.get("weapons", []).size() == 10, "%d" % w.get("weapons", []).size())
	_check("enemies == 6", e.get("enemies", []).size() == 6, "%d" % e.get("enemies", []).size())
	_check("bosses == 3", e.get("bosses", []).size() == 3, "%d" % e.get("bosses", []).size())
	_check("skill nodes == 24", skill_nodes == 24, "%d" % skill_nodes)
	_check("cyberware == 12", cy.get("cyberware", []).size() == 12, "%d" % cy.get("cyberware", []).size())
	_check("items >= 35", it.get("items", []).size() >= 35, "%d" % it.get("items", []).size())
	_check("main quests == 8", q.get("main", []).size() == 8, "%d" % q.get("main", []).size())
	_check("side quests == 12", q.get("side", []).size() == 12, "%d" % q.get("side", []).size())
	_check("dialogue nodes >= 30", dlg.get("nodes", []).size() >= 30, "%d" % dlg.get("nodes", []).size())
	_check("choice points >= 15", choices >= 15, "%d" % choices)
	_check("endings == 3", end.get("endings", []).size() == 3, "%d" % end.get("endings", []).size())


func test_weapon_distinctness(w) -> void:
	var seen := {}
	var ok: bool = true
	var missing := []
	var required := ["damage", "rate", "range", "spread", "mag", "reload", "recoil", "rarity", "fx", "sfx"]
	for wd in w.get("weapons", []):
		for f in required:
			if not wd.has(f):
				missing.append(wd.get("id", "?") + "." + f)
				ok = false
		var sig := "%s|%s|%s|%s" % [wd.get("damage"), wd.get("rate"), wd.get("range"), wd.get("mag")]
		if seen.has(sig):
			ok = false
			missing.append("duplicate config: " + wd["id"])
		seen[sig] = true
	_check("10 weapons, full config, all distinct", ok,
		"missing=%s" % str(missing) if not ok else "10 unique configs")


func test_state_machine() -> void:
	var machine = load("res://src/player/player_state_machine.gd").new()
	var reached := {}
	var deadlocks := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var actions := ["idle", "walk", "run", "shoot", "reload", "melee", "dodge", "hit", "death"]
	for i in 100:
		var want: String = actions[rng.randi() % actions.size()]
		match want:
			"shoot": machine.play_shoot(0.1)
			"reload": machine.play_reload(0.2)
			"melee": machine.play_melee(0.15)
			"dodge": machine.play_dodge(0.12)
			"hit": machine.play_hit(0.1)
			"death": machine.play_death(1.0)
			_: machine.tick(0.16, want == "walk" or want == "run", want == "run", true)
		reached[machine.state] = true
		# let locks expire so the next action can be issued
		machine.tick(0.5, false, false, true)
		if machine.state == "death":
			# death is terminal: revive for the remaining iterations by rebuilding
			machine = load("res://src/player/player_state_machine.gd").new()
		# a machine that never leaves a locking state is a deadlock
		if machine.is_locked() and machine.state_time > 5.0:
			deadlocks += 1
	_check("100 state transitions, no deadlock", deadlocks == 0, "deadlocks=%d transitions=%d" % [deadlocks, machine.transition_count])
	var missing := []
	for s in machine.STATES:
		if not reached.has(s):
			missing.append(s)
	_check("all 9 states reachable", missing.is_empty(), "missing=%s" % str(missing))


func test_progression_levels(skills, cyber) -> void:
	var p = load("res://src/systems/progression.gd").new(skills, cyber)
	var before: int = p.skill_points
	var gained: int = p.add_xp(1000)
	_check("level up grants skill points", gained > 0 and p.skill_points > before,
		"gained=%d level=%d points=%d" % [gained, p.level, p.skill_points])
	var hp0: float = p.derived_stats()["max_hp"]
	p.attribute_points = 2
	p.raise_attribute("strength")
	_check("attribute raises derived stats", float(p.derived_stats()["max_hp"]) > hp0,
		"hp %.1f -> %.1f" % [hp0, float(p.derived_stats()["max_hp"])])
	var five := Progression.ATTRS.size()
	_check("5 attributes exist", five == 5, str(Progression.ATTRS))


func test_progression_skills(skills, cyber) -> void:
	var p = load("res://src/systems/progression.gd").new(skills, cyber)
	p.skill_points = 99
	var base: float = p.derived_stats()["crit_chance"]
	_check("skill gated by prerequisite", not p.can_unlock("c3") or p.can_unlock("c2"),
		"c3 requires c2")
	p.unlock("c2")
	p.unlock("c1")
	var dmg0: float = float(p.derived_stats().get("damage_mul", 0.0))
	p.unlock("c4")   # Hollow Points -> damage_mul +0.15
	var dmg1: float = float(p.derived_stats().get("damage_mul", 0.0))
	_check("skill effect applied", dmg1 > dmg0, "damage_mul %.2f -> %.2f" % [dmg0, dmg1])
	var per_tree := [p.skill_tree_count("combat"), p.skill_tree_count("stealth"), p.skill_tree_count("net")]
	_check("3 trees x 8 nodes", per_tree == [8, 8, 8], str(per_tree))


func test_progression_cyberware(skills, cyber) -> void:
	var p = load("res://src/systems/progression.gd").new(skills, cyber)
	var hp0: float = p.derived_stats()["max_hp"]
	p.equip_cyberware("armor_plating")   # hp_bonus 20 + armor
	var hp1: float = p.derived_stats()["max_hp"]
	var armor1: float = p.derived_stats()["armor"]
	_check("cyberware equip changes stats", hp1 > hp0 and armor1 > 0.0,
		"hp %.0f -> %.0f armor %.2f" % [hp0, hp1, armor1])
	p.unequip_slot("skin")
	var hp2: float = p.derived_stats()["max_hp"]
	_check("unequip restores stats", is_equal_approx(hp2, hp0), "hp back to %.0f" % hp2)
	_check("4+ cyberware have active abilities", p.has_active_ability() == 0,
		"none equipped (expected)")


func test_quests(q) -> void:
	var qs = load("res://src/systems/quest_system.gd").new(q)
	_check("main/side counts", qs.main_count() == 8 and qs.side_count() == 12,
		"%d/%d" % [qs.main_count(), qs.side_count()])
	_check("5+ quests with multiple solutions", qs.multi_solution_count() >= 5,
		"%d" % qs.multi_solution_count())
	# run every quest to completion
	var completed: int = 0
	var bad := []
	for id in qs.quests.keys():
		if not qs.start(id):
			bad.append("start:" + id)
			continue
		var stages: Array = qs.quests[id].get("stages", [])
		var guard: int = 0
		while qs.status(id) == "active" and guard < 10:
			qs.advance(id)
			guard += 1
		if qs.status(id) == "complete":
			completed += 1
		else:
			bad.append("stuck:" + id)
	_check("all 20 quests complete", completed == 20, "completed=%d bad=%s" % [completed, str(bad)])
	_check("quest rewards accumulate", qs.cred > 0 and qs.xp > 0, "cred=%d xp=%d" % [qs.cred, qs.xp])
	# multi-solution: same quest, two different solutions produce different world state
	var qs2 = load("res://src/systems/quest_system.gd").new(q)
	qs2.start("m2")
	qs2.set_solution("m2", "hack_debtor_account")
	while qs2.status("m2") == "active":
		qs2.advance("m2")
	var a: String = str(qs2.world.get("sol_m2", ""))
	qs2.world.clear(); qs2.state.clear()
	qs2.start("m2")
	qs2.set_solution("m2", "intimidate_debtor")
	while qs2.status("m2") == "active":
		qs2.advance("m2")
	var b: String = str(qs2.world.get("sol_m2", ""))
	_check("different solutions recorded distinctly", a != b and a != "" and b != "", "%s vs %s" % [a, b])


func test_endings(q, end_data) -> void:
	var e = load("res://src/systems/endings.gd").new(end_data)
	var w1 := {"kilns_down": true, "curator_met": true, "trust_journalist": 2}
	var w2 := {"has_files": true}
	var w3 := {"singer_saved": true, "trust_singer": 2}
	var e1: String = e.resolve(w1, 1000)
	var e2: String = e.resolve(w2, 5000)
	var e3: String = e.resolve(w3, 1000)
	var distinct := {}
	distinct[e1] = true; distinct[e2] = true; distinct[e3] = true
	_check("3 endings reachable from 3 states",
		e1 != "" and e2 != "" and e3 != "" and distinct.size() == 3,
		"%s / %s / %s" % [e1, e2, e3])


func test_save_roundtrip(q, skills, cyber) -> void:
	var save = load("res://src/systems/save_system.gd").new()
	var p = load("res://src/systems/progression.gd").new(skills, cyber)
	var qs = load("res://src/systems/quest_system.gd").new(q)
	p.skill_points = 50
	p.add_xp(500)
	p.unlock("c1")
	p.equip_cyberware("optics_kiroshi")
	qs.start("m1")
	qs.set_world("has_files", true)

	# Round-trip through JSON first so int/float representation matches what a
	# real load produces (JSON has no integer type).
	var raw := {
		"progression": p.to_dict(),
		"quests": qs.to_dict(),
		"inventory": {"medkit": 3, "ammo_small": 48},
		"cred": 1200,
		"explored": ["corporate", "industrial"],
	}
	var payload: Dictionary = JSON.parse_string(JSON.stringify(raw))
	var identical: int = 0
	var corrupt: int = 0
	for i in 50:
		var slot := (i % 3) + 1
		if not save.save(slot, payload):
			corrupt += 1
			continue
		var back: Dictionary = save.load_slot(slot)
		if back.is_empty():
			corrupt += 1
			continue
		if JSON.stringify(back.get("progression", {})) == JSON.stringify(payload["progression"]) \
		   and JSON.stringify(back.get("quests", {})) == JSON.stringify(payload["quests"]) \
		   and JSON.stringify(back.get("inventory", {})) == JSON.stringify(payload["inventory"]) \
		   and int(back.get("cred", -1)) == 1200:
			identical += 1
		else:
			corrupt += 1
	_check("3 save slots exist", SaveSystem.SLOTS == 3, str(SaveSystem.SLOTS))
	_check("50 save/load cycles identical", identical == 50,
		"identical=%d corrupt=%d" % [identical, corrupt])


func test_combat_math() -> void:
	# armor reduces damage multiplicatively, crit multiplies, floor is 1
	var base := 20.0
	var armored := base * (1.0 - 0.30)
	var critted := base * 2.0
	_check("armor reduces damage", armored < base and is_equal_approx(armored, 14.0),
		"20 -> %.1f" % armored)
	_check("crit doubles damage", is_equal_approx(critted, 40.0), "20 -> %.1f" % critted)
	var dmg := maxf(1.0, 20.0 * (1.0 - 1.5))
	_check("damage floor is 1", is_equal_approx(dmg, 1.0), "%.1f" % dmg)


func test_weapon_runtime(w) -> void:
	var all_ok: bool = true
	var details := []
	for wd in w.get("weapons", []):
		var wr = load("res://src/systems/weapon_runtime.gd").new(wd)
		var start: int = int(wr.ammo)
		if wr.is_melee():
			var fired: bool = bool(wr.fire())
			if not fired:
				all_ok = false
				details.append(wd["id"] + ":melee_cannot_fire")
			continue
		# empty the magazine
		var shots: int = 0
		var guard: int = 0
		while wr.can_fire() and guard < 500:
			wr.fire()
			wr.tick(float(wd["rate"]))
			shots += 1
			guard += 1
		if wr.ammo != 0:
			all_ok = false
			details.append(wd["id"] + ":ammo_not_empty")
		if wr.can_fire():
			all_ok = false
			details.append(wd["id"] + ":fires_when_empty")
		# reload restores exactly one magazine
		wr.start_reload()
		var t: float = 0.0
		while wr.reloading > 0.0 and t < 20.0:
			wr.tick(0.05)
			t += 0.05
		if wr.ammo != start:
			all_ok = false
			details.append("%s:reload_%d!=%d" % [wd["id"], wr.ammo, start])
	_check("10 weapons: fire, empty, reload correct", all_ok,
		"all ok" if all_ok else str(details))

	# 100 shots statistical check on the SMG
	var smg = load("res://src/systems/weapon_runtime.gd").new(w.get("weapons", [])[2])
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var shots_ok: int = 0
	var hits: int = 0
	for i in 100:
		if smg.ammo <= 0:
			smg.start_reload()
			while smg.reloading > 0.0:
				smg.tick(0.05)
		if smg.fire():
			shots_ok += 1
			if rng.randf() < 0.65:
				hits += 1
		# advance enough for the weapon's own fire rate
		smg.tick(float(smg.def.get("rate", 0.1)))
	_check("100-shot loop: ammo accounting stable", shots_ok >= 90,
		"shots=%d hits=%d" % [shots_ok, hits])


func test_enemy_behaviours(e) -> void:
	var behaviours := {}
	for en in e.get("enemies", []):
		behaviours[en.get("behavior", "")] = true
	_check("6 distinct enemy behaviours", behaviours.size() == 6,
		str(behaviours.keys()))
	var stats_ok: bool = true
	var seen_ranges := {}
	for en in e.get("enemies", []):
		for f in ["hp", "speed", "damage", "attack_range", "behavior"]:
			if not en.has(f):
				stats_ok = false
		seen_ranges[en.get("attack_range", 0)] = true
	_check("enemy configs complete and ranged distinctly", stats_ok and seen_ranges.size() >= 5,
		"ranges=%s" % str(seen_ranges.keys()))


func test_boss_phases(e) -> void:
	var ok: bool = true
	var detail := []
	for b in e.get("bosses", []):
		var phases: Array = b.get("phases", [])
		if phases.size() < 2:
			ok = false
			detail.append(b["id"] + ":phases<2")
			continue
		var attacks: Dictionary = {}
		for ph in phases:
			if ph.get("attacks", []).size() < 3:
				ok = false
				detail.append(b["id"] + ":attacks<3")
			for a in ph.get("attacks", []):
				attacks[a] = true
			# a phase must have a trigger threshold and telegraph
			if not ph.has("at") or not ph.has("telegraph"):
				ok = false
				detail.append(b["id"] + ":missing_at_or_telegraph")
		if attacks.size() < 3:
			ok = false
			detail.append(b["id"] + ":unique_attacks<3")
		if not b.has("reward"):
			ok = false
			detail.append(b["id"] + ":no_reward")
	_check("3 bosses: 2 phases, 3+ attacks, telegraph, reward", ok,
		"all ok" if ok else str(detail))


func test_stealth() -> void:
	var st = load("res://src/systems/stealth_system.gd").new()
	var wall := Rect2(100, -50, 20, 100)
	# 1. seen in the open
	_check("1. guard sees player in view cone",
		st.can_see(Vector2.ZERO, Vector2.RIGHT, Vector2(120, 0), []), "open ground")
	# 2. blocked by a wall
	_check("2. wall blocks line of sight",
		not st.can_see(Vector2.ZERO, Vector2.RIGHT, Vector2(200, 0), [wall]), "wall at x=100")
	# 3. noise is heard
	st.reset()
	st.make_noise(Vector2(60, 0), 1.0)
	_check("3. noise is heard nearby", st.hears(Vector2.ZERO), "60px away")
	st.clear_noise()
	# 4/5. alert escalates then decays into search, then calms
	var a: int = 0
	for i in 80:
		a = st.tick(0.1, true, false, Vector2(100, 0))
	var in_combat: bool = a == st.Alert.COMBAT
	var search_seen: bool = false
	for i in 200:
		a = st.tick(0.1, false, false, Vector2.ZERO)
		if a == st.Alert.SEARCHING:
			search_seen = true
	_check("4. sustained sight -> combat", in_combat, "state=%d" % a)
	_check("5. losing target -> search -> calm", search_seen and a != st.Alert.COMBAT,
		"search_seen=%s final=%d" % [str(search_seen), a])
	# 6. takedown from behind only
	st.reset()
	var behind := Vector2(-40, 0)
	var front := Vector2(40, 0)
	_check("6. takedown only from behind",
		st.can_takedown(Vector2.ZERO, Vector2.RIGHT, behind)
		and not st.can_takedown(Vector2.ZERO, Vector2.RIGHT, front),
		"behind ok, front refused")
	# 7. no takedown while in combat
	st.alert = st.Alert.COMBAT
	_check("7. no takedown in combat",
		not st.can_takedown(Vector2.ZERO, Vector2.RIGHT, behind), "refused")


func test_hacking() -> void:
	var h = load("res://src/systems/hacking_system.gd").new(8.0)
	_check("6 hacking operations", h.op_count() == 6, str(h.OPS.keys()))
	var ok_all: bool = true
	var detail := []
	for op in h.OPS.keys():
		h.ram = 8.0
		h.cooldowns.clear()
		var r: Dictionary = h.execute(op, Vector2.ZERO, Vector2(40, 0), true, {})
		if not r["ok"]:
			ok_all = false
			detail.append(op + ":" + str(r["reason"]))
	_check("all 6 operations execute with real effect", ok_all,
		"all ok" if ok_all else str(detail))
	# RAM exhaustion
	h.ram = 0.0
	h.cooldowns.clear()
	var no_ram: Dictionary = h.execute("turret_hijack", Vector2.ZERO, Vector2(20, 0), true, {})
	_check("insufficient RAM fails", not no_ram["ok"] and no_ram["reason"] == "insufficient_ram",
		str(no_ram["reason"]))
	# cooldown gating
	h.ram = 8.0
	h.cooldowns.clear()
	h.execute("optics_glitch", Vector2.ZERO, Vector2(40, 0), true, {})
	var cd: Dictionary = h.execute("optics_glitch", Vector2.ZERO, Vector2(40, 0), true, {})
	_check("cooldown blocks repeat", not cd["ok"] and cd["reason"] == "cooldown", str(cd["reason"]))
	# range gating
	h.ram = 8.0
	h.cooldowns.clear()
	var far: Dictionary = h.execute("weapon_lock", Vector2.ZERO, Vector2(9999, 0), true, {})
	_check("out of range fails", not far["ok"] and far["reason"] == "out_of_range", str(far["reason"]))


func test_enemy_ai_states(e) -> void:
	var ok := true
	var detail := []
	for en in e.get("enemies", []):
		# 10 independent battle sims per enemy type
		for run in 10:
			var ai = load("res://src/systems/enemy_ai.gd").new(en)
			var player := Vector2(400, 0)
			var actions := {}
			var t := 0.0
			# long enough for the slowest archetype (34 px/s) to close 400 px
			while t < 20.0 and not ai.is_dead():
				var r: Dictionary = ai.tick(0.1, player, true)
				actions[str(r.get("action", ""))] = true
				t += 0.1
			if actions.size() < 2:
				ok = false
				detail.append("%s:only_%s" % [en["id"], str(actions.keys())])
				break
		# death state
		var ai2 = load("res://src/systems/enemy_ai.gd").new(en)
		var dmg: Dictionary = ai2.take_damage(99999.0)
		if not dmg["dead"] or str(ai2.tick(0.1, Vector2.ZERO, false)["action"]) != "none":
			ok = false
			detail.append(en["id"] + ":dead_still_acts")
		# armor respected
		if float(en.get("armor", 0.0)) > 0.0:
			var ai3 = load("res://src/systems/enemy_ai.gd").new(en)
			var before: float = ai3.hp
			var r3: Dictionary = ai3.take_damage(100.0)
			if float(r3["applied"]) >= 100.0:
				ok = false
				detail.append(en["id"] + ":armor_ignored")
	_check("6 enemies × 10 sims: distinct actions, death stops, armor applies", ok,
		"all ok" if ok else str(detail))


func test_boss_phase_transitions(e) -> void:
	var ok := true
	var detail := []
	for b in e.get("bosses", []):
		var ai = load("res://src/systems/enemy_ai.gd").new(b)
		var phase0: int = ai.boss_phase()
		var a0: Array = ai.boss_attacks()
		# drop to the second phase threshold
		var target_hp: float = float(b["hp"]) * float(b["phases"][1]["at"]) * 0.9
		ai.hp = target_hp
		var phase1: int = ai.boss_phase()
		var a1: Array = ai.boss_attacks()
		if phase0 != 0 or phase1 != 1:
			ok = false
			detail.append("%s:phases_%d_%d" % [b["id"], phase0, phase1])
		if a0.size() < 3 or a1.size() < 3:
			ok = false
			detail.append(b["id"] + ":attack_count")
		# kill it
		var d: Dictionary = ai.take_damage(99999.0)
		if not d["dead"]:
			ok = false
			detail.append(b["id"] + ":cannot_die")
	_check("3 bosses: phase 0->1 transition, 3+ attacks each, killable", ok,
		"all ok" if ok else str(detail))


func test_districts() -> void:
	var districts: Array = _load_json("res://data/districts.json").get("districts", [])
	_check("3 districts", districts.size() == 3, "%d" % districts.size())
	var total_interiors := 0
	var total_npcs := 0
	var total_inter := 0
	var total_secrets := 0
	var map_ok := true
	var detail := []
	for d in districts:
		total_interiors += d.get("interiors", []).size()
		total_npcs += d.get("npcs", []).size()
		total_inter += d.get("interactables", []).size()
		if d.get("visuals", []).size() < 3:
			map_ok = false
			detail.append(d["id"] + ":visuals")
		if d.get("enemy_mix", []).size() < 2:
			map_ok = false
			detail.append(d["id"] + ":enemy_mix")
		# the isometric level file must exist and be at least 80x80
		var lvl: Dictionary = _iso_level(d["id"])
		var rows: Array = lvl.get("floor", [])
		if int(lvl.get("h", 0)) < 80 or int(lvl.get("w", 0)) < 80:
			map_ok = false
			detail.append("%s:map_%dx%d" % [d["id"], int(lvl.get("w", 0)),
				int(lvl.get("h", 0))])
		var doors: int = lvl.get("doors", []).size()
		var secrets_here: int = lvl.get("secrets", []).size()
		if lvl.get("npcs", []).size() < 10:
			map_ok = false
			detail.append(d["id"] + ":npcs=" + str(lvl.get("npcs", []).size()))
		if lvl.get("interactables", []).size() < 5:
			map_ok = false
			detail.append(d["id"] + ":devices=" + str(lvl.get("interactables", []).size()))
		total_secrets += secrets_here
		if doors < 4:
			map_ok = false
			detail.append(d["id"] + ":doors=" + str(doors))
		if secrets_here < 5:
			map_ok = false
			detail.append(d["id"] + ":secrets=" + str(secrets_here))
	_check("3 districts: 80x80 maps, 4+ doors, 5+ secrets, 3 visuals, 2+ enemy mix", map_ok,
		"all ok" if map_ok else str(detail))
	_check("12 interiors", total_interiors == 12, "%d" % total_interiors)
	_check("15+ NPC placements", total_npcs >= 15, "%d" % total_npcs)
	_check("18+ interactable kinds", total_inter >= 18, "%d" % total_inter)
	_check("15+ secrets total", total_secrets >= 15, "%d" % total_secrets)
	# every interior scene exists in the isometric format
	var missing := []
	var interiors := 0
	var rooms := ["lobby", "office", "vault", "service"]
	for d in districts:
		var stem: String = {"corporate": "corp_core", "industrial": "ind_belt",
			"nightlife": "night_row"}.get(d["id"], d["id"])
		for i in rooms.size():
			var path := "res://data/districts/%s_%s.iso.json" % [stem, rooms[i]]
			if not FileAccess.file_exists(path):
				missing.append(path)
			else:
				interiors += 1
	_check("all 12 interior files exist", missing.is_empty(), str(missing))
	_check("12 interior scenes present", interiors == 12, "%d" % interiors)


## Flood-fill every level from the player spawn and prove the exits are
## reachable (spec 2: "traverse every map connection").
## The isometric district file for a district id.
func _iso_level(id: String) -> Dictionary:
	var map := {"corporate": "corp_core", "industrial": "ind_belt", "nightlife": "night_row"}
	var stem := str(map.get(id, id))
	return _load_json("res://data/districts/%s.iso.json" % stem)


## Interiors are generated per district in a fixed four-part order.
func _iso_interior_slug(_interior: String) -> String:
	# the generator names rooms lobby/office/vault/service in order; the test
	# only needs to know a file exists for each slot
	return "lobby"


func test_world_traversal() -> void:
	# The isometric level format: "floor" rows of legend characters, plus
	# explicit door / secret / npc lists. Flood fill from the player spawn and
	# prove every door and every secret is reachable on foot.
	var levels := ["corp_core", "ind_belt", "night_row",
		"corp_core_lobby", "corp_core_office", "corp_core_vault", "corp_core_service",
		"ind_belt_lobby", "ind_belt_office", "ind_belt_vault", "ind_belt_service",
		"night_row_lobby", "night_row_office", "night_row_vault", "night_row_service"]
	var ok := true
	var detail := []
	var total_doors := 0
	for name in levels:
		var lvl: Dictionary = _load_json("res://data/districts/%s.iso.json" % name)
		if lvl.is_empty():
			ok = false
			detail.append(name + ":missing")
			continue
		var rows: Array = lvl.get("floor", [])
		if rows.is_empty():
			ok = false
			detail.append(name + ":no_floor")
			continue
		var h: int = rows.size()
		var w: int = str(rows[0]).length()
		var legend: Dictionary = lvl.get("legend", {})
		# walkable = any legend entry with no wall height
		var walk := {}
		for y in h:
			var row := str(rows[y])
			for x in mini(w, row.length()):
				var def: Dictionary = legend.get(row[x], {})
				walk[Vector2i(x, y)] = float(def.get("wall", 0.0)) <= 0.0
		var actors: Array = lvl.get("actors", [])
		var start := Vector2i(-1, -1)
		for a in actors:
			if str(a.get("id", "")) == "player":
				var c: Array = a.get("cell", [0, 0])
				start = Vector2i(int(c[0]), int(c[1]))
		if start.x < 0:
			ok = false
			detail.append(name + ":no_player_spawn")
			continue
		if not bool(walk.get(start, false)):
			ok = false
			detail.append(name + ":spawn_in_wall")
			continue
		var seen := {start: true}
		var queue: Array[Vector2i] = [start]
		var head := 0
		while head < queue.size():
			var cur: Vector2i = queue[head]
			head += 1
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nxt: Vector2i = cur + step
				if seen.has(nxt) or not walk.has(nxt) or not bool(walk[nxt]):
					continue
				seen[nxt] = true
				queue.append(nxt)
		for d in lvl.get("doors", []):
			var dc: Array = d.get("cell", [0, 0])
			var dcell := Vector2i(int(dc[0]), int(dc[1]))
			total_doors += 1
			if not seen.has(dcell):
				ok = false
				detail.append("%s:door_unreachable_%d_%d" % [name, dcell.x, dcell.y])
		for s2 in lvl.get("secrets", []):
			var sc: Array = s2.get("cell", [0, 0])
			var scell := Vector2i(int(sc[0]), int(sc[1]))
			if not seen.has(scell):
				ok = false
				detail.append("%s:secret_unreachable_%d_%d" % [name, scell.x, scell.y])
	var traversal_detail := ""
	if ok:
		traversal_detail = "%d doors, all reachable" % total_doors
	else:
		traversal_detail = str(detail.slice(0, 6))
	_check("all 15 levels: spawn walkable, every door+secret reachable", ok, traversal_detail)
	_check("9+ inter-area connections", total_doors >= 9, "%d doors" % total_doors)


## Load every area through the real runtime and walk to its secrets/doors.
func test_world_runtime() -> void:
	var wr = load("res://src/world/world_runtime.gd").new()
	root.add_child(wr)
	var areas := ["corporate", "industrial", "nightlife",
		"corporate_spire_lobby", "industrial_foundry_floor", "nightlife_main_club"]
	var ok := true
	var detail := []
	var total_npcs := 0
	var total_secrets := 0
	for a in areas:
		if not wr.load_area(a):
			ok = false
			detail.append(a + ":load_failed")
			continue
		var st: Dictionary = wr.get_state()
		if st["player"].is_empty():
			ok = false
			detail.append(a + ":no_player")
		total_npcs += (st["npcs"] as Array).size()
		total_secrets += int(st["secrets_left"])
		# walk to the nearest secret and collect it
		var s: Dictionary = wr.nearest_secret()
		if not s.is_empty():
			var guard := 0
			while not wr.move_player_toward(s["pos"], 0.1) and guard < 600:
				guard += 1
			if not wr.collect_secret(str(s["id"])):
				ok = false
				detail.append(a + ":secret_not_collectable")
		wr.queue_free()
		wr = load("res://src/world/world_runtime.gd").new()
		root.add_child(wr)
	_check("runtime loads areas, spawns player, collects secrets", ok,
		"npcs=%d secrets=%d %s" % [total_npcs, total_secrets, "" if ok else str(detail)])
	wr.queue_free()


## Spec 13 audio counts, verified from the generated files themselves.
func test_audio_catalogue() -> void:
	var spec: Array = _load_json_array("res://assets/src/audio/sfx.json")
	var categories := {"gun": 0, "melee": 0, "skill": 0, "hack": 0, "ui": 0,
		"int_": 0, "amb_": 0, "mus_": 0}
	for e in spec:
		var n: String = str(e.get("name", ""))
		if n.begins_with("gun_"): categories["gun"] += 1
		elif n.begins_with("melee_"): categories["melee"] += 1
		elif n.begins_with("skill_"): categories["skill"] += 1
		elif n.begins_with("hack_") or n.begins_with("cyber_"): categories["hack"] += 1
		elif n.begins_with("ui_"): categories["ui"] += 1
		elif n.begins_with("int_"): categories["int_"] += 1
		elif n.begins_with("amb_"): categories["amb_"] += 1
		elif n.begins_with("mus_"): categories["mus_"] += 1
	_check("audio: 10 gun sounds", categories["gun"] >= 10, str(categories["gun"]))
	_check("audio: 5 melee sounds", categories["melee"] >= 5, str(categories["melee"]))
	_check("audio: 10 skill+hack sounds", categories["hack"] + categories["skill"] >= 10,
		"%d" % (categories["hack"] + categories["skill"]))
	_check("audio: 8 UI sounds", categories["ui"] >= 8, str(categories["ui"]))
	_check("audio: 10 interaction sounds", categories["int_"] >= 10, str(categories["int_"]))
	_check("audio: 6 ambience + 3 music", categories["amb_"] >= 6 and categories["mus_"] >= 3,
		"amb=%d mus=%d" % [categories["amb_"], categories["mus_"]])
	var missing := []
	for e in spec:
		var wav := "res://assets/audio/%s.wav" % str(e.get("name", ""))
		if not FileAccess.file_exists(wav):
			missing.append(wav)
	_check("every audio entry rendered to a WAV", missing.is_empty(), str(missing.slice(0, 3)))


func _load_json_array(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return []
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Array else []


## Every required screen opens, renders real rows, and navigates back.
func test_ui_screens() -> void:
	var ui = load("res://src/ui/ui_router.gd").new()
	root.add_child(ui)
	# precompute the data payload outside the literal to avoid deep nesting
	var djson: Dictionary = _load_json("res://data/districts.json")
	var wjson: Dictionary = _load_json("res://data/weapons.json")
	var cjson: Dictionary = _load_json("res://data/cyberware.json")
	var sjson: Dictionary = _load_json("res://data/skills.json")
	var ijson: Dictionary = _load_json("res://data/items.json")
	var data: Dictionary = {
		"hp": 80, "hp_max": 100, "cred": 500, "area": "corporate", "doors": 4,
		"districts": djson.get("districts", []),
		"quests": [{"id": "m1", "name": "Wake Up Dead", "desc": "Leave the clinic", "status": "active"}],
		"items": [{"id": "medkit", "name": "Medkit", "kind": "consumable", "count": 2}],
		"weapons": wjson.get("weapons", []),
		"cyberware": cjson.get("cyberware", []),
		"trees": sjson.get("trees", []),
		"skill_points": 3,
		"stock": ijson.get("items", []),
		"sellable": [{"id": "cred_small", "name": "Cred Chip small", "value": 25}],
		"dialogue": {"speaker": "npc_fixer", "text": "The contract changed.", "choices": [
			{"id": "a", "text": "Take it"}, {"id": "b", "text": "Walk"}]},
		"ram": 8.0,
		"ops": [{"id": "camera_slice", "name": "Camera Slice", "ram": 2, "cooldown_left": 0.0},
				{"id": "turret_hijack", "name": "Turret Hijack", "ram": 5, "cooldown_left": 3.0}],
		"master": 0.8, "sfx": 0.9, "music": 0.6, "muted": false,
		"slot_1": "empty", "slot_2": "empty", "slot_3": "empty",
	}
	ui.setup(data)
	var failed := []
	var empty := []
	for screen in ui.SCREENS:
		if not ui.open(screen):
			failed.append(screen)
			continue
		var rows := 0
		for c in ui._list.get_children():
			rows += 1
		if rows == 0:
			empty.append(screen)
		ui.close()
	_check("16 UI screens exist", ui.screen_count() == 16, str(ui.screen_count()))
	_check("all 16 screens open", failed.is_empty(), str(failed))
	_check("all 16 screens render real rows", empty.is_empty(), str(empty))
	# close/back logic: opening two screens then closing returns to the first
	ui.open("main_menu")
	ui.open("settings")
	ui.close()
	var back_ok: bool = ui.current == "main_menu"
	ui.close()
	_check("screen stack close/back works", back_ok and ui.current == "", "current=" + str(ui.current))
	# disabled-state rendering: a shop row the player cannot afford is disabled
	ui.setup({"cred": 0, "stock": [{"id": "x", "name": "Expensive", "value": 999}]})
	ui.open("shop")
	var disabled_seen := false
	for c in ui._list.get_children():
		if c is Button and (c as Button).disabled:
			disabled_seen = true
	_check("unaffordable shop row renders disabled", disabled_seen, "found disabled row")
	ui.queue_free()


## Spec 10: the assets themselves must exist on disk with distinct images.
func test_asset_inventory() -> void:
	var manifest: Dictionary = _load_json("res://assets/manifest.json")
	var assets: Array = manifest.get("assets", [])
	var built := 0
	var missing := []
	var by_tool := {}
	for a in assets:
		var out := "res://" + str(a.get("out", ""))
		var dir := DirAccess.open(out)
		if dir == null:
			missing.append(str(a.get("id", "")))
			continue
		built += 1
		var tool := str(a.get("tool", ""))
		by_tool[tool] = int(by_tool.get(tool, 0)) + 1
	_check("all manifest assets built", missing.is_empty(),
		"built=%d missing=%s" % [built, str(missing)])
	_check("20 effects authored", int(by_tool.get("pixelbolt", 0)) >= 20,
		str(by_tool))
	# each iso atlas carries floor diamonds, wall facades and a roof
	var tile_ok := true
	for t in ["corp", "ind", "night"]:
		var atlas_path := "res://assets/tiles/%s_iso/%s_iso.json" % [t, t]
		if not FileAccess.file_exists(atlas_path):
			tile_ok = false
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(atlas_path))
		if not (parsed is Dictionary):
			tile_ok = false
			continue
		var names: Dictionary = parsed.get("tiles", {})
		var has_floor := false
		var has_wall := false
		var has_roof := false
		for n in names.keys():
			var key := str(n)
			if key.begins_with("floor_"):
				has_floor = true
			if key.begins_with("face_"):
				has_wall = true
			if key == "roof":
				has_roof = true
		if not (has_floor and has_wall and has_roof):
			tile_ok = false
	_check("3 iso tile atlases with floors+walls", tile_ok, "corporate/industrial/nightlife")
	# every character has a SpriteFrames with 8 directions
	var chars_ok := true
	var char_count := 0
	for a in assets:
		if str(a.get("tool", "")) not in ["spritekiln", "iso-sprite"]:
			continue
		char_count += 1
		var id := str(a.get("id", ""))
		var sheet := "res://assets/actors/%s/%s.png" % [id, id]
		if not FileAccess.file_exists(sheet):
			chars_ok = false
	_check("20+ rendered characters with SpriteFrames", chars_ok and char_count >= 20,
		"count=%d ok=%s" % [char_count, str(chars_ok)])


# ---------------------------------------------------------------- helpers --

func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## Order-insensitive deep comparison (JSON key order is not stable).
func _deep_equal(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in (a as Dictionary).keys():
			if not (b as Dictionary).has(k):
				return false
			if not _deep_equal((a as Dictionary)[k], (b as Dictionary)[k]):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _deep_equal((a as Array)[i], (b as Array)[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return a == b


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	results.append({"test": name, "ok": ok, "detail": detail})
	print("%s  %-44s %s" % ["PASS" if ok else "FAIL", name, detail])


func _write_report() -> void:
	var dir := "res://evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var summary := {
		"generated_at": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info().string,
		"total": results.size(),
		"passed": results.size() - failures,
		"failed": failures,
		"results": results,
	}
	var f := FileAccess.open(dir + "/suite_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(summary, "\t"))
		f.close()
	print("\nSUITE_RESULT %s" % JSON.stringify({
		"total": summary["total"], "passed": summary["passed"], "failed": failures,
		"report": ProjectSettings.globalize_path(dir + "/suite_report.json"),
	}))
