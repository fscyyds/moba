extends CanvasLayer
class_name DangerVignette

## 屏幕边缘红色警告 — 进入敌方塔范围时触发

@export var max_alpha: float = 0.25
@export var fade_speed: float = 3.0

var _target_alpha: float = 0.0
var _current_alpha: float = 0.0
@onready var top_rect: ColorRect = $Top
@onready var bot_rect: ColorRect = $Bot
@onready var left_rect: ColorRect = $Left
@onready var right_rect: ColorRect = $Right


func _ready() -> void:
	_set_all_alpha(0.0)

func _process(delta: float) -> void:
	_current_alpha = move_toward(_current_alpha, _target_alpha, fade_speed * delta)
	_set_all_alpha(_current_alpha)

func set_danger(active: bool) -> void:
	_target_alpha = max_alpha if active else 0.0

func _set_all_alpha(a: float) -> void:
	for rect in [top_rect, bot_rect, left_rect, right_rect]:
		if rect:
			var c := rect.color
			c.a = a
			rect.color = c
