extends Node

## Handles Saving and Loading of the game state to JSON.
## Should be an Autoload.

const SAVE_DIR = "user://saves/"
const SAVE_FILE_NAME = "savegame.json"

# References - assign these in a "Main" script or via a Setup function
var map_manager: MapManager
var job_manager: Node # JobManager is autoload, so we can access directly
var entities_container: Node2D

func _ready() -> void:
	# Ensure save directory exists
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_absolute(SAVE_DIR)

func setup(p_map_manager: MapManager, p_entities_container: Node2D):
	map_manager = p_map_manager
	entities_container = p_entities_container

func save_game(slot_name: String = "default") -> void:
	var save_data = {
		"version": "1.0",
		"timestamp": Time.get_unix_time_from_system(),
		"map_seed": map_manager.seed_value if map_manager else 0,
		"pawns": [],
		"objects": [],
		# "jobs": [] # Jobs are harder to serialize if they reference objects directly, easier to recreate or clear on load
	}
	
	# Save Pawns and Objects
	if entities_container:
		for child in entities_container.get_children():
			if child.has_method("get_save_data"):
				var data = child.get_save_data()
				if child is Pawn:
					save_data["pawns"].append(data)
				elif child is InteractableObject:
					save_data["objects"].append(data)
	
	var path = SAVE_DIR + slot_name + ".json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		print("Game saved to: ", path)
	else:
		push_error("Failed to save game to: ", path)

func load_game(slot_name: String = "default") -> void:
	var path = SAVE_DIR + slot_name + ".json"
	if not FileAccess.file_exists(path):
		push_error("Save file not found: ", path)
		return
		
	var file = FileAccess.open(path, FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)
	
	if error != OK:
		push_error("JSON Parse Error: ", json.get_error_message())
		return
		
	var data = json.get_data()
	_apply_load_data(data)

func _apply_load_data(data: Dictionary) -> void:
	print("Loading game...")
	
	# 1. Clear existing world
	if map_manager:
		map_manager.clear_objects()
		# Regenerate terrain based on seed
		if "map_seed" in data:
			map_manager.generate_map(data["map_seed"])
	
	# 2. Clear Pawns (if any remained or were spawned by map gen)
	# (MapManager currently assumes entities_container holds both, so clear_objects might have hit them if they inherit InteractableObject, but Pawns usually don't)
	if entities_container:
		for child in entities_container.get_children():
			if child is Pawn:
				child.queue_free()
	
	# Wait a frame for deletions? In Godot queue_free happens at end of frame.
	# For robust loading, we might need to await get_tree().process_frame
	await get_tree().process_frame
	
	# 3. Spawn Objects (overwrite generated ones if we want precise state, or just add missing?)
	# Strategy: MapGen creates "pristine" world. Save file contains "current" state.
	# Problem: MapGen spawns trees. Save file has trees. We get duplicates.
	# Solution: If loading, MapGen should NOT spawn objects, or we delete them all before loading objects.
	# We already called map_manager.clear_objects(), so we are good to spawn from save.
	
	if "objects" in data and map_manager:
		for obj_data in data["objects"]:
			_spawn_object_from_data(obj_data)
			
	if "pawns" in data and map_manager:
		for pawn_data in data["pawns"]:
			_spawn_pawn_from_data(pawn_data)
			
	print("Game loaded successfully.")

func _spawn_object_from_data(data: Dictionary) -> void:
	var scene = null
	# Simple mapping based on filename or type
	# ideally we store resource path, but that's brittle.
	# Using type string is safer.
	if data["type"] == "Tree":
		scene = map_manager.tree_scene
	elif data["type"] == "Rock":
		scene = map_manager.rock_scene
	elif data["type"] == "BerryBush":
		scene = map_manager.berry_scene
		
	if scene:
		var instance = scene.instantiate()
		instance.position = Vector2(data["pos_x"], data["pos_y"])
		if instance.has_method("load_save_data"):
			instance.load_save_data(data)
		map_manager.entities_container.add_child(instance)

func _spawn_pawn_from_data(data: Dictionary) -> void:
	# Assuming we have a reference to Pawn scene somewhere, or load it
	var pawn_scene = load("res://scenes/Pawn.tscn")
	if pawn_scene:
		var instance = pawn_scene.instantiate()
		instance.position = Vector2(data["pos_x"], data["pos_y"])
		if instance.has_method("load_save_data"):
			instance.load_save_data(data)
		map_manager.entities_container.add_child(instance)
