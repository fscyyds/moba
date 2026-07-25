extends CharacterBody2D
class_name RiverCrabV2

## 河蟹 — 不攻击，逃跑500px后脱战原地回血

@export var max_hp: int = 1500
@export var flee_speed: float = 300.0
@export var flee_distance: float = 500.0
@export var gold_value: int = 70
@export var xp_value: int = 80

var current_hp: int = 1500
var is_dead: bool = false
var is_fleeing: bool = false
var flee_dir: Vector2 = Vector2.RIGHT
var flee_origin: Vector2
var disengage_timer: float = 0.0


func _ready() -> void:
	add_to_group("monsters")
	current_hp = max_hp
	flee_dir = Vector2(1, -0.3).normalized()
	collision_layer = 32; collision_mask = 1

func _physics_process(delta: float) -> void:
	if is_dead: return
	if is_fleeing:
		velocity = flee_dir * flee_speed
		move_and_slide()
		var d := global_position.distance_to(flee_origin)
		if d >= flee_distance:
			is_fleeing = false
			disengage_timer = 2.0
		return
	if disengage_timer > 0:
		disengage_timer -= delta
		if disengage_timer <= 0:
			current_hp = max_hp  # 回满血
		return

func take_damage(dmg: int) -> void:
	if is_dead: return
	current_hp = max(current_hp - dmg, 0)
	if not is_fleeing:
		is_fleeing = true
		flee_origin = global_position
		flee_dir = Vector2(1 if randf() > 0.5 else -1, randf_range(-0.5, 0.5)).normalized()
	if current_hp <= 0: _die()

func _die() -> void:
	is_dead = true; visible = false; collision_layer = 0
	for h in get_tree().get_nodes_in_group("heroes"):
		if h.has_method("add_gold") and global_position.distance_to(h.global_position) < 500:
			h.add_gold(gold_value)
	await get_tree().create_timer(120.0).timeout
	is_dead = false; current_hp = max_hp; visible = true
	collision_layer = 32; collision_mask = 1
