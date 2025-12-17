class_name ReservationManager
extends Node

## Manages tile reservations to prevent pawn overlaps and conflicts.
## Used for both movement (claiming the next tile) and jobs (claiming a work target).

# Dictionary mapping Vector2i (map coords) to the Pawn (Node) holding the reservation
var _reservations: Dictionary = {}

# Signal for debugging or other systems
signal reservation_changed(tile: Vector2i, owner: Node, reserved: bool)

func _ready() -> void:
	# Ideally this should be part of the MapManager or an Autoload
	pass

## Attempts to reserve a tile for a specific pawn.
## Returns true if successful, false if already reserved by another pawn.
func reserve_tile(tile: Vector2i, pawn: Node) -> bool:
	if _reservations.has(tile):
		var current_owner = _reservations[tile]
		if current_owner == pawn:
			return true # Already reserved by us
		
		# Check if the owner is still valid
		if is_instance_valid(current_owner):
			return false # Reserved by someone else
		else:
			# Owner destroyed, claim it
			_reservations[tile] = pawn
			reservation_changed.emit(tile, pawn, true)
			return true
	
	_reservations[tile] = pawn
	reservation_changed.emit(tile, pawn, true)
	return true

## Releases a reservation for a specific tile.
func release_tile(tile: Vector2i, pawn: Node) -> void:
	if _reservations.has(tile):
		if _reservations[tile] == pawn:
			_reservations.erase(tile)
			reservation_changed.emit(tile, pawn, false)

## Releases all reservations held by a pawn.
## Call this when a pawn dies or is removed.
func release_all_for_pawn(pawn: Node) -> void:
	var tiles_to_remove = []
	for tile in _reservations:
		if _reservations[tile] == pawn:
			tiles_to_remove.append(tile)
	
	for tile in tiles_to_remove:
		_reservations.erase(tile)
		reservation_changed.emit(tile, pawn, false)

## Checks if a tile is reserved by anyone other than the checking pawn.
func is_reserved(tile: Vector2i, excluding_pawn: Node = null) -> bool:
	if _reservations.has(tile):
		var owner = _reservations[tile]
		if is_instance_valid(owner):
			return owner != excluding_pawn
		else:
			# Cleanup invalid owner
			_reservations.erase(tile)
			return false
	return false

## Returns the owner of a reserved tile, or null.
func get_reservation_owner(tile: Vector2i) -> Node:
	if _reservations.has(tile):
		var owner = _reservations[tile]
		if is_instance_valid(owner):
			return owner
		else:
			_reservations.erase(tile)
	return null
