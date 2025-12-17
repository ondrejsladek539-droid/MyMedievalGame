class_name BuildController
extends Node2D

## Handles player input for placing buildings (Blueprints).
## Add this node to your Main scene.

@export var map_manager: MapManager
@export var building_manager: BuildingManager
@export var tile_map_layer: TileMapLayer

enum ToolMode {
	NONE,
	BUILD,
	DECONSTRUCT,
	CANCEL
}

var current_mode: ToolMode = ToolMode.NONE
var active_build_key: String = ""
var ghost_node: Node2D = null

# Dragging support
var is_dragging: bool = false
var drag_start_pos: Vector2i = Vector2i.ZERO

func _ready() -> void:
	# Try to find references if not assigned
	if not map_manager:
		map_manager = get_node_or_null("/root/Main/MapManager")
	if not building_manager:
		building_manager = get_node_or_null("/root/Main/BuildingManager")
	if not tile_map_layer and map_manager:
		tile_map_layer = map_manager.tile_map_layer
		
	set_process_unhandled_input(true)

func _process(_delta: float) -> void:
	if current_mode == ToolMode.BUILD and ghost_node:
		var mouse_pos = get_global_mouse_position()
		var map_pos = tile_map_layer.local_to_map(mouse_pos)
		var snapped_pos = tile_map_layer.map_to_local(map_pos)
		
		ghost_node.global_position = snapped_pos
		
		# Update ghost color based on validity
		if building_manager.can_place_at(snapped_pos, active_build_key):
			ghost_node.modulate = Color(0.5, 1.0, 0.5, 0.5) # Green
		else:
			ghost_node.modulate = Color(1.0, 0.5, 0.5, 0.5) # Red

func _unhandled_input(event: InputEvent) -> void:
	if current_mode == ToolMode.NONE:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag()
			else:
				_end_drag()
				
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_mode()
			
	elif event is InputEventMouseMotion:
		if is_dragging and current_mode != ToolMode.NONE:
			_handle_drag_action(get_global_mouse_position())

func start_build_mode(key: String) -> void:
	current_mode = ToolMode.BUILD
	active_build_key = key
	
	_create_ghost(key)
	print("Build Mode Started: ", key)

func start_deconstruct_mode() -> void:
	current_mode = ToolMode.DECONSTRUCT
	_clear_ghost()
	print("Deconstruct Mode Started")

func start_cancel_mode() -> void:
	current_mode = ToolMode.CANCEL
	_clear_ghost()
	print("Cancel Mode Started")

func cancel_mode() -> void:
	current_mode = ToolMode.NONE
	active_build_key = ""
	_clear_ghost()
	print("Mode Cancelled")

func _create_ghost(key: String) -> void:
	_clear_ghost()
	
	var def = DataManager.get_building_def(key)
	if not def.is_empty():
		# Load the actual scene to show as ghost? Or a simple rect?
		# Loading scene is better for visuals
		var scene = load(def.scene_path).instantiate()
		if scene:
			ghost_node = scene
			
			# Apply texture if overridden in data
			if "texture_path" in def:
				var tex = load(def.texture_path)
				if tex:
					var sprite = scene.get_node_or_null("Sprite2D")
					if sprite:
						sprite.texture = tex
			
			# Strip logic/collision from ghost
			_strip_node_for_ghost(ghost_node)
			add_child(ghost_node)
			
	elif key in BuildingManager.TEMPLATES:
		var tmpl = BuildingManager.TEMPLATES[key]
		ghost_node = Node2D.new() # Container for template ghost
		add_child(ghost_node)
		
		for item in tmpl.buildings:
			var item_key = item.key
			var item_pos = item.pos
			
			var item_def = DataManager.get_building_def(item_key)
			if not item_def.is_empty():
				var scene = load(item_def.scene_path).instantiate()
				if scene:
					_strip_node_for_ghost(scene)
					scene.position = item_pos
					
					# Apply texture if overridden in data
					if "texture_path" in item_def:
						var tex = load(item_def.texture_path)
						if tex:
							var sprite = scene.get_node_or_null("Sprite2D")
							if sprite:
								sprite.texture = tex
					
					ghost_node.add_child(scene)
			
func _strip_node_for_ghost(node: Node) -> void:
	if node is CollisionShape2D or node is CollisionPolygon2D:
		node.queue_free()
	for child in node.get_children():
		_strip_node_for_ghost(child)

func _clear_ghost() -> void:
	if ghost_node:
		ghost_node.queue_free()
		ghost_node = null

func _start_drag() -> void:
	is_dragging = true
	_handle_drag_action(get_global_mouse_position())

func _end_drag() -> void:
	is_dragging = false

func _handle_drag_action(pos: Vector2) -> void:
	match current_mode:
		ToolMode.BUILD:
			_try_place_at(pos)
		ToolMode.DECONSTRUCT:
			_try_deconstruct_at(pos)
		ToolMode.CANCEL:
			_try_cancel_at(pos)

func _try_place_at(pos: Vector2) -> void:
	var map_pos = tile_map_layer.local_to_map(pos)
	var snapped_pos = tile_map_layer.map_to_local(map_pos)
	
	if building_manager.can_place_at(snapped_pos, active_build_key):
		building_manager.request_placement(snapped_pos, active_build_key)

func _try_deconstruct_at(pos: Vector2) -> void:
	# Find structure at position
	# Use small radius check
	if not map_manager or not map_manager.entities_container: return
	
	for child in map_manager.entities_container.get_children():
		if child is Structure:
			if child.global_position.distance_to(pos) < 30.0:
				building_manager.demolish_structure(child)

func _try_cancel_at(pos: Vector2) -> void:
	# Find blueprint at position
	for bp in building_manager.active_blueprints:
		if bp.global_position.distance_to(pos) < 30.0:
			building_manager.cancel_blueprint(bp)
