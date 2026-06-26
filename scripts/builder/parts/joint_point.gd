class_name JointPoint
extends PartBase

const RADIUS         := 0.12
const COLOR_NORMAL   := Color(1.0, 0.55, 0.0)   # orange
const COLOR_SELECTED := Color(1.0, 0.8,  0.2)
const COLOR_HIGHLIGHT:= Color(1.0, 0.9,  0.5)

var _mesh_instance : MeshInstance3D
var _material      : StandardMaterial3D
var _static_body   : StaticBody3D

func _ready() -> void:
	part_type = PartType.JOINT_BALL
	_build_visuals()

func _build_visuals() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color  = COLOR_NORMAL
	_material.metallic      = 0.6
	_material.roughness     = 0.3
	_material.emission_enabled = true
	_material.emission      = COLOR_NORMAL * 0.3

	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = sphere
	_mesh_instance.set_surface_override_material(0, _material)
	add_child(_mesh_instance)

	_static_body = StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = RADIUS * 1.2
	_static_body.add_child(col)
	_static_body.set_meta("part_ref", self)
	add_child(_static_body)

func setup(id: int, pos: Vector3) -> void:
	part_id         = id
	global_position = pos

func get_snap_points() -> Array[Vector3]:
	return [global_position]

func _update_visuals() -> void:
	if not _material:
		return
	if is_selected:
		_material.albedo_color = COLOR_SELECTED
		_material.emission     = COLOR_SELECTED * 0.5
	elif is_highlighted:
		_material.albedo_color = COLOR_HIGHLIGHT
		_material.emission     = COLOR_HIGHLIGHT * 0.5
	else:
		_material.albedo_color = COLOR_NORMAL
		_material.emission     = COLOR_NORMAL * 0.3
