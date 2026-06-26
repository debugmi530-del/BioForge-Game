class_name PartBase
extends Node3D

signal selected(part)
signal deselected(part)

enum PartType { BONE, MUSCLE, JOINT_BALL, JOINT_FIXED }

@export var part_type : PartType = PartType.BONE
@export var part_id   : int = -1

var is_selected   : bool = false
var is_highlighted: bool = false

# Override in subclasses
func get_snap_points() -> Array[Vector3]:
	return []

func set_selected(value: bool) -> void:
	is_selected = value
	_update_visuals()
	if value:
		selected.emit(self)
	else:
		deselected.emit(self)

func set_highlighted(value: bool) -> void:
	is_highlighted = value
	_update_visuals()

func _update_visuals() -> void:
	pass  # Override in subclasses

func delete() -> void:
	queue_free()
