class_name ItemDrop
extends InteractableObject

@onready var label: Label = $Label
@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	super._ready()
	add_to_group("Items")
	total_work_needed = 0.5 # Fast pickup
	
	_update_visuals()

	# Check if already in stockpile
	var zone_manager = get_node_or_null("/root/Main/ZoneManager")
	var is_in_stockpile = false
	if zone_manager:
		is_in_stockpile = zone_manager.is_stockpile_tile(global_position)

	if not is_in_stockpile:
		# Create a haul job automatically
		var job = JobDef.new()
		job.job_type = JobDef.JobType.HAUL
		job.target_object = self
		job.target_position = global_position
		JobManager.add_job(job)
	else:
		print("Item dropped in stockpile. No haul job created.")
		# Notify ResourceManager to update counts
		var resource_manager = get_node_or_null("/root/ResourceManager")
		if resource_manager and resource_manager.has_method("register_item"):
			resource_manager.register_item(loot_type, loot_amount)
	
	# Pop animation
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

func reduce_amount(amount: int) -> int:
	var taken = min(loot_amount, amount)
	loot_amount -= taken
	_update_visuals()
	
	# If in stockpile, update global resources
	var zone_manager = get_node_or_null("/root/Main/ZoneManager")
	if zone_manager and zone_manager.is_stockpile_tile(global_position):
		var resource_manager = get_node_or_null("/root/ResourceManager")
		if resource_manager and resource_manager.has_method("unregister_item"):
			resource_manager.unregister_item(loot_type, taken)
	
	if loot_amount <= 0:
		queue_free()
		
	return taken

func setup(type: String, amount: int) -> void:
	loot_type = type
	loot_amount = amount
	object_name = type
	
	# If ready already called (unlikely if setup called immediately after instantiate), update visuals
	if is_inside_tree():
		_update_visuals()

func _update_visuals() -> void:
	if label:
		label.text = "%d" % loot_amount
	
	if sprite:
		match loot_type:
			"Wood": 
				sprite.texture = load("res://textures/objects/oak.png")
				sprite.modulate = Color(0.8, 0.6, 0.4) # Brownish
				sprite.scale = Vector2(0.3, 0.3)
			"Stone": 
				sprite.texture = load("res://textures/objects/stone.png")
				sprite.modulate = Color(1, 1, 1)
				sprite.scale = Vector2(0.3, 0.3)
			"Food", "Berries": 
				sprite.texture = load("res://textures/objects/berry_bush.png")
				sprite.modulate = Color(1, 1, 1)
				sprite.scale = Vector2(0.3, 0.3)
			_: 
				sprite.modulate = Color.WHITE

func spawn_loot() -> void:
	# Override to prevent ItemDrop from spawning another ItemDrop
	# The loot is collected by the Pawn directly from loot_amount
	pass
