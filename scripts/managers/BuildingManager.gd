class_name BuildingManager
extends Node2D

# Definitions of buildings
# Now loaded via DataManager

const TEMPLATES = {
	"SmallRoom": {
		"name": "Small Room",
		"buildings": [
			{"key": "Wall", "pos": Vector2(0, 0)},
			{"key": "Wall", "pos": Vector2(64, 0)},
			{"key": "Wall", "pos": Vector2(128, 0)},
			{"key": "Wall", "pos": Vector2(0, 64)},
			{"key": "Floor", "pos": Vector2(64, 64)},
			{"key": "Wall", "pos": Vector2(128, 64)},
			{"key": "Wall", "pos": Vector2(0, 128)},
			{"key": "Wall", "pos": Vector2(64, 128)},
			{"key": "Wall", "pos": Vector2(128, 128)},
			# Note: Objects overlapping might need care, but for now we allow it
			{"key": "Bed", "pos": Vector2(64, 64)}
		]
	}
}

var active_blueprints: Array = []
var blocked_blueprints: Array = [] # Blueprints waiting for obstacles to clear
var waiting_for_resources_blueprints: Array = [] # Blueprints waiting for resources to appear

func _process(_delta: float) -> void:
	# Periodically check lists
	if Engine.get_frames_drawn() % 60 == 0:
		_check_blocked_blueprints()
		_check_waiting_resources_blueprints()

func _check_blocked_blueprints() -> void:
	for i in range(blocked_blueprints.size() - 1, -1, -1):
		var bp = blocked_blueprints[i]
		if not is_instance_valid(bp):
			blocked_blueprints.remove_at(i)
			continue
			
		if not _check_and_handle_obstacles(bp):
			# No obstacles! Move to active construction (or resource check)
			blocked_blueprints.remove_at(i)
			_update_blueprint_jobs(bp)
			print("Blueprint %s is now clear for construction." % bp.name)

func _check_waiting_resources_blueprints() -> void:
	for i in range(waiting_for_resources_blueprints.size() - 1, -1, -1):
		var bp = waiting_for_resources_blueprints[i]
		if not is_instance_valid(bp):
			waiting_for_resources_blueprints.remove_at(i)
			continue
		
		# Check if resources are NOW available
		var needed = bp.get_next_needed_resource()
		if needed.is_empty():
			# Unexpected? Maybe filled by magic?
			waiting_for_resources_blueprints.remove_at(i)
			_update_blueprint_jobs(bp)
			continue
			
		if _is_resource_available_globally(needed.type, needed.amount):
			waiting_for_resources_blueprints.remove_at(i)
			_create_delivery_job(bp, needed)
			print("Resources found for %s! Creating delivery job." % bp.object_name)

func _is_resource_available_globally(type: String, amount: int) -> bool:
	# 1. Check Stockpile
	var resource_manager = get_node_or_null("/root/ResourceManager")
	if resource_manager and resource_manager.has_resource(type, 1): # Even 1 is enough to start
		return true
		
	# 2. Check ItemDrops on ground
	var drops = get_tree().get_nodes_in_group("Items")
	var total_on_ground = 0
	for drop in drops:
		if drop is ItemDrop and drop.loot_type == type:
			total_on_ground += drop.loot_amount
			if total_on_ground >= 1: return true # Optimization: Return early
			
	return false

func request_placement(pos: Vector2, key: String) -> void:
	if not DataManager.get_building_def(key).is_empty():
		create_blueprint(pos, key)
	elif key in TEMPLATES:
		create_template(pos, key)
	else:
		push_error("Unknown placement key: " + key)

func can_place_at(pos: Vector2, key: String) -> bool:
	var def = DataManager.get_building_def(key)
	if def.is_empty() and not key in TEMPLATES: return false
	
	var map_manager = get_node_or_null("/root/Main/MapManager")
	if not map_manager: return false
	
	var tile_pos = map_manager.tile_map_layer.local_to_map(pos)
	
	# Check map bounds
	if tile_pos.x < 0 or tile_pos.x >= map_manager.map_width or tile_pos.y < 0 or tile_pos.y >= map_manager.map_height:
		return false
		
	# Check if tile is solid (unless it's a floor that can be built on solid? No, usually floors replace terrain or go on top)
	# For now, prevent building on water (which is solid)
	if map_manager.is_water(tile_pos.x, tile_pos.y):
		return false
		
	# Check for existing buildings/blueprints at this location
	# Simple check: distance to existing entities
	for bp in active_blueprints:
		if bp.global_position.distance_to(pos) < 10.0:
			return false
			
	# Check existing structures?
	if map_manager.astar.is_point_solid(tile_pos):
		# Allow Door on Wall (or other replaceables)
		if key == "Door":
			var is_wall = false
			for child in map_manager.entities_container.get_children():
				if child is InteractableObject and child.global_position.distance_to(pos) < 10.0:
					if child.object_name == "Wall":
						is_wall = true
						break
			if is_wall:
				return true
				
		return false
		
	return true

func create_blueprint(pos: Vector2, building_key: String) -> void:
	var data = DataManager.get_building_def(building_key)
	if data.is_empty():
		push_error("Unknown building key: " + building_key)
		return
	
	var blueprint = preload("res://scenes/objects/Blueprint.tscn").instantiate()
	blueprint.setup(data, building_key)
	blueprint.position = pos
	
	add_child(blueprint)
	active_blueprints.append(blueprint)
	
	# Check for obstacles before creating job
	if _check_and_handle_obstacles(blueprint):
		print("Blueprint placed but blocked by obstacles. Jobs created to clear.")
		blocked_blueprints.append(blueprint)
		blueprint.modulate = Color(1, 0.5, 0.5, 0.6) # Red tint
	else:
		# Create jobs
		_update_blueprint_jobs(blueprint)

func _update_blueprint_jobs(blueprint) -> void:
	# Called when blueprint status changes or needs job refresh
	
	# 1. Check if needs resources
	var needed = blueprint.get_next_needed_resource()
	if not needed.is_empty():
		# CHECK AVAILABILITY
		if _is_resource_available_globally(needed.type, needed.amount):
			_create_delivery_job(blueprint, needed)
		else:
			print("No resources (%s) for %s. Waiting..." % [needed.type, blueprint.object_name])
			if not blueprint in waiting_for_resources_blueprints:
				waiting_for_resources_blueprints.append(blueprint)
		return

	# 2. If resources met, Create Build Job
	if JobManager.get_job_for_object(blueprint):
		return

	blueprint.modulate = Color(0.5, 0.5, 1.0, 0.6) # Reset color to blue
	var job = JobDef.new()
	job.job_type = JobDef.JobType.BUILD
	job.target_object = blueprint
	job.target_position = blueprint.global_position
	
	JobManager.add_job(job)

func _create_delivery_job(blueprint, needed: Dictionary) -> void:
	# Create Delivery Job
	var job = JobDef.new()
	job.job_type = JobDef.JobType.DELIVER_RESOURCES
	job.target_object = blueprint
	job.target_position = blueprint.global_position
	job.required_resource_type = needed.type
	job.required_resource_amount = needed.amount
	job.priority = 5 # Higher than build, lower than urgent
	
	JobManager.add_job(job)
	print("Created Delivery Job for %s: Need %d %s" % [blueprint.object_name, needed.amount, needed.type])

func on_resource_delivered(blueprint) -> void:
	_update_blueprint_jobs(blueprint)

func create_template(origin: Vector2, template_key: String) -> void:
	if not template_key in TEMPLATES:
		push_error("Unknown template: " + template_key)
		return
	
	var tmpl = TEMPLATES[template_key]
	print("Placing template: ", tmpl.name)
	
	for item in tmpl.buildings:
		# Apply offset
		create_blueprint(origin + item.pos, item.key)

# Removed _create_construction_job as it's replaced by _update_blueprint_jobs
# func _create_construction_job(blueprint) -> void: ...

func _check_and_handle_obstacles(blueprint) -> bool:
	var map_manager = get_node_or_null("/root/Main/MapManager")
	if not map_manager or not map_manager.entities_container:
		return false
		
	var has_obstacle = false
	var check_radius = 20.0 # Objects within this radius are obstacles
	
	# Check entities (Trees, Rocks, Items)
	for entity in map_manager.entities_container.get_children():
		if entity == blueprint: continue
		if not is_instance_valid(entity): continue
		
		# Simple distance check. For 64x64 tiles, checking center distance < 30 is safe
		if entity.global_position.distance_to(blueprint.global_position) < 30.0:
			if entity is InteractableObject:
				if entity.object_name == "Tree" or entity.object_name == "Rock" or entity.object_name == "Wall":
					_ensure_removal_job(entity)
					has_obstacle = true
			elif entity.get_script() and entity.get_script().resource_path.contains("ItemDrop"):
				# It's an item drop
				_ensure_haul_job(entity)
				has_obstacle = true
	
	return has_obstacle

func _ensure_removal_job(object: InteractableObject) -> void:
	# Check if job already exists
	if JobManager.get_job_for_object(object):
		return # Already planned
		
	var job = JobDef.new()
	if object.object_name == "Tree":
		job.job_type = JobDef.JobType.CUT_PLANT
	elif object.object_name == "Rock":
		job.job_type = JobDef.JobType.MINE_ROCK
	elif object.object_name == "Wall":
		job.job_type = JobDef.JobType.DECONSTRUCT
	else:
		return
		
	job.target_object = object
	job.target_position = object.global_position
	job.priority = 5 # Higher priority than build (usually 0) to clear path
	
	object.designate_job()
	JobManager.add_job(job)
	print("Auto-designated removal for %s blocking blueprint" % object.object_name)

func _ensure_haul_job(item_drop) -> void:
	if JobManager.get_job_for_object(item_drop):
		return
		
	var job = JobDef.new()
	job.job_type = JobDef.JobType.HAUL
	job.target_object = item_drop
	job.target_position = item_drop.global_position
	job.priority = 6 # Even higher, clear the floor
	
	JobManager.add_job(job)
	print("Auto-designated haul for blocking item")

func complete_construction(blueprint) -> void:
	var data = blueprint.data
	
	# Resources already consumed at placement
	
	var scene = load(data.scene_path).instantiate()
	scene.position = blueprint.position
	
	# Setup structure data if possible
	if scene is Structure:
		scene.setup(blueprint.building_key, data.cost)
	
	# Add to map entities
	var map_manager = get_node("/root/Main/MapManager")
	if map_manager and map_manager.entities_container:
		# Check if any pawn is currently at this location
		# If so, push them away slightly to prevent getting stuck
		var check_radius = 40.0 # TILE_SIZE is 64, so 40 is safe
		for pawn in get_tree().get_nodes_in_group("Pawns"):
			if pawn.global_position.distance_to(scene.global_position) < check_radius:
				# Push pawn away from center of new building
				var push_dir = (pawn.global_position - scene.global_position).normalized()
				if push_dir == Vector2.ZERO: push_dir = Vector2(1, 0) # Fallback
				pawn.global_position += push_dir * 50.0 # Push 50px away
				pawn.velocity = Vector2.ZERO # Stop movement to prevent fighting
				pawn.set_state(pawn.State.IDLE) # Reset state
				print("Pushed pawn %s out of new wall." % pawn.name)

		map_manager.entities_container.add_child(scene)
		
		# Mark as solid in navigation mesh/grid if it's not a floor and not explicitly walkable
		# "floor" type buildings are walkable
		var is_floor = data.get("type", "structure") == "floor"
		var is_walkable = data.get("walkable", false)
		
		if not is_floor and not is_walkable:
			map_manager.set_tile_solid(scene.global_position, true)
	else:
		add_child(scene) # Fallback
		
	# Remove blueprint
	active_blueprints.erase(blueprint)
	blueprint.queue_free()
	print("Construction complete: ", data.name)

func cancel_blueprint(blueprint) -> void:
	if not blueprint in active_blueprints:
		return
	
	var data = blueprint.data
	
	# Cancel associated job
	var job = JobManager.get_job_for_object(blueprint)
	if job:
		JobManager.available_jobs.erase(job)
	
	# Check if any pawn is working on this
	if blueprint.reserved_by and is_instance_valid(blueprint.reserved_by):
		var pawn = blueprint.reserved_by
		if pawn.current_job and pawn.current_job.target_object == blueprint:
			print("Stopping pawn %s from working on cancelled blueprint" % pawn.name)
			pawn.stop_job()

	# Refund resources
	var resource_manager = get_node_or_null("/root/ResourceManager")
	if resource_manager:
		for res in data.cost:
			resource_manager.add_resource(res, data.cost[res])
		print("Refunded resources for %s" % data.name)
		
	active_blueprints.erase(blueprint)
	blueprint.queue_free()

func demolish_structure(structure) -> void:
	if structure is Structure:
		# Check if already designated
		if structure.is_designated_for_job:
			return # Already marked
			
		structure.designate_job()
		
		var job = JobDef.new()
		job.job_type = JobDef.JobType.DECONSTRUCT
		job.target_object = structure
		job.target_position = structure.global_position
		
		JobManager.add_job(job)
		print("Marked %s for deconstruction" % structure.object_name)
	else:
		# Fallback for non-Structure objects (shouldn't happen with current setup but safe to keep)
		structure.queue_free()

