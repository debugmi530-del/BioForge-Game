extends Control

@onready var builder           : Node3D    = $"../../Builder"
@onready var btn_joint_ball    : Button    = $ToolPanel/VBox/BtnJointBall
@onready var btn_joint_fixed   : Button    = $ToolPanel/VBox/BtnJointFixed
@onready var btn_bone          : Button    = $ToolPanel/VBox/BtnBone
@onready var btn_muscle        : Button    = $ToolPanel/VBox/BtnMuscle
@onready var btn_select        : Button    = $ToolPanel/VBox/BtnSelect
@onready var btn_erase         : Button    = $ToolPanel/VBox/BtnErase
@onready var btn_random        : Button    = $ToolPanel/VBox/BtnRandom
@onready var btn_simulate      : Button    = $ToolPanel/VBox/BtnSimulate
@onready var btn_back          : Button    = $ToolPanel/VBox/BtnBack
@onready var symmetry_slider   : HSlider   = $ToolPanel/VBox/SymmetryRow/SymmetrySlider
@onready var symmetry_label    : Label     = $ToolPanel/VBox/SymmetryRow/SymmetryLabel
@onready var props_panel       : Panel     = $PropsPanel
@onready var prop_width        : HSlider   = $PropsPanel/VBox/WidthRow/WidthSlider
@onready var prop_strength     : HSlider   = $PropsPanel/VBox/StrengthRow/StrengthSlider
@onready var prop_width_lbl    : Label     = $PropsPanel/VBox/WidthRow/WidthVal
@onready var prop_strength_lbl : Label     = $PropsPanel/VBox/StrengthRow/StrengthVal
@onready var status_label      : Label     = $StatusLabel

var _tool_buttons : Array[Button] = []

func _ready() -> void:
	_tool_buttons = [btn_joint_ball, btn_joint_fixed, btn_bone, btn_muscle, btn_select, btn_erase]

	btn_joint_ball.pressed.connect(func():  _set_tool(CreatureBuilder.Tool.JOINT_BALL))
	btn_joint_fixed.pressed.connect(func(): _set_tool(CreatureBuilder.Tool.JOINT_FIXED))
	btn_bone.pressed.connect(func():        _set_tool(CreatureBuilder.Tool.BONE))
	btn_muscle.pressed.connect(func():      _set_tool(CreatureBuilder.Tool.MUSCLE))
	btn_select.pressed.connect(func():      _set_tool(CreatureBuilder.Tool.SELECT))
	btn_erase.pressed.connect(func():       _set_tool(CreatureBuilder.Tool.ERASE))
	btn_random.pressed.connect(_on_random)
	btn_simulate.pressed.connect(_on_simulate)
	btn_back.pressed.connect(GameManager.go_to_main_menu)

	symmetry_slider.min_value = 1
	symmetry_slider.max_value = 10
	symmetry_slider.step      = 1
	symmetry_slider.value     = 1
	symmetry_slider.value_changed.connect(_on_symmetry_changed)

	prop_width.min_value    = 0.02
	prop_width.max_value    = 1.0
	prop_width.step         = 0.01
	prop_width.value        = 0.1
	prop_strength.min_value = 0.1
	prop_strength.max_value = 10.0
	prop_strength.step      = 0.1
	prop_strength.value     = 1.0

	prop_width.value_changed.connect(func(v): builder.update_selected_property("width", v); prop_width_lbl.text = "%.2f" % v)
	prop_strength.value_changed.connect(func(v): builder.update_selected_property("strength", v); prop_strength_lbl.text = "%.1f" % v)

	builder.selection_changed.connect(_on_selection_changed)
	builder.part_placed.connect(_on_part_placed)

	props_panel.visible = false
	_set_tool(CreatureBuilder.Tool.SELECT)

func _set_tool(tool: CreatureBuilder.Tool) -> void:
	builder.set_tool(tool)
	for btn in _tool_buttons:
		btn.modulate = Color(1, 1, 1)
	match tool:
		CreatureBuilder.Tool.JOINT_BALL:  btn_joint_ball.modulate  = Color(1.5, 1.0, 0.3)
		CreatureBuilder.Tool.JOINT_FIXED: btn_joint_fixed.modulate = Color(0.3, 1.2, 1.5)
		CreatureBuilder.Tool.BONE:        btn_bone.modulate         = Color(1.2, 1.2, 1.2)
		CreatureBuilder.Tool.MUSCLE:      btn_muscle.modulate       = Color(1.5, 0.4, 0.4)
		CreatureBuilder.Tool.SELECT:      btn_select.modulate       = Color(0.5, 1.5, 0.5)
		CreatureBuilder.Tool.ERASE:       btn_erase.modulate        = Color(1.5, 0.4, 0.4)

	var hints := {
		CreatureBuilder.Tool.SELECT:      "Выбор: кликни на деталь",
		CreatureBuilder.Tool.JOINT_BALL:  "Шарнир (оранжевый): клик — разместить",
		CreatureBuilder.Tool.JOINT_FIXED: "Крепление (синее): клик — разместить",
		CreatureBuilder.Tool.BONE:        "Кость: кликни на шарнир → тяни к другому",
		CreatureBuilder.Tool.MUSCLE:      "Мышца: кликни на кость → тяни к другой",
		CreatureBuilder.Tool.ERASE:       "Стереть: кликни на деталь",
	}
	status_label.text = hints.get(tool, "")

func _on_symmetry_changed(value: float) -> void:
	var n := int(value)
	builder.set_symmetry(n)
	symmetry_label.text = "Симметрия: %d" % n if n > 1 else "Без симметрии"

func _on_random() -> void:
	builder.randomize_creature()
	status_label.text = "Создано случайное существо"

func _on_simulate() -> void:
	if CreatureData.bones.is_empty():
		status_label.text = "Добавь хотя бы одну кость!"
		return
	GameManager.go_to_simulation()

func _on_selection_changed(part: PartBase) -> void:
	props_panel.visible = part != null
	if not part:
		return
	if part is BonePart:
		prop_width.visible    = true
		prop_strength.visible = false
		var bone := CreatureData.get_bone(part.part_id)
		prop_width.value = bone.get("width", 0.1)
		prop_width_lbl.text = "%.2f" % prop_width.value
	elif part is MusclePart:
		prop_width.visible    = true
		prop_strength.visible = true
		var mus := CreatureData.get_muscle(part.part_id)
		prop_width.value    = mus.get("width", 0.15)
		prop_strength.value = mus.get("strength", 1.0)
	else:
		prop_width.visible    = false
		prop_strength.visible = false

func _on_part_placed(_type: String, _id: int) -> void:
	status_label.text = "Деталь размещена"
