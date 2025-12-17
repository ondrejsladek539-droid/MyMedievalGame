extends Node

## Centralized Data Manager for loading and accessing external JSON definitions.
## Loads data from res://data/ at startup.

signal data_reloaded

# Data Stores
var buildings: Dictionary = {}
var items: Dictionary = {}
var furniture: Dictionary = {}
var pawns: Dictionary = {}
var recipes: Dictionary = {}

const DATA_DIR = "res://data/"

func _ready() -> void:
	load_all_data()

func load_all_data() -> void:
	print("DataManager: Loading data from ", DATA_DIR)
	
	# Ensure directory exists (create if not, though usually we expect it to exist in export)
	if not DirAccess.dir_exists_absolute(DATA_DIR):
		DirAccess.make_dir_absolute(DATA_DIR)
		print("DataManager: Created data directory.")
		
	# Load specific categories
	buildings = _load_category("buildings.json")
	items = _load_category("items.json")
	furniture = _load_category("furniture.json")
	pawns = _load_category("pawns.json")
	
	print("DataManager: Loading complete.")
	emit_signal("data_reloaded")

func _load_category(filename: String) -> Dictionary:
	var path = DATA_DIR + filename
	if not FileAccess.file_exists(path):
		print("DataManager: Warning - File not found: ", path)
		return {}
		
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("DataManager: Failed to open file: " + path)
		return {}
		
	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)
	
	if error == OK:
		var data = json.data
		if typeof(data) == TYPE_DICTIONARY:
			print("DataManager: Loaded %d entries from %s" % [data.size(), filename])
			return data
		else:
			push_error("DataManager: Invalid JSON format in %s (Expected Dictionary)" % filename)
			return {}
	else:
		push_error("DataManager: JSON Parse Error in %s at line %s: %s" % [filename, json.get_error_line(), json.get_error_message()])
		return {}

func get_building_def(key: String) -> Dictionary:
	if key in buildings: return buildings[key]
	if key in furniture: return furniture[key] # Fallback/Merge
	push_warning("DataManager: Building definition not found: " + key)
	return {}

func get_all_buildable_defs() -> Dictionary:
	var combined = buildings.duplicate()
	combined.merge(furniture)
	return combined
