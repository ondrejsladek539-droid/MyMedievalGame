extends Node2D

@export var map_width: int = 100
@export var map_height: int = 100
@export var pawn_count: int = 3

@onready var map_manager = $MapManager
@onready var save_manager = $SaveManager
@onready var camera = $Camera2D
@onready var entities_container = $Entities
@onready var selection_manager = $SelectionManager
@onready var ui = $UI
@onready var zone_manager = $ZoneManager
@onready var build_controller = $BuildController # User needs to add this node!

var pawns: Array = []

func _ready() -> void:
	# Ensure managers are initialized
	randomize()
	
	# Connect UI to SelectionManager
	ui.connect("tool_selected", _on_ui_tool_selected)
	ui.connect("build_tool_selected", _on_ui_build_tool_selected)
	selection_manager.connect("mode_changed", _on_selection_mode_changed)
	
	# Try to load existing game or generate new one
	# For now, let's always generate a new one for testing, unless a specific save file exists
	# In a real game, you'd have a main menu.
	
	_start_new_game()

func _on_ui_tool_selected(mode_int: int) -> void:
	# Prioritize BuildController for building/deconstruction
	if build_controller:
		if mode_int == SelectionManager.ToolMode.DECONSTRUCT:
			build_controller.start_deconstruct_mode()
			selection_manager.set_mode(SelectionManager.ToolMode.NONE)
			ui.update_mode_label("DECONSTRUCT")
			return
		elif mode_int == SelectionManager.ToolMode.CANCEL:
			build_controller.start_cancel_mode()
			selection_manager.set_mode(SelectionManager.ToolMode.NONE)
			ui.update_mode_label("CANCEL")
			return
		else:
			# Reset build controller if switching to other tools
			build_controller.cancel_mode()

	selection_manager.set_mode(mode_int)

func _on_ui_build_tool_selected(key: String) -> void:
	if build_controller:
		build_controller.start_build_mode(key)
		selection_manager.set_mode(SelectionManager.ToolMode.NONE)
		ui.update_mode_label("BUILD: " + key)
	else:
		selection_manager.set_build_mode(key)

func _on_selection_mode_changed(mode_name: String) -> void:
	ui.update_mode_label(mode_name)

func _start_new_game() -> void:
	print("Starting new game...")
	
	# Manual assignment to ensure references are set
	map_manager.tile_map_layer = $Terrain
	map_manager.entities_container = entities_container
	
	# Assign dependencies to SelectionManager
	selection_manager.map_manager = map_manager
	selection_manager.camera = camera
	selection_manager.zone_manager = zone_manager
	selection_manager.ui_node = ui
	
	# Generate Map
	map_manager.generate_map()
	
	# Spawn initial pawns
	_spawn_initial_pawns()
	
	# Center camera on spawn area (Top-Left)
	camera.position = Vector2(10 * map_manager.TILE_SIZE, 10 * map_manager.TILE_SIZE)

func _spawn_initial_pawns() -> void:
	var pawn_scene = load("res://scenes/Pawn.tscn")
	if not pawn_scene:
		push_error("Pawn scene not found!")
		return
		
	for i in range(pawn_count):
		var pawn = pawn_scene.instantiate()
		
		# Find a valid spawn position (Top-Left corner)
		var valid_pos = false
		var spawn_pos = Vector2.ZERO
		
		var attempts = 0
		while not valid_pos and attempts < 100:
			attempts += 1
			# Spawn in top-left area (e.g., between tile 5 and 15)
			var x = randi_range(5, 15)
			var y = randi_range(5, 15)
			
			if map_manager.is_water(x, y):
				continue
			
			spawn_pos = Vector2(x * map_manager.TILE_SIZE + map_manager.TILE_SIZE/2, y * map_manager.TILE_SIZE + map_manager.TILE_SIZE/2)
			
			# Check distance to other pawns to avoid overlapping
			var overlap = false
			for existing_pawn in pawns:
				if existing_pawn.position.distance_to(spawn_pos) < 40.0:
					overlap = true
					break
			
			if not overlap:
				valid_pos = true 
			
		pawn.position = spawn_pos
		pawn.map_manager = map_manager
		entities_container.add_child(pawn)
		pawns.append(pawn)
		print("Spawned pawn at: ", spawn_pos)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # Escape key
		save_manager.save_game()
		print("Game saved!")
	elif event.is_action_pressed("ui_accept"): # Enter key
		# Force reload for testing
		get_tree().reload_current_scene()
