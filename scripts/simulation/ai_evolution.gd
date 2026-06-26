class_name AiEvolution
extends RefCounted

# ── Genome ────────────────────────────────────────────────────────────────────
# Each muscle has 3 params: [strength, frequency, phase_offset]
# strength      : 0.1 .. 10.0
# frequency     : 0.1 .. 5.0
# phase_offset  : 0.0 .. TAU

const PARAM_PER_MUSCLE := 3
const MUTATION_STEP    := 0.001

# ── Population ────────────────────────────────────────────────────────────────
var population_size   : int   = 10
var generation        : int   = 0
var best_genome       : Array[float] = []
var best_fitness      : float = -INF

var _genomes          : Array  = []   # Array of Array[float]
var _fitnesses        : Array[float] = []
var _muscle_count     : int   = 0

signal generation_done(generation: int, best_fitness: float, best_genome: Array)

func init(muscle_count: int, pop_size: int) -> void:
	_muscle_count   = muscle_count
	population_size = pop_size
	generation      = 0
	best_fitness    = -INF
	best_genome.clear()
	_genomes.clear()
	_fitnesses.clear()

	# Seed from creature data
	var base := _genome_from_creature_data()

	for i in range(population_size):
		if i == 0 and not base.is_empty():
			_genomes.append(base.duplicate())
		else:
			_genomes.append(_random_genome())
		_fitnesses.append(-INF)

func _genome_from_creature_data() -> Array[float]:
	var g : Array[float] = []
	for m in CreatureData.muscles:
		g.append(clampf(m.get("strength",    1.0), 0.1, 10.0))
		g.append(clampf(m.get("frequency",   1.0), 0.1, 5.0))
		g.append(clampf(m.get("phase_offset",0.0), 0.0, TAU))
	return g

func _random_genome() -> Array[float]:
	var g : Array[float] = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in range(_muscle_count):
		g.append(rng.randf_range(0.1, 5.0))    # strength
		g.append(rng.randf_range(0.5, 3.0))    # frequency
		g.append(rng.randf_range(0.0, TAU))    # phase_offset
	return g

# ── Called after each creature has been evaluated ─────────────────────────────
func submit_fitness(genome_index: int, fitness: float) -> void:
	if genome_index < _fitnesses.size():
		_fitnesses[genome_index] = fitness

# ── Advance to next generation ────────────────────────────────────────────────
func next_generation() -> void:
	# Find best
	var best_idx := 0
	for i in range(_fitnesses.size()):
		if _fitnesses[i] > _fitnesses[best_idx]:
			best_idx = i

	var current_best_fit := _fitnesses[best_idx]
	if current_best_fit > best_fitness:
		best_fitness = current_best_fit
		best_genome  = _genomes[best_idx].duplicate()

	generation += 1

	# Build new population: keep best, mutate the rest
	var new_genomes : Array = []
	new_genomes.append(best_genome.duplicate())  # elitism

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for _i in range(population_size - 1):
		var child := best_genome.duplicate() as Array[float]
		# Mutate every gene by ±MUTATION_STEP (with occasional larger jumps)
		for gi in range(child.size()):
			var step := MUTATION_STEP
			if rng.randf() < 0.05:          # 5% chance of bigger jump
				step = MUTATION_STEP * 10.0
			child[gi] += rng.randf_range(-step, step)
		# Clamp each param to valid range
		for mi in range(_muscle_count):
			var base := mi * PARAM_PER_MUSCLE
			child[base + 0] = clampf(child[base + 0], 0.1, 10.0)   # strength
			child[base + 1] = clampf(child[base + 1], 0.1, 5.0)    # frequency
			child[base + 2] = fmod(child[base + 2] + TAU, TAU)     # phase wrap
		new_genomes.append(child)

	_genomes   = new_genomes
	_fitnesses.resize(population_size)
	_fitnesses.fill(-INF)

	generation_done.emit(generation, best_fitness, best_genome)

# ── Getters ───────────────────────────────────────────────────────────────────
func get_genome(index: int) -> Array[float]:
	if index < _genomes.size():
		return _genomes[index]
	return []

func get_params_for_muscle(genome: Array[float], muscle_index: int) -> Dictionary:
	var base := muscle_index * PARAM_PER_MUSCLE
	if base + 2 >= genome.size():
		return {"strength": 1.0, "frequency": 1.0, "phase_offset": 0.0}
	return {
		"strength"     : genome[base + 0],
		"frequency"    : genome[base + 1],
		"phase_offset" : genome[base + 2],
	}

func apply_best_to_creature_data() -> void:
	if best_genome.is_empty():
		return
	for i in range(CreatureData.muscles.size()):
		var params := get_params_for_muscle(best_genome, i)
		CreatureData.muscles[i]["strength"]     = params.strength
		CreatureData.muscles[i]["frequency"]    = params.frequency
		CreatureData.muscles[i]["phase_offset"] = params.phase_offset
