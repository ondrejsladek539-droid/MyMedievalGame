extends CanvasLayer

signal tool_selected(mode: int)
signal build_tool_selected(key: String)

@onready var label_mode = $Panel/MarginContainer/HBoxContainer/LabelMode
@onready var resource_label = $ResourcePanel/MarginContainer/VBoxContainer/ResourceLabel
@onready var architect_panel = $ArchitectPanel # New panel
@onready var orders_panel = $OrdersPanel

func _ready() -> void:
	# Update label initially
	update_mode_label("NONE")
	
	if architect_panel:
		architect_panel.visible = false
	if orders_panel:
		orders_panel.visible = false
	
	# Connect to ResourceManager (Autoload)
	var resource_manager = get_node_or_null("/root/ResourceManager")
	if resource_manager:
		resource_manager.connect("resources_changed", _on_resources_changed)
		_on_resources_changed(resource_manager.resources)
	else:
		push_error("ResourceManager autoload not found!")
	
	_populate_architect_panel()

func _populate_architect_panel() -> void:
	if not architect_panel: return
	var container = architect_panel.get_node_or_null("VBoxContainer")
	if not container: return
	
	# Clear existing buttons
	for child in container.get_children():
		child.queue_free()
		
	# Add buttons from DataManager
	var defs = DataManager.get_all_buildable_defs()
	for key in defs:
		var def = defs[key]
		var btn = Button.new()
		btn.text = def.get("name", key)
		btn.pressed.connect(_on_dynamic_build_pressed.bind(key))
		container.add_child(btn)
	
	# Add Template buttons manually (TEMPLATES are still in BuildingManager for now)
	var btn_template = Button.new()
	btn_template.text = "Small Room"
	btn_template.pressed.connect(_on_btn_template_pressed)
	container.add_child(btn_template)

func _on_dynamic_build_pressed(key: String) -> void:
	emit_signal("build_tool_selected", key)

func _on_resources_changed(resources: Dictionary) -> void:
	if resource_label:
		var text = "Resources:\n"
		for r in resources:
			text += "%s: %d\n" % [r, resources[r]]
		resource_label.text = text


func _on_btn_chop_pressed() -> void:
	emit_signal("tool_selected", 1) # ToolMode.CHOP

func _on_btn_mine_pressed() -> void:
	emit_signal("tool_selected", 2) # ToolMode.MINE

func _on_btn_harvest_pressed() -> void:
	emit_signal("tool_selected", 3) # ToolMode.HARVEST

func _on_option_zone_item_selected(index: int) -> void:
	# Index 0 is "Zones..." title
	if index == 1:
		emit_signal("tool_selected", 4) # ToolMode.ZONE_STORAGE
	elif index == 2:
		emit_signal("tool_selected", 5) # ToolMode.ZONE_HOME (Future)
	
	# Reset selection to 0 visually if desired, but for now keep it to show active mode
	
func _on_btn_cancel_pressed() -> void:
	emit_signal("tool_selected", 0) # ToolMode.NONE (or CANCEL)
	if architect_panel:
		architect_panel.visible = false
	if orders_panel:
		orders_panel.visible = false

func _on_btn_architect_pressed() -> void:
	if architect_panel:
		architect_panel.visible = not architect_panel.visible
	if orders_panel:
		orders_panel.visible = false

func _on_btn_orders_pressed() -> void:
	if orders_panel:
		orders_panel.visible = not orders_panel.visible
	if architect_panel:
		architect_panel.visible = false

func _on_btn_destroy_pressed() -> void:
	emit_signal("tool_selected", 8) # ToolMode.DESTROY

func _on_btn_wall_pressed() -> void:
	emit_signal("build_tool_selected", "Wall")

func _on_btn_door_pressed() -> void:
	emit_signal("build_tool_selected", "Door")

func _on_btn_floor_pressed() -> void:
	emit_signal("build_tool_selected", "Floor")

func _on_btn_furniture_pressed() -> void:
	emit_signal("build_tool_selected", "Table")

func _on_btn_relax_pressed() -> void:
	emit_signal("build_tool_selected", "Bed")

func _on_btn_template_pressed() -> void:
	emit_signal("build_tool_selected", "SmallRoom")

func _on_btn_deconstruct_pressed() -> void:
	emit_signal("tool_selected", 7) # ToolMode.DECONSTRUCT = 7 based on enum index (0-based)
	# Enum: NONE=0, CHOP=1, MINE=2, HARVEST=3, STORAGE=4, HOME=5, BUILD=6, DECONSTRUCT=7, CANCEL=8

func update_mode_label(mode_name: String) -> void:
	if label_mode:
		label_mode.text = "Current Tool: " + mode_name
