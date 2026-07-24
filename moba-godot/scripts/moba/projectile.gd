extends Area2D
class_name Projectile

## 追踪型弹道 — 速度300px/s，3秒自动销毁

signal hit_target(target: Node2D, damage: int)

var target: Node2D = null
var damage: int = 0
var speed: float = 300.0
var lifetime: float = 0.0
var max_lifetime: float = 3.0

func setup(_target: Node2D, _damage: int, _speed: float = 300.0) -> void:
	target = _target
	damage = _damage
	speed = _speed

func _process(delta: float) -> void:
	lifetime += delta
	if lifetime > max_lifetime:
		queue_free()
		return
	if not target or not is_instance_valid(target):
		queue_free()
		return
	var dir := target.global_position - global_position
	if dir.length() < 10:
		hit_target.emit(target, damage)
		queue_free()
		return
	global_position += dir.normalized() * speed * delta
	rotation = dir.angle()

func _on_body_entered(_body: Node2D) -> void:
	hit_target.emit(_body, damage)
	queue_free()
