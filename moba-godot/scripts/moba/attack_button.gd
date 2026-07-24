extends Control
class_name AttackButton

## 攻击键 — 右下角，半径40，按下触发

signal attack_pressed()

@export var radius: float = 40.0

var _touch_index: int = -1

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			if (event.position - global_position - (size / 2.0)).length() < radius * 2:
				_touch_index = event.index
				attack_pressed.emit()
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
