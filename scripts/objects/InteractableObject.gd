class_name InteractableObject
extends Node2D

## Base class for all world objects that Pawns can interact with (Trees, Rocks, etc.)

signal interaction_completed(object: InteractableObject)
signal progress_updated(current: float, total: float)

@export_group("Resource Properties")
@export var object_name: String = "Generic Object"
@export var total_work_needed: float = 2.0
@export var loot_type: String = "Wood"
@export var loot_amount: int = 5

@export_group("Visuals")
## Reference to the visual sprite. If null, tries to find a Sprite2D child.
@export var visual_node: Node2D 

var current_work_done: float = 0.0
var is_designated_for_job: bool = false
var reserved_by: Node = null # The Pawn working on this

func _ready() -> void:
	if not visual_node:
		visual_node = get_node_or_null("Sprite2D")

## Called by a Pawn every frame/tick when working on this object
func interact(work_speed: float, delta: float) -> void:
	current_work_done += work_speed * delta
	emit_signal("progress_updated", current_work_done, total_work_needed)
	
	_on_interact_visual_feedback()
	
	if current_work_done >= total_work_needed:
		complete_interaction()

func complete_interaction() -> void:
	spawn_loot()
	emit_signal("interaction_completed", self)
	# In a real game, you might want to play a sound or particle effect before freeing
	queue_free()

func spawn_loot() -> void:
	if loot_amount > 0 and loot_type != "":
		print("Spawned %d %s from %s" % [loot_amount, loot_type, object_name])
		
		# Create ItemDrop
		var drop = load("res://scenes/objects/ItemDrop.tscn").instantiate()
		drop.setup(loot_type, loot_amount)
		drop.position = global_position
		
		# Add to map
		var map_manager = get_node_or_null("/root/Main/MapManager")
		if map_manager and map_manager.entities_container:
			map_manager.entities_container.add_child(drop)
		else:
			get_parent().add_child(drop)
		
		# Clear loot amount so the worker doesn't also get it directly
		loot_amount = 0

## Virtual method for visual feedback (shake, flash, etc.)
func _on_interact_visual_feedback() -> void:
	if visual_node:
		# Simple shake effect
		var tween = create_tween()
		tween.tween_property(visual_node, "rotation", 0.1, 0.05)
		tween.tween_property(visual_node, "rotation", -0.1, 0.05)
		tween.tween_property(visual_node, "rotation", 0.0, 0.05)

## Mark this object as a target for a job
func designate_job() -> void:
	is_designated_for_job = true
	modulate = Color(1.2, 1.2, 1.2) # Highlight
	print("%s designated for work." % object_name)

func cancel_job_designation() -> void:
	is_designated_for_job = false
	modulate = Color.WHITE
	reserved_by = null

func _exit_tree() -> void:
	# When destroyed, make the tile walkable again
	# This handles Trees, Rocks, Walls, etc.
	# We check if we are still valid and not just moving scenes
	if not is_queued_for_deletion(): return
	
	var map_manager = get_node_or_null("/root/Main/MapManager")
	if map_manager:
		map_manager.set_tile_solid(global_position, false)

## Serialization
func get_save_data() -> Dictionary:
	return {
		"type": object_name.replace(" ", ""), # "Tree", "Rock" etc. Simplistic mapping.
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"work_done": current_work_done,
		"designated": is_designated_for_job
	}

func load_save_data(data: Dictionary) -> void:
	current_work_done = data.get("work_done", 0.0)
	if data.get("designated", false):
		designate_job()
		# Note: We aren't recreating the JobDef in JobManager here.
		# A full system would need to re-issue the job to the manager.
		var job_type_enum = JobDef.JobType.NONE
		# Infer job type (Hack for prototype)
		if self is TreeObject: job_type_enum = JobDef.JobType.CUT_PLANT
		elif self is WorldRock: job_type_enum = JobDef.JobType.MINE_ROCK
		elif self is BerryBush: job_type_enum = JobDef.JobType.HARVEST_PLANT
		
		if job_type_enum != JobDef.JobType.NONE:
			var job = JobDef.new(self, job_type_enum)
			JobManager.add_job(job)
