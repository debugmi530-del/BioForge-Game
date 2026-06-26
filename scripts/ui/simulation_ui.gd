extends Control

@onready var sim_manager      : Node3D       = $"../../SimulationManager"
@onready var btn_start_ai     : Button       = $Panel/VBox/BtnStartAI
@onready var btn_stop_ai      : Button       = $Panel/VBox/BtnStopAI
@onready var btn_apply_best   : Button       = $Panel/VBox/BtnApplyBest
@onready var btn_back         : Button       = $Panel/VBox/BtnBack
@onready var pop_input        : LineEdit     = $Panel/VBox/PopRow/PopInput
@onready var display_input    : LineEdit     = $Panel/VBox/DisplayRow/DisplayInput
@onready var eval_time_input  : LineEdit     = $Panel/VBox/EvalRow/EvalInput
@onready var mode_option      : OptionButton = $Panel/VBox/ModeRow/ModeOption
@onready var label_gen        : Label        = $Panel/VBox/LabelGen
@onready var label_fitness    : Label        = $Panel/VBox/LabelFitness
@onready var label_evaluated  : Label        = $Panel/VBox/LabelEval
@onready var label_status     : Label        = $Panel/VBox/LabelStatus

# Mode descriptions shown in the status bar when selected
const MODE_HINTS := {
	SimulationManager.SimMode.WALK:
		"Ходьба — стабильная поступь, равномерная скорость, без рывков",
	SimulationManager.SimMode.RUN:
		"Бег — максимальная скорость и дальность, рывки разрешены",
	SimulationManager.SimMode.JUMP_HEIGHT:
		"Прыжок в высоту — достичь максимальной высоты + мягкое приземление",
	SimulationManager.SimMode.JUMP_DIST:
		"Прыжок в длину — максимальная горизонтальная дальность + мягкое приземление",
	SimulationManager.SimMode.ALL:
		"Всё сразу — каждое существо получает случайный режим (тест универсальности)",
}

var _running : bool = false

func _ready() -> void:
	_setup_ui()
	sim_manager.generation_complete.connect(_on_generation_complete)
	sim_manager.simulation_stopped.connect(_on_sim_stopped)

func _setup_ui() -> void:
	btn_start_ai.pressed.connect(_on_start_ai)
	btn_stop_ai.pressed.connect(_on_stop_ai)
	btn_apply_best.pressed.connect(_on_apply_best)
	btn_back.pressed.connect(func():
		sim_manager.stop()
		GameManager.go_to_builder()
	)

	# Populate mode dropdown — order matches SimMode enum values
	mode_option.clear()
	mode_option.add_item("Ходьба",               SimulationManager.SimMode.WALK)
	mode_option.add_item("Бег",                  SimulationManager.SimMode.RUN)
	mode_option.add_item("Прыжок в высоту",      SimulationManager.SimMode.JUMP_HEIGHT)
	mode_option.add_item("Прыжок в длину",       SimulationManager.SimMode.JUMP_DIST)
	mode_option.add_item("Всё сразу",            SimulationManager.SimMode.ALL)
	mode_option.selected = 1   # default: Бег
	mode_option.item_selected.connect(_on_mode_changed)

	pop_input.text       = "100"
	display_input.text   = "10"
	eval_time_input.text = "8"

	btn_stop_ai.disabled    = true
	btn_apply_best.disabled = true
	_update_labels(0, 0.0)
	_show_mode_hint(SimulationManager.SimMode.RUN)

func _on_mode_changed(index: int) -> void:
	var mode := mode_option.get_item_id(index) as SimulationManager.SimMode
	_show_mode_hint(mode)
	# Jump modes need longer eval time by default — suggest it
	if mode == SimulationManager.SimMode.JUMP_HEIGHT or \
	   mode == SimulationManager.SimMode.JUMP_DIST:
		if eval_time_input.text.to_float() < 6.0:
			eval_time_input.text = "10"

func _show_mode_hint(mode: SimulationManager.SimMode) -> void:
	label_status.text = MODE_HINTS.get(mode, "")

func _on_start_ai() -> void:
	var pop     := pop_input.text.to_int()
	var display := display_input.text.to_int()
	var etime   := eval_time_input.text.to_float()
	var mode_idx := mode_option.selected
	var mode    := mode_option.get_item_id(mode_idx) as SimulationManager.SimMode

	pop     = clampi(pop,     1, 1_000_000)
	display = clampi(display, 1, 1000)
	etime   = clampf(etime,   1.0, 120.0)

	sim_manager.display_count = display
	sim_manager.start(pop, mode, etime)

	_running = true
	btn_start_ai.disabled   = true
	btn_stop_ai.disabled    = false
	btn_apply_best.disabled = true
	label_status.text       = "ИИ запущен | режим: %s" % mode_option.get_item_text(mode_idx)

func _on_stop_ai() -> void:
	sim_manager.stop()

func _on_apply_best() -> void:
	sim_manager.apply_best_to_data()
	label_status.text = "★ Лучший геном применён к существу в редакторе"

func _on_generation_complete(gen: int, best_fit: float) -> void:
	_update_labels(gen, best_fit)
	btn_apply_best.disabled = false
	label_status.text       = "Поколение %d завершено" % gen

func _on_sim_stopped() -> void:
	_running = false
	btn_start_ai.disabled   = false
	btn_stop_ai.disabled    = true
	label_status.text       = "ИИ остановлен"

func _update_labels(gen: int, best_fit: float) -> void:
	label_gen.text     = "Поколение: %d"                    % gen
	label_fitness.text = "Лучшая приспособленность: %.3f"   % best_fit
