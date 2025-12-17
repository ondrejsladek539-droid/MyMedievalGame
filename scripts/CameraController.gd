extends Camera2D

@export_category("Camera Settings")
@export var move_speed: float = 600.0
@export var zoom_speed: float = 0.2
@export var min_zoom: float = 0.2
@export var max_zoom: float = 4.0
@export var zoom_smooth: float = 10.0

var target_zoom: Vector2 = Vector2.ONE

func _ready() -> void:
	# Default zoom to 0.6 for RimWorld-like overview
	zoom = Vector2(0.6, 0.6)
	target_zoom = zoom

func _process(delta: float) -> void:
	_handle_movement(delta)
	_handle_zoom(delta)

func _handle_movement(delta: float) -> void:
	var velocity = Vector2.ZERO
	
	# WASD Movement
	if Input.is_physical_key_pressed(KEY_W): velocity.y -= 1
	if Input.is_physical_key_pressed(KEY_S): velocity.y += 1
	if Input.is_physical_key_pressed(KEY_A): velocity.x -= 1
	if Input.is_physical_key_pressed(KEY_D): velocity.x += 1
	
	# Arrow Keys Fallback
	if Input.is_physical_key_pressed(KEY_UP): velocity.y -= 1
	if Input.is_physical_key_pressed(KEY_DOWN): velocity.y += 1
	if Input.is_physical_key_pressed(KEY_LEFT): velocity.x -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT): velocity.x += 1
	
	if velocity.length() > 0:
		velocity = velocity.normalized()
		# Move faster when zoomed out (optional quality of life)
		# When zoomed out (zoom < 1), 1/zoom is > 1. 
		# But wait, zoom 0.5 is FAR, zoom 2 is CLOSE.
		# If we are FAR (0.5), we see MORE map. We want to move FASTER across world units.
		# So dividing by zoom.x works: 600 / 0.5 = 1200 speed. 600 / 2 = 300 speed.
		var current_move_speed = move_speed * (1.0 / zoom.x)
		position += velocity * current_move_speed * delta

func _handle_zoom(delta: float) -> void:
	# Smoothly interpolate current zoom to target zoom
	zoom = zoom.lerp(target_zoom, zoom_smooth * delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				# Zoom IN (Increase zoom value)
				target_zoom += Vector2(zoom_speed, zoom_speed)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				# Zoom OUT (Decrease zoom value)
				target_zoom -= Vector2(zoom_speed, zoom_speed)
			
			# Clamp zoom values
			target_zoom.x = clamp(target_zoom.x, min_zoom, max_zoom)
			target_zoom.y = clamp(target_zoom.y, min_zoom, max_zoom)
