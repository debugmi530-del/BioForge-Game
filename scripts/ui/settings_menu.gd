extends Control

@onready var master_slider : HSlider    = $VBox/MasterRow/Slider
@onready var music_slider  : HSlider    = $VBox/MusicRow/Slider
@onready var sfx_slider  : HSlider    = $VBox/SfxRow/Slider
@onready var vsync_check   : CheckButton= $VBox/VsyncRow/Check
@onready var shadow_option : OptionButton = $VBox/ShadowRow/Option
@onready var btn_close     : Button     = $VBox/BtnClose
@onready var btn_apply     : Button     = $VBox/BtnApply

func _ready() -> void:
	_load_from_settings()
	btn_close.pressed.connect(func(): visible = false)
	btn_apply.pressed.connect(_apply)

func _load_from_settings() -> void:
	master_slider.value = GameManager.settings["master_volume"]
	music_slider.value  = GameManager.settings["music_volume"]
	sfx_slider.value    = GameManager.settings["sfx_volume"]
	vsync_check.button_pressed = GameManager.settings["vsync"]
	shadow_option.selected     = GameManager.settings["shadow_quality"]

func _apply() -> void:
	GameManager.settings["master_volume"]  = master_slider.value
	GameManager.settings["music_volume"]   = music_slider.value
	GameManager.settings["sfx_volume"]     = sfx_slider.value
	GameManager.settings["vsync"]          = vsync_check.button_pressed
	GameManager.settings["shadow_quality"] = shadow_option.selected
	GameManager.save_settings()
	visible = false
