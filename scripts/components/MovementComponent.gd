class_name MovementComponent
extends Node

## Handles grid-based movement, pathfinding, and tile reservation for a Pawn.

signal destination_reached
signal movement_failed
signal path_changed(path: Array[Vector2])

enum State {
	IDLE,
	MOVING,
	WAITING, # Waiting for reservation
	RECALCULATING
}

@export var movement_speed: float = 100.0
@export var rotation_speed: float = 10.0

var pawn: CharacterBody2D
var map_manager: MapManager
var reservation_manager: ReservationManager

var current_state: State = State.IDLE
var current_path: Array[Vector2] = []
var current_target_tile: Vector2i = Vector2i.MAX
var final_destination: Vector2 = Vector2.ZERO

# Smooth movement variables
var next_tile_world: Vector2 = Vector2.ZERO
var is_moving_between_tiles: bool = false
var tile_move_progress: float = 0.0
var start_move_pos: Vector2 = Vector2.ZERO

# Waiting logic
var wait_timer: float = 0.0
const WAIT_TIME_ON_BLOCK: float = 0.5
const MAX_RECALCULATIONS: int = 3
var recalculation_count: int = 0

func setup(p_pawn: CharacterBody2D, p_map_manager: MapManager) -> void:
	pawn = p_pawn
	map_manager = p_map_manager
	if map_manager:
		reservation_manager = map_manager.reservation_manager

func _process(delta: float) -> void:
	if not pawn or not map_manager: return
	
	match current_state:
		State.IDLE:
			pass
		State.MOVING:
			_process_movement(delta)
		State.WAITING:
			_process_waiting(delta)
		State.RECALCULATING:
			_process_recalculating()

func move_to(target_pos: Vector2, adjacent_only: bool = false) -> void:
	final_destination = target_pos
	recalculation_count = 0
	
	if adjacent_only:
		# For interacting/building, we want to go to a neighbor
		current_path = map_manager.get_smart_path(pawn.global_position, target_pos)
	else:
		current_path = map_manager.get_path_points(pawn.global_position, target_pos)
	
	if current_path.is_empty():
		# Try smart path anyway if direct failed (e.g. clicked on wall)
		if not adjacent_only:
			current_path = map_manager.get_smart_path(pawn.global_position, target_pos)
			
		if current_path.is_empty():
			_stop_movement(false) # Failed
			return
	
	# Current path includes start position sometimes? AStarGrid2D usually excludes start if it's the same.
	# But if we are slightly offset, it might include the current tile.
	# Let's clean up the path.
	var current_tile = map_manager.tile_map_layer.local_to_map(pawn.global_position)
	if not current_path.is_empty():
		var first_point_map = map_manager.tile_map_layer.local_to_map(current_path[0])
		if first_point_map == current_tile:
			current_path.pop_front()
	
	if current_path.is_empty():
		_stop_movement(true) # Already there
		return
		
	path_changed.emit(current_path)
	current_state = State.MOVING
	is_moving_between_tiles = false # Ready to start first step

func stop() -> void:
	_stop_movement(false)

func _process_movement(delta: float) -> void:
	# If we are already moving between tiles, continue interpolation
	if is_moving_between_tiles:
		_continue_tile_move(delta)
		return
	
	# If we are at a tile center (logically), pick next tile
	if current_path.is_empty():
		_stop_movement(true)
		return
		
	var next_point = current_path[0]
	var next_tile_map = map_manager.tile_map_layer.local_to_map(next_point)
	var current_tile_map = map_manager.tile_map_layer.local_to_map(pawn.global_position)
	
	# 1. Check if next tile is valid (not solid) - dynamic obstacle check
	if map_manager.astar.is_point_solid(next_tile_map):
		print("Path blocked by obstacle at ", next_tile_map)
		_enter_recalculate_state()
		return
	
	# 2. Check reservations - DISABLED to allow passing through
	# if reservation_manager.is_reserved(next_tile_map, pawn):
	# 	# Tile is occupied by someone else
	# 	# print("Tile reserved by another pawn: ", next_tile_map)
	# 	# Wait briefly
	# 	current_state = State.WAITING
	# 	wait_timer = WAIT_TIME_ON_BLOCK
	# 	return
	
	# 3. Reserve the tile - DISABLED
	# if reservation_manager.reserve_tile(next_tile_map, pawn):
	# 	# Success, start moving
	# 	# Release previous tile reservation (the one we are leaving)
	# 	reservation_manager.release_tile(current_tile_map, pawn)
		
	current_target_tile = next_tile_map
	next_tile_world = next_point
	start_move_pos = pawn.global_position
	is_moving_between_tiles = true
	tile_move_progress = 0.0
	
	# Rotate pawn to face direction
	var dir = (next_tile_world - start_move_pos).normalized()
	if dir != Vector2.ZERO:
		pawn.rotation = lerp_angle(pawn.rotation, dir.angle(), rotation_speed * delta)
		
	current_path.pop_front()
	path_changed.emit(current_path)
	# else:
	# 	# Should not happen if is_reserved returned false, but just in case
	# 	_enter_recalculate_state()

func _continue_tile_move(delta: float) -> void:
	var dist_total = start_move_pos.distance_to(next_tile_world)
	if dist_total <= 0.001:
		is_moving_between_tiles = false
		return
		
	# Calculate speed based on terrain cost
	# We can get cost from AStar
	var terrain_cost = map_manager.astar.get_point_weight_scale(current_target_tile)
	# Avoid division by zero
	if terrain_cost <= 0: terrain_cost = 1.0
	
	var actual_speed = movement_speed / terrain_cost
	var step = actual_speed * delta
	
	tile_move_progress += step
	var t = clamp(tile_move_progress / dist_total, 0.0, 1.0)
	
	pawn.global_position = start_move_pos.lerp(next_tile_world, t)
	
	if t >= 1.0:
		is_moving_between_tiles = false
		# We arrived at the tile center
		# Keep reservation? Yes, we are ON it now.
		# Note: We already released the previous tile in _process_movement step 3.

func _process_waiting(delta: float) -> void:
	wait_timer -= delta
	if wait_timer <= 0:
		# Try to resume move
		current_state = State.MOVING

func _enter_recalculate_state() -> void:
	recalculation_count += 1
	if recalculation_count > MAX_RECALCULATIONS:
		print("Max path recalculations reached. Aborting.")
		_stop_movement(false)
		return
		
	current_state = State.RECALCULATING

func _process_recalculating() -> void:
	# Recalculate path to final destination
	print("Recalculating path...")
	
	# Small delay or instant? Instant for now.
	# We use get_smart_path to try and find ANY way
	current_path = map_manager.get_smart_path(pawn.global_position, final_destination)
	
	if current_path.is_empty():
		_stop_movement(false)
	else:
		path_changed.emit(current_path)
		current_state = State.MOVING

func _stop_movement(success: bool) -> void:
	is_moving_between_tiles = false
	current_path.clear()
	current_state = State.IDLE
	var empty_path: Array[Vector2] = []
	path_changed.emit(empty_path)
	
	if success:
		destination_reached.emit()
	else:
		movement_failed.emit()
	
	# Note: We do NOT release the tile we are standing on. We occupy it.

func _exit_tree() -> void:
	# Cleanup reservations
	if reservation_manager and pawn:
		reservation_manager.release_all_for_pawn(pawn)
