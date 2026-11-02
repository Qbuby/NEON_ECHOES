extends SceneTree
## Map-switch soak: 100 sequential area loads through the real runtime.
var areas := ["corporate", "industrial", "nightlife",
	"corporate_spire_lobby", "corporate_boardroom", "corporate_server_vault", "corporate_exec_office",
	"industrial_foundry_floor", "industrial_warehouse", "industrial_black_market", "industrial_repair_bay",
	"nightlife_main_club", "nightlife_backstage", "nightlife_vip_lounge", "nightlife_alley_market"]
var index := 0
var switches := 0
var errors := 0
var mem_samples: Array[float] = []
var wr = null


func _initialize() -> void:
	wr = load("res://src/world/world_runtime.gd").new()
	root.add_child(wr)


func _process(_delta: float) -> bool:
	if switches >= 100:
		_report()
		return true
	if wr == null:
		return false
	var target: String = areas[index % areas.size()]
	index += 1
	if not wr.load_area(target):
		errors += 1
	switches += 1
	if switches % 10 == 0:
		mem_samples.append(OS.get_static_memory_usage() / 1048576.0)
	return false


func _report() -> void:
	var growth := 0.0
	if mem_samples.size() >= 2:
		growth = mem_samples[-1] - mem_samples[0]
	var out := {
		"switches": switches, "errors": errors,
		"mem_start_mb": snapped(mem_samples[0], 0.1) if mem_samples.size() > 0 else 0.0,
		"mem_end_mb": snapped(mem_samples[-1], 0.1) if mem_samples.size() > 0 else 0.0,
		"mem_growth_mb": snapped(growth, 0.1),
	}
	var dir := "res://evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir + "/soak.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "\t"))
		f.close()
	print("SOAK_RESULT " + JSON.stringify(out))
