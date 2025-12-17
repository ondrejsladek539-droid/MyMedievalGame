class_name Pawn
extends CharacterBody2D

enum State {
	IDLE,
	MOVING_TO_JOB,
	WORKING,
	RETURNING,
	RELAXING,
	MOVING_TO_POSITION
}

@export var work_speed: float = 1.0
@export var inventory_capacity: int = 10

var current_state: State = State.IDLE
var current_job: JobDef = null
var inventory: Dictionary = {} # item_type: amount
var map_manager: MapManager # Assigned by Main upon spawn
var zone_manager: ZoneManager

# Components
var movement_component: MovementComponent

# Selection
var is_selected: bool = false
var selection_indicator: Line2D
var path_line: Line2D

# Relaxing
var relax_timer: float = 0.0

func _ready() -> void:
	add_to_group("Pawns")
	
	# Initialize Components
	movement_component = MovementComponent.new()
	movement_component.name = "MovementComponent"
	add_child(movement_component)
	
	# Connect Signals
	movement_component.destination_reached.connect(_on_destination_reached)
	movement_component.movement_failed.connect(_on_movement_failed)
	movement_component.path_changed.connect(_on_path_changed)
	
	# Setup Visuals
	_setup_visuals()
	
	# Ensure MapManager is assigned (if not already by spawner)
	if not map_manager:
		map_manager = get_node_or_null("/root/Main/MapManager")
	
	if map_manager:
		movement_component.setup(self, map_manager)

func _setup_visuals() -> void:
	# Selection Indicator
	selection_indicator = Line2D.new()
	selection_indicator.width = 2.0
	selection_indicator.default_color = Color(0, 1, 0, 0.8)
	selection_indicator.visible = false
	var points = []
	var radius = 20.0
	for i in range(33):
		var angle = i * TAU / 32.0
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	selection_indicator.points = points
	add_child(selection_indicator)
	
	# Path Line
	path_line = Line2D.new()
	path_line.width = 2.0
	path_line.default_color = Color(1, 1, 1, 0.5)
	path_line.top_level = true
	path_line.visible = false
	add_child(path_line)

func _process(delta: float) -> void:
	# MovementComponent handles movement logic internally via its own _process
	
	match current_state:
		State.IDLE:
			_process_idle_state(delta)
		State.MOVING_TO_JOB:
			_process_moving_to_job(delta)
		State.WORKING:
			_process_working_state(delta)
		State.RETURNING:
			_process_returning_state(delta)
		State.RELAXING:
			_process_relaxing_state(delta)
		State.MOVING_TO_POSITION:
			pass # Handled by signals

func set_selected(selected: bool) -> void:
	is_selected = selected
	selection_indicator.visible = selected
	path_line.visible = selected and movement_component.is_moving_between_tiles # Only show if moving

func command_move_to(pos: Vector2) -> void:
	_cancel_current_job()
	set_state(State.MOVING_TO_POSITION)
	movement_component.move_to(pos)

func stop_job() -> void:
	_cancel_current_job()
	movement_component.stop()
	set_state(State.IDLE)

func _cancel_current_job() -> void:
	if current_job:
		JobManager.cancel_job(current_job)
		current_job = null
	
	# Disconnect working signals if needed
	# (Logic handled in set_state mostly)

func set_state(new_state: State) -> void:
	current_state = new_state
	# print("Pawn state changed to: ", State.keys()[new_state])

# --- State Processing ---

func _process_idle_state(delta: float) -> void:
	if not inventory.is_empty():
		set_state(State.RETURNING)
		return
		
	var new_job = JobManager.request_job(self)
	if new_job:
		current_job = new_job
		set_state(State.MOVING_TO_JOB)
		
		# Determine where to move
		# If job is "Build" (Blueprint), we need adjacent tile
		# If job is "Harvest" (Plant), we need adjacent tile
		# If job is "Haul" (Item), we need adjacent tile
		# Generally, for interactions, we move ADJACENT.
		# But 'move_to' with 'adjacent_only=true' handles this via smart path
		
		# Special handling for Blueprints to find BEST adjacent spot
		if current_job.job_type == JobDef.JobType.BUILD:
			var build_spot = map_manager.get_valid_build_position(global_position, current_job.target_position)
			if build_spot != Vector2.ZERO:
				movement_component.move_to(build_spot)
			else:
				print("No valid build spot found!")
				JobManager.return_job(current_job)
				current_job = null
				set_state(State.IDLE)
		elif current_job.job_type == JobDef.JobType.DELIVER_RESOURCES:
			_start_resource_delivery()
		else:
			# Standard move
			movement_component.move_to(current_job.target_position, true)
			
	else:
		relax_timer -= delta
		if relax_timer <= 0:
			set_state(State.RELAXING)

func _start_resource_delivery() -> void:
	# 1. Check if we already have the resource
	var needed_type = current_job.required_resource_type
	var needed_amount = current_job.required_resource_amount
	
	if inventory.get(needed_type, 0) >= needed_amount:
		# We have it! Go to blueprint.
		set_state(State.RETURNING) # RETURNING handles moving to blueprint if job is DELIVER
		return

	# 2. Find resource source
	# Priority A: ItemDrops on ground
	var closest_drop = _find_closest_item_drop(needed_type)
	if closest_drop:
		movement_component.move_to(closest_drop.global_position)
		return
		
	# Priority B: Stockpile (Virtual fetch)
	# For "Physical Construction", we really should require items on ground.
	# But as a fallback/hybrid, we can fetch from ResourceManager IF we are at a storage zone.
	var storage_tile = zone_manager.get_closest_storage_tile(global_position)
	if storage_tile != Vector2.ZERO:
		var resource_manager = get_node_or_null("/root/ResourceManager")
		if resource_manager and resource_manager.has_resource(needed_type, 1):
			movement_component.move_to(storage_tile)
			return
			
	print("No resource source found for %s" % needed_type)
	JobManager.report_failed_job(current_job)
	current_job = null
	set_state(State.IDLE)

func _find_closest_item_drop(type: String) -> ItemDrop:
	var best_drop: ItemDrop = null
	var min_dist = INF
	
	var drops = get_tree().get_nodes_in_group("Items")
	for drop in drops:
		if drop is ItemDrop and drop.loot_type == type:
			# Check if reserved? Ideally yes, but let's skip for simplicity or add later
			var dist = global_position.distance_to(drop.global_position)
			if dist < min_dist:
				min_dist = dist
				best_drop = drop
				
	return best_drop

func _process_moving_to_job(_delta: float) -> void:
	# Movement is handled by component. We just wait for signals.
	# But we should check if job is still valid
	if current_job and not current_job.is_valid():
		stop_job()

func _process_working_state(delta: float) -> void:
	if not current_job or not is_instance_valid(current_job.target_object):
		_finish_work_cycle() # Target lost
		return
		
	var target = current_job.target_object as InteractableObject
	target.interact(work_speed, delta)

func _process_returning_state(_delta: float) -> void:
	if not zone_manager:
		zone_manager = get_node_or_null("/root/Main/ZoneManager")
		if not zone_manager:
			print("No ZoneManager found.")
			set_state(State.IDLE)
			return

	# If we are not moving, find a storage spot
	if movement_component.current_state == MovementComponent.State.IDLE:
		var target_pos = Vector2.ZERO
		
		# If returning from DELIVER_RESOURCES job, we need to go to the blueprint
		if current_job and current_job.job_type == JobDef.JobType.DELIVER_RESOURCES:
			target_pos = map_manager.get_valid_build_position(global_position, current_job.target_position)
		else:
			# Standard haul to storage
			target_pos = zone_manager.get_closest_storage_tile(global_position)
			
		if target_pos != Vector2.ZERO:
			# Check if we are close enough to deposit
			if global_position.distance_to(target_pos) < 30.0:
				_deposit_items()
			else:
				movement_component.move_to(target_pos)
		else:
			# No storage, just idle
			print("No storage/delivery target found for returning pawn.")
			set_state(State.IDLE)

func _process_relaxing_state(delta: float) -> void:
	# Randomly check for work
	if randf() < 0.01:
		set_state(State.IDLE) # Will check for job next frame
		return
		
	# If not moving, maybe find a relax spot
	if movement_component.current_state == MovementComponent.State.IDLE:
		# (Simplified relax logic: just wander for now)
		var wander_target = global_position + Vector2(randf_range(-100, 100), randf_range(-100, 100))
		# Clamp to map... logic can be added here or in MapManager
		movement_component.move_to(wander_target)

# --- Signal Handlers ---

func _on_destination_reached() -> void:
	match current_state:
		State.MOVING_TO_POSITION:
			set_state(State.IDLE)
		State.MOVING_TO_JOB:
			# If DELIVER_RESOURCES, we arrived at SOURCE (ItemDrop or Stockpile)
			if current_job and current_job.job_type == JobDef.JobType.DELIVER_RESOURCES:
				_handle_resource_pickup()
			else:
				set_state(State.WORKING)
				# Hook up completion signal
				if current_job and is_instance_valid(current_job.target_object):
					var target = current_job.target_object as InteractableObject
					if not target.interaction_completed.is_connected(_on_job_completed):
						target.interaction_completed.connect(_on_job_completed)
		State.RETURNING:
			_deposit_items()
		State.RELAXING:
			# Arrived at relax spot, wait a bit
			pass

func _handle_resource_pickup() -> void:
	# We are at the source.
	var needed_type = current_job.required_resource_type
	var needed_amount = current_job.required_resource_amount
	var current_held = inventory.get(needed_type, 0)
	var amount_to_pickup = needed_amount - current_held
	
	if amount_to_pickup <= 0:
		set_state(State.RETURNING)
		return
		
	# Check for ItemDrop at feet
	var picked_up = false
	var drops = get_tree().get_nodes_in_group("Items")
	for drop in drops:
		if drop is ItemDrop and drop.loot_type == needed_type:
			if drop.global_position.distance_to(global_position) < 30.0:
				var take = drop.reduce_amount(amount_to_pickup)
				inventory[needed_type] = inventory.get(needed_type, 0) + take
				picked_up = true
				break
	
	# Fallback: Stockpile (Virtual Fetch - Only if physical pick up failed but we are at storage)
	if not picked_up:
		var resource_manager = get_node_or_null("/root/ResourceManager")
		# Only allow virtual pickup if we are actually AT the storage tile
		if resource_manager and resource_manager.consume_resource(needed_type, amount_to_pickup):
			# Double check we are at storage
			if zone_manager and zone_manager.is_stockpile_tile(global_position):
				inventory[needed_type] = inventory.get(needed_type, 0) + amount_to_pickup
				picked_up = true
				print("Picked up %d %s from stockpile (virtual)" % [amount_to_pickup, needed_type])
			else:
				# Refund if we weren't actually there (prevent magic teleporting resources)
				resource_manager.add_resource(needed_type, amount_to_pickup)
	
	if picked_up:
		set_state(State.RETURNING)
	else:
		print("Failed to pickup resource at location.")
		JobManager.return_job(current_job)
		current_job = null
		set_state(State.IDLE)

func _on_movement_failed() -> void:
	print("Movement failed.")
	if current_state == State.MOVING_TO_JOB:
		# Job unreachable
		if current_job:
			JobManager.report_failed_job(current_job)
			current_job = null
	
	set_state(State.IDLE)

func _on_path_changed(path: Array[Vector2]) -> void:
	if is_selected:
		path_line.points = [global_position] + path
		path_line.visible = not path.is_empty()

func _on_job_completed(object: InteractableObject) -> void:
	# Collect loot
	var loot_type = object.loot_type
	var amount = object.loot_amount
	
	if amount > 0 and loot_type != "":
		# If object was in stockpile, we must unregister it before it dies
		if zone_manager and zone_manager.is_stockpile_tile(object.global_position):
			var resource_manager = get_node_or_null("/root/ResourceManager")
			if resource_manager:
				resource_manager.unregister_item(loot_type, amount)
				
		if loot_type in inventory:
			inventory[loot_type] += amount
		else:
			inventory[loot_type] = amount
	
	_finish_work_cycle()

func _finish_work_cycle() -> void:
	current_job = null
	if not inventory.is_empty():
		set_state(State.RETURNING)
	else:
		set_state(State.IDLE)

func _deposit_items() -> void:
	# Check if we are delivering to a blueprint
	if current_job and current_job.job_type == JobDef.JobType.DELIVER_RESOURCES:
		if is_instance_valid(current_job.target_object) and current_job.target_object is Blueprint:
			var blueprint = current_job.target_object as Blueprint
			# Deposit all matching resources
			for type in inventory:
				var amount = inventory[type]
				var deposited = blueprint.deposit_resource(type, amount)
				if deposited > 0:
					inventory[type] -= deposited
					print("Deposited %d %s to blueprint" % [deposited, type])
					
					# Notify manager to check for next job
					var building_manager = get_node_or_null("/root/Main/BuildingManager")
					if building_manager:
						building_manager.on_resource_delivered(blueprint)
					
			# Clear empty inventory slots
			var keys_to_remove = []
			for k in inventory:
				if inventory[k] <= 0: keys_to_remove.append(k)
			for k in keys_to_remove: inventory.erase(k)
			
			# Check if blueprint needs more? Or if we are done?
			# For now, assume one trip is one job completion
			_finish_work_cycle()
			return

	# Standard deposit to stockpile (Physical Drop)
	var map_manager = get_node_or_null("/root/Main/MapManager")
	
	for item_type in inventory:
		var amount = inventory[item_type]
		if amount <= 0: continue
		
		# Check if there is already an item here to stack?
		var dropped = false
		for node in get_tree().get_nodes_in_group("Items"):
			if node is ItemDrop and node.global_position.distance_to(global_position) < 20.0 and node.loot_type == item_type:
				# Merge
				# Instead of just adding, we use a method if we had one, but manual is fine for now
				# Since we are ADDING to an existing drop, we must REGISTER the NEW amount
				node.loot_amount += amount
				node._update_visuals()
				
				if zone_manager and zone_manager.is_stockpile_tile(node.global_position):
					var rm = get_node_or_null("/root/ResourceManager")
					if rm: rm.register_item(item_type, amount)
					
				dropped = true
				break
		
		if not dropped:
			var drop = load("res://scenes/objects/ItemDrop.tscn").instantiate()
			drop.setup(item_type, amount)
			drop.position = global_position
			if map_manager:
				map_manager.entities_container.add_child(drop)
			else:
				get_parent().add_child(drop)
			# ItemDrop._ready() will handle registration if in stockpile
			
	inventory.clear()
	movement_component.stop()
	set_state(State.IDLE)

# --- Helpers ---

func has_tool(_tool_name: String) -> bool:
	return true

func get_save_data() -> Dictionary:
	return {
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"inventory": inventory
	}

func load_save_data(data: Dictionary) -> void:
	global_position.x = data.get("pos_x", global_position.x)
	global_position.y = data.get("pos_y", global_position.y)
	inventory = data.get("inventory", {})
