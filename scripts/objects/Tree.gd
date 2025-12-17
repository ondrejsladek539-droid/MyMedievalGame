class_name TreeObject
extends InteractableObject

func _init():
	object_name = "Tree"
	total_work_needed = 3.0
	loot_type = "Wood"
	# loot_amount set in _ready

func _ready():
	super._ready()
	loot_amount = randi_range(20, 60)
	
	# Set up specific tree visuals if needed
	if not visual_node:
		pass

# Override specific behavior if needed
func complete_interaction() -> void:
	# Trees might leave a stump? For now, just destroy.
	super.complete_interaction()
