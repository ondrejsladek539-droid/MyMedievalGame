class_name Structure
extends InteractableObject

var building_key: String = ""
var cost_data: Dictionary = {}

func _ready() -> void:
	super._ready()
	add_to_group("Structures")
	total_work_needed = 4.0 # 4 seconds to deconstruct
	loot_type = "" 
	loot_amount = 0
	
	# Try to initialize loot if not set (e.g. loaded from save or placed in editor)
	if loot_amount == 0 and object_name != "":
		var def = DataManager.get_building_def(object_name)
		if not def.is_empty() and "cost" in def:
			var cost = def.cost
			if "Wood" in cost:
				loot_type = "Wood"
				loot_amount = int(cost["Wood"] * 0.5)

func setup(key: String, cost: Dictionary) -> void:
	building_key = key
	cost_data = cost
	object_name = key
	
	# Apply texture from data if available
	var def = DataManager.get_building_def(key)
	if not def.is_empty() and "texture_path" in def:
		var tex = load(def.texture_path)
		if tex:
			var sprite = get_node_or_null("Sprite2D")
			if sprite:
				sprite.texture = tex
	
	# Calculate loot (50% refund) - Simplistic for now (Wood only)
	if "Wood" in cost:
		loot_type = "Wood"
		loot_amount = int(cost["Wood"] * 0.5)
	
	print("Structure setup: %s (Loot: %d %s)" % [key, loot_amount, loot_type])

func designate_job() -> void:
	super.designate_job()
	# Red tint for deconstruction
	modulate = Color(1.0, 0.4, 0.4) 

func spawn_loot() -> void:
	print("Spawning refund for %s" % object_name)
	
	# If we have cost data, refund 50% of everything
	if not cost_data.is_empty():
		for resource in cost_data:
			var amount = int(cost_data[resource] * 0.5)
			if amount > 0:
				_spawn_drop(resource, amount)
		
		# Clear loot_amount so base class doesn't do anything
		loot_amount = 0
	else:
		# Fallback if cost_data missing (e.g. legacy save or pre-placed)
		# Use the loot_type/loot_amount calculated in _ready
		super.spawn_loot()

func _spawn_drop(type: String, amount: int) -> void:
	var drop = load("res://scenes/objects/ItemDrop.tscn").instantiate()
	drop.setup(type, amount)
	# Random offset to spread them out
	drop.position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	
	var map_manager = get_node_or_null("/root/Main/MapManager")
	if map_manager and map_manager.entities_container:
		map_manager.entities_container.add_child(drop)
	else:
		get_parent().add_child(drop)
