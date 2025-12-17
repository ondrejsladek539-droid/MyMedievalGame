class_name Blueprint
extends InteractableObject

var data: Dictionary
var building_key: String

# Resource requirements
var required_resources: Dictionary = {}
var delivered_resources: Dictionary = {}

func setup(p_data: Dictionary, p_key: String) -> void:
	data = p_data
	building_key = p_key
	object_name = "Blueprint: " + data.name
	total_work_needed = 3.0
	loot_type = ""
	loot_amount = 0
	
	# Load resource costs
	if "cost" in data:
		required_resources = data.cost.duplicate()
	
	# Initialize delivered tracking
	for res in required_resources:
		delivered_resources[res] = 0
	
	# Visual setup
	modulate = Color(0.5, 0.5, 1.0, 0.6) # Blue ghost
	
	# Use a default shape if visual_node is missing
	if not visual_node:
		var poly = Polygon2D.new()
		var size = 64.0
		var half_size = size / 2.0
		poly.polygon = PackedVector2Array([
			Vector2(-half_size, -half_size),
			Vector2(half_size, -half_size),
			Vector2(half_size, half_size),
			Vector2(-half_size, half_size)
		])
		poly.color = Color(1, 1, 1, 0.5)
		add_child(poly)
		visual_node = poly

	# Initial update
	update_status()

func update_status() -> void:
	# Update color/label based on resources
	if not is_fully_delivered():
		modulate = Color(1.0, 0.8, 0.2, 0.6) # Orange/Yellow if waiting for resources
	else:
		modulate = Color(0.5, 0.5, 1.0, 0.6) + Color(0, 0, 0, (current_work_done / total_work_needed) * 0.4)

func is_fully_delivered() -> bool:
	for res in required_resources:
		if delivered_resources.get(res, 0) < required_resources[res]:
			return false
	return true

func get_next_needed_resource() -> Dictionary:
	# Returns {type: String, amount: int} or empty
	for res in required_resources:
		var needed = required_resources[res]
		var current = delivered_resources.get(res, 0)
		if current < needed:
			return {"type": res, "amount": needed - current}
	return {}

func deposit_resource(type: String, amount: int) -> int:
	# Returns amount actually deposited
	if not type in required_resources:
		return 0
		
	var needed = required_resources[type] - delivered_resources.get(type, 0)
	var to_deposit = min(amount, needed)
	
	delivered_resources[type] = delivered_resources.get(type, 0) + to_deposit
	
	update_status()
	return to_deposit

func interact(work_power: float, delta: float) -> void:
	if not is_fully_delivered():
		# Cannot build yet
		return

	current_work_done += work_power * delta
	update_status()
	
	if current_work_done >= total_work_needed:
		complete_interaction()

func complete_interaction() -> void:
	# Consume resources? (Assume done before or ignored for now)
	emit_signal("interaction_completed", self)
	
	# Notify manager
	var building_manager = get_node("/root/Main/BuildingManager")
	if building_manager:
		building_manager.complete_construction(self)
	else:
		queue_free()

func spawn_loot() -> void:
	pass # Do nothing
