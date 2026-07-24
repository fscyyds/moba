extends Area2D
class_name AttackTargetDetector

## 自动索敌区域 — 挂在角色下，检测攻击范围内的敌人
## 通过 signal 通知 BasicAttack 有可用目标

signal enemy_entered_range(enemy: Node2D)
signal enemy_exited_range(enemy: Node2D)

var enemies_in_range: Array[Node2D] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if _is_enemy(body):
		enemies_in_range.append(body)
		enemy_entered_range.emit(body)


func _on_body_exited(body: Node2D) -> void:
	if body in enemies_in_range:
		enemies_in_range.erase(body)
		enemy_exited_range.emit(body)


func _is_enemy(body: Node2D) -> bool:
	var my_groups := get_parent().get_groups()
	var body_groups := body.get_groups()
	for g in my_groups:
		if g.begins_with("team_") and g in body_groups:
			return false
	return true


func get_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = INF
	for e in enemies_in_range:
		if not is_instance_valid(e):
			continue
		var stats := e.get_node_or_null("CharacterStats") as CharacterStats
		if stats and stats.is_dead:
			continue
		var d := global_position.distance_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest
