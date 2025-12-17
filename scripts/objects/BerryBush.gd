class_name BerryBush
extends InteractableObject

var growth_stage: float = 1.0 # 0.0 to 1.0

func _init():
	object_name = "Berry Bush"
	total_work_needed = 1.5
	loot_type = "Food"
	# loot_amount set in _ready

func _ready() -> void:
	super._ready()
	loot_amount = randi_range(20, 80)

func complete_interaction() -> void:
	spawn_loot()
	emit_signal("interaction_completed", self)
	
	# Berry bushes are not destroyed, just reset
	reset_growth()
	# Cancel the job designation but don't free
	cancel_job_designation()

func reset_growth() -> void:
	growth_stage = 0.0
	# Update visuals to show empty bush
	modulate = Color(0.5, 0.5, 0.5) 
	print("Berry bush harvested, resetting growth.")
	
	# Reset loot for next time (spawn_loot set it to 0)
	loot_amount = randi_range(20, 80)
	
	# Start a timer to regrow?
	# For prototype, we just leave it harvested.
