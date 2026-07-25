extends Area2D
class_name Projectile

## 弹道 — 远程小兵/炮车的攻击投射物

@export var speed: float = 400.0
@export var damage: int = 50
var target_pos: Vector2
var team: String = ""
var lifetime: float = 3.0

func setup(_target_pos: Vector2, _damage: int, _team: String) -> void:
	target_pos = _target_pos; damage = _damage; team = _team
	var sp := get_node_or_null("Sprite2D") as Sprite2D
	if sp: sp.modulate = Color.LIGHT_BLUE if team == "team_blue" else Color.LIGHT_CORAL

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0: queue_free(); return
	var dir := (target_pos - global_position).normalized()
	global_position += dir * speed * delta
	if global_position.distance_to(target_pos) < 15:
		_on_hit()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(team): return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()

func _on_hit() -> void:
	queue_free()
