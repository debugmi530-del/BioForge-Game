class_name BonePart
extends PartBase

const COLOR_NORMAL      := Color(0.08, 0.08, 0.08)
const COLOR_SELECTED    := Color(0.3, 0.3, 0.3)
const COLOR_HIGHLIGHT   := Color(0.2, 0.2, 0.5)

var joint_a_id : int = -1
var joint_b_id : int = -1
var bone_width : float = 0.1

var _mesh_instance : MeshInstance3D
var _material      : StandardMaterial3D
var _col_shape     : CollisionShape3D
var _static_body   : StaticBody3D

func _ready() -> void:
	part_type = PartType.BONE
	_build_visuals()

func _build_visuals() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOR_NORMAL
	_material.metallic = 0.8
	_material.roughness = 0.2

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = CylinderMesh.new()
	_mesh_instance.mesh.top_radius    = bone_width * 0.5
	_mesh_instance.mesh.bottom_radius = bone_width * 0.5
	_mesh_instance.mesh.height        = 1.0  # scaled via transform
	_mesh_instance.set_surface_override_material(0, _material)
	add_child(_mesh_instance)

	_static_body = StaticBody3D.new()
	_col_shape   = CollisionShape3D.new()
	_col_shape.shape = CylinderShape3D.new()
	_static_body.add_child(_col_shape)
	add_child(_static_body)
	_static_body.set_meta("part_ref", self)

func setup(id: int, ja: int, jb: int, pos_a: Vector3, pos_b: Vector3, width: float) -> void:
	part_id    = id
	joint_a_id = ja
	joint_b_id = jb
	bone_width = width
	update_geometry(pos_a, pos_b)

func update_geometry(pos_a: Vector3, pos_b: Vector3) -> void:
	var mid    := (pos_a + pos_b) * 0.5
	var length := pos_a.distance_to(pos_b)
	var dir    := (pos_b - pos_a).normalized() if length > 0.001 else Vector3.UP

	global_position = mid
	look_at(mid + dir, Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	rotate_object_local(Vector3.RIGHT, PI * 0.5)

	if _mesh_instance and _mesh_instance.mesh is CylinderMesh:
		_mesh_instance.mesh.height        = length
		_mesh_instance.mesh.top_radius    = bone_width * 0.5
		_mesh_instance.mesh.bottom_radius = bone_width * 0.5

	if _col_shape and _col_shape.shape is CylinderShape3D:
		_col_shape.shape.height = length
		_col_shape.shape.radius = bone_width * 0.5

func get_center() -> Vector3:
	return global_position

func get_snap_points() -> Array[Vector3]:
	# Bone exposes its two endpoints for muscle snapping
	var half_len := _mesh_instance.mesh.height * 0.5 if _mesh_instance else 0.5
	return [
		global_position + global_transform.basis.y * half_len,
		global_position - global_transform.basis.y * half_len,
	]

func _update_visuals() -> void:
	if not _material:
		return
	if is_selected:
		_material.albedo_color = COLOR_SELECTED
	elif is_highlighted:
		_material.albedo_color = COLOR_HIGHLIGHT
	else:
		_material.albedo_color = COLOR_NORMAL
