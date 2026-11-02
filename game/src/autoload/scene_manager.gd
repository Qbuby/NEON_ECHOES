extends Node
## Scene and area transitions with a fade, plus spawn-point placement.
##
##     SceneManager.change_area("res://scenes/levels/level_01.tscn", "start")
##     SceneManager.goto_scene("res://scenes/ui/title.tscn")
##
## Areas are ordinary scenes. A spawn point is any node in the "spawns" group
## with a `spawn_id` property; the player is placed there after the load.

signal area_loaded(area_path: String)

const FADE_TIME := 0.25

var _fade: ColorRect
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.game_over.connect(_on_game_over)
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.086, 0.071, 0.122, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


## Change to another gameplay area and place the player at `spawn_id`.
func change_area(area_path: String, spawn_id: String = "") -> void:
	if _busy:
		return
	_busy = true
	await _fade_to(1.0)
	get_tree().change_scene_to_file(area_path)
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.current_area = area_path
	_place_player(spawn_id)
	await _fade_to(0.0)
	_busy = false
	area_loaded.emit(area_path)
	Log.info("scene.area_loaded", {"area": area_path, "spawn": spawn_id})


## Change to a non-gameplay scene (title, game over) with a fade.
func goto_scene(path: String) -> void:
	if _busy:
		return
	_busy = true
	await _fade_to(1.0)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	await _fade_to(0.0)
	_busy = false
	Log.info("scene.changed", {"scene": path})


func reload_area() -> void:
	var path := GameState.current_area
	if path == "":
		path = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	await change_area(path, GameState.checkpoint)


func _on_game_over(victory: bool) -> void:
	if _busy:
		return
	_busy = true
	await _fade_to(1.0)
	var packed := load("res://scenes/ui/game_over.tscn") as PackedScene
	if packed == null:
		_busy = false
		return
	var node := packed.instantiate()
	node.victory = victory
	var previous := get_tree().current_scene
	get_tree().root.add_child(node)
	get_tree().current_scene = node
	if previous:
		previous.queue_free()
	await get_tree().process_frame
	await _fade_to(0.0)
	_busy = false
	Log.info("scene.game_over", {"victory": victory})


func _place_player(spawn_id: String) -> void:
	if spawn_id == "":
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var player := players[0] as Node2D
	for node in get_tree().get_nodes_in_group("spawns"):
		if String(node.get("spawn_id")) == spawn_id:
			player.global_position = (node as Node2D).global_position
			Log.info("scene.spawned", {"spawn": spawn_id, "at": str(player.global_position)})
			return
	Log.warn("scene.spawn_missing", {"spawn": spawn_id})


func _fade_to(alpha: float) -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tween.finished
