class_name Endings
extends RefCounted
## Resolves the three endings from world state (spec 8.3).

var defs: Array = []


func _init(data: Dictionary) -> void:
	defs = data.get("endings", [])


func count() -> int:
	return defs.size()


## Returns the id of the first ending whose condition is satisfied, or "".
func resolve(world: Dictionary, cred: int) -> String:
	for e in defs:
		if _matches(e.get("condition", {}), world, cred):
			return String(e["id"])
	return ""


func _matches(cond: Dictionary, world: Dictionary, cred: int) -> bool:
	for key in cond.get("flags", {}).keys():
		if world.get(key) != cond["flags"][key]:
			return false
	for npc in cond.get("min_trust", {}).keys():
		if int(world.get("trust_" + String(npc).replace("npc_", ""), 0)) < int(cond["min_trust"][npc]):
			return false
	if cond.has("min_cred") and cred < int(cond["min_cred"]):
		return false
	return true


func text_for(id: String) -> String:
	for e in defs:
		if e["id"] == id:
			return String(e.get("text", ""))
	return ""
