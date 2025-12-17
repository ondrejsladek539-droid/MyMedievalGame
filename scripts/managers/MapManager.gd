class_name MapManager
extends Node

## Handles procedural map generation and object spawning.

@export var map_width: int = 100
@export var map_height: int = 100
@export var seed_value: int = 0
@export var tile_map_layer: TileMapLayer
@export var entities_container: Node2D

# Tile Source IDs (Matches TileSet in main.tscn)
const SOURCE_DIRT = 0
const SOURCE_GRASS = 1
const SOURCE_WATER = 2
const TILE_SIZE = 64 # Re-adding this constant as it is used in Main.gd

# Tile Coordinates (All are 0,0 since they are separate single-tile atlases)
const TILE_COORD_BASE = Vector2i(0, 0)

# Scenes to spawn - Using exports instead of hardcoded preloads to avoid errors if files don't exist yet
# Assign these in the Inspector!
@export var tree_scene: PackedScene
@export var rock_scene: PackedScene
@export var berry_scene: PackedScene

var astar: AStarGrid2D
var reservation_manager: ReservationManager

# Terrain Costs
const COST_GRASS = 1.0
const COST_DIRT = 1.3
const COST_STONE = 2.0
const COST_MUD = 3.0

func _ready() -> void:
	# Initialize ReservationManager
	reservation_manager = ReservationManager.new()
	reservation_manager.name = "ReservationManager"
	add_child(reservation_manager)

	if seed_value == 0:
		seed_value = randi()
	
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, map_width, map_height)
	astar.cell_size = Vector2(TILE_SIZE, TILE_SIZE)
	# Prevent corner cutting by requiring both neighbors to be walkable for diagonal movement
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

func generate_map(p_seed: int = -1) -> void:
	if p_seed != -1:
		seed_value = p_seed
		
	print("Generating map with seed: ", seed_value)
	
	if not tile_map_layer:
		push_error("MapManager: TileMapLayer not assigned!")
		return
		
	tile_map_layer.clear()
	
	# Update AStar region if map size changed
	astar.region = Rect2i(0, 0, map_width, map_height)
	astar.update()
	
	var noise = FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.05
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	
	var counts = {SOURCE_WATER: 0, SOURCE_GRASS: 0, SOURCE_DIRT: 0}
	
	for x in range(map_width):
		for y in range(map_height):
			var val = noise.get_noise_2d(x, y)
			var pos = Vector2i(x, y)
			
			# Reset point to solid false (walkable) by default
			astar.set_point_solid(pos, false)
			
			if val < -0.2:
				tile_map_layer.set_cell(pos, SOURCE_WATER, TILE_COORD_BASE)
				counts[SOURCE_WATER] += 1
				astar.set_point_solid(pos, true) # Water is solid
			elif val < 0.4:
				tile_map_layer.set_cell(pos, SOURCE_GRASS, TILE_COORD_BASE)
				counts[SOURCE_GRASS] += 1
				# Chance to spawn nature
				_try_spawn_nature(x, y, val)
			else:
				tile_map_layer.set_cell(pos, SOURCE_DIRT, TILE_COORD_BASE)
				counts[SOURCE_DIRT] += 1
				# Chance to spawn rocks
				_try_spawn_rock(x, y, val)
	
	print("Map Generation Complete. Tile Counts: ", counts)
	if counts[SOURCE_WATER] == 0: push_warning("No Water generated!")
	if counts[SOURCE_DIRT] == 0: push_warning("No Dirt generated!")
	
	_generate_collisions()

func get_path_points(start_world: Vector2, end_world: Vector2) -> Array[Vector2]:
	var start_map = tile_map_layer.local_to_map(start_world)
	var end_map = tile_map_layer.local_to_map(end_world)
	
	# Clamp to map bounds
	start_map.x = clamp(start_map.x, 0, map_width - 1)
	start_map.y = clamp(start_map.y, 0, map_height - 1)
	end_map.x = clamp(end_map.x, 0, map_width - 1)
	end_map.y = clamp(end_map.y, 0, map_height - 1)
	
	var id_path = astar.get_id_path(start_map, end_map)
	var points: Array[Vector2] = []
	
	for id in id_path:
		# Convert back to world coordinates (center of tile)
		var point = tile_map_layer.map_to_local(id)
		points.append(point)
		
	return points

func get_smart_path(start_world: Vector2, end_world: Vector2) -> Array[Vector2]:
	var start_map = tile_map_layer.local_to_map(start_world)
	var end_map = tile_map_layer.local_to_map(end_world)
	
	# Clamp coords
	start_map.x = clamp(start_map.x, 0, map_width - 1)
	start_map.y = clamp(start_map.y, 0, map_height - 1)
	end_map.x = clamp(end_map.x, 0, map_width - 1)
	end_map.y = clamp(end_map.y, 0, map_height - 1)
	
	# Check if destination is solid
	if astar.is_point_solid(end_map):
		# Find closest non-solid neighbor
		# Prioritize orthogonal neighbors (first 4) to avoid diagonal issues at the end
		var neighbors = [
			Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
		]
		
		var best_neighbor = Vector2i.MAX
		var min_dist = INF
		
		for n in neighbors:
			var check_pos = end_map + n
			if check_pos.x >= 0 and check_pos.x < map_width and check_pos.y >= 0 and check_pos.y < map_height:
				if not astar.is_point_solid(check_pos):
					var dist = Vector2(check_pos).distance_to(Vector2(start_map))
					# Add bias against diagonals (indices 4-7)
					if abs(n.x) == 1 and abs(n.y) == 1:
						dist += 0.5 # Penalty for diagonal to prefer orthogonal if similar distance
						
					if dist < min_dist:
						min_dist = dist
						best_neighbor = check_pos
		
		if best_neighbor != Vector2i.MAX:
			end_map = best_neighbor
		else:
			# No walkable neighbors? Return empty or try anyway (will fail)
			return []
			
	var id_path = astar.get_id_path(start_map, end_map)
	var points: Array[Vector2] = []
	
	for id in id_path:
		var point = tile_map_layer.map_to_local(id)
		points.append(point)
		
	return points

func is_water(x: int, y: int) -> bool:
	if x < 0 or x >= map_width or y < 0 or y >= map_height:
		return true
	return astar.is_point_solid(Vector2i(x, y))

func _generate_collisions() -> void:
	# Clear existing collisions
	if has_node("MapCollisions"):
		get_node("MapCollisions").queue_free()
	
	var static_body = StaticBody2D.new()
	static_body.name = "MapCollisions"
	add_child(static_body)
	
	# 1. Map Borders
	var border_thickness = 100.0
	var map_pixel_size = Vector2(map_width * TILE_SIZE, map_height * TILE_SIZE)
	
	var borders = [
		Rect2(Vector2(-border_thickness, 0), Vector2(border_thickness, map_pixel_size.y)), # Left
		Rect2(Vector2(map_pixel_size.x, 0), Vector2(border_thickness, map_pixel_size.y)), # Right
		Rect2(Vector2(0, -border_thickness), Vector2(map_pixel_size.x, border_thickness)), # Top
		Rect2(Vector2(0, map_pixel_size.y), Vector2(map_pixel_size.x, border_thickness))  # Bottom
	]
	
	for rect in borders:
		var col = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = rect.size
		col.shape = shape
		col.position = rect.position + rect.size / 2
		static_body.add_child(col)
		
	# 2. Water Collisions
	# We iterate through the TileMapLayer to find water tiles
	if not tile_map_layer: return
	
	for x in range(map_width):
		for y in range(map_height):
			var tile_data = tile_map_layer.get_cell_source_id(Vector2i(x, y))
			if tile_data == SOURCE_WATER:
				var col = CollisionShape2D.new()
				var shape = RectangleShape2D.new()
				shape.size = Vector2(TILE_SIZE, TILE_SIZE)
				col.shape = shape
				col.position = Vector2(x * TILE_SIZE + TILE_SIZE/2.0, y * TILE_SIZE + TILE_SIZE/2.0)
				static_body.add_child(col)
	
	print("Map collisions generated (Borders + Water).")

func _try_spawn_nature(x: int, y: int, _noise_val: float) -> void:
	# Use a secondary noise or random chance based on position for deterministic results
	var chance = randf() # Note: randf() is not seeded by FastNoise, so for full determinism reset seed or use noise
	
	if chance < 0.05:
		spawn_object(tree_scene, x, y)
	elif chance < 0.08:
		spawn_object(berry_scene, x, y)

func _try_spawn_rock(x: int, y: int, _noise_val: float) -> void:
	if randf() < 0.03:
		spawn_object(rock_scene, x, y)


func set_tile_solid(pos_world: Vector2, solid: bool) -> void:
	if not tile_map_layer or not astar: return
	var map_pos = tile_map_layer.local_to_map(pos_world)
	if astar.region.has_point(map_pos):
		astar.set_point_solid(map_pos, solid)

func spawn_object(scene: PackedScene, x: int, y: int) -> void:
	if not scene or not entities_container:
		return
		
	var instance = scene.instantiate()
	instance.position = tile_map_layer.map_to_local(Vector2i(x, y))
	entities_container.add_child(instance)
	
	# Mark as solid in AStar
	if astar:
		astar.set_point_solid(Vector2i(x, y), true)

## Clears all interactable objects from the map
func clear_objects() -> void:
	if not entities_container: return
	for child in entities_container.get_children():
		if child is InteractableObject:
			child.queue_free()

func get_storage_position() -> Vector2:
	# For now, return a fixed position near the top-left spawn
	# Ideally, this would be a designated Stockpile zone
	return Vector2(10 * TILE_SIZE, 10 * TILE_SIZE)

## Finds a valid standing spot adjacent to a target tile (e.g. for building)
func get_valid_build_position(pawn_world_pos: Vector2, target_world_pos: Vector2) -> Vector2:
	var target_map = tile_map_layer.local_to_map(target_world_pos)
	var pawn_map = tile_map_layer.local_to_map(pawn_world_pos)
	
	# Get all neighbors
	var neighbors = [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
	]
	
	var best_pos = Vector2.ZERO
	var min_dist = INF
	
	for n in neighbors:
		var check_pos = target_map + n
		
		# Skip if out of bounds
		if check_pos.x < 0 or check_pos.x >= map_width or check_pos.y < 0 or check_pos.y >= map_height:
			continue
			
		# Must be walkable (not solid)
		if astar.is_point_solid(check_pos):
			continue
			
		# Check reservations? Maybe not strictly necessary for *finding* a spot, 
		# but better to avoid reserved spots if possible.
		# For now, just check physical validity.
		
		var dist = Vector2(check_pos).distance_to(Vector2(pawn_map))
		if dist < min_dist:
			min_dist = dist
			best_pos = tile_map_layer.map_to_local(check_pos)
			
	return best_pos
