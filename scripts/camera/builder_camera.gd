class_name BuilderCamera
extends Camera3D

@export var orbit_speed  : float = 0.005
@export var zoom_speed   : float = 0.5
@export var pan_speed    : float = 0.01
@export var min_zoom     : float = 1.0
@export var max_zoom     : float = 30.0

var _pivot       : Vector3  = Vector3.ZERO
var _distance    : float    = 8.0
var _yaw         : float    = 0.4
var _pitch       : float    = 0.5
var _rotating    : bool     = false
var _panning     : bool     = false
var _last_mouse  : Vector2  = Vector2.ZERO

func _ready() -> void:
	_update_transform()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				_rotating = event.pressed
				_last_mouse = event.position
			MOUSE_BUTTON_RIGHT:
				_panning = event.pressed
				_last_mouse = event.position
			MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance - zoom_speed, min_zoom, max_zoom)
				_update_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = clampf(_distance + zoom_speed, min_zoom, max_zoom)
				_update_transform()

	elif event is InputEventMouseMotion:
		if _rotating:
			_yaw   -= event.relative.x * orbit_speed
			_pitch  = clampf(_pitch - event.relative.y * orbit_speed, -PI * 0.48, PI * 0.48)
			_update_transform()
		elif _panning:
			var right := global_transform.basis.x
			var up    := global_transform.basis.y
			_pivot -= right * event.relative.x * pan_speed * _distance
			_pivot += up    * event.relative.y * pan_speed * _distance
			_update_transform()

func _update_transform() -> void:
	var rot := Quaternion(Vector3.UP, _yaw) * Quaternion(Vector3.RIGHT, _pitch)
	var dir := rot * Vector3(0, 0, 1)
	global_position = _pivot + dir * _distance
	look_at(_pivot, Vector3.UP)

func reset_to(target: Vector3 = Vector3.ZERO, dist: float = 8.0) -> void:
	_pivot    = target
	_distance = dist
	_yaw      = 0.4
	_pitch    = 0.5
	_update_transform()
