extends Area2D
class_name TowerProjectile

## 塔攻击弹道 — 速度600，红色/蓝色光束

signal hit_target(target: Node2D, damage: int)

var target: Node2D = null
var damage: int = 0
var speed: float = 600.0
var lifetime: float = 0.0
var max_lifetime: float = 2.0
var team: String = ""

func setup(_target: Node2D, _damage: int, _team: String) -> void:
	target = _target; damage = _damage; team = _team
	# 颜色
	var sp := get_node_or_null("Sprite2D") as Sprite2D
	if sp:
		sp.modulate = Color.RED if team == "team_red" else Color.BLUE

func _process(delta: float) -> void:
	lifetime += delta
	if lifetime > max_lifetime: queue_free(); return
	if not target or not is_instance_valid(target): queue_free(); return
	var dir := target.global_position - global_position
	if dir.length() < 15:
		hit_target.emit(target, damage)
		queue_free()
		return
	global_position += dir.normalized() * speed * delta
	rotation = dir.angle()
