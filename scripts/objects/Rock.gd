class_name WorldRock
extends InteractableObject

func _init():
	object_name = "Rock"
	total_work_needed = 5.0
	loot_type = "Stone"
	# loot_amount set in _ready

func _ready() -> void:
	super._ready()
	loot_amount = randi_range(20, 60)

# Override to have different visual feedback, e.g., particles
func _on_interact_visual_feedback() -> void:
	if visual_node:
		# Rocks don't shake, maybe they flash red
		var tween = create_tween()
		tween.tween_property(visual_node, "modulate", Color.RED, 0.05)
		tween.tween_property(visual_node, "modulate", Color.WHITE, 0.05)
