extends Camera2D
class_name CameraController

## 镜头控制 — 跟随英雄 + 边缘滚动 + 滚轮缩放

@export var min_zoom: float = 0.3
@export var max_zoom: float = 1.5
@export var zoom_speed: float = 0.1
@export var edge_scroll_speed: float = 500.0
@export var edge_margin: float = 30.0

var target_hero: CharacterBody2D = null


func _ready() -> void:
	enabled = true
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER

func _process(delta: float) -> void:
	# 跟随目标
	if target_hero and is_instance_valid(target_hero):
		global_position = global_position.lerp(target_hero.global_position, 5.0 * delta)

	# 边缘滚动
	var mv := Vector2.ZERO
	var mouse := get_viewport().get_mouse_position()
	var vs := get_viewport().get_visible_rect().size
	if mouse.x < edge_margin: mv.x -= 1
	if mouse.x > vs.x - edge_margin: mv.x += 1
	if mouse.y < edge_margin: mv.y -= 1
	if mouse.y > vs.y - edge_margin: mv.y += 1
	if mv.length() > 0: global_position += mv.normalized() * edge_scroll_speed * delta

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom *= (1.0 + zoom_speed); zoom = zoom.clamp(Vector2(min_zoom,min_zoom), Vector2(max_zoom,max_zoom))
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom *= (1.0 - zoom_speed); zoom = zoom.clamp(Vector2(min_zoom,min_zoom), Vector2(max_zoom,max_zoom))

func set_target(hero: CharacterBody2D) -> void:
	target_hero = hero
