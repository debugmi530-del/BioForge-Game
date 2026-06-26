class_name CreaturePhysics
extends Node3D

# Converts a CreatureData graph into a live physics simulation.
# Each bone becomes a RigidBody3D; joints become physics constraints;
# muscles apply forces each physics tick.
#
# sim_mode drives which fitness function is active:
#   WALK        — penalise speed bursts, reward steady pace + stability
#   RUN         — reward max distance + peak speed + stability
#   JUMP_HEIGHT — reward max COM height gain + stable landing
#   JUMP_DIST   — reward XZ displacement at landing + stable landing
#   ALL         — caller picks a random concrete mode before build()

const BONE_DENSITY  := 200.0
const GROUND_Y      := 0.0
const AIRBORNE_THR  := 0.25   # COM must rise this much above start_y to count as jump
const MAX_WALK_SPEED := 3.5   # m/s — exceeding this is penalised in WALK mode

var sim_mode : int = 0        # SimulationManager.SimMode value

# ── Physics nodes ──────────────────────────────────────────────────────────────
var _bodies   : Dictionary = {}
var _joints   : Dictionary = {}
var _muscles  : Array      = []
var _genome   : Array[float] = []

# ── Time ───────────────────────────────────────────────────────────────────────
var _time     : float = 0.0

# ── Shared tracking ────────────────────────────────────────────────────────────
var start_position : Vector3 = Vector3.ZERO
var current_com    : Vector3 = Vector3.ZERO
var fitness        : float   = 0.0
var alive_time     : float   = 0.0

# ── WALK tracking ──────────────────────────────────────────────────────────────
var _speed_samples  : Array[float] = []
var _sample_timer   : float = 0.0
var _prev_com_xz    : Vector2 = Vector2.ZERO
const SAMPLE_INTERVAL := 0.5   # seconds between speed samples

# ── RUN tracking ───────────────────────────────────────────────────────────────
var _max_speed     : float = 0.0
var _speed_sum     : float = 0.0
var _speed_ticks   : int   = 0

# ── JUMP shared tracking ───────────────────────────────────────────────────────
var _start_com_y      : float   = 0.0
var _max_com_y        : float   = 0.0      # highest point reached
var _is_airborne      : bool    = false
var _peak_xz          : Vector2 = Vector2.ZERO  # XZ at highest point (JUMP_DIST)
var _landing_xz       : Vector2 = Vector2.ZERO  # XZ when landed (JUMP_DIST)
var _landed           : bool    = false
var _landing_vel_sum  : float   = 0.0
var _landing_vel_ticks: int     = 0
var _post_land_timer  : float   = 0.0
const LAND_MEASURE_WINDOW := 1.5   # seconds after landing to measure calm

# ── Stability (all modes) ──────────────────────────────────────────────────────
var _max_height_var   : float = 0.0
var _prev_com_y       : float = 0.0

signal fell_over

func _ready() -> void:
	set_physics_process(false)

# ── Build from data ────────────────────────────────────────────────────────────
func build(genome: Array[float] = [], mode: int = 0) -> void:
	_clear_physics()
	_genome   = genome
	sim_mode  = mode
	_time     = 0.0
	fitness   = 0.0
	alive_time = 0.0

	# reset all trackers
	_speed_samples.clear()
	_sample_timer  = 0.0
	_max_speed     = 0.0
	_speed_sum     = 0.0
	_speed_ticks   = 0

	_is_airborne       = false
	_landed            = false
	_landing_vel_sum   = 0.0
	_landing_vel_ticks = 0
	_post_land_timer   = 0.0
	_max_height_var    = 0.0

	# Build joint position lookup
	for j in CreatureData.joints:
		_joints[j.id] = j.position + global_position

	# Build bone rigid bodies
	for b in CreatureData.bones:
		var pa : Vector3 = _joints.get(b.joint_a, Vector3.ZERO)
		var pb : Vector3 = _joints.get(b.joint_b, Vector3.ZERO)
		_spawn_bone_body(b, pa, pb)

	# Connect joints
	for j in CreatureData.joints:
		_connect_joint(j)

	# Register muscles
	for i in range(CreatureData.muscles.size()):
		var m   := CreatureData.muscles[i]
		var ba  := _bodies.get(m.bone_a)
		var bb  := _bodies.get(m.bone_b)
		if ba and bb:
			var params : Dictionary
			if not _genome.is_empty() and i * 3 + 2 < _genome.size():
				params = {
					"strength"    : _genome[i * 3 + 0],
					"frequency"   : _genome[i * 3 + 1],
					"phase_offset": _genome[i * 3 + 2],
				}
			else:
				params = {
					"strength"    : m.get("strength",     1.0),
					"frequency"   : m.get("frequency",    1.0),
					"phase_offset": m.get("phase_offset", 0.0),
				}
			_muscles.append({
				"data"  : m,
				"body_a": ba,
				"body_b": bb,
				"params": params,
			})

	var com       := _compute_com()
	start_position = com
	_start_com_y   = com.y
	_max_com_y     = com.y
	_prev_com_y    = com.y
	_prev_com_xz   = Vector2(com.x, com.z)
	_peak_xz       = _prev_com_xz
	_landing_xz    = _prev_com_xz
	set_physics_process(true)

# ── Bone spawning ─────────────────────────────────────────────────────────────
func _spawn_bone_body(bone: Dictionary, pa: Vector3, pb: Vector3) -> void:
	var mid    := (pa + pb) * 0.5
	var length := pa.distance_to(pb)
	var width  := bone.get("width", 0.1)
	if length < 0.01:
		return

	var body := RigidBody3D.new()
	body.mass = BONE_DENSITY * PI * (width * 0.5) ** 2 * length
	body.linear_damp  = 0.5
	body.angular_damp = 0.8
	body.global_position = mid

	var dir := (pb - pa).normalized()
	if dir.length() > 0.001 and abs(dir.dot(Vector3.UP)) < 0.99:
		body.look_at(mid + dir, Vector3.UP)
	body.rotate_object_local(Vector3.RIGHT, PI * 0.5)

	var shape    := CylinderShape3D.new()
	shape.height  = length
	shape.radius  = width * 0.5
	var col       := CollisionShape3D.new()
	col.shape     = shape
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var cyl        := CylinderMesh.new()
	cyl.height         = length
	cyl.top_radius     = width * 0.5
	cyl.bottom_radius  = width * 0.5
	var mat            := StandardMaterial3D.new()
	mat.albedo_color   = Color(0.08, 0.08, 0.08)
	mat.metallic       = 0.8
	mesh_inst.mesh = cyl
	mesh_inst.set_surface_override_material(0, mat)
	body.add_child(mesh_inst)

	add_child(body)
	_bodies[bone.id] = body

# ── Joint connections ─────────────────────────────────────────────────────────
func _connect_joint(j: Dictionary) -> void:
	var connected : Array = []
	for b in CreatureData.bones:
		if b.joint_a == j.id or b.joint_b == j.id:
			var body := _bodies.get(b.id)
			if body:
				connected.append(body)
	if connected.size() < 2:
		return

	var anchor_world := _joints.get(j.id, Vector3.ZERO)
	var body_a       := connected[0] as RigidBody3D

	for idx in range(1, connected.size()):
		var body_b := connected[idx] as RigidBody3D
		var joint  : Joint3D

		if j.type == "ball":
			var bj := Generic6DOFJoint3D.new()
			bj.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,  true)
			bj.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,  true)
			bj.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,  true)
			bj.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
			bj.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
			bj.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
			joint = bj
		else:
			var fj := Generic6DOFJoint3D.new()
			for flag in [Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,
						 Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT]:
				fj.set_flag_x(flag, true)
				fj.set_flag_y(flag, true)
				fj.set_flag_z(flag, true)
			joint = fj

		joint.node_a = body_a.get_path()
		joint.node_b = body_b.get_path()
		joint.global_position = anchor_world
		add_child(joint)

# ── Physics tick ──────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_time      += delta
	alive_time += delta

	for entry in _muscles:
		_apply_muscle_force(entry)

	current_com = _compute_com()

	_update_mode_trackers(delta)
	fitness = _compute_fitness()

	# Fall detection (fell through the world)
	if current_com.y < GROUND_Y - 3.0:
		fell_over.emit()

# ── Per-mode tracking update ──────────────────────────────────────────────────
func _update_mode_trackers(delta: float) -> void:
	var com_xz := Vector2(current_com.x, current_com.z)

	# Global height variance (used in all modes for stability)
	var height_var := abs(current_com.y - _prev_com_y)
	_max_height_var = maxf(_max_height_var, height_var)
	_prev_com_y = current_com.y

	match sim_mode:
		# ── WALK ─────────────────────────────────────────────────────────────
		0: # SimMode.WALK
			_sample_timer += delta
			if _sample_timer >= SAMPLE_INTERVAL:
				_sample_timer = 0.0
				var dist_step := com_xz.distance_to(_prev_com_xz) / SAMPLE_INTERVAL
				_speed_samples.append(dist_step)
				_prev_com_xz = com_xz

		# ── RUN ──────────────────────────────────────────────────────────────
		1: # SimMode.RUN
			var inst_speed := com_xz.distance_to(_prev_com_xz) / maxf(delta, 0.001)
			_max_speed = maxf(_max_speed, inst_speed)
			_speed_sum   += inst_speed
			_speed_ticks += 1
			_prev_com_xz = com_xz

		# ── JUMP_HEIGHT ───────────────────────────────────────────────────────
		2: # SimMode.JUMP_HEIGHT
			_max_com_y = maxf(_max_com_y, current_com.y)
			_track_jump_landing(com_xz, delta)

		# ── JUMP_DIST ────────────────────────────────────────────────────────
		3: # SimMode.JUMP_DIST
			# Track the XZ position at peak height
			if current_com.y > _max_com_y:
				_max_com_y = current_com.y
				_peak_xz   = com_xz
			_track_jump_landing(com_xz, delta)

# Helper: detect airborne → landed transition and measure post-landing calm
func _track_jump_landing(com_xz: Vector2, delta: float) -> void:
	var height_gain := current_com.y - _start_com_y
	if not _is_airborne and height_gain > AIRBORNE_THR:
		_is_airborne = true

	if _is_airborne and not _landed and height_gain <= 0.05:
		_landed      = true
		_landing_xz  = com_xz

	if _landed:
		_post_land_timer += delta
		if _post_land_timer <= LAND_MEASURE_WINDOW:
			var vel_sum := 0.0
			for b in _bodies.values():
				vel_sum += (b as RigidBody3D).linear_velocity.length()
			_landing_vel_sum   += vel_sum / maxf(_bodies.size(), 1)
			_landing_vel_ticks += 1

# ── Fitness functions ─────────────────────────────────────────────────────────
func _compute_fitness() -> float:
	match sim_mode:
		0: return _fitness_walk()
		1: return _fitness_run()
		2: return _fitness_jump_height()
		3: return _fitness_jump_dist()
		_: return _fitness_run()   # fallback

func _fitness_walk() -> float:
	var com_xz   := Vector2(current_com.x, current_com.z)
	var start_xz := Vector2(start_position.x, start_position.z)
	var dist     := com_xz.distance_to(start_xz)

	# Speed consistency: low variance in speed samples = steady gait
	var consistency := 1.0
	if _speed_samples.size() > 1:
		var mean := 0.0
		for s in _speed_samples:
			mean += s
		mean /= _speed_samples.size()
		var variance := 0.0
		for s in _speed_samples:
			variance += (s - mean) ** 2
		variance /= _speed_samples.size()
		consistency = 1.0 / (1.0 + variance * 4.0)

		# Penalise bursts: if any sample exceeds MAX_WALK_SPEED, deduct
		for s in _speed_samples:
			if s > MAX_WALK_SPEED:
				consistency *= 0.7

	var stability := 1.0 / (1.0 + _max_height_var * 8.0)
	return dist * 0.35 + consistency * 0.40 + stability * 0.25

func _fitness_run() -> float:
	var com_xz   := Vector2(current_com.x, current_com.z)
	var start_xz := Vector2(start_position.x, start_position.z)
	var dist     := com_xz.distance_to(start_xz)
	var avg_speed := _speed_sum / maxf(_speed_ticks, 1)
	var stability := 1.0 / (1.0 + _max_height_var * 6.0)
	return dist * 0.35 + _max_speed * 0.35 + avg_speed * 0.15 + stability * 0.15

func _fitness_jump_height() -> float:
	var height_gain := maxf(_max_com_y - _start_com_y, 0.0)
	var land_calm   := _landing_calm_score()
	var stability   := 1.0 / (1.0 + _max_height_var * 5.0)
	return height_gain * 0.60 + land_calm * 0.30 + stability * 0.10

func _fitness_jump_dist() -> float:
	var start_xz := Vector2(start_position.x, start_position.z)
	var land_xz  := _landing_xz if _landed else Vector2(current_com.x, current_com.z)
	var xz_dist  := land_xz.distance_to(start_xz)
	var height_bonus := maxf(_max_com_y - _start_com_y, 0.0) * 0.1
	var land_calm    := _landing_calm_score()
	return xz_dist * 0.60 + land_calm * 0.30 + height_bonus * 0.10

# Landing calmness: low avg body velocity after touchdown = smooth landing
func _landing_calm_score() -> float:
	if not _landed or _landing_vel_ticks == 0:
		# Never left the ground — bad jump, no reward
		return 0.0 if not _landed else 0.5
	var avg_vel := _landing_vel_sum / float(_landing_vel_ticks)
	return 1.0 / (1.0 + avg_vel * 0.8)

# ── Muscle force ──────────────────────────────────────────────────────────────
func _apply_muscle_force(entry: Dictionary) -> void:
	var p     := entry.params
	var str   := float(p.strength)
	var freq  := float(p.frequency)
	var phase := float(p.phase_offset)
	var body_a := entry.body_a as RigidBody3D
	var body_b := entry.body_b as RigidBody3D
	if not body_a or not body_b:
		return

	var activation := sin(_time * freq * TAU + phase) * str
	var dir_a      := (body_b.global_position - body_a.global_position).normalized()
	var force      := dir_a * activation * 50.0

	body_a.apply_central_force( force)
	body_b.apply_central_force(-force)

# ── COM helper ────────────────────────────────────────────────────────────────
func _compute_com() -> Vector3:
	if _bodies.is_empty():
		return global_position
	var sum := Vector3.ZERO
	for b in _bodies.values():
		sum += (b as RigidBody3D).global_position
	return sum / float(_bodies.size())

func _clear_physics() -> void:
	for child in get_children():
		child.queue_free()
	_bodies.clear()
	_joints.clear()
	_muscles.clear()
	set_physics_process(false)
