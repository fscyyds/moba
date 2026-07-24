extends CanvasLayer
class_name DangerVignette

## 屏幕边缘红色警告 — 进入敌方塔范围时触发

@export var max_intensity: float = 0.6
@export var fade_speed: float = 3.0

var _target: float = 0.0
var _current: float = 0.0
@onready var rect: ColorRect = $ColorRect


func _ready() -> void:
	if rect and rect.material is ShaderMaterial:
		(rect.material as ShaderMaterial).set_shader_parameter("intensity", 0.0)

func _process(delta: float) -> void:
	_current = move_toward(_current, _target, fade_speed * delta)
	if rect and rect.material is ShaderMaterial:
		(rect.material as ShaderMaterial).set_shader_parameter("intensity", _current)

func set_danger(active: bool) -> void:
	_target = max_intensity if active else 0.0
