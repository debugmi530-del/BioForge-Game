extends Node

# ── Creature graph ────────────────────────────────────────────────────────────
# Joints: anchor points where bones connect
# Bones:  rigid segments between two joints
# Muscles: force actuators attached to two bones

var joints  : Array[Dictionary] = []
var bones   : Array[Dictionary] = []
var muscles : Array[Dictionary] = []

var _next_id : int = 0

func _ready() -> void:
	clear()

func clear() -> void:
	joints.clear()
	bones.clear()
	muscles.clear()
	_next_id = 0

func next_id() -> int:
	_next_id += 1
	return _next_id

# ── Joints ────────────────────────────────────────────────────────────────────
# type: "ball" (orange) | "fixed" (blue)
func add_joint(position: Vector3, type: String) -> int:
	var id := next_id()
	joints.append({
		"id"       : id,
		"type"     : type,
		"position" : position,
	})
	return id

func remove_joint(id: int) -> void:
	joints = joints.filter(func(j): return j.id != id)
	# Remove connected bones too
	var dead_bones := bones.filter(func(b): return b.joint_a == id or b.joint_b == id)
	for b in dead_bones:
		remove_bone(b.id)

func get_joint(id: int) -> Dictionary:
	for j in joints:
		if j.id == id:
			return j
	return {}

# ── Bones ─────────────────────────────────────────────────────────────────────
func add_bone(joint_a: int, joint_b: int, width: float = 0.1) -> int:
	var id := next_id()
	bones.append({
		"id"      : id,
		"joint_a" : joint_a,
		"joint_b" : joint_b,
		"width"   : clampf(width, 0.02, 1.0),
	})
	return id

func remove_bone(id: int) -> void:
	bones = bones.filter(func(b): return b.id != id)
	# Remove connected muscles
	muscles = muscles.filter(func(m): return m.bone_a != id and m.bone_b != id)

func get_bone(id: int) -> Dictionary:
	for b in bones:
		if b.id == id:
			return b
	return {}

# ── Muscles ───────────────────────────────────────────────────────────────────
# strength: how hard the muscle contracts  (affects <> size visually)
# width:    visual width of the diamond mid-section
# genome params (used by AI): strength, frequency, phase_offset
func add_muscle(bone_a: int, bone_b: int,
		strength: float = 1.0, width: float = 0.15) -> int:
	var id := next_id()
	muscles.append({
		"id"          : id,
		"bone_a"      : bone_a,
		"bone_b"      : bone_b,
		"strength"    : clampf(strength, 0.1, 10.0),
		"width"       : clampf(width, 0.05, 0.8),
		"frequency"   : 1.0,
		"phase_offset": 0.0,
	})
	return id

func remove_muscle(id: int) -> void:
	muscles = muscles.filter(func(m): return m.id != id)

func get_muscle(id: int) -> Dictionary:
	for m in muscles:
		if m.id == id:
			return m
	return {}

# ── Serialisation ─────────────────────────────────────────────────────────────
func to_dict() -> Dictionary:
	return {
		"joints"  : joints.duplicate(true),
		"bones"   : bones.duplicate(true),
		"muscles" : muscles.duplicate(true),
		"next_id" : _next_id,
	}

func from_dict(d: Dictionary) -> void:
	clear()
	joints   = d.get("joints",  []).duplicate(true)
	bones    = d.get("bones",   []).duplicate(true)
	muscles  = d.get("muscles", []).duplicate(true)
	_next_id = d.get("next_id", 0)

func save_to_file(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "\t"))

func load_from_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	var result := JSON.parse_string(f.get_as_text())
	if result is Dictionary:
		from_dict(result)
		return true
	return false

# ── Random creature generator ─────────────────────────────────────────────────
func generate_random(complexity: int = 4, seed_val: int = -1) -> void:
	clear()
	var rng := RandomNumberGenerator.new()
	if seed_val >= 0:
		rng.seed = seed_val
	else:
		rng.randomize()

	complexity = clampi(complexity, 2, 12)

	# Create root joint at origin
	var root_id := add_joint(Vector3.ZERO, "ball")

	# Grow a tree of bones outward from root
	var frontier := [root_id]
	var total_joints := 1

	for _i in range(complexity * 2):
		if frontier.is_empty():
			break
		var parent_joint_id : int = frontier[randi() % frontier.size()]
		var parent_j := get_joint(parent_joint_id)
		if parent_j.is_empty():
			continue

		# Random direction
		var dir := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range( 0.2, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var length := rng.randf_range(0.4, 1.5)
		var new_pos : Vector3 = parent_j.position + dir * length

		var joint_type := "ball" if rng.randf() > 0.3 else "fixed"
		var new_joint_id := add_joint(new_pos, joint_type)
		add_bone(parent_joint_id, new_joint_id, rng.randf_range(0.04, 0.15))

		frontier.append(new_joint_id)
		total_joints += 1
		if total_joints >= complexity + 2:
			frontier.erase(new_joint_id)

	# Add random muscles between bone pairs
	var bone_ids := bones.map(func(b): return b.id)
	var num_muscles := mini(rng.randi_range(1, bone_ids.size()), bone_ids.size())
	var used_pairs : Array[String] = []
	var attempts := 0
	var m_count := 0
	while m_count < num_muscles and attempts < 50:
		attempts += 1
		if bone_ids.size() < 2:
			break
		var ba := bone_ids[rng.randi() % bone_ids.size()]
		var bb := bone_ids[rng.randi() % bone_ids.size()]
		if ba == bb:
			continue
		var pair := str(mini(ba, bb)) + "_" + str(maxi(ba, bb))
		if pair in used_pairs:
			continue
		used_pairs.append(pair)
		add_muscle(ba, bb, rng.randf_range(0.5, 3.0), rng.randf_range(0.08, 0.3))
		m_count += 1
