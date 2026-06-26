class_name CreatureBuilder
extends Node3D

signal part_placed(part_type: String, part_id: int)
signal part_removed(part_id: int)
signal selection_changed(part)

# ── Tool state ────────────────────────────────────────────────────────────────
enum Tool { SELECT, BONE, MUSCLE, JOINT_BALL, JOINT_FIXED, ERASE }
var current_tool : Tool = Tool.SELECT

# ── Symmetry ──────────────────────────────────────────────────────────────────
var symmetry_count : int = 1   # 1 = none, 2-10 = N-fold around Y axis

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var camera        : Camera3D       = $"../Camera3D"
@onready var part_root     : Node3D         = $PartRoot
@onready var ghost_root    : Node3D         = $GhostRoot

# ── Drag state ────────────────────────────────────────────────────────────────
var _dragging      : bool    = false
var _drag_start    : Vector3 = Vector3.ZERO
var _drag_joint_id : int     = -1       # for bone: the joint we started from
var _drag_bone_id  : int     = -1       # for muscle: the bone we started from
var _ghost         : Node3D  = null

# ── Hover ─────────────────────────────────────────────────────────────────────
var _hovered_part  : PartBase = null
var _selected_part : PartBase = null

# ── Part node maps ────────────────────────────────────────────────────────────
var _joint_nodes  : Dictionary = {}   # id -> JointPoint
var _bone_nodes   : Dictionary = {}   # id -> BonePart
var _muscle_nodes : Dictionary = {}   # id -> MusclePart

# ── Preloads ──────────────────────────────────────────────────────────────────
const JointScene      := preload("res://scenes/parts/joint.tscn")
const ConnectionScene := preload("res://scenes/parts/connection.tscn")
const BoneScene       := preload("res://scenes/parts/bone.tscn")
const MuscleScene     := preload("res://scenes/parts/muscle.tscn")

# ── Build plane ───────────────────────────────────────────────────────────────
var _build_plane := Plane(Vector3.UP, 0.0)

func _ready() -> void:
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_mouse_move(event)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_click_start(event.position)
		else:
			_on_click_release(event.position)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_erase_selected()

# ── Input handlers ────────────────────────────────────────────────────────────
func _on_mouse_move(event: InputEventMouseMotion) -> void:
	var world_pos := _ray_to_plane(event.position)
	_update_hover(event.position)
	if _dragging:
		_update_ghost(world_pos)

func _on_click_start(screen_pos: Vector2) -> void:
	var world_pos := _ray_to_plane(screen_pos)
	var hit_part  := _raycast_part(screen_pos)

	match current_tool:
		Tool.SELECT:
			_select_part(hit_part)
		Tool.JOINT_BALL:
			_begin_place_joint(world_pos, "ball")
		Tool.JOINT_FIXED:
			_begin_place_joint(world_pos, "fixed")
		Tool.BONE:
			if hit_part and (hit_part is JointPoint or hit_part is ConnectionPoint):
				_begin_place_bone(hit_part)
		Tool.MUSCLE:
			if hit_part and hit_part is BonePart:
				_begin_place_muscle(hit_part)
		Tool.ERASE:
			if hit_part:
				_erase_part(hit_part)

func _on_click_release(screen_pos: Vector2) -> void:
	if not _dragging:
		return
	var world_pos := _ray_to_plane(screen_pos)
	var hit_part  := _raycast_part(screen_pos)

	match current_tool:
		Tool.BONE:
			_finish_place_bone(world_pos, hit_part)
		Tool.MUSCLE:
			_finish_place_muscle(hit_part)

	_dragging = false
	_drag_joint_id = -1
	_drag_bone_id  = -1
	_clear_ghost()

# ── Joint placement ───────────────────────────────────────────────────────────
func _begin_place_joint(pos: Vector3, type: String) -> void:
	_place_joint_at(pos, type)

func _place_joint_at(pos: Vector3, type: String) -> void:
	for angle_i in range(symmetry_count):
		var angle := TAU * angle_i / float(symmetry_count)
		var sym_pos := _rotate_y(pos, angle)
		var jid := CreatureData.add_joint(sym_pos, type)
		_spawn_joint_node(jid, sym_pos, type)
	part_placed.emit(type, 0)

func _spawn_joint_node(id: int, pos: Vector3, type: String) -> void:
	var scene := JointScene if type == "ball" else ConnectionScene
	var node  := scene.instantiate() as PartBase
	part_root.add_child(node)
	if node is JointPoint:
		node.setup(id, pos)
	elif node is ConnectionPoint:
		node.setup(id, pos)
	_joint_nodes[id] = node
	node.selected.connect(_on_part_selected)

# ── Bone placement ────────────────────────────────────────────────────────────
func _begin_place_bone(start_joint: PartBase) -> void:
	_dragging      = true
	_drag_joint_id = start_joint.part_id
	_drag_start    = start_joint.global_position
	# Ghost preview
	_ghost = BoneScene.instantiate()
	ghost_root.add_child(_ghost)

func _update_ghost(world_pos: Vector3) -> void:
	if _ghost and current_tool == Tool.BONE:
		var pos_a := _drag_start
		var pos_b := world_pos
		if _ghost is BonePart:
			_ghost.update_geometry(pos_a, pos_b)
	elif _ghost and current_tool == Tool.MUSCLE:
		pass  # Muscle ghost handled separately

func _finish_place_bone(world_pos: Vector3, hit: PartBase) -> void:
	# Need an end joint
	var end_joint_id : int = -1
	var end_pos      : Vector3

	if hit and (hit is JointPoint or hit is ConnectionPoint) and hit.part_id != _drag_joint_id:
		end_joint_id = hit.part_id
		end_pos      = hit.global_position
	else:
		# No valid joint at release — cancel
		return

	for angle_i in range(symmetry_count):
		var angle   := TAU * angle_i / float(symmetry_count)
		var ja_pos  := _rotate_y(_drag_start, angle)
		var jb_pos  := _rotate_y(end_pos,     angle)
		# Find the actual joint ids at these symmetry positions
		var ja_id := _find_joint_near(ja_pos)
		var jb_id := _find_joint_near(jb_pos)
		if ja_id < 0 or jb_id < 0 or ja_id == jb_id:
			continue
		var bid := CreatureData.add_bone(ja_id, jb_id)
		_spawn_bone_node(bid, ja_id, jb_id, ja_pos, jb_pos)
	part_placed.emit("bone", 0)

func _spawn_bone_node(id: int, ja: int, jb: int, pa: Vector3, pb: Vector3) -> void:
	var node := BoneScene.instantiate() as BonePart
	part_root.add_child(node)
	node.setup(id, ja, jb, pa, pb, 0.1)
	_bone_nodes[id] = node
	node.selected.connect(_on_part_selected)

# ── Muscle placement ──────────────────────────────────────────────────────────
func _begin_place_muscle(start_bone: BonePart) -> void:
	_dragging     = true
	_drag_bone_id = start_bone.part_id
	_drag_start   = start_bone.global_position

func _finish_place_muscle(hit: PartBase) -> void:
	if not (hit and hit is BonePart and hit.part_id != _drag_bone_id):
		return

	var bone_a_node := _bone_nodes.get(_drag_bone_id) as BonePart
	var bone_b_node := hit as BonePart
	if not bone_a_node or not bone_b_node:
		return

	for angle_i in range(symmetry_count):
		var angle   := TAU * angle_i / float(symmetry_count)
		var pa      := _rotate_y(bone_a_node.global_position, angle)
		var pb      := _rotate_y(bone_b_node.global_position, angle)
		var ba_id   := _find_bone_near(pa)
		var bb_id   := _find_bone_near(pb)
		if ba_id < 0 or bb_id < 0 or ba_id == bb_id:
			continue
		var mid := CreatureData.add_muscle(ba_id, bb_id)
		_spawn_muscle_node(mid, ba_id, bb_id, pa, pb)
	part_placed.emit("muscle", 0)

func _spawn_muscle_node(id: int, ba: int, bb: int, pa: Vector3, pb: Vector3) -> void:
	var node := MuscleScene.instantiate() as MusclePart
	part_root.add_child(node)
	node.setup(id, ba, bb, pa, pb, 1.0, 0.15)
	_muscle_nodes[id] = node
	node.selected.connect(_on_part_selected)

# ── Erase ─────────────────────────────────────────────────────────────────────
func _erase_part(part: PartBase) -> void:
	var id := part.part_id
	if part is JointPoint or part is ConnectionPoint:
		# Remove connected bones first
		var dead := CreatureData.bones.filter(func(b): return b.joint_a == id or b.joint_b == id)
		for b in dead:
			_remove_bone_node(b.id)
		CreatureData.remove_joint(id)
		_joint_nodes.erase(id)
		part.queue_free()
	elif part is BonePart:
		_remove_bone_node(id)
	elif part is MusclePart:
		CreatureData.remove_muscle(id)
		_muscle_nodes.erase(id)
		part.queue_free()
	part_removed.emit(id)

func _remove_bone_node(bid: int) -> void:
	# Remove muscles attached to this bone
	var dead_muscles := CreatureData.muscles.filter(func(m): return m.bone_a == bid or m.bone_b == bid)
	for m in dead_muscles:
		if _muscle_nodes.has(m.id):
			_muscle_nodes[m.id].queue_free()
			_muscle_nodes.erase(m.id)
	CreatureData.remove_bone(bid)
	if _bone_nodes.has(bid):
		_bone_nodes[bid].queue_free()
		_bone_nodes.erase(bid)

func _erase_selected() -> void:
	if _selected_part:
		_erase_part(_selected_part)
		_selected_part = null
		selection_changed.emit(null)

# ── Selection ─────────────────────────────────────────────────────────────────
var _selecting : bool = false  # recursion guard

func _select_part(part: PartBase) -> void:
	if _selecting:
		return
	_selecting = true
	if _selected_part and is_instance_valid(_selected_part) and _selected_part != part:
		_selected_part.is_selected = false
		_selected_part._update_visuals()
	_selected_part = part
	if part and not part.is_selected:
		part.is_selected = true
		part._update_visuals()
	_selecting = false
	selection_changed.emit(part)

func _on_part_selected(part: PartBase) -> void:
	if _selecting:
		return
	_select_part(part)

# ── Hover ─────────────────────────────────────────────────────────────────────
func _update_hover(screen_pos: Vector2) -> void:
	var hit := _raycast_part(screen_pos)
	if _hovered_part and is_instance_valid(_hovered_part) and _hovered_part != hit:
		_hovered_part.set_highlighted(false)
	_hovered_part = hit
	if hit:
		hit.set_highlighted(true)

# ── Ghost ─────────────────────────────────────────────────────────────────────
func _clear_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null

# ── Raycast helpers ───────────────────────────────────────────────────────────
func _ray_to_plane(screen_pos: Vector2) -> Vector3:
	if not camera:
		return Vector3.ZERO
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	var dist := _build_plane.intersects_ray(from, dir)
	if dist >= 0.0:
		return from + dir * dist
	return Vector3.ZERO

func _raycast_part(screen_pos: Vector2) -> PartBase:
	if not camera:
		return null
	var space  := get_world_3d().direct_space_state
	var from   := camera.project_ray_origin(screen_pos)
	var to     := from + camera.project_ray_normal(screen_pos) * 100.0
	var query  := PhysicsRayQueryParameters3D.create(from, to)
	var result := space.intersect_ray(query)
	if result and result.collider:
		var body := result.collider
		if body.has_meta("part_ref"):
			return body.get_meta("part_ref") as PartBase
	return null

# ── Utility ───────────────────────────────────────────────────────────────────
func _rotate_y(pos: Vector3, angle: float) -> Vector3:
	return Vector3(
		pos.x * cos(angle) - pos.z * sin(angle),
		pos.y,
		pos.x * sin(angle) + pos.z * cos(angle)
	)

func _find_joint_near(pos: Vector3, threshold: float = 0.2) -> int:
	for j in CreatureData.joints:
		if j.position.distance_to(pos) < threshold:
			return j.id
	return -1

func _find_bone_near(pos: Vector3, threshold: float = 0.5) -> int:
	var best_id   := -1
	var best_dist := threshold
	for b in _bone_nodes.values():
		var d := b.global_position.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best_id   = b.part_id
	return best_id

# ── Public API ────────────────────────────────────────────────────────────────
func set_tool(tool: Tool) -> void:
	current_tool = tool
	_select_part(null)

func set_symmetry(n: int) -> void:
	symmetry_count = clampi(n, 1, 10)

func clear_creature() -> void:
	for n in part_root.get_children():
		n.queue_free()
	_joint_nodes.clear()
	_bone_nodes.clear()
	_muscle_nodes.clear()
	CreatureData.clear()

func randomize_creature() -> void:
	clear_creature()
	CreatureData.generate_random(randi_range(3, 8))
	_rebuild_from_data()

func _rebuild_from_data() -> void:
	for j in CreatureData.joints:
		_spawn_joint_node(j.id, j.position, j.type)
	for b in CreatureData.bones:
		var ja := CreatureData.get_joint(b.joint_a)
		var jb := CreatureData.get_joint(b.joint_b)
		if not ja.is_empty() and not jb.is_empty():
			_spawn_bone_node(b.id, b.joint_a, b.joint_b, ja.position, jb.position)
	for m in CreatureData.muscles:
		var ba := _bone_nodes.get(m.bone_a) as BonePart
		var bb := _bone_nodes.get(m.bone_b) as BonePart
		if ba and bb:
			_spawn_muscle_node(m.id, m.bone_a, m.bone_b, ba.global_position, bb.global_position)

func update_selected_property(property: String, value: Variant) -> void:
	if not _selected_part:
		return
	if _selected_part is BonePart:
		var bone := CreatureData.get_bone(_selected_part.part_id)
		if bone.is_empty():
			return
		match property:
			"width":
				bone.width = clampf(value, 0.02, 1.0)
				CreatureData.bones[CreatureData.bones.find(bone)].width = bone.width
				var ja := CreatureData.get_joint(bone.joint_a)
				var jb := CreatureData.get_joint(bone.joint_b)
				(_selected_part as BonePart).update_geometry(ja.position, jb.position)
	elif _selected_part is MusclePart:
		var mus := CreatureData.get_muscle(_selected_part.part_id)
		if mus.is_empty():
			return
		match property:
			"strength":
				mus.strength = clampf(value, 0.1, 10.0)
			"width":
				mus.width = clampf(value, 0.05, 0.8)
