class_name ZoneManager
extends Node2D

## Manages zones (Storage, Home, etc.) and renders them.

enum ZoneType {
	STORAGE,
	HOME
}

class Zone:
	var type: ZoneType
	var cells: Array[Vector2i] = []
	var color: Color
	
	func _init(p_type: ZoneType, p_color: Color):
		type = p_type
		color = p_color

var zones: Array[Zone] = []
var grid_to_zone: Dictionary = {} # Vector2i -> Zone

# Constants
const TILE_SIZE = 64

func _ready() -> void:
	z_index = -1 # Draw below entities but above terrain (Terrain is -1? Need to check)
	# Terrain is -1. Let's put this at 0, but with transparency. 
	# Actually, if Terrain is -1, 0 is fine.

func create_zone(rect: Rect2, type: ZoneType) -> void:
	# Convert world rect to grid coordinates
	var start_x = int(rect.position.x / TILE_SIZE)
	var start_y = int(rect.position.y / TILE_SIZE)
	var end_x = int((rect.position.x + rect.size.x) / TILE_SIZE)
	var end_y = int((rect.position.y + rect.size.y) / TILE_SIZE)
	
	# Create new zone
	var zone_color = Color(0.2, 0.8, 0.2, 0.3) if type == ZoneType.STORAGE else Color(0.2, 0.2, 0.8, 0.3)
	var new_zone = Zone.new(type, zone_color)
	
	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			var cell = Vector2i(x, y)
			
			# Remove from existing zone if any
			if cell in grid_to_zone:
				_remove_cell_from_zone(cell, grid_to_zone[cell])
			
			# Add to new zone
			new_zone.cells.append(cell)
			grid_to_zone[cell] = new_zone
	
	if new_zone.cells.size() > 0:
		zones.append(new_zone)
		queue_redraw()
		print("Created zone of type %s with %d cells" % [ZoneType.keys()[type], new_zone.cells.size()])

func _remove_cell_from_zone(cell: Vector2i, zone: Zone) -> void:
	zone.cells.erase(cell)
	grid_to_zone.erase(cell)
	# If zone empty, remove it?
	if zone.cells.is_empty():
		zones.erase(zone)

func is_stockpile_tile(pos: Vector2) -> bool:
	var cell = Vector2i(pos / TILE_SIZE)
	if cell in grid_to_zone:
		return grid_to_zone[cell].type == ZoneType.STORAGE
	return false

func get_closest_storage_tile(pawn_pos: Vector2) -> Vector2:
	var pawn_cell = Vector2i(pawn_pos / TILE_SIZE)
	var best_cell = Vector2i.ZERO
	var min_dist = INF
	var found = false
	
	# Naive search: check all storage zones
	# Optimization: Cache storage cells or use a spatial structure
	for zone in zones:
		if zone.type == ZoneType.STORAGE:
			for cell in zone.cells:
				# Simple Manhattan distance or Euclidean
				var dist = Vector2(cell).distance_to(Vector2(pawn_cell))
				if dist < min_dist:
					min_dist = dist
					best_cell = cell
					found = true
	
	if found:
		return Vector2(best_cell.x * TILE_SIZE + TILE_SIZE/2, best_cell.y * TILE_SIZE + TILE_SIZE/2)
	
	return Vector2.ZERO # No storage found

func get_random_point_in_zone(type: ZoneType) -> Vector2:
	var candidates = []
	for zone in zones:
		if zone.type == type:
			candidates.append_array(zone.cells)
	
	if candidates.is_empty():
		return Vector2.ZERO
	
	var cell = candidates.pick_random()
	# Return center of tile
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE/2.0, cell.y * TILE_SIZE + TILE_SIZE/2.0)

func _draw() -> void:
	for zone in zones:
		for cell in zone.cells:
			var pos = Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)
			draw_rect(Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE)), zone.color)
			# Draw border
			draw_rect(Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE)), zone.color.lightened(0.2), false, 2.0)
