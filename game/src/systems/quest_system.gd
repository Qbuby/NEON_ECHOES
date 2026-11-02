class_name QuestSystem
extends RefCounted
## Quest state machine with stages, multiple solutions and world flags
## (spec section 8). Pure logic, headless-testable.

signal quest_started(id: String)
signal stage_completed(quest_id: String, stage_id: String)
signal quest_completed(id: String, solution: String)

var quests: Dictionary = {}       # id -> quest data
var state: Dictionary = {}        # id -> {status, stage, solution}
var world: Dictionary = {}        # shared world flags
var cred: int = 0
var xp: int = 0
var log_lines: Array[String] = []


func _init(quest_data: Dictionary) -> void:
	for q in quest_data.get("main", []):
		q["kind"] = "main"
		quests[q["id"]] = q
	for q in quest_data.get("side", []):
		q["kind"] = "side"
		quests[q["id"]] = q


func main_count() -> int:
	var n := 0
	for id in quests.keys():
		if quests[id]["kind"] == "main":
			n += 1
	return n


func side_count() -> int:
	var n := 0
	for id in quests.keys():
		if quests[id]["kind"] == "side":
			n += 1
	return n


func multi_solution_count() -> int:
	var n := 0
	for id in quests.keys():
		if quests[id].get("solutions", []).size() >= 2:
			n += 1
	return n


func status(id: String) -> String:
	return String(state.get(id, {}).get("status", "inactive"))


func current_stage(id: String) -> int:
	return int(state.get(id, {}).get("stage", 0))


func start(id: String) -> bool:
	if not quests.has(id) or status(id) != "inactive":
		return false
	state[id] = {"status": "active", "stage": 0, "solution": ""}
	log_lines.append("start " + id)
	quest_started.emit(id)
	return true


## Advance the current stage. `solution` is recorded on the final stage.
func advance(id: String, solution: String = "") -> bool:
	if status(id) != "active":
		return false
	var q: Dictionary = quests[id]
	var stages: Array = q.get("stages", [])
	var st: Dictionary = state[id]
	if st["stage"] >= stages.size():
		return false
	st["stage"] += 1
	stage_completed.emit(id, String(stages[st["stage"] - 1].get("id", "")))
	if st["stage"] >= stages.size():
		_complete(id, solution)
	return true


func _complete(id: String, solution: String) -> void:
	var q: Dictionary = quests[id]
	var sols: Array = q.get("solutions", [])
	var st: Dictionary = state[id]
	# keep a solution recorded earlier via set_solution()
	var chosen: String = solution
	if chosen == "":
		chosen = String(st.get("solution", ""))
	if chosen == "" and not sols.is_empty():
		chosen = String(sols[0])
	st["status"] = "complete"
	st["solution"] = chosen
	var reward: Dictionary = q.get("reward", {})
	cred += int(reward.get("cred", 0))
	xp += int(reward.get("xp", 0))
	if q.has("flag"):
		world[q["flag"]] = true
	world.merge(q.get("world", {}), true)
	if chosen != "":
		world["sol_" + id] = chosen
	log_lines.append("complete %s (%s)" % [id, chosen])
	quest_completed.emit(id, chosen)


## A stage can be solved in several ways; record which one was used.
func set_solution(id: String, solution: String) -> bool:
	var q: Dictionary = quests.get(id, {})
	if not (solution in q.get("solutions", [])):
		return false
	state[id]["solution"] = solution
	world["sol_" + id] = solution
	return true


func set_world(key: String, value: Variant) -> void:
	world[key] = value


func to_dict() -> Dictionary:
	return {"state": state.duplicate(true), "world": world.duplicate(true),
			"cred": cred, "xp": xp}


func from_dict(d: Dictionary) -> void:
	state = (d.get("state", {}) as Dictionary).duplicate(true)
	world = (d.get("world", {}) as Dictionary).duplicate(true)
	cred = int(d.get("cred", 0))
	xp = int(d.get("xp", 0))
