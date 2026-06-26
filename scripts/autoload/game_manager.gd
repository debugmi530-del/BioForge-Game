extends Node

# ── Scenes ──────────────────────────────────────────────────────────────────
const SCENE_MAIN_MENU   := "res://scenes/main_menu.tscn"
const SCENE_BUILDER     := "res://scenes/builder.tscn"
const SCENE_SIMULATION  := "res://scenes/simulation.tscn"

# ── Settings (persisted) ─────────────────────────────────────────────────────
var settings := {
	"master_volume"  : 1.0,
	"music_volume"   : 0.8,
	"sfx_volume"     : 1.0,
	"shadow_quality" : 1,       # 0=low 1=med 2=high
	"vsync"          : true,
}

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	load_settings()

# ── Scene switching ───────────────────────────────────────────────────────────
func go_to_builder() -> void:
	get_tree().change_scene_to_file(SCENE_BUILDER)

func go_to_simulation() -> void:
	get_tree().change_scene_to_file(SCENE_SIMULATION)

func go_to_main_menu() -> void:
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)

func quit_game() -> void:
	get_tree().quit()

# ── Settings persistence ──────────────────────────────────────────────────────
func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.save(SETTINGS_PATH)
	_apply_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for key in settings:
			if cfg.has_section_key("settings", key):
				settings[key] = cfg.get_value("settings", key)
	_apply_settings()

func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Master"),
		linear_to_db(settings["master_volume"])
	)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if settings["vsync"] else DisplayServer.VSYNC_DISABLED
	)
