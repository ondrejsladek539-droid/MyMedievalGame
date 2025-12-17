extends Node

signal resources_changed(resources: Dictionary)

var resources: Dictionary = {
	"Wood": 0,
	"Stone": 0,
	"Food": 0
}

func register_item(type: String, amount: int) -> void:
	add_resource(type, amount)

func unregister_item(type: String, amount: int) -> void:
	if type in resources:
		resources[type] -= amount
		if resources[type] < 0: resources[type] = 0
		emit_signal("resources_changed", resources)

func add_resource(type: String, amount: int) -> void:
	if type in resources:
		resources[type] += amount
	else:
		resources[type] = amount
	
	emit_signal("resources_changed", resources)
	print("Resources updated: ", resources)

func has_resource(type: String, amount: int) -> bool:
	return resources.get(type, 0) >= amount

func consume_resource(type: String, amount: int) -> bool:
	if has_resource(type, amount):
		resources[type] -= amount
		emit_signal("resources_changed", resources)
		return true
	return false
