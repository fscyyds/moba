extends Node3D

const MAP_W := 6000.0
const MAP_H := 4000.0

# 实体场景
@export var hero_scene: PackedScene
@export var tower_scene: PackedScene
@export var minion_scene: PackedScene
@export var monster_scene: PackedScene
@export var projectile_scene: PackedScene

# 节点引用
@onready var entities_node: Node3D = $Entities
@onready var projectiles_node: Node3D = $Projectiles
@onready var camera: Camera3D = $Camera3D

var game_state: Dictionary = {}
var my_hero_id: int = -1
var my_team: int = -1

# 实体对象池 id -> Node3D
var entity_nodes: Dictionary = {}
var projectile_nodes: Dictionary = {}

func _ready() -> void:
	NetworkClient.state_received.connect(_on_state_received)
	NetworkClient.event_received.connect(_on_event_received)
	NetworkClient.connected_to_server.connect(_on_connected)

func _on_connected() -> void:
	# 默认自动加入战士，实际应由 UI 选择
	# 这里先不自动加入，等玩家选择
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
			# TODO: 3D 飘字
			pass
		"shake":
			_camera_shake(data.get("duration", 0.2), data.get("intensity", 5.0))
		"sound":
			# TODO: 音效播放
			pass
		"end":
			# TODO: 显示结束界面
			pass
		"reset":
			_clear_all_entities()

func _update_entities() -> void:
	var alive_ids: Array[int] = []
	
	# 更新英雄
	for h in game_state.get("heroes", []):
		_update_entity(int(h.id), h, "hero", alive_ids)
	# 更新小兵
	for m in game_state.get("minions", []):
		_update_entity(int(m.id), m, "minion", alive_ids)
	# 更新防御塔
	for t in game_state.get("towers", []):
		_update_entity(int(t.id), t, "tower", alive_ids)
	# 更新野怪
	for m in game_state.get("monsters", []):
		_update_entity(int(m.id), m, "monster", alive_ids)
	
	# 移除已死亡的实体
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
	
	# 更新位置（插值）
	var target_pos := Vector3(float(data.x), 0.0, float(data.y))
	node.position = node.position.lerp(target_pos, 0.3)
	
	# 更新朝向
	if data.has("faceAngle"):
		node.rotation.y = -float(data.faceAngle)
	
	# 更新视觉效果
	if node.has_method("update_visuals"):
		node.update_visuals(data, my_team, my_hero_id)

func _create_entity_node(kind: String, data: Dictionary) -> Node3D:
	match kind:
		"hero":
			return hero_scene.instantiate()
		"tower":
			return tower_scene.instantiate()
		"minion":
			return minion_scene.instantiate()
		"monster":
			return monster_scene.instantiate()
	return Node3D.new()

func _update_projectiles() -> void:
	var alive_ids: Array[int] = []
	for p in game_state.get("projectiles", []):
		var id := int(p.id)
		alive_ids.append(id)
		var node: Node3D
		if projectile_nodes.has(id):
			node = projectile_nodes[id]
		else:
			node = projectile_scene.instantiate()
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
			# 固定俯视角，摄像机在英雄上方偏后
			var cam_target := target + Vector3(0, 18, 12)
			camera.position = camera.position.lerp(cam_target, 0.1)
			camera.look_at(target, Vector3.UP)
			return

func _camera_shake(duration: float, intensity: float) -> void:
	# 简单震动：用 Tween 或 Shader，这里先占位
	pass

func screen_to_world(screen_pos: Vector2) -> Vector3:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	# 与 y=0 平面相交
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
