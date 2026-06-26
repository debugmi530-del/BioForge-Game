class_name MusclePart
extends PartBase

# Muscle looks like  --<>--  (thin ends, diamond middle)
const COLOR_NORMAL    := Color(0.8, 0.1, 0.1)
const COLOR_SELECTED  := Color(1.0, 0.3, 0.3)
const COLOR_HIGHLIGHT := Color(1.0, 0.5, 0.2)

var bone_a_id   : int   = -1
var bone_b_id   : int   = -1
var strength    : float = 1.0
var mus_width   : float = 0.15   # diamond belly width

var _mesh_instance : MeshInstance3D
var _material      : StandardMaterial3D

# Attach-point positions in world space (middle of each bone)
var attach_a    : Vector3 = Vector3.ZERO
var attach_b    : Vector3 = Vector3.ZERO

func _ready() -> void:
	part_type = PartType.MUSCLE
	_build_visuals()

func _build_visuals() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color     = COLOR_NORMAL
	_material.metallic         = 0.3
	_material.roughness        = 0.6
	_material.emission_enabled = true
	_material.emission         = COLOR_NORMAL * 0.2

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _build_muscle_mesh()
	_mesh_instance.set_surface_override_material(0, _material)
	add_child(_mesh_instance)

func _build_muscle_mesh() -> ArrayMesh:
	# Build  --<>--  shape as an ArrayMesh (lathe around Y axis)
	var arr_mesh := ArrayMesh.new()
	var verts    := PackedVector3Array()
	var normals  := PackedVector3Array()
	var indices  := PackedInt32Array()

	var segments   := 10
	var belly      := mus_width * 0.5
	var thin       := belly * 0.18
	var length     := 1.0  # scaled in update_geometry

	# Profile along Y axis: (radius, y)
	var profile : Array[Vector2] = [
		Vector2(thin,  -0.5),
		Vector2(thin,  -0.25),
		Vector2(belly, 0.0),
		Vector2(thin,  0.25),
		Vector2(thin,  0.5),
	]

	var cols := segments + 1
	for pi in range(profile.size()):
		for si in range(cols):
			var angle := TAU * si / float(segments)
			var r     := profile[pi].x
			var y     := profile[pi].y * length
			verts.append(Vector3(cos(angle) * r, y, sin(angle) * r))
			normals.append(Vector3(cos(angle), 0.0, sin(angle)).normalized())

	for pi in range(profile.size() - 1):
		for si in range(segments):
			var a := pi * cols + si
			var b := pi * cols + si + 1
			var c := (pi + 1) * cols + si
			var d := (pi + 1) * cols + si + 1
			indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX]  = indices
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh

func setup(id: int, ba: int, bb: int, pos_a: Vector3, pos_b: Vector3,
		str_val: float, width: float) -> void:
	part_id  = id
	bone_a_id = ba
	bone_b_id = bb
	strength = str_val
	mus_width = width
	update_geometry(pos_a, pos_b)

func update_geometry(pos_a: Vector3, pos_b: Vector3) -> void:
	attach_a = pos_a
	attach_b = pos_b
	var mid    := (pos_a + pos_b) * 0.5
	var length := pos_a.distance_to(pos_b)
	var dir    := (pos_b - pos_a).normalized() if length > 0.001 else Vector3.UP

	global_position = mid
	look_at(mid + dir, Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT)
	rotate_object_local(Vector3.RIGHT, PI * 0.5)
	scale = Vector3(1.0, length, 1.0)

	# Rebuild mesh to reflect new width/strength
	if _mesh_instance:
		_mesh_instance.mesh = _build_muscle_mesh()

func _update_visuals() -> void:
	if not _material:
		return
	if is_selected:
		_material.albedo_color = COLOR_SELECTED
		_material.emission     = COLOR_SELECTED * 0.3
	elif is_highlighted:
		_material.albedo_color = COLOR_HIGHLIGHT
		_material.emission     = COLOR_HIGHLIGHT * 0.3
	else:
		_material.albedo_color = COLOR_NORMAL
		_material.emission     = COLOR_NORMAL * 0.2
