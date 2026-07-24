extends Label
class_name AlertIcon

## 塔顶感叹号 — 敌方塔预警 "!" / 危险 "!!"

@export var float_amplitude: float = 5.0
@export var float_speed: float = 3.0

var time: float = 0.0
var base_y: float = 0.0

func _ready() -> void:
	base_y = position.y
	visible = false
	add_theme_font_size_override("font_size", 20)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _process(delta: float) -> void:
	if not visible: return
	time += delta
	position.y = base_y + sin(time * float_speed) * float_amplitude
