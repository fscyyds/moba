extends Control
class_name MiniMap

## 小地图 — 显示所有单位位置

@export var map_size: float = 200.0
@export var world_size: float = 10000.0

var dots: Dictionary = {}  # node_path → ColorRect
var camera_rect: ColorRect


func _ready() -> void:
	camera_rect = ColorRect.new(); camera_rect.color = Color(1,1,1,0.2)
	camera_rect.size = Vector2(30, 20); add_child(camera_rect)
	set_process(true)

func _process(_delta: float) -> void:
	queue_redraw()
	var cam := get_viewport().get_camera_2d()
	if cam:
		var cpos := cam.global_position
		camera_rect.position = world_to_map(cpos) - camera_rect.size / 2

func world_to_map(wpos: Vector2) -> Vector2:
	return Vector2(wpos.x / world_size * map_size, (1.0 - wpos.y / world_size) * map_size)

func _draw() -> void:
	var r := map_size / world_size
	# 塔
	for t in get_tree().get_nodes_in_group("towers"):
		var c := Color.BLUE if t.is_in_group("team_blue") else Color.RED
		draw_rect(Rect2(world_to_map(t.global_position) - Vector2(3,3), Vector2(6,6)), c)
	# 英雄
	for h in get_tree().get_nodes_in_group("heroes"):
		var c := Color.CYAN if h.is_in_group("team_blue") else Color.ORANGE_RED
		draw_circle(world_to_map(h.global_position), 4, c)
	# 小兵
	for m in get_tree().get_nodes_in_group("minions"):
		var c := Color.LIGHT_BLUE if m.is_in_group("team_blue") else Color.LIGHT_CORAL
		draw_rect(Rect2(world_to_map(m.global_position) - Vector2(1,1), Vector2(2,2)), c)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var wp := Vector2(event.position.x / map_size * world_size, (1.0 - event.position.y / map_size) * world_size)
		var cam := get_viewport().get_camera_2d()
		if cam: cam.global_position = wp
