extends Node3D

const MAP_W := 10000.0
const MAP_H := 10000.0

@export var hero_scene: PackedScene
@export var tower_scene: PackedScene
@export var minion_scene: PackedScene
@export var monster_scene: PackedScene
@export var projectile_scene: PackedScene

@onready var entities_node: Node3D = $Entities
@onready var projectiles_node: Node3D = $Projectiles
@onready var camera: Camera3D = $Camera3D

var game_state: Dictionary = {}
var my_hero_id: int = -1
var my_team: int = -1

var entity_nodes: Dictionary = {}
var projectile_nodes: Dictionary = {}

func _ready() -> void:
	NetworkClient.state_received.connect(_on_state_received)
	NetworkClient.event_received.connect(_on_event_received)
	NetworkClient.connected_to_server.connect(_on_connected)

func _on_connected() -> void:
	pass

func _on_state_received(state: Dictionary) -> void:
	game_state = state
	my_hero_id = NetworkClient.my_hero_id
	my_team = NetworkClient.my_team
	_update_entities()
	_update_projectiles()
	_update_camera()

func _on_event_received(type: String, data: Dictionary) -> void:
	match type:
		"damage_number":
			pass
		"shake":
			_camera_shake(data.get("duration", 0.2), data.get("intensity", 5.0))
		"sound":
			pass
		"end":
			pass
		"reset":
			_clear_all_entities()

func _update_entities() -> void:
	var alive_ids: Array[int] = []
	for h in game_state.get("heroes", []):
		_update_entity(int(h.id), h, "hero", alive_ids)
	for m in game_state.get("minions", []):
		_update_entity(int(m.id), m, "minion", alive_ids)
	for t in game_state.get("towers", []):
		_update_entity(int(t.id), t, "tower", alive_ids)
	for m in game_state.get("monsters", []):
		_update_entity(int(m.id), m, "monster", alive_ids)
	for id in entity_nodes.keys():
		if not id in alive_ids:
			entity_nodes[id].queue_free()
			entity_nodes.erase(id)

func _update_entity(id: int, data: Dictionary, kind: String, alive_ids: Array[int]) -> void:
	alive_ids.append(id)
	var node: Node3D
	if entity_nodes.has(id):
		node = entity_nodes[id]
	else:
		node = _create_entity_node(kind, data)
		entity_nodes[id] = node
		entities_node.add_child(node)
	var target_pos := Vector3(float(data.x), 0.0, float(data.y))
	node.position = node.position.lerp(target_pos, 0.3)
	if data.has("faceAngle"):
		node.rotation.y = -float(data.faceAngle)

func _create_entity_node(kind: String, data: Dictionary) -> Node3D:
	var node: Node3D
	match kind:
		"hero":
			node = hero_scene.instantiate() if hero_scene else MeshInstance3D.new()
		"tower":
			node = tower_scene.instantiate() if tower_scene else MeshInstance3D.new()
		"minion":
			node = minion_scene.instantiate() if minion_scene else MeshInstance3D.new()
		"monster":
			node = monster_scene.instantiate() if monster_scene else MeshInstance3D.new()
		_:
			node = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _get_entity_color(kind, data)
	node.material_override = mat
	return node

func _get_entity_color(kind: String, data: Dictionary) -> Color:
	var team := int(data.get("team", -1))
	var is_me := int(data.get("id", -1)) == my_hero_id
	match kind:
		"hero":
			if is_me: return Color.GOLD
			return Color.BLUE if team == 0 else Color.RED
		"tower":
			return Color.DARK_BLUE if team == 0 else Color.DARK_RED
		"minion":
			return Color.LIGHT_BLUE if team == 0 else Color.LIGHT_CORAL
		"monster":
			var mtype := data.get("type", "")
			if mtype == "baron": return Color.PURPLE
			if mtype == "dragon": return Color.ORANGE
			var ctype := data.get("campType", "")
			if ctype == "red_buff": return Color.RED
			if ctype == "blue_buff": return Color.BLUE
			return Color.DARK_GREEN
	return Color.WHITE

func _update_projectiles() -> void:
	var alive_ids: Array[int] = []
	for p in game_state.get("projectiles", []):
		var id := int(p.id)
		alive_ids.append(id)
		var node: Node3D
		if projectile_nodes.has(id):
			node = projectile_nodes[id]
		else:
			node = projectile_scene.instantiate() if projectile_scene else MeshInstance3D.new()
			projectile_nodes[id] = node
			projectiles_node.add_child(node)
		node.position = node.position.lerp(Vector3(float(p.x), 0.5, float(p.y)), 0.4)
	for id in projectile_nodes.keys():
		if not id in alive_ids:
			projectile_nodes[id].queue_free()
			projectile_nodes.erase(id)

func _clear_all_entities() -> void:
	for node in entity_nodes.values():
		node.queue_free()
	entity_nodes.clear()
	for node in projectile_nodes.values():
		node.queue_free()
	projectile_nodes.clear()

func _update_camera() -> void:
	if my_hero_id < 0:
		return
	for h in game_state.get("heroes", []):
		if int(h.id) == my_hero_id:
			var target := Vector3(float(h.x), 0.0, float(h.y))
			var cam_target := target + Vector3(0, 25, 15)
			camera.position = camera.position.lerp(cam_target, 0.1)
			camera.look_at(target, Vector3.UP)
			return

func _camera_shake(duration: float, intensity: float) -> void:
	pass

func screen_to_world(screen_pos: Vector2) -> Vector3:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var t := -ray_origin.y / ray_dir.y
	var hit := ray_origin + ray_dir * t
	return Vector3(hit.x, 0.0, hit.z)

func get_my_hero() -> Dictionary:
	if my_hero_id < 0:
		return {}
	for h in game_state.get("heroes", []):
		if int(h.id) == my_hero_id:
			return h
	return {}
