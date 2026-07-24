extends Control
class_name Joystick

## 虚拟摇杆 — 左下角，半径60，输出归一化方向

signal direction_changed(dir: Vector2)

@export var radius: float = 60.0
@onready var base: ColorRect = $Base
@onready var knob: ColorRect = $Knob

var _touch_index: int = -1
var _center: Vector2

func _ready() -> void:
	_center = base.position + base.size / 2.0
	knob.position = _center - knob.size / 2.0

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			if (event.position - global_position - _center).length() < radius * 2:
				_touch_index = event.index
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			_reset()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_knob(event.position - global_position)

func _update_knob(pos: Vector2) -> void:
	var offset := pos - _center
	var clamped := offset.limit_length(radius)
	knob.position = _center + clamped - knob.size / 2.0
	direction_changed.emit(clamped / radius)

func _reset() -> void:
	knob.position = _center - knob.size / 2.0
	direction_changed.emit(Vector2.ZERO)
