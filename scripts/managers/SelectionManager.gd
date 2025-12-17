extends Node2D

class_name SelectionManager

# Current tool mode
enum ToolMode {
	NONE,
	CHOP,
	MINE,
	HARVEST,
	ZONE_STORAGE,
	ZONE_HOME,
	BUILD,
	DECONSTRUCT,
	DESTROY,
	CANCEL
}

var current_mode: ToolMode = ToolMode.NONE
var current_building_key: String = "" # For BUILD mode
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var selection_rect: ReferenceRect

# Pawn Selection
var selected_pawns: Array[Pawn] = []

@export var map_manager: MapManager
@export var camera: Camera2D
@export var zone_manager: ZoneManager # New dependency

var ui_node: Node = null
var context_menu_scene = preload("res://scenes/BlueprintContextMenu.tscn")

signal mode_changed(new_mode: String)

func _ready() -> void:
	# Create a visual rectangle for selection
	selection_rect = ReferenceRect.new()
	selection_rect.editor_only = false
	selection_rect.border_color = Color(0, 1, 0, 0.5)
	selection_rect.border_width = 2.0
	selection_rect.visible = false
	add_child(selection_rect)

func set_mode(mode: ToolMode) -> void:
	current_mode = mode
	var mode_name = ToolMode.keys()[mode]
	emit_signal("mode_changed", mode_name)
	print("Selection Mode set to: ", mode_name)
	
	# Clear pawn selection when changing tool mode (optional, but cleaner)
	if mode != ToolMode.NONE:
		_clear_pawn_selection()

func set_build_mode(building_key: String) -> void:
	current_building_key = building_key
	set_mode(ToolMode.BUILD)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_selection(get_global_mouse_position())
			else:
				_end_selection(get_global_mouse_position())
		
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var mouse_pos = get_global_mouse_position()
			
			# Check for blueprint
			var blueprint = _get_blueprint_at(mouse_pos)
			if blueprint:
				_show_context_menu(blueprint)
				return
			
			# Move command for selected pawns
			if not selected_pawns.is_empty():
				var target_pos = mouse_pos
				print("Commanding ", selected_pawns.size(), " pawns to move to ", target_pos)
				for pawn in selected_pawns:
					pawn.command_move_to(target_pos)
					# Add slight offset to avoid stacking perfectly?
					# For now, exact position is fine.

	elif event is InputEventMouseMotion and is_dragging:
		_update_selection_visual(get_global_mouse_position())

func _get_blueprint_at(pos: Vector2) -> Node:
	var building_manager = get_node_or_null("/root/Main/BuildingManager")
	if not building_manager: return null
	
	var tile_size = 64.0 # Should ideally get from MapManager
	
	for bp in building_manager.active_blueprints:
		if is_instance_valid(bp):
			# Check using Rect2 for better coverage of square tiles
			var rect = Rect2(bp.global_position - Vector2(tile_size/2, tile_size/2), Vector2(tile_size, tile_size))
			if rect.has_point(pos):
				return bp
	return null

func _show_context_menu(blueprint: Node) -> void:
	if not ui_node: return
	
	var menu = context_menu_scene.instantiate()
	menu.setup(blueprint)
	ui_node.add_child(menu)
	
	# Position menu at mouse position (screen space for UI)
	menu.global_position = get_viewport().get_mouse_position()
	
	menu.connect("action_selected", _on_context_menu_action)

func _on_context_menu_action(action: String, target: Node) -> void:
	if action == "prioritize":
		var job = JobManager.get_job_for_object(target)
		if job:
			job.priority = 10
			print("Priority increased for blueprint job: ", target.name)
		else:
			# Try to force update from BuildingManager to create job if possible
			var building_manager = get_node_or_null("/root/Main/BuildingManager")
			if building_manager:
				building_manager._update_blueprint_jobs(target)
				
				# Try getting job again
				job = JobManager.get_job_for_object(target)
				if job:
					job.priority = 10
					print("Priority increased for NEW blueprint job: ", target.name)
				else:
					print("Priority FAILED: No pending job found for ", target.name)
	elif action == "cancel":
		var building_manager = get_node_or_null("/root/Main/BuildingManager")
		if building_manager:
			building_manager.cancel_blueprint(target)

func _start_selection(pos: Vector2) -> void:
	# Allow selection in NONE mode
	# if current_mode == ToolMode.NONE: return 
	
	is_dragging = true
	drag_start = pos
	selection_rect.position = pos
	selection_rect.size = Vector2.ZERO
	selection_rect.visible = true

func _update_selection_visual(current_pos: Vector2) -> void:
	var top_left = Vector2(min(drag_start.x, current_pos.x), min(drag_start.y, current_pos.y))
	var bottom_right = Vector2(max(drag_start.x, current_pos.x), max(drag_start.y, current_pos.y))
	selection_rect.position = top_left
	selection_rect.size = bottom_right - top_left

func _end_selection(end_pos: Vector2) -> void:
	if not is_dragging: return
	
	is_dragging = false
	selection_rect.visible = false
	
	# Calculate selection rectangle
	var rect = Rect2(selection_rect.position, selection_rect.size)
	
	# If rect is too small, treat as single click
	if rect.size.length() < 5:
		rect = Rect2(end_pos - Vector2(1,1), Vector2(2,2))
		
	_apply_action_to_area(rect)

func _apply_action_to_area(rect: Rect2) -> void:
	if current_mode == ToolMode.ZONE_STORAGE:
		if zone_manager:
			zone_manager.create_zone(rect, ZoneManager.ZoneType.STORAGE)
		else:
			push_warning("ZoneManager not assigned to SelectionManager")
		return
	elif current_mode == ToolMode.ZONE_HOME:
		if zone_manager:
			zone_manager.create_zone(rect, ZoneManager.ZoneType.HOME)
		return
	elif current_mode == ToolMode.BUILD:
		_handle_build_tool(rect)
		return
	
	# Handle Pawn Selection (ToolMode.NONE)
	if current_mode == ToolMode.NONE:
		_handle_pawn_selection(rect)
		return

	if not map_manager or not map_manager.entities_container: 
		push_warning("SelectionManager: MapManager or EntitiesContainer not assigned!")
		return
	
	var is_single_click = rect.size.length() < 10
	var click_pos = rect.position + rect.size / 2
	
	# Find all interactable objects in the rectangle
	for child in map_manager.entities_container.get_children():
		var should_check = false
		if child is InteractableObject:
			should_check = true
		elif current_mode == ToolMode.DECONSTRUCT and (child.is_in_group("Structures") or child is Blueprint):
			should_check = true
		elif current_mode == ToolMode.DESTROY and child is InteractableObject:
			should_check = true
			
		if should_check:
			var selected = false
			
			if is_single_click:
				# Check distance to center (approximate radius of 24 pixels)
				if child.global_position.distance_to(click_pos) < 24.0:
					selected = true
			else:
				# Drag selection: Check if center is inside rect
				if rect.has_point(child.global_position):
					selected = true
					
			if selected:
				print("Selected object: ", child.get("object_name"))
				_process_object(child)

func _clear_pawn_selection() -> void:
	for pawn in selected_pawns:
		if is_instance_valid(pawn):
			pawn.set_selected(false)
	selected_pawns.clear()

func _handle_pawn_selection(rect: Rect2) -> void:
	# Clear previous selection unless Shift is held? (Keep simple for now: always clear)
	_clear_pawn_selection()
	
	var is_single_click = rect.size.length() < 10
	var click_pos = rect.position + rect.size / 2
	
	var all_pawns = get_tree().get_nodes_in_group("Pawns")
	for node in all_pawns:
		var pawn = node as Pawn
		if not pawn: continue
		
		var selected = false
		if is_single_click:
			if pawn.global_position.distance_to(click_pos) < 30.0: # Pawn radius
				selected = true
		else:
			if rect.has_point(pawn.global_position):
				selected = true
		
		if selected:
			pawn.set_selected(true)
			selected_pawns.append(pawn)
	
	print("Selected ", selected_pawns.size(), " pawns.")


func _handle_build_tool(rect: Rect2) -> void:
	var building_manager = get_node_or_null("/root/Main/BuildingManager")
	if not building_manager:
		push_error("BuildingManager not found!")
		return
		
	# Grid align
	var tile_size = 64
	var start_x = int(rect.position.x / tile_size)
	var start_y = int(rect.position.y / tile_size)
	var end_x = int((rect.position.x + rect.size.x) / tile_size)
	var end_y = int((rect.position.y + rect.size.y) / tile_size)
	
	# Clamp / Validate?
	
	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			var pos = Vector2(x * tile_size + tile_size/2.0, y * tile_size + tile_size/2.0)
			building_manager.request_placement(pos, current_building_key)

func _process_object(obj) -> void:
	match current_mode:
		ToolMode.DECONSTRUCT:
			var building_manager = get_node_or_null("/root/Main/BuildingManager")
			if not building_manager: return
			
			if obj is Blueprint:
				building_manager.cancel_blueprint(obj)
			elif obj.is_in_group("Structures"):
				building_manager.demolish_structure(obj)
				
		ToolMode.CHOP:
			if obj is TreeObject: # Assuming class_name TreeObject for Tree.gd
				_create_job(obj, JobDef.JobType.CUT_PLANT)
		ToolMode.MINE:
			if obj is WorldRock: # Assuming class_name WorldRock
				_create_job(obj, JobDef.JobType.MINE_ROCK)
		ToolMode.HARVEST:
			if obj is BerryBush: # Assuming class_name BerryBush
				_create_job(obj, JobDef.JobType.HARVEST_PLANT)
		ToolMode.DESTROY:
			# Target vegetation (Trees, Bushes) or anything destructible
			# Exclude Blueprints because interacting with them BUILDS them
			if obj is InteractableObject and not obj is Blueprint:
				print("Creating DESTROY job for ", obj.name)
				_create_job(obj, JobDef.JobType.DESTROY)
		ToolMode.CANCEL:
			# Logic to cancel job on this object would go here
			pass

func _create_job(obj: InteractableObject, type: JobDef.JobType) -> void:
	var job = JobDef.new()
	job.job_type = type
	job.target_object = obj
	job.target_position = obj.global_position
	# job.required_tool = "Axe" # Optional
	
	JobManager.add_job(job)
