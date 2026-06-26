extends Control

@onready var btn_start    : Button      = $Panel/VBox/BtnStart
@onready var btn_settings : Button      = $Panel/VBox/BtnSettings
@onready var btn_quit     : Button      = $Panel/VBox/BtnQuit
@onready var bg_viewport  : SubViewport = $BgLayer/BgViewport
@onready var title_label  : Label       = $Panel/VBox/Title
@onready var settings_panel : Control   = $SettingsOverlay

var _bg_creatures : Array = []
var _bg_timer     : float = 0.0
const BG_SPAWN_INTERVAL := 6.0

func _ready() -> void:
	_setup_ui()
	_spawn_background_creature()
	settings_panel.visible = false

func _setup_ui() -> void:
	btn_start.pressed.connect(func(): GameManager.go_to_builder())
	btn_settings.pressed.connect(func(): settings_panel.visible = true)
	btn_quit.pressed.connect(func(): GameManager.quit_game())

func _process(delta: float) -> void:
	_bg_timer += delta
	if _bg_timer >= BG_SPAWN_INTERVAL:
		_bg_timer = 0.0
		_spawn_background_creature()

func _spawn_background_creature() -> void:
	# Generate a random creature in the background viewport
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	CreatureData.generate_random(randi_range(3, 7), rng.randi())

	var inst := preload("res://scripts/simulation/creature_physics.gd").new()
	if bg_viewport:
		bg_viewport.add_child(inst)
	inst.global_position = Vector3(rng.randf_range(-5.0, 5.0), 1.0, rng.randf_range(-3.0, 3.0))
	inst.build()
	_bg_creatures.append(inst)

	# Clean old ones
	while _bg_creatures.size() > 4:
		var old := _bg_creatures.pop_front()
		if is_instance_valid(old):
			old.queue_free()
