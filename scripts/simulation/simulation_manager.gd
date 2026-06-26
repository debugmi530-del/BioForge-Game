class_name SimulationManager
extends Node3D

# SimMode values mirror the int used in CreaturePhysics.sim_mode
enum SimMode {
	WALK        = 0,   # steady gait, no bursts, max stability
	RUN         = 1,   # fast movement, bursts ok, reward max speed + distance
	JUMP_HEIGHT = 2,   # reward max vertical height + stable landing
	JUMP_DIST   = 3,   # reward max horizontal distance + stable landing
	ALL         = 4,   # random concrete mode per creature (stress test)
}

@export var sim_mode         : SimMode = SimMode.RUN
@export var display_count    : int     = 10
@export var population_size  : int     = 100

var _evolution        : AiEvolution
var _instances        : Array      = []
var _instance_genomes : Dictionary = {}   # CreaturePhysics -> genome_index
var _batch_index      : int        = 0
var _batch_size       : int        = 10
var _eval_time        : float      = 8.0
var _timer            : float      = 0.0
var _running          : bool       = false
var _total_evaluated  : int        = 0

var _rng : RandomNumberGenerator = RandomNumberGenerator.new()

signal generation_complete(gen: int, best_fit: float)
signal simulation_stopped

const CreaturePhysicsScene := preload("res://scenes/simulation_creature.tscn")

func _ready() -> void:
	_rng.randomize()
	set_process(false)

func start(pop_size: int, mode: SimMode, eval_seconds: float = 8.0) -> void:
	population_size = pop_size
	sim_mode        = mode
	_eval_time      = eval_seconds
	_batch_size     = mini(display_count, pop_size)
	_batch_index    = 0
	_total_evaluated = 0

	_evolution = AiEvolution.new()
	_evolution.init(CreatureData.muscles.size(), pop_size)
	_evolution.generation_done.connect(_on_generation_done)

	_clear_instances()
	_instance_genomes.clear()
	_spawn_batch(0)

	_timer   = 0.0
	_running = true
	set_process(true)

func stop() -> void:
	_running = false
	set_process(false)
	_clear_instances()
	simulation_stopped.emit()

func _process(delta: float) -> void:
	if not _running:
		return
	_timer += delta
	if _timer >= _eval_time:
		_timer = 0.0
		_collect_fitness_and_advance()

func _collect_fitness_and_advance() -> void:
	for inst in _instances:
		if is_instance_valid(inst) and _instance_genomes.has(inst):
			_evolution.submit_fitness(_instance_genomes[inst], inst.fitness)
	_total_evaluated += _instances.size()

	_clear_instances()

	var next_start := (_batch_index + 1) * _batch_size
	if next_start >= population_size:
		_evolution.next_generation()
		_batch_index     = 0
		_total_evaluated = 0
		_spawn_batch(0)
	else:
		_batch_index += 1
		_spawn_batch(_batch_index)

func _spawn_batch(batch_idx: int) -> void:
	var start_genome := batch_idx * _batch_size
	var spread       := 4.0

	for i in range(_batch_size):
		var genome_idx := start_genome + i
		if genome_idx >= population_size:
			break

		var genome     := _evolution.get_genome(genome_idx)
		var creature_mode := _resolve_mode()   # ALL → random concrete mode

		var inst := CreaturePhysics.new()
		add_child(inst)
		inst.global_position = Vector3((i - _batch_size * 0.5) * spread, 0.5, 0.0)
		inst.build(genome, creature_mode)

		_instance_genomes[inst] = genome_idx
		inst.fell_over.connect(func(): _on_creature_fell(inst))
		_instances.append(inst)

# Returns a concrete SimMode int — for ALL picks randomly from the 4 real modes
func _resolve_mode() -> int:
	if sim_mode == SimMode.ALL:
		return _rng.randi_range(0, 3)   # WALK / RUN / JUMP_HEIGHT / JUMP_DIST
	return int(sim_mode)

func _on_creature_fell(inst: CreaturePhysics) -> void:
	if _instance_genomes.has(inst):
		_evolution.submit_fitness(_instance_genomes[inst], inst.fitness)
		_instance_genomes.erase(inst)
	_instances.erase(inst)
	if is_instance_valid(inst):
		inst.queue_free()

func _clear_instances() -> void:
	for inst in _instances:
		if is_instance_valid(inst):
			inst.queue_free()
	_instances.clear()
	_instance_genomes.clear()

func _on_generation_done(gen: int, best_fit: float, _genome: Array) -> void:
	generation_complete.emit(gen, best_fit)

func get_best_genome() -> Array[float]:
	if _evolution:
		return _evolution.best_genome
	return []

func apply_best_to_data() -> void:
	if _evolution:
		_evolution.apply_best_to_creature_data()
