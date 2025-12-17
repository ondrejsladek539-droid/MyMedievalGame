extends PanelContainer

signal action_selected(action: String, target: Node)

var target_object: Node = null

func setup(target: Node) -> void:
	target_object = target

func _on_prioritize_pressed() -> void:
	emit_signal("action_selected", "prioritize", target_object)
	queue_free()

func _on_cancel_pressed() -> void:
	emit_signal("action_selected", "cancel", target_object)
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Check if clicked outside
		# Note: Control nodes use local coordinates for rect, but input events are usually global or viewport relative.
		# get_global_rect() returns global screen coordinates if in CanvasLayer.
		
		# If this node is in the world (Node2D), we need to handle differently.
		# Assuming this is added to a CanvasLayer (UI).
		if not get_global_rect().has_point(event.global_position):
			queue_free()
