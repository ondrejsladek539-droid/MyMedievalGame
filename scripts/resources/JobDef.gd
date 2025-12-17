class_name JobDef
extends Resource

## Defines a job that a Pawn can perform.
## This resource can be created at runtime to represent a specific task.

enum JobType {
	NONE,
	CUT_PLANT,
	MINE_ROCK,
	HARVEST_PLANT,
	HAUL,
	BUILD,
	DECONSTRUCT,
	DELIVER_RESOURCES,
	DESTROY
}

# Node references cannot be exported in Resources in Godot 4.x
var target_object: Node2D
@export var job_type: JobType = JobType.NONE
@export var required_tool: String = "" # e.g., "Axe", "Pickaxe"
@export var required_resource_type: String = "" # For DELIVER_RESOURCES (e.g. "Wood")
@export var required_resource_amount: int = 0
@export var target_position: Vector2
@export var priority: int = 0 # Higher value means higher priority

# Optional: Store specific parameters like amount to mine, etc.

func _init(p_target: Node2D = null, p_type: JobType = JobType.NONE, p_tool: String = ""):
	target_object = p_target
	job_type = p_type
	required_tool = p_tool
	
	if is_instance_valid(target_object):
		target_position = target_object.global_position

func is_valid() -> bool:
	return is_instance_valid(target_object) and job_type != JobType.NONE
